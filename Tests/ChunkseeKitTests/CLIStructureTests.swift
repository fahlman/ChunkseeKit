import Foundation
import Testing
import ChunkseeKit

@Suite struct CLIStructureTests {
    @Test func completedChunksAndPlacementEvidenceControlTheListing() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("CLI structures"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        var chunks: [Fixtures.RegionChunk] = []
        func add(_ name: String, status: String?, uppercase: Bool = false, min: Int32 = 0, max: Int32 = 1,
                 minZ: Int32? = nil, maxZ: Int32? = nil,
                 pieceID: String = "minecraft:jigsaw", height: Int32? = nil) {
            let x = chunks.count
            var piece: [String: NBT] = ["id": .string(pieceID), "BB": .intArray([min, 60, minZ ?? min, max, 64, maxZ ?? max])]
            if let height { piece["HPos"] = .int(height) }
            var fields = Fixtures.chunk(x: x, z: 0, dataVersion: 5023, sections: [], extra: [
                "structures": .compound(["starts": .compound([name: .compound([
                    "id": .string(name), "ChunkX": .int(Int32(x)), "ChunkZ": .int(0), "Children": .list([.compound(piece)]),
                ])])]),
            ]).compound!
            fields.removeValue(forKey: "status")
            if let status { fields[uppercase ? "Status" : "status"] = .string(status) }
            chunks.append(.init(localX: x, localZ: 0, nbt: .compound(fields)))
        }
        add("custom:positive", status: "minecraft:full")
        add("custom:negative", status: "full", uppercase: true, min: -4, max: -1)
        add("custom:fractional_center", status: "full", min: -2, max: 0, minZ: 10, maxZ: 12)
        add("custom:unknown_piece", status: "minecraft:full", pieceID: "custom:piece", height: -1)
        add("custom:unfinished", status: "minecraft:structure_starts")
        add("custom:features_only", status: "minecraft:features")
        add("custom:unknown_status", status: nil)
        add("minecraft:jungle_pyramid", status: "minecraft:full", pieceID: "minecraft:tejp", height: -1)
        add("INVALID", status: "minecraft:full")
        try Fixtures.write(try Fixtures.region(chunks), to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        let result = try Fixtures.runCLI(root, command: "structures")
        #expect(result.status == 0)
        #expect(result.output.contains("minecraft:overworld: 4 structures"))
        #expect(result.output.contains("custom:positive  (1, 1)"))
        #expect(result.output.contains("custom:negative  (-2, -2)"))
        #expect(result.output.contains("custom:fractional_center  (-1, 11)"))
        #expect(result.output.contains("custom:unknown_piece"))
        for absent in ["custom:unfinished", "custom:features_only", "custom:unknown_status", "minecraft:jungle_pyramid", "INVALID"] {
            #expect(!result.output.contains(absent))
        }
    }
}
