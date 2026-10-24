import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct CLIShoulderPetTests {
    @Test func bothShouldersJoinEntityCreaturesAtTheCarrierPosition() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try player(in: root, id: carrier, fields: [
            "Dimension": .string("minecraft:overworld"), "Pos": position([-8.7, 64.9, -513.1]),
            "ShoulderEntityLeft": parrot("Left"), "ShoulderEntityRight": parrot("Right"),
        ])
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "DataVersion": .int(5023), "Entities": .list([parrot("Ground")]),
        ]))]), to: root.appendingPathComponent("dimensions/minecraft/overworld/entities/r.0.0.mca"))

        let result = try Fixtures.runCLI(root, command: "creatures")
        #expect(result.status == 0)
        for name in ["Left", "Right"] {
            #expect(result.output.contains("minecraft:parrot \"\(name)\" at (-9, 64, -514) owned by \(owner) on shoulder of \(carrier)"))
        }
        #expect(result.output.contains("minecraft:parrot \"Ground\" at (1, 70, 2) owned by \(owner)\n"))
        #expect(result.output.contains("3 minecraft:parrot\n"))
    }

    @Test func unnamedUnownedShoulderPetStillUsesItsCarrierPosition() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try player(in: root, id: carrier, fields: [
            "Dimension": .string("minecraft:overworld"), "Pos": position([-8.7, 64.9, -513.1]),
            "ShoulderEntityLeft": .compound(["id": .string("minecraft:parrot"), "Health": .float(6),
                                              "Pos": position([1, 70, 2])]),
        ])

        let result = try Fixtures.runCLI(root, command: "creatures")
        #expect(result.status == 0)
        #expect(result.output.contains("minecraft:parrot at (-9, 64, -514) on shoulder of \(carrier)\n"))
        #expect(!result.output.contains("owned by") && !result.output.contains("at (1, 70, 2)"))
        #expect(result.output.contains("1 minecraft:parrot\n"))
    }

    @Test func carrierDimensionRestrictsTheListing() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try player(in: root, id: carrier, fields: [
            "Dimension": .string("minecraft:overworld"), "Pos": position([1, 64, 2]),
            "ShoulderEntityLeft": parrot("Overworld"),
        ])
        try player(in: root, id: "11111111-1111-1111-1111-111111111111", fields: [
            "Dimension": .string("minecraft:the_nether"), "Pos": position([4, 65, 6]),
            "ShoulderEntityLeft": parrot("Nether"),
        ])
        try player(in: root, id: "22222222-2222-2222-2222-222222222222", fields: [
            "Dimension": .int(21), "Pos": position([1, 64, 2]),
            "ShoulderEntityLeft": parrot("Unrecognized Dimension"),
        ])
        try player(in: root, id: "33333333-3333-3333-3333-333333333333", fields: [
            "Pos": position([1, 64, 2]), "ShoulderEntityLeft": parrot("Unknown Dimension"),
        ])

        for (dimension, included, excluded) in [("overworld", "Overworld", "Nether"), ("the_nether", "Nether", "Overworld")] {
            let result = try Fixtures.runCLI(root, command: "creatures", arguments: [dimension])
            #expect(result.status == 0)
            #expect(result.output.contains("\"\(included)\""))
            #expect(!result.output.contains("\"\(excluded)\""))
            #expect(!result.output.contains("Unrecognized Dimension") && !result.output.contains("Unknown Dimension"))
            #expect(result.output.contains("1 minecraft:parrot\n"))
        }
    }

    @Test(arguments: [Double.nan, Double.infinity, Double(Int.max)])
    func invalidCarrierCoordinatesNeverUseTheMountingPosition(_ invalid: Double) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try player(in: root, id: carrier, fields: [
            "Dimension": .string("minecraft:overworld"), "Pos": position([invalid, 64, 2]),
            "ShoulderEntityLeft": parrot("Carried"),
        ])
        let result = try Fixtures.runCLI(root, command: "creatures")
        #expect(result.status == 0)
        #expect(result.output.contains("\"Carried\" at unknown position owned by \(owner) on shoulder of \(carrier)"))
        #expect(!result.output.contains("at (1, 70, 2)"))
        #expect(result.output.contains("1 minecraft:parrot\n"))
    }

    private let carrier = "01234567-89ab-cdef-0123-456789abcdef"
    private let owner = "fedcba98-7654-3210-fedc-ba9876543210"

    private func position(_ values: [Double]) -> NBT { .list(values.map(NBT.double)) }

    private func parrot(_ name: String) -> NBT {
        .compound(["id": .string("minecraft:parrot"), "CustomName": .string(name),
                   "Health": .float(6), "Owner": .string(owner), "Pos": position([1, 70, 2])])
    }

    private func player(in root: URL, id: String, fields: [String: NBT]) throws {
        var fields = fields
        fields["DataVersion"] = .int(5023)
        try Fixtures.writeGzippedNBT(.compound(fields), to: root.appendingPathComponent("players/data/\(id).dat"))
    }

    private func world() throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("CLI shoulder pets"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        for dimension in ["overworld", "the_nether"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/\(dimension)/region"),
                                                    withIntermediateDirectories: true)
        }
        return root
    }
}
