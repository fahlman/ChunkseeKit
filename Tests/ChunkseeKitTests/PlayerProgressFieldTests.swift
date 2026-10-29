import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct PlayerProgressFieldTests {
    private func fields(_ value: NBT) -> [String: NBT] {
        ["DataVersion": .int(Int32.max), "Dimension": .string("minecraft:overworld"),
         "Pos": .list([.double(1.25), .double(64), .double(-2.75)]),
         "Health": .double(17.0000001), "foodLevel": value, "foodSaturationLevel": value,
         "XpLevel": value, "XpP": value, "XpTotal": value]
    }

    private func expectProgress(_ player: PlayerInfo, matches sample: SavedNumericSample) throws {
        #expect(player.foodLevel == sample.intValue, "\(sample)")
        #expect(player.experienceLevel == sample.intValue, "\(sample)")
        #expect(player.experienceTotal == sample.intValue, "\(sample)")
        let expected = Double(sample.floatValue)
        for result in [player.saturation, player.experienceProgress] {
            let actual = try #require(result, "\(sample)")
            if expected.isNaN {
                #expect(actual.isNaN, "\(sample)")
            } else {
                #expect(actual.bitPattern == expected.bitPattern, "\(sample)")
            }
        }
        #expect(player.position == .init(dimension: "minecraft:overworld", x: 1.25, y: 64, z: -2.75))
        #expect(player.health == 17.0000001) // Health projection is a separate saved-field contract.
    }

    @Test(arguments: SavedNumericSample.all)
    func publicPlayerProgressMatchesMinecraft(_ sample: SavedNumericSample) throws {
        let original = NBT.compound(fields(sample.tag)).serialized()
        let decoded = try NBT.read(original).value
        try expectProgress(PlayerInfo(uuid: UUID(), nbt: decoded), matches: sample)
        #expect(decoded.serialized() == original)
    }

    @Test func worldPlayerFilesAndEmbeddedPlayerShareTheConversions() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let embeddedID = UUID()
        let embeddedSample = try #require(SavedNumericSample.all.first { $0.id == "double:negative-half" })
        var embedded = fields(embeddedSample.tag)
        embedded["UUID"] = Fixtures.uuidInts(embeddedID)
        let levelFile = root.appendingPathComponent("level.dat")
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Player progress"), "DataVersion": .int(Int32.max),
            "Player": .compound(embedded),
        ])]), to: levelFile)
        var inputs = [levelFile: try Data(contentsOf: levelFile)]
        var expected = [embeddedID: embeddedSample]
        for sample in SavedNumericSample.all {
            let id = UUID()
            let file = root.appendingPathComponent("players/data/\(id.uuidString.lowercased()).dat")
            try Fixtures.writeGzippedNBT(.compound(fields(sample.tag)), to: file)
            inputs[file] = try Data(contentsOf: file)
            expected[id] = sample
        }
        let players = try World(contentsOf: root).players()
        #expect(players.count == expected.count)
        #expect(Set(players.map(\.uuid)) == Set(expected.keys))
        for player in players {
            try expectProgress(player, matches: #require(expected[player.uuid]))
        }
        for (file, bytes) in inputs { #expect(try Data(contentsOf: file) == bytes) }
    }

    @Test func unreadableProgressStaysIndependentAndDoesNotInventLoadDefaults() throws {
        let invalidValues: [NBT?] = [nil, .string(""), .string("1"), .string("true"),
            .compound([:]), .list([]), .list([.int(1)]), .byteArray([1]), .intArray([1]), .longArray([1])]
        for invalid in invalidValues {
            for key in ["foodLevel", "foodSaturationLevel", "XpLevel", "XpP", "XpTotal"] {
                var source = fields(.int(20))
                source["foodSaturationLevel"] = .float(0.5)
                source["XpP"] = .float(0.25)
                source[key] = invalid
                let bytes = NBT.compound(source).serialized()
                let decoded = try NBT.read(bytes).value
                let player = PlayerInfo(uuid: UUID(), nbt: decoded)
                #expect(player.foodLevel == (key == "foodLevel" ? nil : 20))
                #expect(player.saturation == (key == "foodSaturationLevel" ? nil : 0.5))
                #expect(player.experienceLevel == (key == "XpLevel" ? nil : 20))
                #expect(player.experienceProgress == (key == "XpP" ? nil : 0.25))
                #expect(player.experienceTotal == (key == "XpTotal" ? nil : 20))
                #expect(player.position?.x == 1.25 && player.health == 17.0000001)
                #expect(decoded.serialized() == bytes)
            }
        }
        let empty = PlayerInfo(uuid: UUID(), nbt: .compound([:]))
        #expect(empty.foodLevel == nil && empty.saturation == nil)
        #expect(empty.experienceLevel == nil && empty.experienceProgress == nil && empty.experienceTotal == nil)
    }

    @Test func savedValuesAreNotClampedToTheUsualGameplayRange() {
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "foodLevel": .double(25.75), "foodSaturationLevel": .double(-0.25),
            "XpLevel": .float(-0.5), "XpP": .double(1.5), "XpTotal": .long(4_294_967_297),
        ]))
        #expect(player.foodLevel == 25 && player.saturation == -0.25)
        #expect(player.experienceLevel == -1 && player.experienceProgress == 1.5 && player.experienceTotal == 1)
    }
}
