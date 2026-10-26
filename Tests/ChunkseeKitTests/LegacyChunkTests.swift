import CoreFoundation
import Foundation
import Testing
import ChunkseeKitTestSupport
@testable import ChunkseeKit

extension GeneratedLegacyChunkProofs.Record: CustomTestStringConvertible {
    var testDescription: String { "\(name), saved \(version)" }
}

@Suite struct LegacyChunkTests {
    @Test(arguments: GeneratedLegacyChunkProofs.records)
    func savedTerrainMatchesMinecraftCompleteUpgrade(_ record: GeneratedLegacyChunkProofs.Record) throws {
        let input = try jsonNBT(record.input)
        let output = try jsonNBT(record.output)
        let original = input
        let actual = try Chunk(nbt: input)
        let expected = try Chunk(nbt: output)
        #expect(actual.x == expected.x && actual.z == expected.z)
        #expect(actual.minSectionY == expected.minSectionY)
        #expect(actual.lastUpdate == expected.lastUpdate && actual.inhabitedTime == expected.inhabitedTime)
        #expect(actual.isLightOn == expected.isLightOn)
        #expect(Identifier(actual.status ?? "") == Identifier(expected.status ?? ""))
        #expect(actual.sections.map(\.y) == expected.sections.map(\.y))
        for (section, reference) in zip(actual.sections, expected.sections) {
            let blocks = (0..<4096).map { section.blockStates?[$0] }
            let referenceBlocks = (0..<4096).map { reference.blockStates?[$0] }
            #expect(blocks == referenceBlocks, "\(record.name), saved \(record.version), section \(section.y)")
            let biomes = (0..<64).map { section.biomes?[$0] }
            let referenceBiomes = (0..<64).map { reference.biomes?[$0] }
            #expect(biomes == referenceBiomes, "\(record.name), saved \(record.version), section \(section.y)")
            #expect(section.blockLight == reference.blockLight && section.skyLight == reference.skyLight)
        }
        #expect(actual.heightmapNames == expected.heightmapNames)
        for name in expected.heightmapNames { #expect(actual.heightmap(name) == expected.heightmap(name)) }
        #expect(actual.blockEntities == expected.blockEntities)
        #expect(ItemContainer.containers(inChunk: input) == ItemContainer.containers(inChunk: output))
        #expect(input == original)
    }

    @Test func ordinaryRegionReadRetainsOldTerrainAndEmbeddedMobs() throws {
        let record = try #require(GeneratedLegacyChunkProofs.records.first { $0.name == "palette-17" })
        let nbt = try jsonNBT(record.input)
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let position = ChunkPosition(x: 2, z: -3)
        let url = dimension.regionURL(at: position.region)
        try Fixtures.write(Fixtures.region([.init(localX: position.localX, localZ: position.localZ, nbt: nbt)]), to: url)
        let before = try Data(contentsOf: url)
        let loaded = try dimension.chunk(at: position)
        let chunk = try #require(loaded)
        #expect(chunk.isFullyGenerated && chunk.block(x: 0, y: 64, z: 0)?.id == "minecraft:short_grass")
        let facts = try dimension.scan(region: position.region)
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 0)
        #expect(facts.creatures.map(\.id) == ["minecraft:cow"])
        #expect(try dimension.creatures(chunkX: position.x, chunkZ: position.z) == facts.creatures)
        #expect(try dimension.creatures(regionX: position.region.x, regionZ: position.region.z) == facts.creatures)
        #expect(try dimension.entities(chunkX: position.x, chunkZ: position.z).count == 1)
        #expect(try dimension.entities(in: chunk) == dimension.entities(chunkX: position.x, chunkZ: position.z))
        #expect(try dimension.containers(regionX: position.region.x, regionZ: position.region.z) == facts.containers)
        #expect(facts.containers.first?.items.first?.id == "minecraft:short_grass")
        #expect(facts.chunks.first?.isFullyGenerated == true)
        #expect(facts.inhabitedTimes[position.localZ * 32 + position.localX] == 345)
        let file = try RegionFile(contentsOf: url)
        let terrainNBT = try file.chunkNBT(localX: position.localX, localZ: position.localZ,
                                           skipping: Chunk.keysNotNeededForTerrain)
        let terrain = try Chunk(nbt: #require(terrainNBT))
        #expect(terrain.block(x: 0, y: 64, z: 0) == chunk.block(x: 0, y: 64, z: 0))
        #expect(terrain.heightmap("WORLD_SURFACE") == chunk.heightmap("WORLD_SURFACE"))
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Legacy layout"), "DataVersion": .int(Int32(record.version)),
        ])]), to: root.appendingPathComponent("level.dat"))
        let scan = try Fixtures.runCLI(root, command: "scan", arguments: ["overworld"])
        #expect(scan.status == 0 && scan.output.contains("1 chunks, 16 sections, 1 chunks with entities"))
        let mobs = try Fixtures.runCLI(root, command: "creatures", arguments: ["overworld"])
        #expect(mobs.status == 0 && mobs.output.contains("1 minecraft:cow"))
        let separate = NBT.compound(["DataVersion": .int(2508), "Entities": .list([
            Fixtures.mob(["id": .string("minecraft:zombie_pigman"),
                          "Pos": .list([.double(33), .double(70), .double(-47)])]),
        ])])
        try Fixtures.write(Fixtures.region([.init(localX: position.localX, localZ: position.localZ, nbt: separate)]),
                           to: dimension.regionURL(.entities, at: position.region))
        let mixed = try dimension.scan(region: position.region)
        #expect(mixed.creatures.map(\.id) == ["minecraft:cow", "minecraft:zombified_piglin"])
        #expect(try dimension.creatures(chunkX: position.x, chunkZ: position.z) == mixed.creatures)
        #expect(try dimension.creatures(regionX: position.region.x, regionZ: position.region.z) == mixed.creatures)
        #expect(try dimension.entities(in: chunk).count == 2)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func unfamiliarMetadataDoesNotHideReadablePalettesAndBadPackingFailsSafely() throws {
        let record = try #require(GeneratedLegacyChunkProofs.records.first { $0.name == "palette-17" })
        let nbt = try jsonNBT(record.input)
        for version in [nil, Int32.max] as [Int32?] {
            var fields = try #require(nbt.compound)
            fields["DataVersion"] = version.map(NBT.int)
            let chunk = try Chunk(nbt: .compound(fields))
            #expect(chunk.block(x: 1, y: 64, z: 0)?.id == "example:block_1")
            #expect(chunk.heightmap("WORLD_SURFACE")?.first == 80)
        }
        var fields = try #require(nbt.compound)
        var level = try #require(fields["Level"]?.compound)
        var sections = try #require(level["Sections"]?.list)
        var section = try #require(sections.first?.compound)
        section["BlockStates"] = .longArray([0])
        sections[0] = .compound(section); level["Sections"] = .list(sections); fields["Level"] = .compound(level)
        #expect(throws: ChunkError.self) { try Chunk(nbt: .compound(fields)) }
    }

    private func jsonNBT(_ text: String) throws -> NBT {
        func convert(_ object: Any, key: String = "", parent: String = "") -> NBT {
            if let value = object as? String { return .string(value) }
            if let value = object as? NSNumber {
                if CFGetTypeID(value) == CFBooleanGetTypeID() { return .byte(value.boolValue ? 1 : 0) }
                if String(cString: value.objCType) == "d" { return .double(value.doubleValue) }
                return .long(value.int64Value)
            }
            if let values = object as? [Any] {
                if key == "Pos" { return .list(values.map { .double(($0 as! NSNumber).doubleValue) }) }
                if key == "BlockLight" || key == "SkyLight" { return .byteArray(values.map { ($0 as! NSNumber).int8Value }) }
                if key == "BlockStates" || (key == "data" && ["block_states", "biomes"].contains(parent)) || parent == "Heightmaps" {
                    return .longArray(values.map { ($0 as! NSNumber).int64Value })
                }
                if key == "Biomes" || key == "UUID" { return .intArray(values.map { ($0 as! NSNumber).int32Value }) }
                return .list(values.map { convert($0) })
            }
            let fields = object as! [String: Any]
            return .compound(Dictionary(uniqueKeysWithValues:
                fields.map { ($0.key, convert($0.value, key: $0.key, parent: key)) }))
        }
        return convert(try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }
}
