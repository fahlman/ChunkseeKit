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
            for id in ["example:beekeeper", "example:farmer", "minecraft:wandering_trader", "invalid id"] {
                #expect(try villager(id).supportsTrading(using: definitions) == nil)
            }
            #expect(try villager("farmer").supportsTrading(using: nil) == nil)
        }
    }

    @Test func emptyMissingDynamicAndMalformedResourcesStayDistinct() throws {
        let cases: [(Any, Any, Bool?)] = [
            (["test:offer"], 2, true), ("test:offer", 2, true),
            ([String](), 2, false), (["test:offer"], 0, false),
            (["test:offer"], ["type": "example:dynamic"], nil),
            ([String](), ["type": "example:dynamic"], false),
            (["test:missing"], 2, nil), (["invalid id"], 2, nil),
            (["test:offer"], true, nil), (["test:offer"], 2.5, nil)
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

    @Test func enabledFolderAndZipOverridesChangeNewSnapshotsWithoutTouchingSaves() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try jar(sets(trades: "#test:root") + [offer, tag("root", ["test:offer"])])
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

    @Test func cancellationPropagatesAndOversizedSelectionsStayUnknown() async throws {
        let assets = try jar(sets(trades: Array(repeating: "test:offer", count: 4097)) + [offer])
        #expect(try villager("farmer").supportsTrading(using: assets.tradingDefinitions()) == nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try assets.tradingDefinitions()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private var offer: TestZIP.Entry {
        .init(path: "data/test/villager_trade/offer.json", text: #"{"wants":{"id":"wheat"},"gives":{"id":"emerald"}}"#)
    }

    private func sets(trades: Any, amount: Any = 2) throws -> [TestZIP.Entry] {
        let data = try JSONSerialization.data(withJSONObject: ["amount": amount, "trades": trades])
        return (1...5).map { .init(path: "data/minecraft/trade_set/farmer/level_\($0).json", text: String(decoding: data, as: UTF8.self)) }
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
