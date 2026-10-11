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

    func chunkWithPieces(_ pieces: [NBT], id: String = "minecraft:jungle_pyramid") -> NBT {
        .compound(["structures": .compound(["starts": .compound([id: .compound([
            "id": .string(id), "ChunkX": .int(-17), "ChunkZ": .int(4), "Children": .list(pieces),
        ])])])])
    }

    func scatteredPiece(_ id: String, height: Int32?) -> NBT {
        var fields = piece(id, [-272, 64, 64, -261, 73, 78]).compound!
        if let height { fields["HPos"] = .int(height) }
        return .compound(fields)
    }

    @Test func upgradedUnplacedJunglePyramidIsExcluded() {
        // The record at X -266, Z 71 in an upgraded taiga chunk. Minecraft never aligned it with
        // the ground or placed its chests/traps; its bounding box alone previously made a marker.
        var fields = scatteredPiece("minecraft:tejp", height: -1).compound!
        fields.merge(["Width": .int(12), "Height": .int(10), "Depth": .int(15), "O": .int(2),
                      "placedMainChest": .byte(0), "placedHiddenChest": .byte(0),
                      "placedTrap1": .byte(0), "placedTrap2": .byte(0)]) { $1 }
        let nbt = chunkWithPieces([.compound(fields)])
        #expect(StructureStart.starts(inChunk: nbt).isEmpty)
        // The same outcome with the fast structure-only NBT read used by scan clients.
        let decoded = try? NBT.read(nbt.serialized(), skipping: Chunk.keysNotNeededForStructures).1
        #expect(decoded.map { StructureStart.starts(inChunk: $0).isEmpty } == true)
    }

    @Test(arguments: ["minecraft:tejp", "minecraft:tedp", "minecraft:tesh"])
    func scatteredFeaturesExcludeOnlyTheUnsetHeight(_ id: String) {
        #expect(StructureStart.starts(inChunk: chunkWithPieces([scatteredPiece(id, height: -1)])).isEmpty)
        for height in [Int32(0), 68] {
            #expect(StructureStart.starts(inChunk: chunkWithPieces([scatteredPiece(id, height: height)])).count == 1)
        }
        // Missing fields in older or unusual records do not prove a structure was never built.
        #expect(StructureStart.starts(inChunk: chunkWithPieces([scatteredPiece(id, height: nil)])).count == 1)
    }

    @Test func partialAndUnknownPlacementIsRetained() {
        #expect(StructureStart.starts(inChunk: chunkWithPieces([
            scatteredPiece("minecraft:tejp", height: -1), scatteredPiece("minecraft:tejp", height: 68),
        ])).count == 1)
        for id in ["minecraft:jigsaw", "minecraft:iglu", "custom:temple"] {
            #expect(StructureStart.starts(inChunk: chunkWithPieces([scatteredPiece(id, height: -1)])).count == 1)
        }
    }

    @Test func emptyOrMalformedPiecesCannotMakeAStructure() {
        #expect(StructureStart.starts(inChunk: chunkWithPieces([])).isEmpty)
        #expect(StructureStart.starts(inChunk: chunkWithPieces([
            .compound(["id": .string("minecraft:tejp"), "BB": .intArray([1, 2])]),
        ])).isEmpty)
    }
}
