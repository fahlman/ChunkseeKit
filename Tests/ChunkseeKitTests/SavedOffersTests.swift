import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct SavedOffersTests {
    private var recipe: NBT {
        .compound([
            "buy": .compound(["id": .string("wheat"), "count": .int(20)]),
            "sell": .compound(["id": .string("emerald"), "count": .int(1)])
        ])
    }

    private var cases: [(offers: NBT?, state: Villager.OfferState, trading: Bool?, recipes: Int)] {
        [
            (nil, .absent, true, 0),
            (.compound([:]), .complete, false, 0),
            (.compound(["Recipes": .list(.compound, [])]), .complete, false, 0),
            (.string("unreadable"), .incomplete, nil, 0),
            (.compound(["Recipes": .string("unreadable")]), .incomplete, nil, 0),
            (.compound(["Recipes": .list([.compound([:])])]), .incomplete, nil, 0),
            (.compound(["Recipes": .list([recipe])]), .complete, true, 1),
            (.compound(["Recipes": .list([recipe, .compound([:])])]), .incomplete, true, 1)
        ]
    }

    @Test func onlyAbsentOffersConsultCurrentDefinitions() throws {
        let definitions = try definitions()
        for value in cases {
            let villager = try #require(Villager(record(offers: value.offers)))
            #expect(villager.offerState == value.state)
            #expect(villager.trades.count == value.recipes)
            #expect(villager.supportsTrading(using: definitions) == value.trading)
            if value.state == .absent { #expect(villager.supportsTrading(using: nil) == nil) }
            else { #expect(villager.supportsTrading(using: nil) == value.trading) }
        }
    }

    @Test func emptyOrUnreadableOffersSurviveWithoutVillagerData() throws {
        for offers in [NBT.compound([:]), .compound(["Recipes": .list(.compound, [])]), .string("unreadable")] {
            let villager = try #require(Villager(.compound(["Offers": offers])))
            #expect(villager.profession == nil && villager.level == nil && villager.trades.isEmpty)
            #expect(villager.supportsTrading(using: nil) == (offers.compound == nil ? nil : false))
        }
        #expect(Villager(.compound([:])) == nil)
    }

    @Test func actualRegionScanAndCacheKeepEveryOfferStateAndReadableRecipe() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:market", url: root)
        let position = RegionPosition(x: 0, z: 0)
        let entities = cases.enumerated().map { offset, value in
            Fixtures.mob(record(offers: value.offers).compound!.merging([
                "id": .string("example:merchant"),
                "Pos": .list([.double(Double(offset)), .double(64), .double(0)])
            ]) { _, new in new })
        }
        let path = dimension.regionURL(.entities, at: position)
        let input = try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "DataVersion": .int(.max), "Entities": .list(entities)
        ]))])
        try Fixtures.write(input, to: path)
        let scanned = try dimension.scan(region: position)
        let cached = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(scanned))
        #expect(cached.creatures == scanned.creatures)
        #expect(cached.creatures.count == cases.count)
        let definitions = try definitions()
        for (creature, value) in zip(cached.creatures, cases) {
            let villager = try #require(creature.villager)
            #expect(villager.offerState == value.state && villager.trades.count == value.recipes)
            #expect(villager.supportsTrading(using: definitions) == value.trading)
        }
        #expect(try Data(contentsOf: path) == Data(input))
    }

    @Test func olderStandaloneRecordsKeepKnownTradesWithoutInventingOfferPresence() throws {
        let definitions = try definitions()
        for value in cases {
            let current = try #require(Villager(record(offers: value.offers)))
            let encoded = try JSONEncoder().encode(current)
            var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            fields.removeValue(forKey: "offerState")
            let old = try JSONDecoder().decode(Villager.self, from: JSONSerialization.data(withJSONObject: fields))
            #expect(old.offerState == nil && old.trades == current.trades)
            #expect(old.supportsTrading(using: definitions) == (value.recipes > 0 ? true : nil))
        }
    }

    private func record(offers: NBT?) -> NBT {
        var fields: [String: NBT] = ["VillagerData": .compound(["profession": .string("farmer"), "level": .int(1)])]
        fields["Offers"] = offers
        return .compound(fields)
    }

    private func definitions() throws -> TradingDefinitions {
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"any","world_version":1}"#),
            .init(path: "data/minecraft/trade_set/farmer/level_1.json", text: #"{"amount":1,"trades":["test:offer"]}"#),
            .init(path: "data/test/villager_trade/offer.json", text: #"{"wants":{"id":"wheat"},"gives":"emerald"}"#)
        ]))))
        return try assets.tradingDefinitions()
    }
}
