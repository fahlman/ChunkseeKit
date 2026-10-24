import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

/// Exercise the shipped command front end against compressed synthetic saves.
@Suite struct CLIPositionTests {
    @Test func namedCreaturesAndPlayersUseTheContainingBlock() throws {
        let world = try fixture(position: [-8.7, -0.1, -513.1])
        defer { try? FileManager.default.removeItem(at: world) }
        let creature = try Fixtures.runCLI(world, command: "creatures")
        #expect(creature.status == 0)
        #expect(creature.output.contains("minecraft:wolf \"Check Wolf\" at (-9, -1, -514)"))
        #expect(creature.output.contains("1 minecraft:wolf"))
        let player = try Fixtures.runCLI(world, command: "players")
        #expect(player.status == 0)
        #expect(player.output.contains("position: minecraft:overworld -9 -1 -514"))
        #expect(player.output.contains("death:    minecraft:the_nether -16 60 32"))
        #expect(player.output.contains("respawn:  minecraft:overworld 8 65 -12"))
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, Double(Int.max), -Double.greatestFiniteMagnitude])
    func unavailableCoordinatesDoNotCrashOrHideTheRecord(_ invalid: Double) throws {
        for axis in 0..<3 {
            var position = [1.0, 64.0, -2.0]
            position[axis] = invalid
            let world = try fixture(position: position)
            defer { try? FileManager.default.removeItem(at: world) }
            for command in ["creatures", "players"] {
                let result = try Fixtures.runCLI(world, command: command)
                #expect(result.status == 0, "\(command) must not trap for invalid axis \(axis)")
                #expect(result.output.contains("unknown position"))
                #expect(result.output.contains(command == "creatures" ? "Check Wolf" : playerID.uuidString.lowercased()))
                if command == "creatures" { #expect(result.output.contains("1 minecraft:wolf")) }
                else { #expect(result.output.contains("respawn:  minecraft:overworld 8 65 -12")) }
            }
        }
    }

    @Test func exactIntegerEdgesAndFractionsRemainRepresentable() throws {
        let world = try fixture(position: [Double(Int.min), Double(Int.max).nextDown, 0.999])
        defer { try? FileManager.default.removeItem(at: world) }
        let player = try Fixtures.runCLI(world, command: "players")
        #expect(player.status == 0)
        #expect(player.output.contains("position: minecraft:overworld -9223372036854775808 9223372036854774784 0"))
    }

    @Test(arguments: [false, true])
    func creaturesReadEntityRegionsWithOrWithoutMatchingTerrain(_ terrainPresent: Bool) throws {
        let root = try fixture(position: [1.25, 64, 2.5])
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = root.appendingPathComponent("dimensions/minecraft/overworld")
        if !terrainPresent { try FileManager.default.removeItem(at: dimension.appendingPathComponent("region")) }
        func write(_ path: String, localX: Int, entities: [NBT]) throws {
            try Fixtures.write(try Fixtures.region([.init(localX: localX, localZ: 0, nbt: .compound([
                "DataVersion": .int(5023), "Entities": .list(entities),
            ]))]), to: root.appendingPathComponent(path))
        }
        try write("dimensions/minecraft/overworld/entities/r.-1.0.mca", localX: 31, entities: [
            .compound(["id": .string("minecraft:wolf"), "Health": .float(8), "Owner": Fixtures.uuidInts(playerID),
                       "Pos": .list([.double(-8.7), .double(70.5), .double(1.25)])]),
            .compound(["id": .string("minecraft:item"), "CustomName": .string("Not a creature"),
                       "Pos": .list([.double(-8), .double(70), .double(1)])]),
        ])
        try write("dimensions/minecraft/overworld/entities/r.1.0.mca", localX: 1, entities: [
            .compound(["id": .string("minecraft:cat"), "Health": .float(10), "CustomName": .string("Distant Cat"),
                       "Pos": .list([.double(528.9), .double(64), .double(0)])]),
        ])
        try write("dimensions/minecraft/the_nether/entities/r.0.0.mca", localX: 0, entities: [
            .compound(["id": .string("minecraft:wolf"), "Health": .float(8), "CustomName": .string("Other Dimension"),
                       "Pos": .list([.double(0), .double(70), .double(0)])]),
        ])
        let result = try Fixtures.runCLI(root, command: "creatures")
        #expect(result.status == 0)
        #expect(result.output.contains("at (-9, 70, 1) owned by \(playerID.uuidString.lowercased())"))
        #expect(result.output.contains("Check Wolf") && result.output.contains("Distant Cat"))
        #expect(result.output.contains("2 minecraft:wolf") && result.output.contains("1 minecraft:cat"))
        #expect(!result.output.contains("Not a creature") && !result.output.contains("Other Dimension"))
    }

    @Test func sharedCreatureCategoriesIncludeUnnamedVillagersWithoutHidingUnknownPositions() throws {
        let root = try fixture(position: [1.25, 64, 2.5])
        defer { try? FileManager.default.removeItem(at: root) }
        let villagerData = NBT.compound(["profession": .string("minecraft:farmer")])
        let entities: [NBT] = [
            .compound(["id": .string("minecraft:villager"), "Health": .float(20), "VillagerData": villagerData,
                       "Pos": .list([.double(-8.7), .double(64.9), .double(-513.1)])]),
            .compound(["id": .string("minecraft:villager"), "Health": .float(20), "VillagerData": villagerData,
                       "Pos": .list([.double(.nan), .double(64), .double(2)])]),
            .compound(["id": .string("minecraft:cat"), "Health": .float(10), "Owner": Fixtures.uuidInts(playerID),
                       "Pos": .list([.double(4), .double(65), .double(6)])]),
            .compound(["id": .string("minecraft:cow"), "Health": .float(10),
                       "Pos": .list([.double(7), .double(66), .double(8)])]),
        ]
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "DataVersion": .int(5023), "Entities": .list(entities),
        ]))]), to: root.appendingPathComponent("dimensions/minecraft/overworld/entities/r.1.0.mca"))

        let result = try Fixtures.runCLI(root, command: "creatures")
        #expect(result.status == 0)
        #expect(result.output.contains("minecraft:villager at (-9, 64, -514)\n"))
        #expect(result.output.contains("minecraft:villager at unknown position\n"))
        #expect(result.output.contains("minecraft:cat at (4, 65, 6) owned by \(playerID.uuidString.lowercased())\n"))
        #expect(result.output.contains("minecraft:wolf \"Check Wolf\" at (1, 64, 2)\n"))
        #expect(!result.output.contains("minecraft:cow at"))
        for count in ["2 minecraft:villager", "1 minecraft:cat", "1 minecraft:cow", "1 minecraft:wolf"] {
            #expect(result.output.contains("\(count)\n"))
        }
    }

    private var playerID: UUID { UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")! }

    private func fixture(position: [Double]) throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("CLI positions"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        let pos = NBT.list(position.map(NBT.double))
        try Fixtures.writeGzippedNBT(.compound([
            "DataVersion": .int(5023), "Dimension": .string("minecraft:overworld"), "Pos": pos,
            "LastDeathLocation": .compound(["dimension": .string("minecraft:the_nether"), "pos": .intArray([-16, 60, 32])]),
            "respawn": .compound(["dimension": .string("minecraft:overworld"), "pos": .intArray([8, 65, -12])]),
        ]), to: root.appendingPathComponent("players/data/\(playerID.uuidString.lowercased()).dat"))
        let mob = NBT.compound(["id": .string("minecraft:wolf"), "Health": .float(8),
                                "Pos": pos, "CustomName": .string("Check Wolf")])
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "DataVersion": .int(5023), "Entities": .list([mob]),
        ]))]), to: root.appendingPathComponent("dimensions/minecraft/overworld/entities/r.0.0.mca"))
        // Match the current terrain enumeration to isolate coordinate presentation in this slice.
        try Fixtures.write(try Fixtures.region([]), to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        return root
    }

}
