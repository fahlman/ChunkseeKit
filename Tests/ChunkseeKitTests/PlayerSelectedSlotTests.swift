import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct PlayerSelectedSlotTests {
    private func item(slot: Int) -> NBT {
        .compound(["id": .string("minecraft:stick"), "count": .int(1), "Slot": .byte(Int8(slot)),
            "components": .compound(["minecraft:attribute_modifiers": .list([.compound([
                "id": .string("test:selected"), "type": .string("minecraft:max_health"),
                "amount": .double(Double(slot + 1)), "operation": .string("add_value"), "slot": .string("mainhand")
            ])])])])
    }

    private func fields(_ selected: NBT?) -> [String: NBT] {
        var fields: [String: NBT] = [
            "DataVersion": .int(Int32.max), "Dimension": .string("minecraft:overworld"),
            "Pos": .list([.double(5.25), .double(64), .double(-7.5)]), "Health": .float(17), "foodLevel": .int(19),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20)])]),
            "Inventory": .list((0..<9).map { item(slot: $0) })
        ]
        fields["SelectedItemSlot"] = selected
        return fields
    }

    private func expectSelection(_ player: PlayerInfo, slot: Int?, note: String) {
        #expect(player.selectedSlot == slot, "\(note)")
        #expect(player.mainHandItem?.slot == slot && player.equippedItems["mainhand"]?.slot == slot, "\(note)")
        if let slot { #expect(player.maximumHealth(enchantments: [:]) == Double(21 + slot), "\(note)") }
        #expect(player.inventory.count == 9 && player.foodLevel == 19 && player.health == 17, "\(note)")
        #expect(player.position == .init(dimension: "minecraft:overworld", x: 5.25, y: 64, z: -7.5), "\(note)")
    }

    @Test(arguments: SavedNumericSample.all)
    func savedSelectionsUseMinecraftConversionBeforeSlotValidation(_ sample: SavedNumericSample) throws {
        // The captured game result supplies conversion. Inventory.setSelectedSlot accepts 0...8.
        let slot = (0...8).contains(sample.intValue) ? sample.intValue : nil
        let bytes = NBT.compound(fields(sample.tag)).serialized(), decoded = try NBT.read(bytes).value
        expectSelection(PlayerInfo(uuid: UUID(), nbt: decoded), slot: slot, note: sample.id)
        #expect(decoded.serialized() == bytes)
    }

    @Test func worldPlayerFilesAndEmbeddedSelectionUseTheSameValidatedReader() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let embeddedID = UUID()
        var embedded = fields(.double(8.75))
        embedded["UUID"] = Fixtures.uuidInts(embeddedID)
        let level = root.appendingPathComponent("level.dat")
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Selected slot"), "DataVersion": .int(Int32.max), "Player": .compound(embedded)
        ])]), to: level)
        var inputBytes = [level: try Data(contentsOf: level)]
        var expected = [UUID: SavedNumericSample]()
        for sample in SavedNumericSample.all {
            let id = UUID(), file = root.appendingPathComponent("players/data/\(id.uuidString.lowercased()).dat")
            try Fixtures.writeGzippedNBT(.compound(fields(sample.tag)), to: file)
            inputBytes[file] = try Data(contentsOf: file)
            expected[id] = sample
        }
        let players = try World(contentsOf: root).players()
        #expect(players.count == expected.count + 1)
        #expect(Set(players.map(\.uuid)) == Set(expected.keys).union([embeddedID]))
        for player in players {
            if player.uuid == embeddedID {
                expectSelection(player, slot: 8, note: "embedded fractional slot")
            } else {
                let sample = try #require(expected[player.uuid])
                expectSelection(player, slot: (0...8).contains(sample.intValue) ? sample.intValue : nil, note: sample.id)
            }
        }
        for (file, bytes) in inputBytes { #expect(try Data(contentsOf: file) == bytes) }
    }

    @Test func invalidSelectionKeepsIndependentFieldsAndAnExplicitMainHandStillWins() throws {
        let unavailable: [NBT?] = [nil, .string("0"), .string(""), .compound([:]), .list([]),
            .list([.int(0)]), .byteArray([0]), .intArray([0]), .longArray([0]), .int(-1), .int(9), .double(-0.25)]
        for invalid in unavailable {
            let source = fields(invalid), bytes = NBT.compound(source).serialized()
            let decoded = try NBT.read(bytes).value
            expectSelection(PlayerInfo(uuid: UUID(), nbt: decoded), slot: nil, note: "invalid selection")
            #expect(decoded.serialized() == bytes)
        }
        for selected in [NBT?.none, .int(9), .double(2.75), .long(4_294_967_301)] {
            var source = fields(selected)
            source["equipment"] = .compound(["mainhand": .compound([
                "id": .string("minecraft:iron_sword"), "count": .int(1),
                "components": .compound(["minecraft:attribute_modifiers": .list([.compound([
                    "id": .string("test:explicit"), "type": .string("minecraft:max_health"),
                    "amount": .double(12), "operation": .string("add_value"), "slot": .string("mainhand")
                ])])])])])
            let player = PlayerInfo(uuid: UUID(), nbt: .compound(source))
            #expect(player.mainHandItem?.id == "minecraft:iron_sword")
            #expect(player.equippedItems["mainhand"]?.id == "minecraft:iron_sword" && player.maximumHealth(enchantments: [:]) == 32)
            #expect(player.inventory.count == 9)
        }
    }

    @Test func everyHotbarSlotIsValidAndRangeChecksFollowNarrowing() {
        for slot in 0...8 {
            expectSelection(PlayerInfo(uuid: UUID(), nbt: .compound(fields(.int(Int32(slot))))), slot: slot, note: "slot \(slot)")
        }
        for (tag, slot) in [(NBT.long(4_294_967_301), 5), (.double(8.75), 8), (.double(-0.0), 0)] {
            expectSelection(PlayerInfo(uuid: UUID(), nbt: .compound(fields(tag))), slot: slot, note: "converted selection")
        }
    }
}
