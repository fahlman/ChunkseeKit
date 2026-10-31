import ChunkseeKitTestSupport
import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct ChunkPrimitiveFieldTests {
    func saved(_ sample: SavedNumericSample) throws -> NBT {
        var section = try #require(Fixtures.section(y: 0, palette: [.string("minecraft:stone")]).compound)
        section["Y"] = sample.tag
        section["BlockLight"] = .byteArray([Int8](repeating: 0x33, count: 2048))
        section["SkyLight"] = .byteArray([Int8](repeating: 0x55, count: 2048))
        return Fixtures.chunk(x: 0, z: 0, sections: [.compound(section)], extra: [
            "xPos": sample.tag, "zPos": sample.tag, "LastUpdate": sample.tag,
            "InhabitedTime": sample.tag, "isLightOn": sample.tag,
        ])
    }

    @Test(arguments: SavedNumericSample.all)
    func publicChunkReadsMatchMinecraft(_ sample: SavedNumericSample) throws {
        let bytes = try saved(sample).serialized()
        let decoded = try NBT.read(bytes).value
        let chunk = try Chunk(nbt: decoded)
        #expect(chunk.x == sample.intValue && chunk.z == sample.intValue)
        #expect(chunk.sections.map(\.y) == [sample.byteValue])
        #expect(chunk.lastUpdate == sample.longValue && chunk.inhabitedTime == sample.longValue)
        #expect(Chunk.inhabitedTime(in: decoded) == sample.longValue)
        #expect(chunk.isLightOn == sample.booleanValue)
        let y = sample.byteValue * 16
        #expect(chunk.block(x: 0, y: y, z: 0)?.id == "minecraft:stone")
        #expect(chunk.biomeSnapshot.biome(x: 0, y: y, z: 0) == "minecraft:plains")
        #expect(chunk.blockLight(x: 0, y: y, z: 0) == (sample.booleanValue ? 3 : nil))
        #expect(chunk.resolvedBlockLight(x: 0, y: y, z: 0) == (sample.booleanValue ? 3 : nil))
        #expect(chunk.skyLight(x: 0, y: y, z: 0) == (sample.booleanValue ? 5 : nil))
        // Reading/interpreting must retain the exact numeric tags, including exceptional bits.
        #expect(decoded.serialized() == bytes)
    }

    @Test func combinedRegionAndSelectiveReadsUseTheSameFieldRules() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let position = RegionPosition(x: 0, z: 0)
        let entries = try SavedNumericSample.all.enumerated().map { index, sample in
            Fixtures.RegionChunk(localX: index % 32, localZ: index / 32, nbt: try saved(sample))
        }
        let bytes = try Fixtures.region(entries)
        let url = dimension.regionURL(.terrain, at: position)
        try Fixtures.write(bytes, to: url)
        let facts = try dimension.scan(region: position)
        #expect(facts.formats.readable == entries.count && facts.formats.unreadableTerrain == 0)
        #expect(facts.inhabitedTimes == (try dimension.inhabitedTimes(regionX: 0, regionZ: 0)))
        for (index, sample) in SavedNumericSample.all.enumerated() {
            let at = ChunkPosition(x: index % 32, z: index / 32)
            let terrain = try #require(facts.chunks.first { $0.position == at })
            // Region identity belongs to the file slot even when the saved coordinates differ.
            #expect(terrain.blockDeposits == [.init(id: "minecraft:stone", count: 4096,
                minY: sample.byteValue * 16, maxY: sample.byteValue * 16 + 15)], "\(sample)")
            #expect(facts.inhabitedTimes[index] == sample.longValue, "\(sample)")
        }
        #expect(try Data(contentsOf: url) == Data(bytes))
    }

    var absentOrNonnumeric: [NBT?] {
        [nil, .string(""), .string("1"), .string("true"), .compound([:]), .list([]),
         .list([.int(1)]), .byteArray([1]), .intArray([1]), .longArray([1])]
    }

    @Test func requiredIdentityAndOptionalMetadataKeepSavedPresence() throws {
        let original = try #require(Fixtures.chunk(x: 1, z: -2, sections: []).compound)
        for invalid in absentOrNonnumeric {
            for key in ["xPos", "zPos"] {
                var fields = original
                fields[key] = invalid
                #expect(throws: ChunkError.missingField("xPos/zPos")) {
                    try Chunk(nbt: NBT.read(NBT.compound(fields).serialized()).value)
                }
            }
            var section: [String: NBT] = [:]
            section["Y"] = invalid
            var fields = original
            fields["sections"] = .list([.compound(section)])
            #expect(throws: ChunkError.missingField("sections[].Y")) {
                try Chunk(nbt: NBT.read(NBT.compound(fields).serialized()).value)
            }
            fields["sections"] = .list([])
            for key in ["LastUpdate", "InhabitedTime", "isLightOn"] { fields[key] = invalid }
            let nbt = try NBT.read(NBT.compound(fields).serialized()).value
            let chunk = try Chunk(nbt: nbt)
            #expect(chunk.lastUpdate == nil && chunk.inhabitedTime == nil && !chunk.isLightOn)
            #expect(Chunk.inhabitedTime(in: nbt) == nil)
            #expect(chunk.x == 1 && chunk.z == -2)
        }
    }

    @Test func inhabitedTimeRemainsIndependentOfTerrainAndKeepsFallbackPrecedence() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let position = RegionPosition(x: 0, z: 0)
        let source: [(NBT?, Int)] = absentOrNonnumeric.map { ($0, -2) }
            + [(.double(-0.5), -1), (.float(-0.5), 0), (.long(0), 0)]
        let entries = source.enumerated().map { index, sample in
            var fields: [String: NBT] = [
                "xPos": .int(0), "zPos": .int(0), "sections": .list([.compound(["Y": .string("bad")])]),
                "Level": .compound(["InhabitedTime": .double(-1.5)]),
            ]
            fields["InhabitedTime"] = sample.0
            return Fixtures.RegionChunk(localX: index, localZ: 0, nbt: .compound(fields))
        }
        try Fixtures.write(Fixtures.region(entries), to: dimension.regionURL(.terrain, at: position))
        let facts = try dimension.scan(region: position)
        #expect(facts.chunks.isEmpty && facts.formats.unreadableTerrain == entries.count)
        #expect(facts.inhabitedTimes == (try dimension.inhabitedTimes(regionX: 0, regionZ: 0)))
        for (index, entry) in entries.enumerated() {
            #expect(Chunk.inhabitedTime(in: entry.nbt) == source[index].1)
            #expect(facts.inhabitedTimes[index] == source[index].1)
        }
    }

    @Test func wrappedTerrainUsesNormalizedFieldsWhileRecordsRetainRootPrecedence() throws {
        var section = try #require(Fixtures.section(y: 0, palette: [.string("minecraft:stone")]).compound)
        section["Y"] = .short(260)
        // Isolate root/Level selection from the older layout fixers' separate numeric rules.
        let source = NBT.compound(["DataVersion": .int(Int32.max), "InhabitedTime": .double(-0.5), "Level": .compound([
            "xPos": .double(-0.5), "zPos": .long(4_294_967_297), "Status": .string("full"),
            "Sections": .list([.compound(section)]), "InhabitedTime": .float(-0.5), "LastUpdate": .double(-1.5),
            "isLightOn": .int(256),
        ])])
        let decoded = try NBT.read(source.serialized()).value
        let chunk = try Chunk(nbt: decoded)
        #expect(chunk.x == -1 && chunk.z == 1 && chunk.sections.map(\.y) == [4])
        #expect(chunk.block(x: 0, y: 64, z: 0)?.id == "minecraft:stone")
        #expect(chunk.inhabitedTime == 0 && chunk.lastUpdate == -2 && !chunk.isLightOn)
        #expect(Chunk.inhabitedTime(in: decoded) == -1)
    }

    @Test func selectiveTerrainProfilesKeepTheirLightPolicy() throws {
        let sample = try #require(SavedNumericSample.all.first { $0.id == "double:negative-half" })
        let source = try saved(sample).serialized()
        for skipping in [Set<String>(), Chunk.keysNotNeededForTerrainAndLight,
                         Chunk.keysNotNeededForTerrain, Chunk.keysNotNeededForBiomes] {
            let chunk = try Chunk(nbt: NBT.read(source, skipping: skipping).value)
            #expect(chunk.x == -1 && chunk.z == -1 && chunk.sections.map(\.y) == [-1])
            #expect(chunk.inhabitedTime == -1)
            #expect(chunk.biomeSnapshot.biome(x: 0, y: -16, z: 0) == "minecraft:plains")
            let keepsLight = !skipping.contains("isLightOn")
            #expect(chunk.isLightOn == keepsLight)
            #expect(chunk.blockLight(x: 0, y: -16, z: 0) == (keepsLight ? 3 : nil))
        }
    }

    @Test func rawAccessorsAndCodecConversionsRemainDistinct() throws {
        let source = NBT.compound(["narrow": .long(4_294_967_297), "flag": .int(256),
            "fraction": .double(-0.5), "zero": .float(Float(bitPattern: 0x80000000))])
        let nbt = try NBT.read(source.serialized()).value
        #expect(nbt["narrow"]?.int == 4_294_967_297 && nbt["narrow"]?.javaInt == 1)
        #expect(nbt["flag"]?.bool == true)
        #expect(nbt["fraction"]?.int == nil && nbt["fraction"]?.javaInt == 0)
        #expect(nbt["fraction"]?.javaFloat == -0.5)
        #expect(nbt["zero"]?.double?.sign == .minus && nbt["zero"]?.javaFloat?.sign == .plus)
        #expect(nbt.serialized() == source.serialized())
    }
}
