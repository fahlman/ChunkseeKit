import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct PetDataTests {
    func pet(_ species: String, _ fields: [String: NBT] = [:], version: Int? = 5023) throws -> Creature {
        let base: [String: NBT] = ["id": .string("minecraft:" + species), "Health": .float(8),
                                  "Pos": .list([.double(1), .double(64), .double(2)]), "Owner": .intArray([1, 2, 3, 4])]
        return try #require(Creature(Fixtures.mob(base.merging(fields) { _, new in new }), dataVersion: version))
    }

    func item(_ id: String, _ components: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string("minecraft:" + id), "count": .int(1), "components": .compound(components)])
    }

    @Test func savedWolfAppearanceOrderCollarAndArmor() throws {
        let wolf = try pet("wolf", [
            "Health": .float(40), "Sitting": .byte(1), "CollarColor": .byte(1), "variant": .string("minecraft:pale"),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(40)])]),
            "equipment": .compound(["body": item("wolf_armor", ["minecraft:damage": .int(17)])]),
        ])
        #expect(wolf.health == 40 && wolf.maxHealth == 40 && wolf.sittingOrder == true)
        #expect(wolf.appearance == CreatureAppearance(variant: "minecraft:pale") && wolf.collarColor == "orange")
        #expect(wolf.equipment?["body"]?.durability == ItemDurability(remaining: 47, maximum: 64))
        let bytes = try PropertyListEncoder().encode(RegionContents(containers: [], signs: [], namedCreatures: [wolf]))
        #expect(try PropertyListDecoder().decode(RegionContents.self, from: bytes).namedCreatures == [wolf])
    }

    @Test func catAndParrotRetainTheirSavedDetails() throws {
        let cat = try pet("cat", ["variant": .string("minecraft:siamese"), "Sitting": .byte(0)])
        #expect(cat.maxHealth == 10 && cat.sittingOrder == false && cat.collarColor == "red")
        #expect(cat.appearance?.variant == "minecraft:siamese" && cat.equipment == [:])
        let parrot = try pet("parrot", ["Variant": .int(3), "CollarColor": .byte(1), "Sitting": .byte(1)])
        #expect(parrot.appearance?.variant == "minecraft:yellow_blue" && parrot.maxHealth == 6)
        #expect(parrot.sittingOrder == true && parrot.collarColor == "orange" && parrot.equipment == [:])
        let emptyWolf = try pet("wolf")
        #expect(emptyWolf.equipment?.isEmpty == true && emptyWolf.sittingOrder == false)
    }

    @Test func everySavedCollarUsesTheSharedDyeIdentity() throws {
        for (id, color) in DyeColor.allCases.enumerated() {
            #expect(try pet("wolf", ["CollarColor": .int(Int32(id))]).collarColor == color.rawValue)
            #expect(try pet("cat", ["CollarColor": .byte(Int8(id))]).collarColor == color.rawValue)
        }
        #expect(try pet("wolf", ["CollarColor": .int(16)]).collarColor == nil)
    }

    @Test func horseCoatAndMarkingsStaySeparateFromSaddleAndArmor() throws {
        let horse = try pet("horse", ["Variant": .int(772), "Sitting": .byte(1), "CollarColor": .byte(1),
            "equipment": .compound(["saddle": item("saddle"), "body": item("diamond_horse_armor")])])
        #expect(horse.appearance == CreatureAppearance(variant: "minecraft:black", markings: "minecraft:white_dots"))
        #expect(horse.sittingOrder == nil && horse.collarColor == "orange")
        #expect(horse.equipment?.mapValues(\.id) == ["saddle": "minecraft:saddle", "body": "minecraft:diamond_horse_armor"])
        #expect(horse.equipment?["body"]?.durability == nil)
        let llama = try pet("llama", ["Variant": .int(2), "DecorItem": item("red_carpet"), "ChestedHorse": .byte(1)])
        #expect(llama.appearance?.variant == "minecraft:brown")
        #expect(llama.equipment?.mapValues(\.id) == ["body": "minecraft:red_carpet", "storage": "minecraft:chest"])
        let donkey = try pet("donkey", ["SaddleItem": item("saddle")])
        #expect(donkey.appearance == nil && donkey.equipment?["saddle"]?.id == "minecraft:saddle")
    }

    @Test func legacyAppearanceAndEquipmentAndCurrentEquipmentPrecedence() throws {
        let cat = try pet("cat", ["CatType": .int(5)], version: nil)
        #expect(cat.appearance?.variant == "minecraft:calico")
        let horse = try pet("horse", ["ArmorItem": item("golden_horse_armor"), "SaddleItem": item("saddle")], version: nil)
        #expect(horse.equipment?.count == 2)
        let wolf = try pet("wolf", ["body_armor_item": item("wolf_armor")], version: nil)
        #expect(wolf.equipment?["body"]?.id == "minecraft:wolf_armor")
        let empty = try pet("horse", ["equipment": .compound([:]), "ArmorItem": item("diamond_horse_armor")])
        #expect(empty.equipment?.isEmpty == true)
    }

    @Test func maximumHealthIncludesAllSavedModifierOperations() throws {
        let wolf = try pet("wolf", ["Attributes": .list([.compound([
            "Name": .string("generic.maxHealth"), "Base": .double(20), "Modifiers": .list([
                .compound(["Amount": .double(4), "Operation": .int(0)]),
                .compound(["Amount": .double(0.5), "Operation": .int(1)]),
                .compound(["Amount": .double(0.25), "Operation": .int(2)]),
            ]),
        ])])], version: nil)
        #expect(wolf.maxHealth == 45)
        let cat = try pet("cat", ["attributes": .list([.compound([
            "id": .string("minecraft:generic.max_health"), "base": .double(10), "modifiers": .list([
                .compound(["amount": .double(2), "operation": .string("add_value")]),
                .compound(["amount": .double(0.5), "operation": .string("add_multiplied_base")]),
                .compound(["amount": .double(1), "operation": .string("add_multiplied_total")]),
            ]),
        ])])])
        #expect(cat.maxHealth == 36)
    }

    @Test func generatedDefaultsPassThroughTheEntityChunkReader() throws {
        let entity = Fixtures.mob(["id": .string("minecraft:cat"), "Health": .float(7), "Pos": .list([.double(0), .double(64), .double(0)])])
        let chunk = NBT.compound(["DataVersion": .int(5023), "Entities": .list([entity])])
        #expect(Creature.creatures(inEntityChunk: chunk).first?.maxHealth == 10)
        #expect(Creature(entity)?.maxHealth == 10)
        #expect(try pet("cat", version: 100).maxHealth == 10)
        #expect(try pet("cat", version: 6000).maxHealth == 10)
    }

    @Test func unknownMaximumStaysUnavailableAndExplicitEquipmentIsIncluded() throws {
        let unknown = try pet("cat", ["attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .string("unknown")])])])
        #expect(unknown.maxHealth == nil)
        let gear = try pet("wolf", ["equipment": .compound(["body": item("wolf_armor", ["minecraft:attribute_modifiers": .list([
            .compound(["type": .string("minecraft:max_health"), "amount": .double(10), "operation": .string("add_value")]),
        ])])])])
        #expect(gear.maxHealth == 18)
    }

    @Test func savedHealthBoostModifierIsIncludedOnce() throws {
        let cat = try pet("cat", [
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(10), "modifiers": .list([
                .compound(["id": .string("minecraft:effect.health_boost"), "amount": .double(4), "operation": .string("add_value")]),
            ])])]),
            "active_effects": .list([.compound(["id": .string("minecraft:health_boost"), "amplifier": .byte(0), "duration": .int(1200)])]),
        ])
        #expect(cat.maxHealth == 14)
    }

    @Test(arguments: [("wolf", 8.0), ("horse", 53), ("donkey", 53), ("mule", 53), ("llama", 53),
                      ("trader_llama", 53), ("skeleton_horse", 15), ("zombie_horse", 25), ("camel", 32),
                      ("camel_husk", 32), ("nautilus", 15), ("zombie_nautilus", 15)])
    func omittedMaximumUsesTheLoadedSpeciesDefault(species: String, maximum: Double) throws {
        #expect(try pet(species).maxHealth == maximum)
    }

    @Test func nautilusAndCamelHuskHaveApplicableSaddleAndArmorRows() throws {
        for species in ["nautilus", "zombie_nautilus", "camel_husk"] {
            let creature = try pet(species, ["equipment": .compound(["saddle": item("saddle"), "body": item("diamond_nautilus_armor")])])
            #expect(creature.equipment?.count == 2 && creature.sittingOrder == nil && creature.collarColor == nil)
            #expect(try pet(species).equipment?.isEmpty == true)
        }
    }

    @Test func maximumUsesTheSameFloatPrecisionAsSavedCurrentHealth() throws {
        let base = 25.786716356710073
        let horse = try pet("horse", ["Health": .float(Float(base)),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(base)])])])
        #expect(horse.maxHealth == horse.health)
    }

    @Test func invalidDetailsStayUnavailableAndWildAnimalsKeepReadableAppearance() throws {
        let parrot = try pet("parrot", ["Variant": .int(99), "Sitting": .string("unknown")])
        #expect(parrot.appearance == nil && parrot.sittingOrder == nil)
        #expect(try pet("cat", ["CollarColor": .byte(-1)]).collarColor == nil)
        let wild = try #require(Creature(Fixtures.mob(["id": .string("minecraft:wolf"), "Health": .float(8),
            "Pos": .list([.double(0), .double(64), .double(0)]), "variant": .string("minecraft:pale"), "Sitting": .byte(1), "CollarColor": .byte(14)])))
        #expect(wild.appearance?.variant == "minecraft:pale" && wild.collarColor == "red")
        #expect(wild.sittingOrder == nil && wild.equipment == [:])
    }

    @Test func equipmentDurabilityUsesSavedOverridesAndSkipsUnbreakableOrInvalidItems() throws {
        let custom = try #require(ItemStack(item("wolf_armor", ["minecraft:max_damage": .int(100), "minecraft:damage": .int(7)])))
        #expect(custom.durability == ItemDurability(remaining: 93, maximum: 100))
        #expect(try #require(ItemStack(item("wolf_armor"))).durability?.remaining == 64)
        #expect(try #require(ItemStack(item("saddle"))).durability == nil)
        let invalid: [[String: NBT]] = [
            ["minecraft:unbreakable": .compound([:])], ["minecraft:damage": .int(-1)],
            ["minecraft:max_damage": .int(0)], ["minecraft:damage": .string("unknown")],
            ["!minecraft:max_damage": .compound([:])],
        ]
        for components in invalid {
            #expect(try #require(ItemStack(item("wolf_armor", components))).durability == nil)
        }
    }
}
