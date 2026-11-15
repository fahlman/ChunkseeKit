import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct LegacyEquipmentTests {
    private func item(_ id: String, components: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string(id), "count": .int(1), "components": .compound(components)])
    }

    private func mob(_ fields: [String: NBT] = [:], id: String = "example:mount") -> NBT {
        Fixtures.mob(["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)])]
            .merging(fields) { $1 })
    }

    @Test func savedItemFieldsApplyWithoutTypeOwnerOrVersionInventories() throws {
        for id in ["minecraft:horse", "minecraft:llama", "minecraft:wolf", "example:mount"] {
            for version in [nil, 999999] as [Int?] {
                for (key, slot) in [("ArmorItem", "body"), ("DecorItem", "body"),
                                    ("body_armor_item", "body"), ("SaddleItem", "saddle"), ("saddle", "saddle")] {
                    let creature = try #require(Creature(mob([key: item("example:gear")], id: id), dataVersion: version))
                    #expect(creature.equipment?.mapValues(\.id) == [slot: "example:gear"])
                    #expect(creature.owner == nil)
                }
            }
        }
    }

    @Test func currentAndEmptyItemFieldsSupersedeOlderEquipment() throws {
        let legacy: [String: NBT] = ["ArmorItem": item("example:armor"), "DecorItem": item("example:decor"),
            "SaddleItem": item("example:saddle"), "Saddle": .byte(1)]
        for slots in [[:], ["example:back": item("example:pack")]] as [[String: NBT]] {
            let creature = try #require(Creature(mob(legacy.merging(["equipment": .compound(slots)]) { $1 })))
            #expect(creature.equipment?.mapValues(\.id) == slots.compactMapValues { $0["id"]?.string })
        }
        let emptySaddle = try #require(Creature(mob(legacy.merging(["saddle": .compound([:])]) { $1 })))
        #expect(emptySaddle.equipment?["saddle"] == nil)
        let savedSaddle = try #require(Creature(mob(legacy.merging(["saddle": item("example:new_saddle")]) { $1 })))
        #expect(savedSaddle.equipment?["saddle"]?.id == "example:new_saddle")
    }

    @Test func omittedEquipmentIsEmptyButUnreadableSavedFieldsStayUnavailable() throws {
        for id in ["minecraft:cat", "minecraft:wolf", "minecraft:zombie", "example:mount"] {
            #expect(try #require(Creature(mob(id: id))).equipment == [:])
            #expect(try #require(Creature(mob(["Owner": .intArray([1, 2, 3, 4])], id: id))).equipment == [:])
            for key in ["equipment", "ArmorItems", "HandItems", "body_armor_item", "ArmorItem", "DecorItem", "saddle", "SaddleItem", "Saddle"] {
                #expect(try #require(Creature(mob([key: .string("unreadable")], id: id))).equipment == nil)
            }
        }
        let partial = try #require(Creature(mob(["ArmorItem": .string("unreadable"),
            "HandItems": .list([item("example:held")])])))
        #expect(partial.equipment?.mapValues(\.id) == ["mainhand": "example:held"])
    }

    @Test func attachmentFlagsRetainSaddlesAndChestsWithoutReplacingSavedItems() throws {
        let attached = try #require(Creature(mob(["Saddle": .byte(1), "ChestedHorse": .byte(1)])))
        #expect(attached.equipment?.mapValues(\.id) == ["saddle": "minecraft:saddle", "storage": "minecraft:chest"])
        #expect(attached.equipment?["saddle"]?.count == 1)
        #expect(try #require(Creature(mob(["Saddle": .byte(0), "ChestedHorse": .byte(0)]))).equipment == [:])
        let saved = try #require(Creature(mob(["ChestedHorse": .byte(1),
            "equipment": .compound(["storage": item("example:storage")])])))
        #expect(saved.equipment?.mapValues(\.id) == ["storage": "example:storage"])
    }

    @Test func regionalScanHealthContainersAndCacheShareLegacyEquipment() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Legacy equipment"), "DataVersion": .int(999999),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let gear = item("example:armor", components: ["minecraft:attribute_modifiers": .list([.compound([
            "type": .string("minecraft:max_health"), "id": .string("example:vitality"), "amount": .double(4),
            "operation": .string("add_value"), "slot": .string("body"),
        ])])])
        let entity = mob(["DecorItem": gear, "Saddle": .byte(1), "ChestedHorse": .byte(1),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20)])])])
        let region = RegionPosition(x: 0, z: 0)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "DataVersion": .int(999999), "Entities": .list([entity]),
        ]))]), to: dimension.regionURL(.entities, at: region))
        let facts = try dimension.scan(region: region)
        let creature = try #require(facts.creatures.first)
        #expect(creature.equipment?.mapValues(\.id) == ["body": "example:armor", "saddle": "minecraft:saddle", "storage": "minecraft:chest"])
        #expect(creature.maximumHealth(enchantments: [:]) == 24)
        #expect(Set(facts.containers.flatMap(\.items).map(\.id)) == ["example:armor", "minecraft:saddle"])
        let encoded = try JSONEncoder().encode(facts)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: encoded)
        #expect(restored.creatures == facts.creatures && restored.containers == facts.containers)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old["version"] = RegionFacts.interpretationVersion.revision - 1
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RegionFacts.self, from: JSONSerialization.data(withJSONObject: old))
        }
    }
}
