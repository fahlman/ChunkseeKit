import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct CodableTests {
    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> Bool {
        let data = try PropertyListEncoder().encode(value)
        return try PropertyListDecoder().decode(T.self, from: data) == value
    }

    @Test func resultTypesRoundTrip() throws {
        let nbt = NBT.compound(["n": .int(1), "list": .list([.string("a")]), "longs": .longArray([1, -2])])
        #expect(try roundTrip(nbt))
        #expect(try roundTrip(NBT.string("plain")))
        let item = try #require(ItemStack(.compound(["id": .string("minecraft:shulker_box"), "count": .int(1), "components": .compound([
            "minecraft:custom_name": .string("Box"),
            "minecraft:container": .list([.compound(["slot": .int(0), "item": .compound(["id": .string("minecraft:diamond"), "count": .int(64)])])]),
        ])])))
        let contents = RegionContents(
            containers: [ItemContainer(kind: "minecraft:chest", x: 1, y: 2, z: 3, items: [item], customName: nil, isSealedLoot: false, isEntity: false)],
            signs: [Sign(kind: "minecraft:sign", x: 0, y: 64, z: 0, front: ["Hi", "", "", ""])])
        #expect(try roundTrip(contents))
        #expect(try roundTrip(Creature(id: "minecraft:wolf", x: 1.5, y: 64, z: 2.5,
                                     customName: "Summer", owner: UUID(), health: 7.5)))
        #expect(try roundTrip(PointOfInterest(type: "minecraft:home", x: 1, y: 2, z: 3, freeTickets: 0)))
    }

    @Test func cachedCreatureFromBeforeHealthStillDecodes() throws {
        let owner = UUID()
        let oldRecord: [String: Any] = [
            "id": "minecraft:cat", "x": 1.0, "y": 64.0, "z": 2.0, "customName": "Mittens",
            "owner": owner.uuidString,
        ]
        let bytes = try PropertyListSerialization.data(fromPropertyList: oldRecord, format: .binary, options: 0)
        let creature = try PropertyListDecoder().decode(Creature.self, from: bytes)
        #expect(creature.health == nil && creature.owner == owner && creature.customName == "Mittens")
        #expect(creature.x == 1 && creature.y == 64 && creature.z == 2)
        #expect(creature.maximumHealth(enchantments: [:]) == nil && creature.sittingOrder == nil && creature.appearance == nil)
        #expect(creature.collarColor == nil && creature.equipment == nil)
        #expect(creature.uuid == nil)
    }

    @Test func anOldResolvedMaximumDoesNotSubstituteForSavedInputs() throws {
        let bytes = Data(#"{"id":"minecraft:cat","x":1,"y":64,"z":2,"health":0,"maxHealth":10}"#.utf8)
        let creature = try JSONDecoder().decode(Creature.self, from: bytes)
        #expect(creature.health == 0 && creature.healthInputs == nil)
        #expect(creature.maximumHealth(enchantments: [:]) == nil)
    }
}
