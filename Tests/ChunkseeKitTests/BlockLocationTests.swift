import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct BlockLocationTests {
    private func world(spawn: NBT?, legacy: Bool = false) throws -> URL {
        let root = try Fixtures.tempDirectory()
        var fields: [String: NBT] = ["LevelName": .string("Block locations"), "DataVersion": .int(5023)]
        fields["spawn"] = spawn
        if legacy {
            fields["SpawnX"] = .int(-9)
            fields["SpawnY"] = .int(64)
            fields["SpawnZ"] = .int(-17)
        }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return root
    }

    @Test(arguments: [
        NBT.compound(["pos": .intArray([101, 70, 202])]),
        .compound(["dimension": .int(0), "pos": .intArray([101, 70, 202])]),
        .compound(["dimension": .string("minecraft:overworld")]),
        .compound(["dimension": .string("minecraft:overworld"), "pos": .intArray([101, 70])]),
        .compound(["dimension": .string("minecraft:overworld"), "pos": .list([.int(101), .int(70), .int(202)])]),
        .string("not a location"),
    ])
    func modernWorldSpawnPublishesOnlyACompleteLocation(_ spawn: NBT) throws {
        let root = try world(spawn: spawn, legacy: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let level = try World(contentsOf: root).level
        #expect(level.spawnDimension == nil)
        #expect(level.spawnPosition == nil) // Never combine partial modern data with the legacy location.
        let player = PlayerInfo(uuid: UUID(), nbt: .compound(["LastDeathLocation": spawn, "respawn": spawn]))
        #expect(player.lastDeath == nil && player.respawn == nil)
    }

    @Test(arguments: ["minecraft:overworld", "mymod:deep/mines", "overworld", "the_nether", ""])
    func completeModernLocationsShareTheExistingDimensionRule(_ dimension: String) throws {
        let expected = dimension.contains(":") ? dimension : "minecraft:" + dimension
        let position: [Int32] = [.min, -64, .max]
        let location = NBT.compound(["dimension": .string(dimension), "pos": .intArray(position)])
        let root = try world(spawn: location)
        defer { try? FileManager.default.removeItem(at: root) }
        let level = try World(contentsOf: root).level
        #expect(level.spawnDimension == expected)
        #expect(level.spawnPosition.map { [$0.x, $0.y, $0.z] } == position.map(Int.init))
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Dimension": .string(dimension), "Pos": .list(position.map { .double(Double($0)) }),
            "LastDeathLocation": location, "respawn": location,
        ]))
        let point = PlayerInfo.Location(dimension: expected, x: Double(position[0]), y: Double(position[1]), z: Double(position[2]))
        #expect(player.position == point)
        #expect(player.lastDeath == point)
        #expect(player.respawn == point)
    }

    @Test func legacyWorldAndPlayerFallbacksKeepTheirOriginalMeaning() throws {
        let root = try world(spawn: nil, legacy: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let level = try World(contentsOf: root).level
        #expect(level.spawnDimension == "minecraft:overworld")
        #expect(level.spawnPosition.map { [$0.x, $0.y, $0.z] } == [-9, 64, -17])
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "respawn": .compound(["pos": .intArray([101, 70, 202])]),
            "SpawnDimension": .int(-1), "SpawnX": .int(-9), "SpawnY": .int(64), "SpawnZ": .int(-17),
        ]))
        #expect(player.respawn == .init(dimension: "minecraft:the_nether", x: -9, y: 64, z: -17))
    }
}
