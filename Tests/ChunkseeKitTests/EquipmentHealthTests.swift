import Foundation
import ChunkseeKitTestSupport
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
        try Fixtures.writeGzippedNBT(Fixtures.mob(saved.merging(fields) { $1 }), to: file)
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
        let irrelevantLegacyField = try pair(["ArmorItem": item(["minecraft:attribute_modifiers": .list([modifier(100, slot: "body")])])])
        #expect(irrelevantLegacyField.pet.maxHealth == 20) // ArmorItem is a horse field, not a wolf field.
        let invalid = try pair(["equipment": .compound(["body": item(["minecraft:attribute_modifiers": .string("unreadable")])])])
        #expect(invalid.pet.maxHealth == nil && invalid.player.maxHealth == nil)
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

    @Test func oldHorseBodyConversionClearsTheChestSlotButLlamaConversionKeepsIt() throws {
        let chest = item(["minecraft:attribute_modifiers": .list([modifier(100, slot: "any", id: "example:old_chest")])], id: "minecraft:iron_chestplate")
        let body = item(["minecraft:attribute_modifiers": .list([modifier(3, slot: "body")])], id: "minecraft:diamond_horse_armor")
        let armor = NBT.list([.compound([:]), .compound([:]), chest, .compound([:])])
        for oldBody in [body, .compound([:])] {
            let horse = try pair(["id": .string("minecraft:horse"), "ArmorItems": armor, "ArmorItem": oldBody]).pet
            #expect(horse.equipment?["chest"] == nil)
            #expect(horse.maxHealth == (oldBody == body ? 23 : 20))
        }
        let llama = try pair(["id": .string("minecraft:llama"), "ArmorItems": armor, "DecorItem": body]).pet
        #expect(llama.equipment?["chest"]?.id == "minecraft:iron_chestplate")
        #expect(llama.maxHealth == 123)
    }

    @Test func unsupportedActiveEnchantmentsDoNotReturnPartialHealth() throws {
        let active = NBT.compound(["example:vitality": .int(2)])
        let components: [[String: NBT]] = [
            ["minecraft:enchantments": active],
            ["minecraft:enchantments": .compound(["levels": active, "show_in_tooltip": .byte(0)])],
            ["minecraft:enchantments": .compound(["minecraft:custom_health": .int(1), "minecraft:protection": .int(4)])],
            ["minecraft:enchantments": active, "!minecraft:attribute_modifiers": .compound([:])],
            ["minecraft:enchantments": active, "minecraft:attribute_modifiers": .list([modifier(4, slot: "body")])],
        ]
        for fields in components {
            let values = try pair(["equipment": .compound(["body": item(fields)])])
            #expect(values.pet.maxHealth == nil && values.player.maxHealth == nil)
        }
        let boots = NBT.compound(["id": .string("minecraft:iron_boots"), "Count": .byte(1), "Slot": .byte(100),
            "tag": .compound(["Enchantments": .list([.compound(["id": .string("example:vitality"), "lvl": .short(2)])])])])
        let legacy = try pair(["ArmorItems": .list([boots]), "Inventory": .list([boots])])
        #expect(legacy.pet.maxHealth == nil && legacy.player.maxHealth == nil)
    }

    @Test func storedRemovedEmptyAndBrokenEnchantmentsDoNotHideHealth() throws {
        let active = NBT.compound(["example:vitality": .int(2)])
        let stored = NBT.compound(["id": .string("minecraft:enchanted_book"), "Count": .byte(1), "tag": .compound([
            "StoredEnchantments": .list([.compound(["id": .string("example:vitality"), "lvl": .short(2)])]),
        ])])
        let items = [
            item(["minecraft:stored_enchantments": active], id: "minecraft:enchanted_book"),
            item(["minecraft:stored_enchantments": .compound(["levels": active])], id: "minecraft:enchanted_book"),
            stored,
            item(["!minecraft:enchantments": .compound([:]), "minecraft:enchantments": active]),
            item(["minecraft:enchantments": active], count: 0),
            item(["minecraft:enchantments": active, "minecraft:damage": .int(64)]),
        ]
        for gear in items {
            let values = try pair(["equipment": .compound(["body": gear])])
            #expect(values.pet.maxHealth == 20 && values.player.maxHealth == 20)
        }
        // Stored enchantments stay available for display/search without becoming equipped effects.
        for gear in items.prefix(3) {
            #expect(ItemStack(gear)?.enchantments == ["example:vitality": 2])
        }
        // Without a resource snapshot even a vanilla ID cannot prove its definition unchanged.
        let unresolved = try pair(["equipment": .compound(["body": item([
            "minecraft:enchantments": .compound(["minecraft:protection": .int(4), "minecraft:mending": .int(1)])])])])
        #expect(unresolved.pet.maxHealth == nil && unresolved.player.maxHealth == nil)
    }

    @Test func onlyTheEquippedSelectedItemIntroducesEnchantmentUncertainty() throws {
        let gear = NBT.compound(["id": .string("minecraft:diamond_sword"), "count": .int(1), "Slot": .byte(0),
            "components": .compound(["minecraft:enchantments": .compound(["example:vitality": .int(2)])])])
        for selected in [Int32(0), 1] {
            let values = try pair(["Inventory": .list([gear]), "SelectedItemSlot": .int(selected),
                                   "Items": .list([gear])])
            #expect(values.player.maxHealth == (selected == 0 ? nil : 20))
            #expect(values.pet.maxHealth == 20)
        }
        let held = try pair(["HandItems": .list([gear]), "equipment": .compound(["mainhand": gear])])
        #expect(held.pet.maxHealth == nil && held.player.maxHealth == nil)
    }
}
