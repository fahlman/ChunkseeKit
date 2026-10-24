import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct BiomeSamplerTests {
    // Coordinates captured from official 26.3 BiomeManager.getBiome with a recording source.
    // The origins are its quart coordinates multiplied by four without narrowing to Int32.
    private static let samples: [(Int64, Int, Int, Int, Int, Int, Int)] = [
        (0, 0, 0, 0, -4, 0, -4),
        (0, 1, 63, 1, 0, 60, 0),
        (0, -1, 64, -1, -4, 64, -4),
        (0, 15, 319, 15, 12, 316, 12),
        (0, -17, -65, -17, -20, -68, -20),
        (1, 0, 0, 0, 0, 0, 0),
        (1, 1, 63, 1, 0, 60, 0),
        (1, -1, 64, -1, -4, 60, -4),
        (1, 15, 319, 15, 12, 316, 12),
        (1, -17, -65, -17, -20, -68, -20),
        (-1, 0, 0, 0, 0, 0, -4),
        (-1, 1, 63, 1, 0, 60, 0),
        (-1, -1, 64, -1, -4, 64, -4),
        (-1, 15, 319, 15, 12, 316, 12),
        (-1, -17, -65, -17, -20, -64, -20),
        (-9223372036854775808, 0, 0, 0, 0, 0, 0),
        (-9223372036854775808, 1, 63, 1, 0, 60, 0),
        (-9223372036854775808, -1, 64, -1, -4, 64, 0),
        (-9223372036854775808, 15, 319, 15, 12, 316, 12),
        (-9223372036854775808, -17, -65, -17, -20, -68, -16),
        (9223372036854775807, 0, 0, 0, -4, 0, -4),
        (9223372036854775807, 1, 63, 1, 0, 60, 0),
        (9223372036854775807, -1, 64, -1, -4, 64, -4),
        (9223372036854775807, 15, 319, 15, 12, 316, 12),
        (9223372036854775807, -17, -65, -17, -20, -68, -16),
        (0, -2147483648, -2147483648, -2147483648, 2147483648, 2147483648, 2147483648),
        (0, -2147483647, -2147483647, -2147483647, 2147483648, 2147483648, 2147483648),
        (0, -2147483646, -2147483646, -2147483646, -2147483648, -2147483648, -2147483648),
        (0, 2147483645, 2147483645, 2147483645, 2147483644, 2147483644, 2147483644),
        (0, 2147483646, 2147483646, 2147483646, 2147483644, 2147483644, 2147483644),
        (0, 2147483647, 2147483647, 2147483647, 2147483648, 2147483644, 2147483644),
    ]

    @Test(arguments: samples)
    func selectedCellMatchesTheGame(seed: Int64, x: Int, y: Int, z: Int, cellX: Int, cellY: Int, cellZ: Int) {
        let sampler = BiomeSampler(seed: seed)
        let result = sampler.cellOrigin(at: BlockPosition(blockX: x, blockY: y, blockZ: z))
        #expect(result == BlockPosition(blockX: cellX, blockY: cellY, blockZ: cellZ))
        let block = BlockPosition(blockX: x, blockY: y, blockZ: z)
        let expected = BlockPosition(blockX: cellX, blockY: cellY, blockZ: cellZ)
        #expect(sampler.cellOrigins(at: [block, block]) == [expected, expected])
    }

    @Test(arguments: [Int64.min, -1, 0, 1, Int64.max])
    func nearbyBatchesPreserveScalarResultsAndInputOrder(seed: Int64) {
        let sampler = BiomeSampler(seed: seed)
        var blocks: [BlockPosition] = []
        for y in [-65, -64, -63, -1, 0, 63, 64, 65, 319] {
            for z in -18..<2 {
                for x in -2..<18 {
                    blocks.append(BlockPosition(blockX: x, blockY: y, blockZ: z))
                }
            }
        }
        let expected = blocks.map { sampler.cellOrigin(at: $0) }
        #expect(sampler.cellOrigins(at: blocks) == expected)
        #expect(sampler.cellOrigins(at: Array(blocks.reversed())) == Array(expected.reversed()))
        // A second grid must not reuse the first grid's coordinates or another seed's offsets.
        let translated = blocks.map { BlockPosition(blockX: $0.x + 17, blockY: $0.y + 3, blockZ: $0.z - 33) }
        let translatedExpected = translated.map { sampler.cellOrigin(at: $0) }
        #expect(sampler.cellOrigins(at: translated) == translatedExpected)
    }

    @Test func batchesKeepUnavailableEntriesAndRepeatedPositions() {
        let sampler = BiomeSampler(seed: 0)
        let first = BlockPosition(blockX: 1, blockY: 63, blockZ: 1)
        let second = BlockPosition(blockX: -1, blockY: 64, blockZ: -1)
        let invalid = BlockPosition(blockX: Int.max, blockY: 63, blockZ: 0)
        let expectedFirst = BlockPosition(blockX: 0, blockY: 60, blockZ: 0)
        let expectedSecond = BlockPosition(blockX: -4, blockY: 64, blockZ: -4)
        #expect(sampler.cellOrigins(at: []) == [])
        #expect(sampler.cellOrigins(at: [first]) == [expectedFirst])
        #expect(sampler.cellOrigins(at: [invalid, invalid]) == [nil, nil])
        #expect(sampler.cellOrigins(at: [first, invalid, second, first]) == [expectedFirst, nil, expectedSecond, expectedFirst])
    }

    @Test func sparseAndWrappedBatchBoundsStayAvailableWithoutOverflow() {
        let sampler = BiomeSampler(seed: Int64.min)
        let values = [Int.min, Int(Int32.min) - 1, Int(Int32.min), Int(Int32.min) + 1,
                      Int(Int32.min) + 2, -30_000_000, -1, 0, 1, 30_000_000,
                      Int(Int32.max), Int(Int32.max) + 1, Int.max]
        var blocks: [BlockPosition] = []
        for value in values {
            blocks.append(BlockPosition(blockX: value, blockY: 0, blockZ: 0))
            blocks.append(BlockPosition(blockX: 0, blockY: value, blockZ: 0))
            blocks.append(BlockPosition(blockX: 0, blockY: 0, blockZ: value))
            blocks.append(BlockPosition(blockX: value, blockY: value, blockZ: value))
        }
        let expected = blocks.map { sampler.cellOrigin(at: $0) }
        #expect(sampler.cellOrigins(at: blocks) == expected)
    }

    @Test func coordinatesOutsideTheGameIntegerRangeStayUnavailable() {
        let sampler = BiomeSampler(seed: 0)
        for value in [Int.min, Int.max, Int(Int32.min) - 1, Int(Int32.max) + 1] {
            #expect(sampler.cellOrigin(at: BlockPosition(blockX: value, blockY: 0, blockZ: 0)) == nil)
            #expect(sampler.cellOrigin(at: BlockPosition(blockX: 0, blockY: value, blockZ: 0)) == nil)
            #expect(sampler.cellOrigin(at: BlockPosition(blockX: 0, blockY: 0, blockZ: value)) == nil)
        }
    }

    @Test func selectedCellsReadTheNeighboringChunkAndSection() throws {
        let section0 = Fixtures.section(y: 0, palette: [.compound(["Name": .string("minecraft:air")])], biomes: ["minecraft:swamp"])
        let section3 = Fixtures.section(y: 3, palette: [.compound(["Name": .string("minecraft:air")])], biomes: ["minecraft:desert"])
        let section4 = Fixtures.section(y: 4, palette: [.compound(["Name": .string("minecraft:air")])], biomes: ["minecraft:plains"])
        let neighbor = try Chunk(nbt: Fixtures.chunk(x: -1, z: -1, dataVersion: 5023, sections: [section0, section3, section4]))
        let origin = try #require(BiomeSampler(seed: 0).cellOrigin(at: BlockPosition(blockX: 0, blockY: 0, blockZ: 0)))
        #expect(origin.chunk == ChunkPosition(x: -1, z: -1))
        #expect(neighbor.biome(x: origin.x & 15, y: origin.y, z: origin.z & 15) == "minecraft:swamp")

        let upper = BlockPosition(blockX: -1, blockY: 64, blockZ: -1)
        #expect(neighbor.biome(x: 15, y: upper.y, z: 15) == "minecraft:plains")
        let lower = try #require(BiomeSampler(seed: 1).cellOrigin(at: upper))
        #expect(lower.y == 60 && lower.chunk == upper.chunk)
        #expect(neighbor.biome(x: lower.x & 15, y: lower.y, z: lower.z & 15) == "minecraft:desert")
    }
}
