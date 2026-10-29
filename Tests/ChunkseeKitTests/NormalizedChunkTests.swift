import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct NormalizedChunkTests {
    enum Terrain: CaseIterable, Sendable { case modern, legacy, malformed, numeric, missing }
    private let region = RegionPosition(x: 0, z: 0)

    private func blockRecords(x: Int32 = 3) -> [NBT] {
        let position: [String: NBT] = ["x": .int(x), "y": .int(64), "z": .int(4)]
        return [
            .compound(position.merging(["id": .string("minecraft:chest"), "Items": .list([item])]) { $1 }),
            .compound(position.merging(["id": .string("minecraft:oak_sign"), "Text1": .string("Saved sign")]) { $1 }),
            .compound(position.merging(["id": .string("minecraft:mob_spawner"),
                "SpawnData": .compound(["id": .string("minecraft:zombie_pigman")])]) { $1 }),
        ]
    }

    private var item: NBT { .compound(["id": .string("minecraft:grass"), "Count": .byte(3)]) }

    private var rider: NBT {
        Fixtures.mob(["id": .string("minecraft:zombie_pigman"), "CustomName": .string("Rider"),
            "Pos": .list([.double(8), .double(65), .double(9)]), "Items": .list([item])])
    }

    private var vehicle: NBT {
        .compound(["id": .string("minecraft:minecart"), "Pos": .list([.double(8), .double(64), .double(9)]),
                   "Passengers": .list([rider])])
    }

    private var legacySections: NBT {
        .list([.compound(["Y": .byte(4), "Palette": .list([.compound(["Name": .string("minecraft:stone")])]),
                          "BlockStates": .longArray([])])])
    }

    private func terrain(_ kind: Terrain) -> NBT {
        var records: [String: NBT] = ["block_entities": .list(blockRecords()), "entities": .list([vehicle]),
                                     "InhabitedTime": .long(47)]
        switch kind {
        case .modern, .malformed:
            let section = kind == .modern ? Fixtures.section(y: 4, palette: [.string("minecraft:stone")])
                : NBT.compound(["Y": .string("unreadable")])
            return Fixtures.chunk(x: 0, z: 0, dataVersion: 2508, sections: [section], extra: records)
        case .legacy, .numeric:
            records["TileEntities"] = records.removeValue(forKey: "block_entities")
            records["Entities"] = records.removeValue(forKey: "entities")
            records["xPos"] = .int(0); records["zPos"] = .int(0); records["Status"] = .string("full")
            records["Sections"] = kind == .legacy ? legacySections : .list([
                .compound(["Y": .byte(4), "Blocks": .byteArray([Int8](repeating: 1, count: 4096))]),
            ])
            return .compound(["DataVersion": .int(2508), "Level": .compound(records)])
        case .missing:
            records["DataVersion"] = .int(2508)
            return .compound(records)
        }
    }

    private func write(_ nbt: NBT, to dimension: ChunkseeKit.Dimension,
                       folder: ChunkseeKit.Dimension.Folder = .terrain) throws -> URL {
        let url = dimension.regionURL(folder, at: region)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]), to: url)
        return url
    }

    @Test(arguments: Terrain.allCases)
    func independentRecordsSurviveTerrainFailuresAndMatchSelectiveReads(_ kind: Terrain) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let saved = terrain(kind)
        let url = try write(saved, to: dimension)
        let original = try Data(contentsOf: url)
        let facts = try dimension.scan(region: region)
        let contents = try dimension.contents(regionX: 0, regionZ: 0)
        #expect(facts.containers == contents.containers && facts.signs == contents.signs)
        #expect(facts.spawners == contents.spawners && facts.creatures == contents.namedCreatures)
        #expect(facts.containers == ItemContainer.containers(inChunk: saved))
        #expect(facts.signs == Sign.signs(inChunk: saved) && facts.spawners == Spawner.spawners(inChunk: saved))
        #expect(facts.containers.map(\.kind) == ["minecraft:chest", "minecraft:zombified_piglin"])
        #expect(facts.containers.map { $0.items.first?.id } == ["minecraft:short_grass", "minecraft:short_grass"])
        #expect(facts.containers.map { $0.items.first?.count } == [3, 3])
        #expect(facts.signs.first?.front.first == "Saved sign")
        #expect(facts.spawners.map(\.mob) == ["minecraft:zombified_piglin"])
        #expect(facts.creatures.map(\.id) == ["minecraft:zombified_piglin"])
        #expect(facts.creatures.first?.y == 65 && facts.inhabitedTimes[0] == 47)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == facts.creatures)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == facts.creatures)
        #expect(try dimension.inhabitedTimes(regionX: 0, regionZ: 0) == facts.inhabitedTimes)
        let raw = try dimension.entities(chunkX: 0, chunkZ: 0)
        #expect(raw == [vehicle, rider])
        if kind == .modern || kind == .legacy {
            let chunk = try #require(try dimension.chunk(x: 0, z: 0))
            #expect(facts.formats.readable == 1 && facts.formats.legacy == 0)
            #expect(chunk.block(x: 0, y: 64, z: 0)?.id == "minecraft:stone")
            #expect(chunk.blockEntities.map(\.id) == ["minecraft:chest", "minecraft:oak_sign", "minecraft:mob_spawner"])
            #expect(chunk.blockEntity(x: 3, y: 64, z: 4) == chunk.blockEntities.first)
            #expect(try dimension.entities(in: chunk) == raw)
        } else {
            #expect(facts.chunks.isEmpty && facts.formats.readable == 0)
            #expect(facts.formats.legacy == (kind == .numeric ? 1 : 0))
            #expect(facts.formats.unreadableTerrain == (kind == .numeric ? 0 : 1))
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func conflictingAndMalformedRootFieldsRetainTheirOwnFallbackRules() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let oldBlocks = blockRecords(x: 7)
        let rootFields: [NBT?] = [nil, .string("malformed"), .list([]), .list(blockRecords(x: 1))]
        for (index, rootBlocks) in rootFields.enumerated() {
            var fields = try #require(Fixtures.chunk(x: 0, z: 0, dataVersion: 2508, sections: []).compound)
            fields["block_entities"] = rootBlocks
            fields["entities"] = .list([])
            fields["InhabitedTime"] = .string("malformed")
            fields["structures"] = .compound(["starts": .string("malformed")])
            fields["Level"] = .compound(["TileEntities": .list(oldBlocks), "Entities": .list([vehicle]),
                "InhabitedTime": .long(47), "Structures": .compound(["Starts": starts])])
            let nbt = NBT.compound(fields)
            _ = try write(nbt, to: dimension)
            let facts = try dimension.scan(region: region)
            let contents = try dimension.contents(regionX: 0, regionZ: 0)
            #expect(facts.containers == contents.containers && facts.signs == contents.signs && facts.spawners == contents.spawners)
            let expectedBlockX: [Int] = index == 0 ? [7] : (index == 3 ? [1] : [])
            let expectedTextX: [Int] = index < 2 ? [7] : (index == 3 ? [1] : [])
            #expect(facts.containers.filter { !$0.isEntity }.map(\.x) == expectedBlockX)
            #expect(facts.signs.map(\.x) == expectedTextX && facts.spawners.map(\.x) == expectedTextX)
            #expect(facts.creatures.map(\.id) == ["minecraft:zombified_piglin"])
            #expect(facts.inhabitedTimes[0] == 47 && facts.structures.isEmpty)
            #expect(Chunk.inhabitedTime(in: nbt) == 47 && StructureStart.starts(inChunk: nbt).isEmpty)
            let blockPositions = try Chunk(nbt: nbt).blockEntities.compactMap { $0.position?.x }
            #expect(blockPositions == expectedBlockX.flatMap { [$0, $0, $0] })
        }
    }

    private var starts: NBT {
        .compound(["example:structure": .compound(["ChunkX": .int(0), "ChunkZ": .int(0),
            "Children": .list([.compound(["id": .string("example:piece"), "BB": .intArray([0, 1, 2, 3, 4, 5])])])])])
    }

    @Test func legacyTerrainMergeKeepsItsExistingPrecedenceAndRawRecordQueries() throws {
        var fields = try #require(terrain(.legacy).compound)
        fields["block_entities"] = .list(blockRecords(x: 1))
        fields["InhabitedTime"] = .long(91)
        let nbt = NBT.compound(fields)
        let chunk = try Chunk(nbt: nbt)
        #expect(chunk.blockEntities.compactMap { $0.position?.x } == [3, 3, 3])
        #expect(chunk.inhabitedTime == 47)
        #expect(ItemContainer.containers(inChunk: nbt).filter { !$0.isEntity }.map(\.x) == [1])
        #expect(Chunk.inhabitedTime(in: nbt) == 91)
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        _ = try write(nbt, to: dimension)
        let facts = try dimension.scan(region: region)
        #expect(facts.containers == ItemContainer.containers(inChunk: nbt))
        #expect(facts.inhabitedTimes[0] == 91)
        #expect(try dimension.entities(in: chunk) == [vehicle, rider])
    }

    @Test func separateEntityFilesKeepTheirOwnVersionsAndRawPassengerRecords() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        _ = try write(terrain(.legacy), to: dimension)
        let separate = NBT.compound(["DataVersion": .int(Int32.max), "Entities": .list([vehicle])])
        let url = try write(separate, to: dimension, folder: .entities)
        let original = try Data(contentsOf: url)
        let facts = try dimension.scan(region: region)
        #expect(facts.creatures.map(\.id) == ["minecraft:zombified_piglin", "minecraft:zombie_pigman"])
        #expect(facts.containers.filter(\.isEntity).map { $0.items.first?.id } == ["minecraft:short_grass", "minecraft:grass"])
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == facts.creatures)
        #expect(try dimension.contents(regionX: 0, regionZ: 0).containers == facts.containers)
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0) == [vehicle, rider, vehicle, rider])
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func missingAndMalformedEmbeddedListsDoNotFallThroughToAnotherSource() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let fields: [String: NBT] = ["DataVersion": .int(2508), "entities": .list([vehicle])]
        for embedded in [NBT.string("malformed"), .list([])] {
            let nbt = NBT.compound(fields.merging(["Level": .compound(["Entities": embedded])]) { $1 })
            _ = try write(nbt, to: dimension)
            #expect(ItemContainer.containers(inChunk: nbt).isEmpty)
            #expect(try dimension.creatures(chunkX: 0, chunkZ: 0).isEmpty)
            #expect(try dimension.scan(region: region).creatures.isEmpty)
        }
        #expect(ItemContainer.containers(inChunk: .compound(fields)).map(\.kind) == ["minecraft:zombified_piglin"])
    }
}
