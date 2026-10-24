import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct BlockPropertyDefaultsTests {
    private func assets(_ id: String, _ definition: String, version: Int = 5023) throws -> GameAssets {
        let name = try #require(Identifier(id))
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}"),
            .init(path: "assets/\(name.namespace)/blockstates/\(name.path).json", text: definition),
            .init(path: "assets/minecraft/models/block/a.json", text: "{}"),
            .init(path: "assets/minecraft/models/block/b.json", text: "{}")
        ]
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func names(_ assets: GameAssets, _ state: BlockState) throws -> [String] {
        try #require(assets.blockModel(for: state)).parts.flatMap { $0.alternatives.map(\.modelID.path) }
    }

    @Test func compactSavedPalettesResolveModelsWithoutChangingTheirSavedProperties() throws {
        let reader = try assets("minecraft:oak_log", #"{"variants":{"axis=y":{"model":"block/a"},"axis=x":{"model":"block/b"}}}"#)
        for entry: NBT in [.string("minecraft:oak_log"), .compound(["": .string("minecraft:oak_log")]),
                           .compound(["id": .string("minecraft:oak_log")])] {
            let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 5023,
                                                     sections: [Fixtures.section(y: 0, palette: [entry])]))
            let saved = try #require(chunk.block(x: 0, y: 0, z: 0))
            #expect(try names(reader, saved) == ["block/a"])
            #expect(saved.properties.isEmpty)
            #expect(saved.description == "minecraft:oak_log")
            #expect(saved == BlockState("minecraft:oak_log"))
        }
    }

    @Test func partialPropertiesOverrideOnlyTheirSavedValuesIncludingNamespaceAliases() throws {
        let definition = #"{"variants":{"axis=y":{"model":"block/a"},"axis=x":{"model":"block/b"}}}"#
        let logs = try assets("minecraft:oak_log", definition)
        for id in ["oak_log", ":oak_log", "minecraft:oak_log"] {
            #expect(try names(logs, .init(id)) == ["block/a"])
            #expect(try names(logs, .init(id, properties: ["axis": "x"])) == ["block/b"])
        }
        let leaves = try assets("oak_leaves", #"{"variants":{"distance=7,persistent=false,waterlogged=false":{"model":"block/a"},"distance=7,persistent=true,waterlogged=false":{"model":"block/b"}}}"#)
        #expect(try names(leaves, .init("oak_leaves")) == ["block/a"])
        #expect(try names(leaves, .init("oak_leaves", properties: ["persistent": "true"])) == ["block/b"])
    }

    @Test func multipartUsesTheSameDefaultsForPositiveAndNegativePredicates() throws {
        let reader = try assets("oak_fence", #"{"multipart":[{"apply":{"model":"block/a"}},{"when":{"east":true},"apply":{"model":"block/b"}},{"when":{"AND":[{"waterlogged":false},{"west":"!true"}]},"apply":{"model":"block/a"}}]}"#)
        #expect(try names(reader, .init("oak_fence")) == ["block/a", "block/a"])
        #expect(try names(reader, .init("oak_fence", properties: ["east": "true"])) == ["block/a", "block/b", "block/a"])
        #expect(try names(reader, .init("oak_fence", properties: ["west": "true"])) == ["block/a"])
    }

    @Test func compactBedsAndDoubleBlocksUseTheRegisteredSeedProperties() throws {
        let definition = #"{"variants":{"":[{"model":"block/a","weight":1},{"model":"block/b","weight":3}]}}"#
        let position = BlockPosition(blockX: -1162, blockY: 62, blockZ: -1082)
        let ordinary = try #require(assets("stone", definition).blockModel(for: .init("stone")))
        for id in ["red_bed", "straw_bed"] {
            let reader = try assets(id, definition)
            let foot = try #require(reader.blockModel(for: .init(id)))
            let north = BlockPosition(blockX: position.x, blockY: position.y, blockZ: position.z - 1)
            #expect(foot.selectedAlternatives(at: position) == ordinary.selectedAlternatives(at: north))
            let head = try #require(reader.blockModel(for: .init(id, properties: ["part": "head"])))
            #expect(head.selectedAlternatives(at: position) == ordinary.selectedAlternatives(at: position))
        }
        for id in ["oak_door", "sunflower", "tall_grass"] {
            let reader = try assets(id, definition)
            let lower = try #require(reader.blockModel(for: .init(id)))
            #expect(lower.selectedAlternatives(at: position) == ordinary.selectedAlternatives(at: position))
            let upper = try #require(reader.blockModel(for: .init(id, properties: ["half": "upper"])))
            let below = BlockPosition(blockX: position.x, blockY: position.y - 1, blockZ: position.z)
            #expect(upper.selectedAlternatives(at: position) == ordinary.selectedAlternatives(at: below))
        }
    }

    @Test func unknownVersionsNamesNamespacesAndPropertiesHaveNoInventedDefault() throws {
        let definition = #"{"variants":{"axis=y":{"model":"block/a"}}}"#
        for version in [0, 4903, 5022, 5024, Int(Int32.max)] {
            let reader = try assets("oak_log", definition, version: version)
            #expect(reader.blockModel(for: .init("oak_log")) == nil)
            #expect(try names(reader, .init("oak_log", properties: ["axis": "y"])) == ["block/a"])
        }
        for id in ["example:oak_log", "minecraft:unregistered_log", "minecraft:stone"] {
            let reader = try assets(id, definition)
            #expect(reader.blockModel(for: .init(id)) == nil)
            #expect(try names(reader, .init(id, properties: ["axis": "y"])) == ["block/a"])
        }
        let extra = try assets("oak_log", #"{"variants":{"unknown=true":{"model":"block/a"}}}"#)
        #expect(extra.blockModel(for: .init("oak_log")) == nil)
    }

    @Test func explicitInvalidValuesAndUnavailableSelectedResourcesKeepTheFallback() throws {
        let reader = try assets("oak_log", #"{"variants":{"axis=y":{"model":"block/a"}}}"#)
        for value in ["", "up", "Y", " y"] {
            #expect(reader.blockModel(for: .init("oak_log", properties: ["axis": value])) == nil)
        }
        let missing = try assets("oak_log", #"{"variants":{"axis=y":{"model":"block/missing"}}}"#)
        #expect(missing.blockModel(for: .init("oak_log")) == nil)
        let absent = try assets("other_log", #"{"variants":{"":{"model":"block/a"}}}"#)
        #expect(absent.blockModel(for: .init("oak_log")) == nil)
    }
}
