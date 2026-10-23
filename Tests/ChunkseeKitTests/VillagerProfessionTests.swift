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

    @Test func tradingProfessionsDoNotNeedOffersToHaveBeenSaved() throws {
        let trading = ["armorer", "butcher", "cartographer", "cleric", "farmer", "fisherman",
                       "fletcher", "leatherworker", "librarian", "mason", "shepherd", "toolsmith",
                       "weaponsmith"]
        for profession in trading + ["none", "nitwit"] {
            for prefix in ["minecraft:", "", ":"] {
                let saved = prefix + profession
                var nbt: [String: NBT] = ["VillagerData": .compound(["profession": .string(saved)])]
                for offersSaved in [false, true] {
                    if offersSaved { nbt["Offers"] = .compound(["Recipes": .list([])]) }
                    let villager = try #require(Villager(.compound(nbt)))
                    #expect(villager.supportsTrading == trading.contains(profession), "Saved profession: \(saved)")
                    #expect(villager.level == 1 && villager.trades.isEmpty)
                }
            }
        }
    }

    @Test func absentOrUnverifiedProfessionsDoNotInventTrading() throws {
        let professions: [NBT?] = [nil, .int(0), .string(""), .string("minecraft:"),
                                  .string("Minecraft:farmer"), .string("not a profession"),
                                  .string("example:farmer"), .string("example:none"),
                                  .string("minecraft:beekeeper")]
        for profession in professions {
            var data: [String: NBT] = [:]
            data["profession"] = profession
            let villager = try #require(Villager(.compound([
                "VillagerData": .compound(data),
                "Offers": .compound(["Recipes": .list([.compound(["buy": .int(0)])])]),
            ])))
            #expect(villager.supportsTrading == nil)
            #expect(villager.trades.isEmpty)
        }
    }

    @Test func savedOffersEstablishTradingIncludingCustomAndEditedVillagers() throws {
        for profession in [nil, "example:beekeeper", "minecraft:none", "minecraft:nitwit", "invalid value"] {
            var nbt: [String: NBT] = ["Offers": .compound(["Recipes": .list([
                .compound([
                    "buy": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
                    "sell": .compound(["id": .string("minecraft:cactus"), "count": .int(1)]),
                    "uses": .int(12), "maxUses": .int(12),
                ]),
            ])])]
            if let profession { nbt["VillagerData"] = .compound(["profession": .string(profession)]) }
            let villager = try #require(Villager(.compound(nbt)))
            #expect(villager.supportsTrading == true)
            #expect(villager.trades.first?.isSoldOut == true)
            #expect(villager.profession == profession)
            #expect(villager.level == (profession == nil ? nil : 1))
        }
    }

    @Test func cachedTradingFactsFollowTheExistingMutableFields() throws {
        let old = Data(#"{"profession":"minecraft:nitwit","level":1,"trades":[]}"#.utf8)
        var villager = try JSONDecoder().decode(Villager.self, from: old)
        #expect(villager.supportsTrading == false && villager.level == 1)
        villager.profession = "minecraft:farmer"
        #expect(villager.supportsTrading == true)
        villager.profession = "example:farmer"
        #expect(villager.supportsTrading == nil)
        let trade = try #require(Trade(.compound([
            "buy": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
            "sell": .compound(["id": .string("minecraft:cactus"), "count": .int(1)]),
        ])))
        villager.trades = [trade]
        let encoded = try JSONEncoder().encode(villager)
        let decoded = try JSONDecoder().decode(Villager.self, from: encoded)
        #expect(villager.supportsTrading == true && decoded.supportsTrading == true)
        #expect(decoded == villager)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(fields.keys) == ["profession", "level", "trades"])
        villager.trades = []
        #expect(villager.supportsTrading == nil)
    }
}
