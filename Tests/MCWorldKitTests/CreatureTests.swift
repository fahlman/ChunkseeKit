import Foundation
import Testing
@testable import MCWorldKit

@Suite struct CreatureTests {
    let owner = UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!

    func ownerInts() -> NBT { Fixtures.uuidInts(owner) }

    func pos(_ x: Double, _ y: Double, _ z: Double) -> NBT { .list([.double(x), .double(y), .double(z)]) }

    @Test func creaturesPetsAndVillagers() throws {
        let chunk = NBT.compound(["Entities": .list([
            .compound(["id": .string("minecraft:wolf"), "Health": .float(8), "Pos": pos(-4563, 63, -1247.4),
                       "CustomName": .string("§fSummer§r: [§a❤❤§c]"), "Owner": ownerInts()]),
            .compound(["id": .string("minecraft:cat"), "Health": .float(10), "Pos": pos(1, 2, 3), "OwnerUUID": .string(owner.uuidString)]),
            .compound(["id": .string("minecraft:villager"), "Health": .float(20), "Pos": pos(0, 64, 0),
                       "VillagerData": .compound(["profession": .string("minecraft:farmer"), "level": .int(2), "type": .string("minecraft:desert")]),
                       "Offers": .compound(["Recipes": .list([.compound([
                           "buy": .compound(["id": .string("minecraft:wheat"), "count": .int(20)]),
                           "sell": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
                           "uses": .int(16), "maxUses": .int(16),
                       ])])])]),
            .compound(["id": .string("minecraft:item"), "Pos": pos(0, 0, 0), "Item": .compound(["id": .string("minecraft:dirt")])]),
            .compound(["id": .string("minecraft:sheep"), "Health": .float(8), "Pos": pos(5, 64, 5), "CustomName": .string("§r")]),
        ])])
        let creatures = Creature.creatures(inEntityChunk: chunk)
        #expect(creatures.map(\.id) == ["minecraft:wolf", "minecraft:cat", "minecraft:villager", "minecraft:sheep"])
        #expect(creatures[0].customName == "Summer: [❤❤]" && creatures[0].owner == owner)
        #expect(creatures[1].owner == owner && creatures[1].customName == nil)
        let villager = try #require(creatures[2].villager)
        #expect(villager.profession == "minecraft:farmer" && villager.level == 2 && villager.type == "minecraft:desert")
        #expect(villager.trades.first?.buy.count == 20 && villager.trades.first?.sell.id == "minecraft:emerald")
        #expect(villager.trades.first?.isSoldOut == true)
        #expect(creatures[3].customName == nil)   // only formatting codes
        #expect(creatures[0].villager == nil)
    }
}
