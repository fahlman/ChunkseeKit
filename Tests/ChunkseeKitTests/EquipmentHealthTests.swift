import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct EquipmentHealthTests {
    private func pair(_ fields: [String: NBT]) throws -> (pet: Creature, player: PlayerInfo) {
        let folder = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved: [String: NBT] = ["id": .string("minecraft:wolf"), "Owner": .intArray([1, 2, 3, 4]),
            "Health": .float(10), "Pos": .list([.double(0), .double(64), .double(0)]), "DataVersion": .int(5023),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20)])])]
        let file = folder.appendingPathComponent("saved.dat")
        try Fixtures.writeGzippedNBT(.compound(saved.merging(fields) { $1 }), to: file)
        let nbt = try NBT.read(contentsOf: file)
        return (try #require(Creature(nbt, dataVersion: 5023)), PlayerInfo(uuid: UUID(), nbt: nbt))
    }

    private func modifier(_ amount: Double, slot: String, id: String = "example:health") -> NBT {
        .compound(["type": .string("minecraft:max_health"), "amount": .double(amount), "id": .string(id),
                   "operation": .string("add_value"), "slot": .string(slot)])
    }

    private func item(_ components: [String: NBT], id: String = "minecraft:wolf_armor", count: Int32 = 1) -> NBT {
        .compound(["id": .string(id), "count": .int(count), "components": .compound(components)])
    }

    @Test func supportedBodyModifiersUseTheSameArithmeticAndSlotGroups() throws {
        for group in ["body", "armor", "any"] {
            let values = try pair(["equipment": .compound(["body": item(["minecraft:attribute_modifiers": .list([modifier(4, slot: group)])])])])
            #expect(values.pet.maxHealth == 24 && values.player.maxHealth == 24)
        }
    }

    @Test func wrongSlotEmptyBrokenAndRemovedModifiersDoNotHideTheSavedMaximum() throws {
        let wrongSlot = item(["minecraft:attribute_modifiers": .list([modifier(4, slot: "head")])])
        let empty = item(["minecraft:attribute_modifiers": .list([modifier(4, slot: "body")])], count: 0)
        let broken = item(["minecraft:damage": .int(64), "minecraft:attribute_modifiers": .list([modifier(4, slot: "body")])])
        let removed = item(["!minecraft:attribute_modifiers": .compound([:]), "minecraft:attribute_modifiers": .list([modifier(4, slot: "body")])])
        for gear in [wrongSlot, empty, broken, removed] {
            let values = try pair(["equipment": .compound(["body": gear])])
            #expect(values.pet.maxHealth == 20 && values.player.maxHealth == 20)
        }
    }

    @Test func unsupportedModdedDefaultsHaveOneConservativePolicy() throws {
        let gear = item([:], id: "example:armor")
        let unsupported = try pair(["equipment": .compound(["body": gear])])
        #expect(unsupported.pet.maxHealth == nil && unsupported.player.maxHealth == nil)
        let explicit = try pair(["equipment": .compound(["body": item(["minecraft:attribute_modifiers": .list([])], id: "example:armor")])])
        #expect(explicit.pet.maxHealth == 20 && explicit.player.maxHealth == 20)
        let effect = try pair(["active_effects": .list([.compound(["id": .string("example:health"), "duration": .int(100)])])])
        #expect(effect.pet.maxHealth == nil && effect.player.maxHealth == nil)
    }

    @Test func legacyArmorAndHandListsReachEquipmentAndHealth() throws {
        func legacy(_ id: String, slot: String, amount: Double, uuid: Int32, inventory: Int8) -> NBT {
            .compound(["id": .string(id), "Count": .byte(1), "Slot": .byte(inventory), "tag": .compound([
                "AttributeModifiers": .list([.compound(["AttributeName": .string("generic.maxHealth"), "Amount": .double(amount),
                    "Operation": .int(0), "UUID": .intArray([1, 2, 3, uuid]), "Slot": .string(slot)])]),
            ])])
        }
        let boots = legacy("minecraft:iron_boots", slot: "feet", amount: 2, uuid: 4, inventory: 100)
        let shield = legacy("minecraft:shield", slot: "offhand", amount: 3, uuid: 5, inventory: -106)
        let values = try pair(["ArmorItems": .list([boots, .compound([:]), .compound([:]), .compound([:])]),
                               "HandItems": .list([.compound([:]), shield]), "Inventory": .list([boots, shield])])
        #expect(values.pet.equipment?["feet"]?.id == "minecraft:iron_boots")
        #expect(values.pet.equipment?["offhand"]?.id == "minecraft:shield")
        #expect(values.pet.maxHealth == 25 && values.player.maxHealth == 25)
        let current = try pair(["equipment": .compound([:]), "ArmorItems": .list([boots])])
        #expect(current.pet.equipment?.isEmpty == true && current.pet.maxHealth == 20)
    }

    @Test func replacementUsesSlotOrderAndDoesNotDuplicateSavedHealthBoost() throws {
        let values = try pair([
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20), "modifiers": .list([
                .compound(["id": .string("example:health"), "amount": .double(100), "operation": .string("add_value")]),
                .compound(["id": .string("minecraft:effect.health_boost"), "amount": .double(4), "operation": .string("add_value")]),
            ])])]),
            "equipment": .compound([
                "head": item(["minecraft:attribute_modifiers": .list([modifier(6, slot: "head")])], id: "minecraft:iron_helmet"),
                "body": item(["minecraft:attribute_modifiers": .list([modifier(2, slot: "body")])]),
            ]),
            "active_effects": .list([.compound(["id": .string("minecraft:health_boost"), "amplifier": .byte(9), "duration": .int(100)])]),
        ])
        #expect(values.pet.maxHealth == 26 && values.player.maxHealth == 26)
    }
}
