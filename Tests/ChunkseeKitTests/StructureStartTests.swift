import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct StructureStartTests {
    func piece(_ id: String, _ box: [Int32]) -> NBT { .compound(["id": .string(id), "BB": .intArray(box), "GD": .int(0)]) }

    var chunkNBT: NBT {
        .compound([
            "DataVersion": .int(5023), "xPos": .int(-302), "zPos": .int(-51), "yPos": .int(-4), "Status": .string("minecraft:full"),
            "sections": .list(.compound, []),
            "structures": .compound([
                "References": .compound([:]),
                "starts": .compound([
                    "minecraft:stronghold": .compound([
                        "id": .string("minecraft:stronghold"), "ChunkX": .int(-302), "ChunkZ": .int(-51), "references": .int(0),
                        "Children": .list([
                            piece("minecraft:shstart", [-4830, -19, -814, -4826, -9, -810]),
                            piece("minecraft:shpr", [-4900, -40, -830, -4890, -32, -815]),
                        ]),
                    ]),
                    "minecraft:mineshaft": .compound(["id": .string("INVALID")]),
                ]),
            ]),
        ])
    }

    @Test func readsStartsPiecesAndBounds() throws {
        let starts = try Chunk(nbt: chunkNBT).structureStarts
        #expect(starts.map(\.id) == ["minecraft:stronghold"])  // INVALID placeholder left out
        let stronghold = try #require(starts.first)
        #expect((stronghold.chunkX, stronghold.chunkZ) == (-302, -51))
        #expect(stronghold.pieces.map(\.id) == ["minecraft:shstart", "minecraft:shpr"])
        #expect(stronghold.bounds == BlockBox(minX: -4900, minY: -40, minZ: -830, maxX: -4826, maxY: -9, maxZ: -810))
    }

    @Test func structureScanSkipsBlockData() throws {
        let (_, nbt) = try NBT.read(chunkNBT.serialized(), skipping: Chunk.keysNotNeededForStructures)
        #expect(nbt["sections"] == nil)
        #expect(StructureStart.starts(inChunk: nbt).count == 1)
    }

    @Test func noStructures() throws {
        #expect(StructureStart.starts(inChunk: .compound([:])).isEmpty)
        #expect(StructureStart(id: "x", chunkX: 0, chunkZ: 0, pieces: []).bounds == nil)
    }
}
