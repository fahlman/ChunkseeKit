import Foundation
import Testing
@testable import MCWorldKit

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
            signs: [Sign(kind: "minecraft:sign", x: 0, y: 64, z: 0, front: ["Hi", "", "", ""])],
            namedCreatures: [Creature(id: "minecraft:wolf", x: 1.5, y: 64, z: 2.5, customName: "Summer", owner: UUID())])
        #expect(try roundTrip(contents))
        #expect(try roundTrip(PointOfInterest(type: "minecraft:home", x: 1, y: 2, z: 3, freeTickets: 0)))
    }
}
