import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct MobAppearanceTests {
    private func mob(_ id: String, _ fields: [String: NBT] = [:], owned: Bool = false) -> NBT {
        var base: [String: NBT] = ["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)]),
                                  "CustomName": .string("Kept"), "Health": .float(7)]
        if owned { base["Owner"] = .intArray([1, 2, 3, 4]) }
        return Fixtures.mob(base.merging(fields) { $1 })
    }

    private func item(_ id: String) -> NBT { .compound(["id": .string(id), "count": .int(1)]) }

    @Test func savedRegistryVariantsAndCollarsDoNotRequireATypeCatalogOrOwner() throws {
        for owned in [false, true] {
            for id in ["minecraft:cat", "minecraft:wolf", "minecraft:frog", "minecraft:pig",
                       "minecraft:cow", "minecraft:chicken", "example:new_mob"] {
                let creature = try #require(Creature(mob(id, ["variant": .string("example:spotted"),
                    "CollarColor": .byte(11)], owned: owned), dataVersion: 999999))
                #expect(creature.appearance == CreatureAppearance(variant: "example:spotted"))
                #expect(creature.collarColor == "blue" && creature.health == 7 && creature.customName == "Kept")
                #expect((creature.owner != nil) == owned)
            }
        }
        let future = try #require(Creature(mob("example:future", ["Variant": .string("example:striped")])))
        #expect(future.appearance?.variant == "example:striped")
        let currentCat = try #require(Creature(mob("minecraft:cat", ["variant": .string("example:new"), "CatType": .int(4)])))
        #expect(currentCat.appearance?.variant == "example:new")
        #expect(Creature(mob("minecraft:cat"))?.collarColor == nil)
    }

    @Test func numericAppearancesMatchTheGameForWildAndOwnedMobs() throws {
        // Independent expectations for the public saved-number interpretation, not generated inputs.
        let cases: [(String, String, [String])] = [
            ("sheep", "Color", ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                                 "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]),
            ("axolotl", "Variant", ["lucy", "wild", "gold", "cyan", "blue"]),
            ("parrot", "Variant", ["red_blue", "blue", "green", "yellow_blue", "gray"]),
            ("llama", "Variant", ["creamy", "white", "brown", "gray"]),
            ("trader_llama", "Variant", ["creamy", "white", "brown", "gray"]),
            ("horse", "Variant", ["white", "creamy", "chestnut", "brown", "black", "gray", "dark_brown"]),
            ("cat", "CatType", ["tabby", "black", "red", "siamese", "british_shorthair", "calico",
                                "persian", "ragdoll", "white", "jellie", "all_black"]),
        ]
        for owned in [false, true] {
            for (species, field, variants) in cases {
                for (number, variant) in variants.enumerated() {
                    let creature = try #require(Creature(mob("minecraft:" + species,
                        [field: .int(Int32(number))], owned: owned)))
                    #expect(creature.appearance == CreatureAppearance(variant: "minecraft:" + variant))
                }
            }
            for (number, marking) in [nil, "white", "white_field", "white_dots", "black_dots"].enumerated() {
                let horse = try #require(Creature(mob("minecraft:horse", ["Variant": .int(Int32(4 + number * 256))], owned: owned)))
                #expect(horse.appearance == CreatureAppearance(variant: "minecraft:black", markings: marking.map { "minecraft:" + $0 }))
            }
        }
    }

    @Test func unknownAppearanceDoesNotDiscardOtherSavedFacts() throws {
        for (id, field, value) in [("example:unfamiliar", "variant", NBT.compound(["pattern": .string("future")])),
                                   ("example:unfamiliar", "Variant", .int(123)),
                                   ("minecraft:axolotl", "Variant", .int(99)),
                                   ("minecraft:sheep", "Color", .int(-1))] {
            let creature = try #require(Creature(mob(id, [field: value,
                "equipment": .compound(["example:back": item("example:pack")])])))
            #expect(creature.appearance == nil)
            #expect(creature.id == id && creature.customName == "Kept" && creature.health == 7)
            #expect(creature.x == 1 && creature.y == 64 && creature.z == 2)
            #expect(creature.equipment?["example:back"]?.id == "example:pack")
        }
        let horse = try #require(Creature(mob("minecraft:horse", ["Variant": .int(4 + 99 * 256)])))
        #expect(horse.appearance == CreatureAppearance(variant: "minecraft:black"))
    }

    @Test func savedEquipmentAndEmptySlotsAreKeptWithoutAnOwner() throws {
        for id in ["minecraft:zombie", "minecraft:pig", "example:wearer"] {
            let armored = try #require(Creature(mob(id, ["equipment": .compound([
                "head": item("minecraft:iron_helmet"), "example:back": item("example:pack")])])))
            #expect(armored.equipment?.mapValues(\.id) == ["head": "minecraft:iron_helmet", "example:back": "example:pack"])
            let empty = try #require(Creature(mob(id, ["equipment": .compound([:]),
                "ArmorItems": .list([item("minecraft:iron_boots")])])))
            #expect(empty.equipment == [:])
            #expect(Creature(mob(id, ["HandItems": .list(.compound, [])]))?.equipment == [:])
            #expect(Creature(mob(id, ["equipment": .string("unreadable")]))?.equipment == nil)
            let legacy = try #require(Creature(mob(id, ["ArmorItems": .list([item("minecraft:iron_boots")]),
                "HandItems": .list([item("minecraft:bow")])])))
            #expect(legacy.equipment?.mapValues(\.id) == ["feet": "minecraft:iron_boots", "mainhand": "minecraft:bow"])
        }
        let storage = try #require(Creature(mob("example:carrier", ["ChestedHorse": .byte(1)])))
        #expect(storage.equipment?["storage"]?.id == "minecraft:chest")
        let saved = try #require(Creature(mob("minecraft:llama", ["ChestedHorse": .byte(1),
            "equipment": .compound(["storage": item("example:storage")])])))
        #expect(saved.equipment?["storage"]?.id == "example:storage")
    }

    @Test func regionScanAndCacheKeepWildAppearanceAndEquipment() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Mob appearance")])]),
                                    to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let entities = [mob("minecraft:sheep", ["Color": .byte(5)]),
                        mob("minecraft:axolotl", ["Variant": .int(4)]),
                        mob("minecraft:pig", ["variant": .string("example:cold")]),
                        mob("minecraft:zombie", ["equipment": .compound(["head": item("minecraft:iron_helmet")])])]
        let region = RegionPosition(x: 0, z: 0)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound(["Entities": .list(entities)]))]),
                           to: dimension.regionURL(.entities, at: region))
        let creatures = try dimension.creatures(chunkX: 0, chunkZ: 0)
        #expect(creatures.count == 4 && creatures.allSatisfy { $0.owner == nil })
        #expect(creatures.compactMap(\.appearance?.variant) == ["minecraft:lime", "minecraft:blue", "example:cold"])
        #expect(creatures.last?.equipment?["head"]?.id == "minecraft:iron_helmet")
        let facts = try dimension.scan(region: region)
        #expect(facts.creatures == creatures)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.creatures == creatures)
    }
}
