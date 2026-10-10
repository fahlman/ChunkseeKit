import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct ChunkTests {
    let air = NBT.string("minecraft:air")

    @Test func stringPalette() throws {
        // 26.3+: a list of strings when every entry is a default state.
        let palette: [NBT] = [.string("minecraft:air"), .string("minecraft:stone")]
        let raw = Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: 0, palette: palette, indices: (0..<4096).map { $0 % 2 })])
        let chunk = try Chunk(nbt: NBT.read(raw.serialized()).value)
        #expect(chunk.block(x: 1, y: 0, z: 0) == BlockState("minecraft:stone"))
    }

    @Test func acceptsEveryCompoundPaletteEntryShape() throws {
        let palette: [NBT] = [
            .compound(["": .string("minecraft:air")]),
            .compound(["": .string("minecraft:stone")]),
            .compound(["id": .string("minecraft:oak_stairs"), "properties": .compound(["facing": .string("east")])]),
            .compound(["Name": .string("minecraft:chest"), "Properties": .compound(["type": .string("left")])]),
        ]
        let indices = (0..<4096).map { $0 % 4 }
        let raw = Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: 0, palette: palette, indices: indices)])
        let chunk = try Chunk(nbt: NBT.read(raw.serialized()).value)
        #expect(chunk.block(x: 0, y: 0, z: 0)?.isAir == true)
        #expect(chunk.block(x: 1, y: 0, z: 0) == BlockState("minecraft:stone"))
        #expect(chunk.block(x: 2, y: 0, z: 0) == BlockState("minecraft:oak_stairs", properties: ["facing": "east"]))
        #expect(chunk.block(x: 3, y: 0, z: 0)?.description == "minecraft:chest[type=left]")
    }

    @Test func packedIndicesDoNotStraddleLongs() throws {
        // 17 entries → 5 bits → 12 per long with 4 padding bits.
        let palette = (0..<17).map { NBT.string("minecraft:block_\($0)") }
        let indices = (0..<4096).map { ($0 * 7) % 17 }
        let section = try ChunkSection(Fixtures.section(y: 2, palette: palette, indices: indices, bits: 5))
        #expect(section.blockStates?.bitsPerEntry == 5)
        #expect(section.blockStates?.allPaletteIndices() == indices)
        for (x, y, z) in [(0, 0, 0), (11, 0, 0), (12, 0, 0), (15, 15, 15), (3, 9, 7)] {
            let i = y * 256 + z * 16 + x
            #expect(section.block(x: x, y: y, z: z)?.id == "minecraft:block_\(indices[i])")
        }
    }

    @Test func minimumBlockBitsIsFour() throws {
        let indices = (0..<4096).map { $0 % 2 }
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air, .string("minecraft:dirt")], indices: indices, bits: 4))
        #expect(section.blockStates?.bitsPerEntry == 4)
        #expect(section.block(x: 1, y: 0, z: 0)?.id == "minecraft:dirt")
    }

    @Test func uniformSectionHasNoData() throws {
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: -4, palette: [.string("minecraft:bedrock")])]))
        #expect(chunk.block(x: 5, y: -60, z: 9)?.id == "minecraft:bedrock")
        #expect(chunk.block(x: 5, y: 100, z: 9) == nil)
    }

    @Test func cellBiomes() throws {
        // Pre-26.4: 64 entries, one per 4×4×4 cell.
        let biomes = ["minecraft:plains", "minecraft:desert"]
        let cells = (0..<64).map { $0 == 21 ? 1 : 0 }  // cell (x1, y1, z1)
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air], biomes: biomes, biomeIndices: cells, biomeBits: 1))
        #expect(!section.hasPerBlockBiomes)
        #expect(section.biome(x: 4, y: 4, z: 4) == "minecraft:desert")
        #expect(section.biome(x: 7, y: 7, z: 7) == "minecraft:desert")
        #expect(section.biome(x: 8, y: 4, z: 4) == "minecraft:plains")
    }

    @Test func perBlockBiomes() throws {
        // 26.4+: 4096 entries in YZX order, like blocks.
        let biomes = ["minecraft:plains", "minecraft:sulfur_caves", "minecraft:river"]
        let perBlock = (0..<4096).map { $0 % 3 }
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air], biomes: biomes, biomeIndices: perBlock, biomeBits: 2))
        #expect(section.hasPerBlockBiomes)
        #expect(section.biome(x: 1, y: 0, z: 0) == "minecraft:sulfur_caves")
        #expect(section.biome(x: 2, y: 0, z: 0) == "minecraft:river")
        #expect(section.biome(x: 0, y: 1, z: 0) == biomes[256 % 3])
    }

    @Test func statusFieldEitherCase() throws {
        let old = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 4671, sections: [],
                                                extra: ["status": .string("x"), "Status": .string("minecraft:features")]))
        #expect(old.status == "x")  // lowercase wins when both are present
        var fields = Fixtures.chunk(x: 0, z: 0, dataVersion: 4671, sections: []).compound!
        fields["status"] = nil
        fields["Status"] = .string("minecraft:features")
        #expect(try Chunk(nbt: .compound(fields)).status == "minecraft:features")
    }

    @Test func rejectsLegacyLevelWrapper() {
        let legacy = NBT.compound(["DataVersion": .int(2586), "Level": .compound([:])])
        #expect(throws: ChunkError.unsupportedLegacyFormat(dataVersion: 2586)) { try Chunk(nbt: legacy) }
    }

    @Test func toleratesVestigialLevelCompound() throws {
        // Upgraded pre-1.18 chunks keep `Level: {Structures: ...}` next to the modern fields.
        let nbt = Fixtures.chunk(x: 3, z: 4, dataVersion: 5023, sections: [], extra: ["Level": .compound(["Structures": .compound([:])])])
        #expect(try Chunk(nbt: nbt).x == 3)
    }

    @Test func heightmap() throws {
        let heights = (0..<256).map { $0 % 384 + 1 }
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [],
                                                  extra: ["Heightmaps": .compound(["WORLD_SURFACE": .longArray(Fixtures.pack(heights, bits: 9))])]))
        #expect(chunk.heightmap("WORLD_SURFACE")?.first == 1 - 64)
        #expect(chunk.heightmap("WORLD_SURFACE")?[255] == 256 - 64)
    }
}
