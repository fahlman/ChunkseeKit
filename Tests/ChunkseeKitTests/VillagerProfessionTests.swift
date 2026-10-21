import Foundation
import Testing
import ChunkseeKit

@Suite struct VillagerProfessionTests {
    @Test func savedProfessionUsesTheSharedIdentifierRules() throws {
        let cases: [(String, Bool?)] = [
            ("minecraft:none", true), ("none", true), (":none", true),
            ("minecraft:farmer", false), ("farmer", false), ("minecraft:nitwit", false),
            ("example:none", false), ("example:beekeeper", false),
            ("", nil), ("minecraft:", nil), ("Minecraft:none", nil), ("not a profession", nil),
        ]
        for (saved, expected) in cases {
            let villager = try #require(Villager(.compound([
                "VillagerData": .compound(["profession": .string(saved)]),
            ])))
            #expect(villager.isUnemployed == expected, "Saved profession: \(saved)")
            #expect(villager.profession == saved)
        }
    }

    @Test func missingInvalidAndTraderRecordsDoNotInventEmployment() throws {
        let missing: [[String: NBT]] = [[:], ["profession": .int(0)]]
        for fields in missing {
            let villager = try #require(Villager(.compound(["VillagerData": .compound(fields)])))
            #expect(villager.isUnemployed == nil && villager.profession == nil)
        }
        let trader = try #require(Villager(.compound(["Offers": .compound(["Recipes": .list([
            .compound([
                "buy": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
                "sell": .compound(["id": .string("minecraft:cactus"), "count": .int(1)]),
            ]),
        ])])])))
        #expect(trader.trades.count == 1)
        #expect(trader.isUnemployed == nil && trader.profession == nil)
    }

    @Test func cachedAndEditedProfessionsKeepTheirRawValue() throws {
        let old = Data(#"{"profession":"minecraft:none","trades":[]}"#.utf8)
        var villager = try JSONDecoder().decode(Villager.self, from: old)
        #expect(villager.isUnemployed == true)
        let changes: [(String, Bool?)] = [("example:none", false), ("minecraft:nitwit", false),
                                         ("invalid value", nil), ("none", true)]
        for (saved, expected) in changes {
            villager.profession = saved
            let decoded = try JSONDecoder().decode(Villager.self, from: JSONEncoder().encode(villager))
            #expect(villager.isUnemployed == expected)
            #expect(decoded.profession == saved && decoded.isUnemployed == expected)
        }
        villager.profession = nil
        #expect(villager.isUnemployed == nil)
    }
}
