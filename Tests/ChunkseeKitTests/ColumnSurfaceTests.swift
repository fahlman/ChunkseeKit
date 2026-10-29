import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct ColumnSurfaceTests {
    @Test func defaultNamespaceAirDoesNotSupplyASurface() throws {
        for id in ["air", "cave_air", "void_air", ":air", ":cave_air", ":void_air",
                   "minecraft:air", "minecraft:cave_air", "minecraft:void_air"] {
            let chunk = try decode([Fixtures.section(y: 0, palette: [.string(id)])])
            #expect(chunk.surfaceY(x: 8, z: 8) == nil, "Air spelling: \(id)")
            #expect(chunk.surfaceHeights().allSatisfy { $0 == nil }, "Air spelling: \(id)")
            #expect(chunk.block(x: 8, y: 0, z: 8)?.id == id)
        }
        var blocks = [Int](repeating: 0, count: 4096)
        blocks[8 * 16 + 8] = 1
        let mixed = try decode([Fixtures.section(y: 0, palette: [.string("air"), .string("stone")], indices: blocks)])
        #expect(mixed.surfaceY(x: 8, z: 8) == 0 && mixed.surfaceHeights()[8 * 16 + 8] == 0)
        for id in ["example:air", "example:cave_air", "example:void_air", "minecraft:stone"] {
            let chunk = try decode([Fixtures.section(y: 0, palette: [.string(id)])])
            #expect(chunk.surfaceY(x: 8, z: 8) == 15)
        }
    }

    @Test func missingHeightmapsSampleTheActualMiddleColumn() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        var blocks = [Int](repeating: 0, count: 4096)
        blocks[1 * 256 + 8 * 16 + 8] = 1
        let biomes = (0..<64).map { $0 < 16 ? 1 : 0 }
        let ground = Fixtures.section(y: 3, palette: [.string("minecraft:air"), .string("minecraft:stone")],
                                      indices: blocks, biomes: ["minecraft:plains", "minecraft:desert"],
                                      biomeIndices: biomes)
        let unusedStone = Fixtures.section(y: 4, palette: [.string("minecraft:air"), .string("minecraft:stone")],
                                          indices: [Int](repeating: 0, count: 4096), biomes: ["minecraft:snowy_taiga"])
        blocks[1 * 256 + 8 * 16 + 8] = 0
        blocks[0] = 1 // A neighboring column must not supply this column's surface.
        let neighbor = Fixtures.section(y: 3, palette: [.string("minecraft:air"), .string("minecraft:stone")],
                                        indices: blocks, biomes: ["minecraft:plains"])
        let chunks = [[ground, unusedStone], [neighbor], [unusedStone]].enumerated().map { index, sections in
            Fixtures.RegionChunk(localX: index, localZ: 0,
                nbt: Fixtures.chunk(x: index, z: 0, dataVersion: 5023, sections: sections, extra: ["yPos": .int(0)]))
        }
        try Fixtures.write(Fixtures.region(chunks),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        let dimension = try #require(World(contentsOf: root).dimension("minecraft:overworld"))
        let facts = try dimension.scan(region: .init(x: 0, z: 0), options: .init(blockIDs: []))
        let samples = Dictionary(uniqueKeysWithValues: facts.chunks.map { ($0.position.x, $0.sampledBiome) })
        #expect(samples[0] == .some("minecraft:desert"))
        #expect(samples[1] == .some(nil))
        #expect(samples[2] == .some(nil))
        let explicit = try dimension.scan(region: .init(x: 0, z: 0), options: .init(blockIDs: [], biomeSampleY: 79))
        #expect(explicit.chunks.first?.sampledBiome == "minecraft:snowy_taiga")
    }

    @Test func batchAndSingleQueriesFindEachColumnsReferencedBlock() throws {
        var blocks = [Int](repeating: 0, count: 4096)
        let expected = (0..<256).map { ($0 * 7) % 16 - 16 }
        for i in 0..<256 { blocks[(expected[i] + 16) * 256 + i] = 1 }
        let section = Fixtures.section(y: -1, palette: [.string("minecraft:cave_air"), .string("minecraft:stone")], indices: blocks)
        let air = Fixtures.section(y: 2, palette: [.string("minecraft:void_air")])
        let chunk = try decode([section, air])
        #expect(chunk.surfaceHeights() == expected.map(Optional.some))
        for i in 0..<256 { #expect(chunk.surfaceY(x: i % 16, z: i / 16) == expected[i]) }
        #expect(chunk.surfaceY(x: -1, z: -1) == expected[255])
        #expect(chunk.surfaceY(x: 16, z: 16) == expected[0])
        #expect(chunk.surfaceY(x: Int.max, z: Int.min) == expected[15])
    }

    @Test func uniformSectionsGapsAndEmptyColumnsHaveNoInventedSurface() throws {
        let stone = Fixtures.section(y: -2, palette: [.string("minecraft:stone")])
        let air = Fixtures.section(y: 4, palette: [.string("minecraft:air")])
        let void = Fixtures.section(y: 2, palette: [.string("minecraft:void_air")])
        let cave = Fixtures.section(y: 1, palette: [.string("minecraft:cave_air")])
        #expect(try decode([stone, air, void, cave]).surfaceHeights() == [Int?](repeating: -17, count: 256))
        #expect(try decode([air, void, cave]).surfaceHeights().allSatisfy { $0 == nil })
        #expect(try decode([]).surfaceY(x: 0, z: 0) == nil)
        let below = Fixtures.section(y: -5, palette: [.string("minecraft:stone")])
        #expect(try decode([below]).surfaceHeights().allSatisfy { $0 == nil })
    }

    @Test func savedHeightmapsKeepFirstFreeYAndEmptyColumnMeaning() throws {
        var values = [Int](repeating: 65, count: 256)
        values[0] = 0; values[255] = 384
        let stone = Fixtures.section(y: 0, palette: [.string("minecraft:stone")])
        let chunk = try decode([stone], extra: ["Heightmaps": .compound([
            "WORLD_SURFACE": .longArray(Fixtures.pack(values, bits: 9)),
        ])])
        let expected = values.map { $0 == 0 ? nil : $0 - 65 }
        #expect(chunk.surfaceHeights() == expected)
        #expect(chunk.surfaceHeights(height: 384) == expected)
        #expect(chunk.surfaceY(x: 0, z: 0) == nil)
        #expect(chunk.surfaceY(x: 1, z: 0, height: 384) == 0)
        #expect(chunk.surfaceY(x: 15, z: 15) == 319)
        for height in [0, -1, Int.max] {
            #expect(chunk.surfaceY(x: 1, z: 0, height: height) == nil)
            #expect(chunk.surfaceHeights(height: height).allSatisfy { $0 == nil })
        }
    }

    @Test func unavailableOrAmbiguousHeightmapsUseBlocksUnlessHeightResolvesThem() throws {
        let stone = Fixtures.section(y: 0, palette: [.string("minecraft:stone")])
        let bad = try decode([stone], extra: ["Heightmaps": .compound(["WORLD_SURFACE": .longArray([0])])])
        #expect(bad.surfaceHeights() == [Int?](repeating: 15, count: 256))
        let packed = Fixtures.pack([Int](repeating: 3000, count: 256), bits: 12)
        let tall = try decode([], extra: ["yPos": .int(-127),
            "Heightmaps": .compound(["WORLD_SURFACE": .longArray(packed)]),
        ])
        #expect(tall.surfaceHeights().allSatisfy { $0 == nil })
        #expect(tall.surfaceHeights(height: 4000) == [Int?](repeating: 967, count: 256))
        #expect(tall.surfaceY(x: 3, z: 5, height: 4000) == 967)
        let fallback = try decode([stone], extra: ["Heightmaps": .compound(["WORLD_SURFACE": .longArray(packed)])])
        #expect(fallback.surfaceY(x: 3, z: 5) == 15)
    }

    @Test func surfaceIncludesWaterAndPlantsInsteadOfUsingMotionBlocking() throws {
        var blocks = [Int](repeating: 0, count: 4096)
        blocks[13 * 256] = 1
        blocks[11 * 256 + 1] = 2
        let section = Fixtures.section(y: 2, palette: [.string("minecraft:air"), .string("minecraft:short_grass"),
                                                     .string("minecraft:water")], indices: blocks)
        let chunk = try decode([section], extra: ["Heightmaps": .compound([
            "MOTION_BLOCKING": .longArray(Fixtures.pack([Int](repeating: 80, count: 256), bits: 9)),
        ])])
        var expected = [Int?](repeating: nil, count: 256)
        expected[0] = 45; expected[1] = 43
        #expect(chunk.surfaceHeights() == expected)
        #expect(chunk.surfaceY(x: 0, z: 0) == 45 && chunk.surfaceY(x: 1, z: 0) == 43)
    }

    @Test func malformedReferencesAndExtremeSavedBottomsStayUnavailable() throws {
        var blocks = [Int](repeating: 0, count: 4096)
        blocks[15 * 256] = 7 // Unknown block above a known stone cannot prove a surface.
        blocks[0] = 1; blocks[3 * 256 + 1] = 1
        let section = Fixtures.section(y: 0, palette: [.string("minecraft:air"), .string("minecraft:stone")], indices: blocks)
        let chunk = try decode([section])
        #expect(chunk.surfaceY(x: 0, z: 0) == nil && chunk.surfaceHeights()[0] == nil)
        #expect(chunk.surfaceY(x: 1, z: 0) == 3 && chunk.surfaceHeights()[1] == 3)
        for value in [Int64.min, Int64.max] {
            let badBottom = try decode([section], extra: ["yPos": .long(value)])
            #expect(badBottom.surfaceHeights().allSatisfy { $0 == nil })
            #expect(badBottom.surfaceY(x: 1, z: 0) == nil)
        }
    }

    @Test func wideSavedSectionCoordinatesNarrowBeforeSurfaceQueries() throws {
        let section = Fixtures.section(y: 0, palette: [.string("minecraft:stone")])
        for (saved, sectionY, surfaceY) in [(Int64.min, 0, 15), (Int64.max, -1, -1)] {
            var fields = try #require(section.compound)
            fields["Y"] = .long(saved)
            let chunk = try decode([.compound(fields)])
            #expect(chunk.sections.map(\.y) == [sectionY])
            #expect(chunk.surfaceHeights() == [Int?](repeating: surfaceY, count: 256))
            #expect(chunk.surfaceY(x: 1, z: 0) == surfaceY)
        }
    }

    private func decode(_ sections: [NBT], extra: [String: NBT] = [:]) throws -> Chunk {
        let nbt = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: sections, extra: extra)
        return try Chunk(nbt: NBT.read(nbt.serialized()).value)
    }
}
