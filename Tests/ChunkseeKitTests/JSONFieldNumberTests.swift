import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct JSONFieldNumberTests {
    // Actual ServerStatsCounter.STATS_CODEC, NbtUtils Dynamic DataVersion,
    // DetectedVersion and Language outputs, json-number-readers-evidence/field-proof-1.
    // Raw rows SHA256: 6a1f5bb98344bea956efc4c18d701f1b59c94cce023e7a233594f785a48ddc3f.
    // Nil means no readable saved integer, never the game's load-time fallback.
    private let samples: [(token: String, integer: Int?, language: String?)] = [
        ("0", 0, "0"), ("-0", 0, "-0"), ("1", 1, "1"),
        ("1.50", 1, "1.50"), ("-1.50", -1, "-1.50"),
        ("2147483648", -2147483648, "2147483648"),
        ("-2147483649", 2147483647, "-2147483649"),
        ("4294967297.9", 1, "4294967297.9"),
        ("-4294967297.9", -1, "-4294967297.9"),
        ("9223372036854775807", -1, "9223372036854775807"),
        ("9223372036854775808", 0, "9223372036854775808"),
        ("1e+3", 1000, "1e+3"), ("1E-3", 0, "1E-3"),
        ("1000000000000000000.01", -1486618624, "1000000000000000000.01"),
        ("1e100", 0, "1e100"), ("1e-100", 0, "1e-100"),
        ("1e9999", 0, "1e9999"), ("1e10000", nil, "1e10000"),
        ("0.000", 0, "0.000"), (#""1""#, nil, "1"),
        ("true", nil, "true"), ("false", nil, "false"),
        ("null", nil, nil), ("[]", nil, nil), ("{}", nil, nil),
    ]

    @Test func statisticFilesKeepReadableCountsAndOptionalVersion() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([:])]),
                                     to: root.appendingPathComponent("level.dat"))
        let world = try World(contentsOf: root)
        for sample in samples {
            let id = UUID()
            let input = Data("""
            {"DataVersion":\(sample.token),"stats":{
              "minecraft:custom":{"minecraft:jump":\(sample.token),"minecraft:play_time":7},
              "minecraft:mined":{"minecraft:stone":9},"unreadable":false,
              "example:future_category":{"example:future_stat":3.9}}}
            """.utf8)
            let file = root.appendingPathComponent("players/stats/\(id.uuidString.lowercased()).json")
            try Fixtures.write(Array(input), to: file)
            let result = try #require(world.statistics(for: id))
            #expect(result.dataVersion == sample.integer, "\(sample.token)")
            var custom = ["minecraft:play_time": 7]
            custom["minecraft:jump"] = sample.integer
            #expect(result.values == ["minecraft:custom": custom, "minecraft:mined": ["minecraft:stone": 9],
                                      "example:future_category": ["example:future_stat": 3]], "\(sample.token)")
            #expect(try Data(contentsOf: file) == input)
        }
        let missing = try PlayerStatistics(json: Data(#"{"stats":{"example:new":{"example:new":3}}}"#.utf8))
        #expect(missing.dataVersion == nil && missing.values == ["example:new": ["example:new": 3]])
    }

    @Test func flatStatisticsShareTheCountConversion() throws {
        // StatsCounterFix keeps numeric values for the current statistic codec to consume.
        for sample in samples {
            let data = Data("{\"stat.jump\":\(sample.token),\"stat.playOneMinute\":7,\"stat.useItem.7\":9}".utf8)
            let stats = try PlayerStatistics(json: data)
            var expected = ["minecraft:play_time": 7, "stat.useItem.7": 9]
            expected["minecraft:jump"] = sample.integer
            #expect(stats.values == ["minecraft:custom": expected], "\(sample.token)")
        }
        let modern = try PlayerStatistics(json: Data(#"{"stats":{"broken":false},"stat.jump":7}"#.utf8))
        #expect(modern.values.isEmpty)
    }

    @Test func installedVersionUsesTheGamesIntegerReader() throws {
        for sample in samples {
            let metadata = "{\"id\":\"fixture\",\"world_version\":\(sample.token),\"stable\":true}"
            let game = GameAssets(data: Data(TestZIP.zip([.init(path: "version.json", text: metadata)])))
            #expect(game.map { Int($0.version.dataVersion) } == sample.integer, "\(sample.token)")
            if sample.integer != nil { #expect(game?.version.id == "fixture" && game?.version.isStable == true) }
        }
    }

    @Test func languageKeepsNumericSpellingAndReadableNeighbors() throws {
        for sample in samples {
            let game = try #require(GameAssets(data: Data(TestZIP.zip([
                .init(path: "version.json", text: #"{"id":"fixture","world_version":1}"#),
                .init(path: "assets/minecraft/lang/en_us.json",
                      text: "{\"value\":\(sample.token),\"neighbor\":\"Still readable %d\"}"),
            ]))))
            let language = game.language("en_us")
            #expect(language["value"] == sample.language, "\(sample.token)")
            #expect(language["neighbor"] == "Still readable %s")
        }
    }

    @Test func advancementFilesUseConvertedVersionWithoutNumericBooleanBridging() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([:])]),
                                     to: root.appendingPathComponent("level.dat"))
        let world = try World(contentsOf: root)
        for token in ["2099.75", "4294969395.75"] {
            let id = UUID()
            let data = Data("""
            {"DataVersion":\(token),"minecraft:recipes/misc/sugar":{"done":true,
              "criteria":{"proof":"2020-01-01 00:00:00 +0000"}},
              "example:unknown":{"done":1,"criteria":{"proof":"2020-01-01 00:00:00 +0000"}}}
            """.utf8)
            let file = root.appendingPathComponent("players/advancements/\(id.uuidString.lowercased()).json")
            try Fixtures.write(Array(data), to: file)
            let values = try #require(world.advancements(for: id))
            let renamed = try #require(values.first { $0.id == "minecraft:recipes/misc/sugar_from_sugar_cane" })
            #expect(renamed.isDone && renamed.criteria.count == 1)
            let unknown = try #require(values.first { $0.id == "example:unknown" })
            #expect(!unknown.isDone && unknown.criteria.count == 1)
            #expect(try Data(contentsOf: file) == data)
        }
    }

    @Test func gsonMetadataPrimitivesStaySeparateFromPublicDecoding() throws {
        let game = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":1.50,"world_version":1.50,"stable":"TrUe","build_time":"2026-01-01T12:00:00Z"}"#),
        ]))))
        #expect(game.version.id == "1.50" && game.version.dataVersion == 1 && game.version.isStable == true)
        #expect(game.version.buildTime == ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        let decoded = try JSONDecoder().decode(GameAssets.Version.self, from: Data(#"{"id":"fixture","world_version":1}"#.utf8))
        #expect(decoded.dataVersion == 1)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GameAssets.Version.self, from: Data(#"{"id":"fixture","world_version":1.50}"#.utf8))
        }
    }
}
