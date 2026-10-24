import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct ChunkBiomeSnapshotTests {
    @Test func biomeOnlyRegionReadKeepsSavedLayoutsWithoutBlockData() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blockPalette: [NBT] = [.string("minecraft:stone"), .string("minecraft:dirt")]
        let blocks = (0..<4096).map { $0 % 2 }
        let cells = (0..<64).map { $0 % 3 } // Includes unavailable palette references.
        let perBlock = (0..<4096).map { $0 % 2 }
        let sections = [
            Fixtures.section(y: -4, palette: blockPalette, indices: blocks,
                             biomes: ["minecraft:plains", "minecraft:desert"], biomeIndices: cells, biomeBits: 2),
            Fixtures.section(y: -2, palette: blockPalette, indices: blocks,
                             biomes: ["minecraft:swamp", "minecraft:jungle"], biomeIndices: perBlock),
            Fixtures.section(y: 0, palette: blockPalette, indices: blocks, biomes: ["minecraft:forest"]),
            NBT.compound(["Y": .byte(1), "BlockLight": .byteArray([Int8](repeating: -1, count: 2048))]),
        ]
        let nbt = Fixtures.chunk(x: -33, z: 32, sections: sections, extra: [
            "Heightmaps": .compound(["WORLD_SURFACE": .longArray(Fixtures.pack([Int](repeating: 64, count: 256), bits: 9))]),
            "isLightOn": .byte(1),
        ])
        let url = root.appendingPathComponent("r.-2.1.mca")
        try Data(Fixtures.region([.init(localX: 31, localZ: 0, nbt: nbt)])).write(to: url)
        let file = try RegionFile(contentsOf: url)
        let fullNBT = try #require(try file.chunkNBT(localX: 31, localZ: 0))
        let full = try Chunk(nbt: fullNBT)
        let filtered = try #require(try file.chunkNBT(localX: 31, localZ: 0, skipping: Chunk.keysNotNeededForBiomes))
        let reduced = try Chunk(nbt: filtered)
        #expect(reduced.x == -33 && reduced.z == 32 && reduced.isFullyGenerated)
        #expect(reduced.sections.map(\.y) == full.sections.map(\.y))
        #expect(full.heightmapNames == ["WORLD_SURFACE"])
        #expect(reduced.heightmapNames.isEmpty && !reduced.isLightOn)
        #expect(reduced.sections.allSatisfy { $0.blockStates == nil && $0.blockLight == nil && $0.skyLight == nil })
        let snapshot = reduced.biomeSnapshot
        let fullSnapshot = full.biomeSnapshot
        for y in -80..<48 {
            #expect(snapshot.hasPerBlockBiomes(atBlockY: y) == fullSnapshot.hasPerBlockBiomes(atBlockY: y))
            for z in 0..<16 {
                for x in 0..<16 { #expect(snapshot.biome(x: x, y: y, z: z) == full.biome(x: x, y: y, z: z)) }
            }
        }
        #expect(snapshot.biome(x: 0, y: -64, z: 0) == "minecraft:plains")
        #expect(snapshot.biome(x: 8, y: -64, z: 0) == nil)
        #expect(snapshot.hasPerBlockBiomes(atBlockY: -32) == true)
        #expect(snapshot.hasPerBlockBiomes(atBlockY: 16) == nil)
    }

    @Test func biomeOnlyReadDoesNotValidateSkippedBlockPalettes() throws {
        let section = Fixtures.section(y: 0, palette: [.int(42)], biomes: ["minecraft:plains"])
        let bytes = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [section]).serialized()
        #expect(throws: ChunkError.self) { try Chunk(nbt: NBT.read(bytes).value) }
        let chunk = try Chunk(nbt: NBT.read(bytes, skipping: Chunk.keysNotNeededForBiomes).value)
        #expect(chunk.biomeSnapshot.biome(x: 0, y: 0, z: 0) == "minecraft:plains")
        #expect(chunk.block(x: 0, y: 0, z: 0) == nil)
    }

    @Test func biomeOnlyReadStillRejectsMalformedBiomesAndSectionIdentity() throws {
        let sections: [NBT] = [
            .compound(["Y": .byte(0), "biomes": .compound(["palette": .list([.int(42)])])]),
            .compound(["Y": .byte(0), "biomes": .compound(["palette": .list([.string("minecraft:plains"), .string("minecraft:desert")])])]),
            .compound(["biomes": .compound(["palette": .list([.string("minecraft:plains")])])]),
        ]
        for section in sections {
            let bytes = Fixtures.chunk(x: 0, z: 0, sections: [section]).serialized()
            let filtered = try NBT.read(bytes, skipping: Chunk.keysNotNeededForBiomes).value
            #expect(throws: ChunkError.self) { try Chunk(nbt: filtered) }
        }
    }

    @Test(arguments: [(-64, 384, -64, 316), (0, 256, 0, 252), (-2032, 4064, -2032, 2028), (2016, 16, 2016, 2028)])
    func sourceCellHeightUsesTheSavedBuildRange(minY: Int, height: Int, firstCell: Int, lastCell: Int) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let type: NBT = .compound(["min_y": .int(Int32(minY)), "height": .int(Int32(height)),
                                   "logical_height": .int(0), "has_ceiling": .byte(1)])
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Biome Source"), "DataVersion": .int(5023),
            "WorldGenSettings": .compound(["dimensions": .compound([
                "example:source": .compound(["type": type])
            ])])
        ])]), to: root.appendingPathComponent("level.dat"))
        let dimension = try #require(World(contentsOf: root).dimensionTypes()["example:source"])
        let sampler = BiomeSampler(seed: 0)
        let lower = try #require(sampler.cellOrigin(at: BlockPosition(blockX: -1, blockY: -10000, blockZ: 0), in: dimension))
        let upper = try #require(sampler.cellOrigin(at: BlockPosition(blockX: -1, blockY: 10000, blockZ: 0), in: dimension))
        #expect(lower.y == firstCell && upper.y == lastCell)
        let inside = BlockPosition(blockX: -1, blockY: minY + height / 2, blockZ: 0)
        #expect(sampler.cellOrigin(at: inside, in: dimension) == sampler.cellOrigin(at: inside))
        #expect(sampler.cellOrigin(at: BlockPosition(blockX: Int.max, blockY: 0, blockZ: 0), in: dimension) == nil)
    }

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
