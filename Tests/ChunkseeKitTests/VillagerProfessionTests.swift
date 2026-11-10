import ChunkseeKitTestSupport
import Foundation
import Testing
import ChunkseeKit

@Suite struct VillagerProfessionTests {
    @Test func savedProfessionUsesTheSharedIdentifierRules() throws {
        let cases: [(String, String, Bool?)] = [
            ("minecraft:none", "minecraft:none", true), ("none", "none", true), (":none", ":none", true),
            ("minecraft:farmer", "minecraft:farmer", false), ("farmer", "farmer", false),
            ("minecraft:nitwit", "minecraft:nitwit", false),
            ("example:none", "example:none", false), ("example:beekeeper", "example:beekeeper", false),
            ("", "", nil), ("minecraft:", "minecraft:", nil),
            ("Minecraft:none", "minecraft:none", true), ("not a profession", "minecraft:none", true),
        ]
        for (saved, expectedProfession, expected) in cases {
            let villager = try #require(Villager(.compound([
                "VillagerData": .compound(["profession": .string(saved)]),
            ])))
            #expect(villager.isUnemployed == expected, "Saved profession: \(saved)")
            #expect(villager.profession == expectedProfession)
            #expect(villager.savedData?.value?["profession"] == .string(saved))
        }
    }

    @Test func missingAndInvalidCompoundFieldsDefaultWithoutChangingTraderRecords() throws {
        let missing: [[String: NBT]] = [[:], ["profession": .int(0)]]
        for fields in missing {
            let villager = try #require(Villager(.compound(["VillagerData": .compound(fields)])))
            #expect(villager.isUnemployed == true && villager.profession == "minecraft:none")
            #expect(villager.savedData?.value == .compound(fields))
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

    @Test func currentDefinitionsApplyOnlyBeforeOffersHaveBeenSaved() throws {
        let trading = ["armorer", "butcher", "cartographer", "cleric", "farmer", "fisherman",
                       "fletcher", "leatherworker", "librarian", "mason", "shepherd", "toolsmith",
                       "weaponsmith"]
        let definitions = try tradingDefinitions(for: trading)
        for profession in trading + ["none", "nitwit"] {
            for prefix in ["minecraft:", "", ":"] {
                let saved = prefix + profession
                var nbt: [String: NBT] = ["VillagerData": .compound(["profession": .string(saved)])]
                for offersSaved in [false, true] {
                    if offersSaved { nbt["Offers"] = .compound(["Recipes": .list([])]) }
                    let villager = try #require(Villager(.compound(nbt)))
                    let expected = !offersSaved && trading.contains(profession)
                    #expect(villager.supportsTrading(using: definitions) == expected, "Saved profession: \(saved)")
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
            #expect(villager.supportsTrading(using: nil) == nil)
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
            #expect(villager.supportsTrading(using: nil) == true)
            #expect(villager.trades.first?.isSoldOut == true)
            #expect(villager.profession == (profession == "invalid value" ? "minecraft:none" : profession))
            #expect(villager.savedData?.value?["profession"] == profession.map(NBT.string))
            #expect(villager.level == (profession == nil ? nil : 1))
        }
    }

    @Test func cachedTradingFactsFollowTheExistingMutableFields() throws {
        let definitions = try tradingDefinitions(for: ["farmer"])
        let old = Data(#"{"profession":"minecraft:nitwit","level":1,"trades":[]}"#.utf8)
        var villager = try JSONDecoder().decode(Villager.self, from: old)
        #expect(villager.supportsTrading(using: definitions) == nil && villager.level == 1)
        #expect(villager.offerState == nil)
        villager.profession = "minecraft:farmer"
        #expect(villager.supportsTrading(using: definitions) == nil)
        villager.offerState = .uninitialized
        #expect(villager.supportsTrading(using: definitions) == true)
        villager.profession = "example:farmer"
        #expect(villager.supportsTrading(using: definitions) == nil)
        let trade = try #require(Trade(.compound([
            "buy": .compound(["id": .string("minecraft:emerald"), "count": .int(1)]),
            "sell": .compound(["id": .string("minecraft:cactus"), "count": .int(1)]),
        ])))
        villager.trades = [trade]
        let encoded = try JSONEncoder().encode(villager)
        let decoded = try JSONDecoder().decode(Villager.self, from: encoded)
        #expect(villager.supportsTrading(using: definitions) == true && decoded.supportsTrading(using: definitions) == true)
        #expect(decoded == villager)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(fields.keys) == ["profession", "level", "trades", "offerState"])
        villager.trades = []
        #expect(villager.supportsTrading(using: definitions) == nil)
    }
    private func tradingDefinitions(for professions: [String]) throws -> TradingDefinitions {
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: #"{"id":"any","world_version":1}"#),
            .init(path: "data/test/villager_trade/offer.json", text: #"{"wants":{"id":"wheat"},"gives":{"id":"emerald"}}"#)
        ] + professions.map {
            .init(path: "data/minecraft/trade_set/\($0)/level_1.json", text: #"{"amount":2,"trades":["test:offer"]}"#)
        }
        let assets = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        return try assets.tradingDefinitions()
    }

}
