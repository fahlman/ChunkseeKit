import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct PlayerDetailTests {
    let uuid = UUID(uuidString: "52DFB519-DE9C-47E6-BC6C-BB053CC423E7")!

    func player(_ fields: [String: NBT] = [:]) -> PlayerInfo {
        PlayerInfo(uuid: uuid, nbt: .compound(["DataVersion": NBT.int(5023)].merging(fields) { _, new in new }))
    }

    func item(_ id: String, slot: Int8? = nil, components: [String: NBT] = [:]) -> NBT {
        var fields: [String: NBT] = ["id": .string("minecraft:" + id), "count": .int(1), "components": .compound(components)]
        if let slot { fields["Slot"] = .byte(slot) }
        return .compound(fields)
    }

    func modifier(_ amount: Double, slot: String, id: String = "example:extra_health", operation: String = "add_value") -> NBT {
        .compound(["type": .string("minecraft:max_health"), "id": .string(id), "amount": .double(amount),
                   "operation": .string(operation), "slot": .string(slot)])
    }

    @Test func activeEffectsKeepStrengthDurationAndInfinityWithoutHiddenOrExpiredEffects() {
        let info = player(["active_effects": .list([
            .compound(["id": .string("minecraft:strength"), "amplifier": .int(1), "duration": .int(1680),
                       "hidden_effect": .compound(["id": .string("minecraft:strength"), "amplifier": .int(0), "duration": .int(9000)])]),
            .compound(["id": .string("minecraft:night_vision"), "duration": .int(-1)]),
            .compound(["id": .string("minecraft:speed"), "duration": .int(0)]),
            .compound(["id": .string("minecraft:poison"), "duration": .int(-2)]),
            .compound(["id": .string("example:custom"), "duration": .int(100)]),
            .compound(["duration": .int(100)]),
        ])])
        #expect(info.activeEffects.map(\.id) == ["minecraft:strength", "minecraft:night_vision", "example:custom"])
        #expect(info.activeEffects.map(\.level) == [2, 1, 1])
        #expect(info.activeEffects.map(\.durationTicks) == [1680, -1, 100])
        #expect(player().activeEffects.isEmpty)
    }

    @Test func legacyEffectsAndEquipmentRemainReadable() throws {
        let info = player(["ActiveEffects": .list([.compound(["Id": .byte(1), "Amplifier": .byte(2), "Duration": .int(200)])]),
            "Inventory": .list([.compound(["id": .string("minecraft:diamond_helmet"), "Count": .byte(1), "Slot": .byte(103),
                "tag": .compound(["Damage": .short(12), "Enchantments": .list([.compound(["id": .string("minecraft:protection"), "lvl": .short(4)])])])])])])
        #expect(info.activeEffects == [StatusEffect(id: "minecraft:speed", amplifier: 2, durationTicks: 200)])
        let helmet = try #require(info.equipment["head"])
        #expect(helmet.durability == ItemDurability(remaining: 351, maximum: 363))
        #expect(helmet.enchantments == ["minecraft:protection": 4])
    }

    @Test func maximumIncludesHealthBoostAndOnlyEquippedItemModifiers() {
        let info = player([
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20), "modifiers": .list([
                .compound(["id": .string("example:permanent"), "amount": .double(4), "operation": .string("add_value")]),
            ])])]),
            "active_effects": .list([.compound(["id": .string("minecraft:health_boost"), "amplifier": .byte(1), "duration": .int(1000)])]),
            "SelectedItemSlot": .int(2),
            "Inventory": .list([
                item("diamond_sword", slot: 2, components: ["minecraft:attribute_modifiers": .list([modifier(6, slot: "mainhand")])]),
                item("diamond_sword", slot: 3, components: ["minecraft:attribute_modifiers": .list([modifier(100, slot: "mainhand")])]),
            ]),
            "equipment": .compound(["head": item("diamond_helmet", components: ["minecraft:attribute_modifiers": .list([
                modifier(0.25, slot: "head", id: "example:helmet_bonus", operation: "add_multiplied_total"),
            ])])]),
        ])
        #expect(info.maxHealth == 47.5) // (20 + 4 + 8 + 6) × 1.25; unselected sword contributes nothing.
        #expect(info.mainHandItem?.slot == 2)
        let unmatched = player(["SelectedItemSlot": .int(0), "Inventory": .list([
            item("diamond_sword", slot: 0, components: ["minecraft:attribute_modifiers": .list([modifier(100, slot: "head")])]),
        ])])
        #expect(unmatched.maxHealth == 20)
    }

    @Test func transientIdentityReplacesSavedModifierAndLegacySlotsApply() {
        let info = player(["attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20),
            "modifiers": .list([.compound(["id": .string("minecraft:effect.health_boost"), "amount": .double(4), "operation": .string("add_value")])])])]),
            "active_effects": .list([.compound(["id": .string("minecraft:health_boost"), "amplifier": .byte(1), "duration": .int(1000)])]),
        ])
        #expect(info.maxHealth == 28)
        let legacy = player(["Inventory": .list([.compound(["id": .string("minecraft:iron_helmet"), "Slot": .byte(103), "Count": .byte(1),
            "tag": .compound(["AttributeModifiers": .list([.compound([
                "AttributeName": .string("generic.maxHealth"), "Amount": .double(10), "Operation": .int(0), "Slot": .string("head"),
            ])])])])])])
        #expect(legacy.maxHealth == 30)
    }

    @Test func maximumAndMainHandStayUnavailableWhenDataCannotResolveThem() {
        #expect(PlayerInfo(uuid: uuid, nbt: .compound([:])).maxHealth == nil)
        #expect(player().maxHealth == 20 && player().mainHandItem == nil)
        #expect(player(["DataVersion": .int(6000)]).maxHealth == nil)
        let unsupported = player(["equipment": .compound(["head": item("diamond_helmet", components: ["minecraft:attribute_modifiers": .list([
            modifier(10, slot: "head", operation: "unknown_operation"),
        ])])])])
        #expect(unsupported.maxHealth == nil)
        #expect(player(["active_effects": .list([.compound(["id": .string("example:custom"), "duration": .int(100)])])]).maxHealth == nil)
        let explicit = player(["SelectedItemSlot": .int(0), "Inventory": .list([item("iron_sword", slot: 0)]),
                               "equipment": .compound(["mainhand": item("diamond_sword")])])
        #expect(explicit.mainHandItem?.id == "minecraft:diamond_sword")
    }

    @Test(arguments: [("diamond_pickaxe", 1561), ("iron_sword", 250), ("copper_axe", 190), ("wooden_spear", 59),
                      ("diamond_chestplate", 528), ("copper_boots", 143), ("turtle_helmet", 275), ("elytra", 432), ("shield", 336)])
    func vanillaDurabilityDefaultsAreAvailableWhenTheSaveOmitsThem(id: String, maximum: Int) throws {
        let stack = try #require(ItemStack(item(id, components: ["minecraft:damage": .int(10)])))
        #expect(stack.durability == ItemDurability(remaining: maximum - 10, maximum: maximum))
    }

    @Test func durabilityHonorsOverridesAndOnlyAppliesToDamageableItems() throws {
        let customized = try #require(ItemStack(item("diamond_sword", components: ["minecraft:max_damage": .int(5000), "minecraft:damage": .int(2)])))
        #expect(customized.durability?.remaining == 4998)
        let removed: [[String: NBT]] = [
            ["minecraft:unbreakable": .compound([:])], ["!minecraft:damage": .compound([:])], ["!minecraft:max_damage": .compound([:])],
        ]
        for components in removed { #expect(try #require(ItemStack(item("diamond_sword", components: components))).durability == nil) }
        #expect(try #require(ItemStack(item("apple"))).durability == nil)
        #expect(ItemStack(id: "example:diamond_sword").durability == nil)
    }

    @Test func individualCreatureIdentityReadsCurrentAndLegacyUUIDsAndSurvivesCaching() throws {
        let expected = UUID(uuidString: "00000001-0000-0002-0000-000300000004")!
        let encodings: [[String: NBT]] = [
            ["UUID": .intArray([1, 2, 3, 4])], ["UUID": .string(expected.uuidString)],
            ["UUIDMost": .long(0x0000000100000002), "UUIDLeast": .long(0x0000000300000004)],
        ]
        for fields in encodings {
            let entity: [String: NBT] = ["id": .string("minecraft:wolf"), "Health": .float(40),
                                       "Pos": .list([.double(1), .double(64), .double(2)])]
            let creature = try #require(Creature(.compound(entity.merging(fields) { _, new in new })))
            #expect(creature.uuid == expected)
            let encoded = try PropertyListEncoder().encode(creature)
            #expect(try PropertyListDecoder().decode(Creature.self, from: encoded).uuid == expected)
        }
    }
}
