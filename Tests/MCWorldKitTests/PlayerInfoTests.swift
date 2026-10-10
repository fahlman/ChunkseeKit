import Foundation
import Testing
@testable import MCWorldKit

@Suite struct PlayerInfoTests {
    let uuid = UUID(uuidString: "52DFB519-DE9C-47E6-BC6C-BB053CC423E7")!

    func pos(_ x: Double, _ y: Double, _ z: Double) -> NBT { .list([.double(x), .double(y), .double(z)]) }

    @Test func current26xFormat() {
        let info = PlayerInfo(uuid: uuid, nbt: .compound([
            "DataVersion": .int(5023),
            "Dimension": .string("minecraft:overworld"),
            "Pos": pos(-2806.6, 65, -3895.2),
            "LastDeathLocation": .compound(["dimension": .string("minecraft:overworld"), "pos": .intArray([-2824, 39, -4033])]),
            "respawn": .compound(["dimension": .string("minecraft:overworld"), "pos": .intArray([-2811, 48, -3918]),
                                  "yaw": .float(-142), "pitch": .float(27)]),
        ]))
        #expect(info.dataVersion == 5023)
        #expect(info.position == .init(dimension: "minecraft:overworld", x: -2806.6, y: 65, z: -3895.2))
        #expect(info.lastDeath == .init(dimension: "minecraft:overworld", x: -2824, y: 39, z: -4033))
        #expect(info.respawn == .init(dimension: "minecraft:overworld", x: -2811, y: 48, z: -3918))
        #expect(!info.isFromBukkitServer)
    }

    @Test func pre121SpawnFields() {
        let info = PlayerInfo(uuid: uuid, nbt: .compound([
            "DataVersion": .int(2730), "Dimension": .string("minecraft:the_nether"), "Pos": pos(1, 2, 3),
            "SpawnX": .int(119), "SpawnY": .int(67), "SpawnZ": .int(-81), "SpawnDimension": .string("minecraft:overworld"),
        ]))
        #expect(info.position?.dimension == "minecraft:the_nether")
        #expect(info.respawn == .init(dimension: "minecraft:overworld", x: 119, y: 67, z: -81))
        #expect(info.lastDeath == nil)
    }

    @Test func legacyIntegerDimensionsAndBukkitWorlds() {
        let nether = PlayerInfo(uuid: uuid, nbt: .compound(["Dimension": .int(-1), "Pos": pos(5, 70, 5)]))
        #expect(nether.position?.dimension == "minecraft:the_nether")

        let bukkit = PlayerInfo(uuid: uuid, nbt: .compound([
            "Dimension": .int(21), "Pos": pos(176.4, 74, 484.6),
            "WorldUUIDMost": .long(1), "WorldUUIDLeast": .long(2),
            "SpawnX": .int(-122), "SpawnY": .int(71), "SpawnZ": .int(321), "SpawnWorld": .string("hannapolis"),
        ]))
        #expect(bukkit.position == nil)  // dimension 21 isn't guessed
        #expect(bukkit.unrecognizedDimension == "21")
        #expect(bukkit.isFromBukkitServer)
        #expect(bukkit.bukkitWorldName == "hannapolis")
    }

    @Test func worldListsPlayerFilesAndEmbeddedPlayer() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!
        let embedded = UUID(uuidString: "11C0E607-2120-4B62-A7E5-938F830B3CE7")!
        func ints(_ u: UUID) -> NBT {
            let b = withUnsafeBytes(of: u.uuid) { Array($0) }
            return .intArray((0..<4).map { i in Int32(bitPattern: b[i * 4..<i * 4 + 4].reduce(0) { $0 << 8 | UInt32($1) }) })
        }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("W"), "DataVersion": .int(5023),
            "Player": .compound(["UUID": ints(embedded), "Dimension": .string("minecraft:the_end"), "Pos": pos(0, 64, 0)]),
        ])]), to: dir.appendingPathComponent("level.dat"))
        for (u, x) in [(uuid, 10.0), (other, 20.0)] {
            try Fixtures.writeGzippedNBT(.compound(["Dimension": .string("minecraft:overworld"), "Pos": pos(x, 64, 0)]),
                                         to: dir.appendingPathComponent("players/data/\(u.uuidString.lowercased()).dat"))
        }
        // Not a player file; must be ignored.
        try Fixtures.write(Array("x".utf8), to: dir.appendingPathComponent("players/data/\(other.uuidString.lowercased()).dat_old"))

        let players = try World(contentsOf: dir).players()
        #expect(Set(players.map(\.uuid)) == [uuid, other, embedded])
        #expect(players.first { $0.uuid == embedded }?.position?.dimension == "minecraft:the_end")
        #expect(players.first { $0.uuid == other }?.position?.x == 20)
    }

    @Test func vitalsAndGameMode() {
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Health": .float(17.5), "AbsorptionAmount": .float(4), "foodLevel": .int(19), "foodSaturationLevel": .float(0.5),
            "XpLevel": .int(25), "XpP": .float(0.25), "XpTotal": .int(929), "playerGameType": .int(1), "SelectedItemSlot": .int(5),
        ]))
        #expect(player.health == 17.5 && player.absorption == 4 && player.foodLevel == 19 && player.saturation == 0.5)
        #expect(player.experienceLevel == 25 && player.experienceProgress == 0.25 && player.experienceTotal == 929)
        #expect(player.gameMode == .creative && player.selectedSlot == 5)
        // Files from before 1.9 stored health as a short.
        #expect(PlayerInfo(uuid: UUID(), nbt: .compound(["Health": .short(20)])).health == 20)
    }
}
