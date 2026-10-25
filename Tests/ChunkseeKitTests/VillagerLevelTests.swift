import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct VillagerLevelTests {
    private func creature(data: NBT?, trader: Bool = false) throws -> Creature {
        var entity: [String: NBT] = [
            "id": .string(trader ? "minecraft:wandering_trader" : "minecraft:villager"),
            "Health": .float(20), "Pos": .list([.double(0), .double(64), .double(0)]),
        ]
        entity["VillagerData"] = data
        if trader {
            entity["Offers"] = .compound(["Recipes": .list([.compound([
                "buy": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
                "sell": .compound(["id": .string("minecraft:fern"), "count": .int(1)]),
            ])])])
        }
        let chunk = NBT.compound(["DataVersion": .int(5023), "Entities": .list([Fixtures.mob(entity)])])
        return try #require(Creature.creatures(inEntityChunk: chunk).first)
    }

    @Test func missingLevelInVillagerDataUsesTheGameDefault() throws {
        for data in [NBT.compound(["profession": .string("minecraft:farmer")]), .compound([:])] {
            let villager = try #require(creature(data: data).villager)
            #expect(villager.level == 1)
        }
    }

    @Test func explicitLevelsArePreservedAndMalformedLevelsStayUnavailable() throws {
        for value in [-1, 0, 1, 2, 3, 4, 5, 6] {
            let villager = try #require(creature(data: .compound(["level": .int(Int32(value))])).villager)
            #expect(villager.level == value)
        }
        let malformed = try #require(creature(data: .compound(["level": .string("unknown")])).villager)
        #expect(malformed.level == nil)
    }

    @Test func absentOrMalformedVillagerDataDoesNotInventALevel() throws {
        #expect(try creature(data: nil).villager == nil)
        for data in [NBT.string("unknown"), .list([])] {
            #expect(try creature(data: data).villager?.level == nil)
        }
        let trader = try #require(creature(data: nil, trader: true).villager)
        #expect(trader.level == nil && trader.trades.count == 1)
    }

    @Test func cachedUnavailableLevelsNeedARescan() throws {
        var original = try creature(data: .compound(["level": .int(2)]))
        original.villager?.level = nil
        let cached = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Creature.self, from: cached)
        #expect(decoded.villager?.level == nil)
    }
}
