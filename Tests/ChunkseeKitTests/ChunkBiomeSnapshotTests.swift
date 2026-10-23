import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct ChunkBiomeSnapshotTests {
    @Test func retainedCellsKeepNegativeHeightsAndMissingData() throws {
        func read() throws -> ChunkBiomeSnapshot {
            var indices = [Int](repeating: 0, count: 64)
            indices[21] = 1
            indices[63] = 3 // An invalid palette reference must stay unavailable.
            let lower = Fixtures.section(y: -1, palette: [.compound(["Name": .string("minecraft:stone")])],
                                         biomes: ["minecraft:plains", "minecraft:desert"], biomeIndices: indices, biomeBits: 2)
            let upper = Fixtures.section(y: 1, palette: [.compound(["Name": .string("minecraft:stone")])],
                                         biomes: ["minecraft:jungle"])
            let noBiomes: NBT = .compound(["Y": .byte(2), "BlockLight": .byteArray([Int8](repeating: -1, count: 2048))])
            return try Chunk(nbt: Fixtures.chunk(x: -1, z: 0, dataVersion: 5023,
                                                sections: [lower, upper, noBiomes])).biomeSnapshot
        }
        let view = try read() // The full chunk is no longer needed by the caller.
        #expect(view.biome(x: 0, y: -16, z: 0) == "minecraft:plains")
        #expect(view.biome(x: 4, y: -12, z: 4) == "minecraft:desert")
        #expect(view.biome(x: -9, y: -9, z: -9) == "minecraft:desert")
        #expect(view.biome(x: 15, y: -1, z: 15) == nil)
        #expect(view.biome(x: 0, y: 16, z: 0) == "minecraft:jungle")
        for y in [Int.min, -17, 0, 15, 32, Int.max] {
            #expect(view.biome(x: 0, y: y, z: 0) == nil)
            #expect(view.hasPerBlockBiomes(atBlockY: y) == nil)
        }
        #expect(view.hasPerBlockBiomes(atBlockY: -12) == false)
        #expect(view.hasPerBlockBiomes(atBlockY: 16) == false)
    }

    @Test func perBlockPalettesStayPerBlockInTheSnapshot() throws {
        var indices = [Int](repeating: 0, count: 4096)
        indices[281] = 1 // x=9, y=1, z=1 in the independently packed fixture.
        let section = Fixtures.section(y: -1, palette: [.compound(["Name": .string("minecraft:air")])],
                                       biomes: ["minecraft:plains", "minecraft:swamp"], biomeIndices: indices)
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [section]))
        let view = chunk.biomeSnapshot
        #expect(view.hasPerBlockBiomes(atBlockY: -15) == true)
        #expect(view.biome(x: 9, y: -15, z: 1) == "minecraft:swamp")
        #expect(view.biome(x: 8, y: -15, z: 1) == "minecraft:plains")
        for y in -16..<0 {
            for z in 0..<16 {
                for x in 0..<16 { #expect(view.biome(x: x, y: y, z: z) == chunk.biome(x: x, y: y, z: z)) }
            }
        }
    }

    @Test func sparseAndDuplicateSectionsKeepTheOriginalLookup() throws {
        let sections = [(-4, "minecraft:plains"), (-2, "minecraft:desert"), (-2, "minecraft:jungle")].map { y, biome in
            Fixtures.section(y: y, palette: [.compound(["Name": .string("minecraft:air")])], biomes: [biome])
        }
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: sections))
        let view = chunk.biomeSnapshot
        // Preserve the existing contiguous-index fast path even for a malformed duplicate Y.
        #expect(view.biome(x: 0, y: -32, z: 0) == "minecraft:jungle")
        for y in -80...16 {
            #expect(view.biome(x: 0, y: y, z: 0) == chunk.biome(x: 0, y: y, z: 0))
            #expect(view.hasPerBlockBiomes(atBlockY: y) == chunk.section(atBlockY: y).map(\.hasPerBlockBiomes))
        }
    }
}
