import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct TradingDefinitionsTests {
    @Test func selectedResourcesDeterminePotentialTradesWithoutFolderNameGuessing() throws {
        for version in [1, 999_999] {
            let assets = try jar(sets(trades: ["test:offer"]) + [offer,
                .init(path: "data/example/trade_set/beekeeper/level_1.json",
                      text: #"{"amount":2,"trades":["test:offer"]}"#)], version: version)
            let definitions = try assets.tradingDefinitions()
            for id in ["farmer", ":farmer", "minecraft:farmer"] {
                #expect(try villager(id).supportsTrading(using: definitions) == true)
            }
            for id in ["none", "nitwit"] {
                #expect(try villager(id).supportsTrading(using: definitions) == false)
                #expect(try villager(id).supportsTrading(using: nil) == false)
            }
            for id in ["example:beekeeper", "example:farmer", "minecraft:wandering_trader"] {
                #expect(try villager(id).supportsTrading(using: definitions) == nil)
            }
            let malformed = try villager("invalid id")
            #expect(malformed.profession == "minecraft:none")
            #expect(malformed.supportsTrading(using: definitions) == false)
            #expect(malformed.supportsTrading(using: nil) == false)
            #expect(malformed.savedData?.value?["profession"] == .string("invalid id"))
            #expect(try villager("farmer").supportsTrading(using: nil) == nil)
        }
    }

    @Test func emptyMissingDynamicAndMalformedResourcesStayDistinct() throws {
        let cases: [(Any, Any, Bool?)] = [
            (["test:offer"], 2, true), ("test:offer", 2, true),
            (["test:offer"], ["type": "constant", "value": 2], true),
            (["test:offer"], ["type": "minecraft:constant", "value": 0], false),
            ([String](), 2, false), (["test:offer"], 0, false),
            (["test:offer"], ["type": "example:dynamic"], nil),
            ([String](), ["type": "example:dynamic"], false),
            (["test:missing"], 2, nil), (["invalid id"], 2, nil),
            (["test:offer"], true, nil), (["test:offer"], 2.5, true),
            ([String](), true, nil), ([String](), ["type": "constant", "value": true], nil)
        ]
        for (members, amount, expected) in cases {
            let definitions = try jar(sets(trades: members, amount: amount) + [offer]).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: definitions) == expected)
        }
        let missing = try jar([]).tradingDefinitions()
        #expect(try villager("farmer").supportsTrading(using: missing) == nil)
        let malformed = try jar(sets(trades: ["test:offer"]) + [
            .init(path: offer.path, text: #"{"wants":{"id":"wheat"}}"#)
        ]).tradingDefinitions()
        #expect(try villager("farmer").supportsTrading(using: malformed) == nil)
    }

    @Test func tradeTagsResolveRequiredAndOptionalDefinitions() throws {
        let cases: [([Any], Bool?)] = [
            (["test:offer"], true), (["test:missing"], nil),
            ([["id": "test:missing", "required": false]], false),
            ([["id": "test:bad", "required": false]], nil),
            (["#test:nested"], true), (["#test:cycle"], nil)
        ]
        for (members, expected) in cases {
            let entries = try sets(trades: "#test:root") + [offer,
                tag("root", members), tag("nested", ["test:offer"]), tag("cycle", ["#test:cycle"]),
                .init(path: "data/test/villager_trade/bad.json", text: "invalid")]
            let definitions = try jar(entries).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: definitions) == expected)
        }
    }

    @Test(arguments: ["", ":", "minecraft:"])
    func referencesNormalizeAliasesWhileKeepingTagAndListFormsDistinct(prefix: String) throws {
        let resources: [TestZIP.Entry] = [
            .init(path: "data/minecraft/villager_trade/offer.json", text: offer.text),
            .init(path: "data/minecraft/tags/villager_trade/offers.json", text: #"{"values":["offer"]}"#)
        ]
        let cases: [Any] = [prefix + "offer", [prefix + "offer", prefix + "offer"], "#" + prefix + "offers"]
        for members in cases {
            let definitions = try jar(sets(trades: members) + resources).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: definitions) == true)
        }
    }

    @Test func malformedAndUnsafeReferencesKeepTradeAvailabilityUnknown() throws {
        let cases: [Any] = [
            "", "#", "test:../offer", "#test:../offer", "test:foo//offer",
            ["#test:root"], ["test:offer", "#test:root"], ["test:offer", 1],
            ["test:offer", NSNull()], true, NSNull(), ["id": "test:offer"]
        ]
        for members in cases {
            let definitions = try jar(sets(trades: members) + [offer, tag("root", ["test:offer"])]).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: definitions) == nil)
        }
    }

    @Test func malformedLaterMembersRetainEarlierReadsInTheSharedBudget() throws {
        var malformed = Array(repeating: "test:offer", count: 4096)
        malformed[4095] = "invalid id"
        let entries = try sets(trades: malformed)
            + sets(trades: Array(repeating: "test:offer", count: 4096), profession: "fletcher") + [offer]
        let definitions = try jar(entries).tradingDefinitions()
        #expect(try villager("farmer").supportsTrading(using: definitions) == nil)
        var fletcher = try villager("fletcher")
        for level in [1, 2] {
            fletcher.level = level
            #expect(fletcher.supportsTrading(using: definitions) == true)
        }
        fletcher.level = 3
        #expect(fletcher.supportsTrading(using: definitions) == nil)
    }

    @Test func constantAmountsUseGameIntegerCoercion() throws {
        for (amount, expected) in [(1.5, true), (0.9, false), (4294967297.9, true), (2147483648.0, false)] {
            for value: Any in [amount, ["type": "constant", "value": amount]] {
                let definitions = try jar(sets(trades: ["test:offer"], amount: value) + [offer]).tradingDefinitions()
                #expect(try villager("farmer").supportsTrading(using: definitions) == expected)
            }
        }
    }

    @Test func namedConstantAmountsResolveAtRuntimeAndCyclesRemainUnknown() throws {
        let positive = try jar(sets(trades: ["test:offer"], amount: "test:count") + [offer,
            .init(path: "data/test/context_int_provider/count.json", text: #""test:actual""#),
            .init(path: "data/test/context_int_provider/actual.json", text: #"{"type":"constant","value":2}"#)
        ]).tradingDefinitions()
        #expect(try villager("farmer").supportsTrading(using: positive) == true)
        for text in [#""test:count""#, #""test:missing""#, "invalid"] {
            let unknown = try jar(sets(trades: ["test:offer"], amount: "test:count") + [offer,
                .init(path: "data/test/context_int_provider/count.json", text: text)
            ]).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: unknown) == nil)
        }
    }

    @Test func givesAcceptsTheGamesBareItemTemplateWhileWantsKeepsItsObjectFormat() throws {
        for gives in [#""minecraft:emerald""#, #"{"id":"minecraft:emerald"}"#] {
            let trade = TestZIP.Entry(path: offer.path, text: #"{"wants":{"id":"wheat"},"gives":\#(gives)}"#)
            let definitions = try jar(sets(trades: ["test:offer"]) + [trade]).tradingDefinitions()
            #expect(try villager("farmer").supportsTrading(using: definitions) == true)
        }
        let invalid = TestZIP.Entry(path: offer.path, text: #"{"wants":"minecraft:wheat","gives":"minecraft:emerald"}"#)
        let definitions = try jar(sets(trades: ["test:offer"]) + [invalid]).tradingDefinitions()
        #expect(try villager("farmer").supportsTrading(using: definitions) == nil)
    }

    @Test func onlyTheCurrentClampedLevelSelectsTheTradeSet() throws {
        let entries = try sets(trades: [])
        let definitions = try jar(entries.filter { !$0.path.hasSuffix("level_2.json") } + [offer,
            .init(path: "data/minecraft/trade_set/farmer/level_2.json", text: #"{"amount":2,"trades":["test:offer"]}"#)
        ]).tradingDefinitions()
        var value = try villager("farmer")
        for level in [Int.min, -1, 0, 1, 3, 5, 6, Int.max] {
            value.level = level
            #expect(value.supportsTrading(using: definitions) == false)
        }
        value.level = 2
        #expect(value.supportsTrading(using: definitions) == true)
        value.level = nil
        #expect(value.supportsTrading(using: definitions) == nil)
        let first = try jar(sets(trades: ["test:offer"]) + [offer]).tradingDefinitions()
        for level in [Int.min, -1, 0, 1] {
            value.level = level
            #expect(value.supportsTrading(using: first) == true)
        }
    }

    @Test func enabledFolderAndZipOverridesChangeNewSnapshotsWithoutTouchingSaves() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try jar(sets(trades: "#test:root", amount: "test:count") + [offer, tag("root", ["test:offer"]),
            .init(path: "data/test/context_int_provider/count.json", text: "2")])
        let folder = root.appendingPathComponent("datapacks/low")
        let extra = try tag("root", [["id": "test:missing", "required": false]])
        try Fixtures.write(Array(extra.text.utf8), to: folder.appendingPathComponent(extra.path))
        try Fixtures.write(Array(#"{"pack":{"description":"test"}}"#.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(1),
            "DataPacks": .compound(["Enabled": .list(["vanilla", "file/low", "file/high.zip"].map(NBT.string))])
        ])]), to: root.appendingPathComponent("level.dat"))
        let world = try World(contentsOf: root), file = root.appendingPathComponent("level.dat")
        let before = try Data(contentsOf: file)
        func high(_ entries: [TestZIP.Entry]) throws {
            let metadata = TestZIP.Entry(path: "pack.mcmeta", text: #"{"pack":{"description":"test"}}"#)
            try Fixtures.write(TestZIP.zip([metadata] + entries), to: root.appendingPathComponent("datapacks/high.zip"))
        }
        try high([])
        let original = try world.tradingDefinitions(assets: assets)
        #expect(try villager("farmer").supportsTrading(using: original) == true)
        try high([.init(path: "data/test/context_int_provider/count.json", text: "0")])
        #expect(try villager("farmer").supportsTrading(using: world.tradingDefinitions(assets: assets)) == false)
        try high([tag("root", [], replace: true)])
        let empty = try world.tradingDefinitions(assets: assets)
        #expect(try villager("farmer").supportsTrading(using: empty) == false)
        #expect(try villager("farmer").supportsTrading(using: original) == true)
        try high([.init(path: "data/test/tags/villager_trade/root.json", text: "invalid")])
        #expect(try villager("farmer").supportsTrading(using: world.tradingDefinitions(assets: assets)) == nil)
        try high(sets(trades: []))
        #expect(try villager("farmer").supportsTrading(using: world.tradingDefinitions(assets: nil)) == false)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test(arguments: [4096, 4097])
    func cancellationPropagatesAndSelectionsRespectTheMemberLimit(count: Int) async throws {
        let assets = try jar(sets(trades: Array(repeating: "test:offer", count: count)) + [offer])
        let expected: Bool? = count == 4096 ? true : nil
        #expect(try villager("farmer").supportsTrading(using: assets.tradingDefinitions()) == expected)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try assets.tradingDefinitions()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private var offer: TestZIP.Entry {
        .init(path: "data/test/villager_trade/offer.json", text: #"{"wants":{"id":"wheat"},"gives":{"id":"emerald"}}"#)
    }

    private func sets(trades: Any, amount: Any = 2, profession: String = "farmer") throws -> [TestZIP.Entry] {
        let data = try JSONSerialization.data(withJSONObject: ["amount": amount, "trades": trades])
        return (1...5).map { .init(path: "data/minecraft/trade_set/\(profession)/level_\($0).json", text: String(decoding: data, as: UTF8.self)) }
    }

    private func tag(_ name: String, _ members: [Any], replace: Bool = false) throws -> TestZIP.Entry {
        let data = try JSONSerialization.data(withJSONObject: ["replace": replace, "values": members])
        return .init(path: "data/test/tags/villager_trade/\(name).json", text: String(decoding: data, as: UTF8.self))
    }

    private func jar(_ entries: [TestZIP.Entry], version: Int = 999_999) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"any\",\"world_version\":\(version)}")
        ] + entries))))
    }

    private func villager(_ profession: String) throws -> Villager {
        try #require(Villager(.compound(["VillagerData": .compound(["profession": .string(profession)])])))
    }
}
