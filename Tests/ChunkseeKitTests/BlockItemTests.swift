import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct BlockItemTests {
    private func assets(_ items: [String], version: Int = 5023) throws -> GameAssets {
        var entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}"),
            .init(path: "assets/test/models/item/picture.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"test:item/picture"}}"#),
        ]
        for name in items {
            let id = try #require(Identifier(name))
            entries.append(.init(path: "assets/\(id.namespace)/items/\(id.path).json",
                                 text: #"{"model":{"type":"model","model":"test:item/picture"}}"#))
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    @Test func actualRelationshipsUseTheExistingItemModelReader() throws {
        let cases = ["minecraft:stone": "minecraft:stone", "minecraft:spawner": "minecraft:spawner",
                     "minecraft:red_bed": "minecraft:red_bed", "minecraft:oak_wall_sign": "minecraft:oak_sign",
                     "minecraft:oak_wall_hanging_sign": "minecraft:oak_hanging_sign",
                     "minecraft:wall_torch": "minecraft:torch"]
        let reader = try assets(Array(cases.values))
        for (block, expected) in cases {
            let item = try #require(reader.blockItemID(for: block))
            #expect(item.description == expected)
            #expect(reader.defaultItemModel(item.description)?.parts.count == 1)
        }
        for block in ["stone", ":stone"] { #expect(reader.blockItemID(for: block)?.description == "minecraft:stone") }
    }

    @Test func neitherNamesNorPicturesInventMissingRelationships() throws {
        let reader = try assets(["minecraft:air", "minecraft:water", "test:stone", "minecraft:made_up",
                                 "minecraft:oak_wall_sign", "minecraft:oak_sign"])
        for block in ["air", "water", "test:stone", "made_up", "", "../stone"] {
            #expect(reader.blockItemID(for: block) == nil)
        }
        #expect(reader.defaultItemModel("test:stone") != nil)
        #expect(reader.blockItemID(for: "oak_wall_sign")?.description == "minecraft:oak_sign")
    }

    @Test func theSelectedJarMustSupplyTheActualItemDefinition() throws {
        let reader = try assets(["minecraft:oak_wall_sign", "minecraft:stone"])
        #expect(reader.blockItemID(for: "oak_wall_sign") == nil)
        #expect(reader.blockItemID(for: "stone")?.description == "minecraft:stone")
    }

    @Test func parseableVersionsKeepAvailableCodeRelationships() throws {
        for version in [0, Int(Int32.max)] {
            let reader = try assets(["minecraft:oak_sign"], version: version)
            #expect(reader.blockItemID(for: "oak_wall_sign")?.description == "minecraft:oak_sign")
        }
    }
}
