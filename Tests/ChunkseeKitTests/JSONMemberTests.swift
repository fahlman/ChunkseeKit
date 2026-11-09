import Foundation
import Testing
@testable import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct JSONMemberTests {
    @Test func savedTextUsesLastDecodedMemberIncludingNestedObjectsAndNull() throws {
        let historical = SavedTextUpgrade.Context(dataVersion: GeneratedSavedText.boundary - 1)
        for json in [#"{"text":"first","text":"last"}"#,
                     #"{"text":"first","\u0074ext":"last"}"#,
                     #"{"\u0074ext":"first","text":"last"}"#,
                     #"{"text":null,"text":"last"}"#] {
            #expect(TextComponent.content(json: Data(json.utf8)) == .literal("last"))
            #expect(TextComponent.plainText(historical.component(.string(json))) == "last")
            let savedSign = NBT.compound([
                "id": .string("minecraft:oak_sign"), "x": .int(0), "y": .int(64), "z": .int(0), "Text1": .string(json)
            ])
            let sign = Sign.signs(inChunk: Fixtures.chunk(x: 0, z: 0, dataVersion: GeneratedSavedText.signBoundary,
                sections: [], extra: ["block_entities": .list([savedSign])])).first
            #expect(sign?.front.first == "last")
        }
        #expect(TextComponent.content(json: Data(#"{"text":"first","text":null}"#.utf8)) == nil)
        let nested = #"{"text":"root","extra":[{"text":"old","text":"a"},{"text":"old","text":"b"}]}"#
        #expect(TextComponent.plainText(historical.component(.string(nested))) == "rootab")
        let number = #"{"translate":"n","with":[1],"\u0077ith":[9007199254740993]}"#
        #expect(TextComponent.content(json: Data(number.utf8)) ==
            .translated(key: "n", fallback: nil, arguments: [.integer(9_007_199_254_740_993)]))
        for invalid in [#"{"text":"bad\q","text":"last"}"#, #"{"unused":01,"text":"last"}"#,
                        #"{"text":"first","text":}"#] {
            #expect(TextComponent.content(json: Data(invalid.utf8)) == nil)
        }
    }

    @Test func metadataLanguageAndTagsShareDecodedMemberSelection() throws {
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: #"{"id":"old","id":"last","world_version":1,"world_version":999999,"stable":false,"stable":true}"#),
            .init(path: "assets/minecraft/lang/en_us.json", text: #"{"same":"first","\u0073ame":"last","renamed":"old","renamed":"value","S0:x":"first","S0:x":"last marker","N123":"literal","empty":"first","empty":null,"number":1,"number":2}"#),
            .init(path: "assets/minecraft/lang/deprecated.json", text: #"{"removed":["same"],"removed":[],"renamed":{"renamed":"old"},"renamed":{"renamed":"new"}}"#),
            .init(path: "data/test/tags/block/picked.json", text: #"{"values":["test:first"],"\u0076alues":[{"id":"test:old","id":"test:last","required":true,"required":false}]}"#),
            .init(path: "data/test/advancement/picked.json", text: #"{"display":{"title":"first"},"display":{"title":{"text":"old","text":"last"}}}"#),
        ]
        let game = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        #expect(game.version.id == "last" && game.version.dataVersion == 999999 && game.version.isStable == true)
        let language = game.language("en_US")
        #expect(language["same"] == "last" && language["new"] == "value" && language["renamed"] == nil)
        #expect(language["S0:x"] == "last marker" && language["N123"] == "literal")
        #expect(language["empty"] == nil && language["number"] == "2")
        let tag = try #require(try game.tag("test:picked", in: "block"))
        #expect(tag.members.map(\.id) == ["test:last"] && tag.members.first?.required == false)
        #expect(try game.advancementDefinitions(for: ["test:picked"])["test:picked"]?.title == .literal("last"))
        let fractionalVersion = TestZIP.Entry(path: "version.json", text: #"{"id":"fixture","world_version":2,"world_version":1.5}"#)
        #expect(try GameAssets(data: Data(TestZIP.zip([fractionalVersion])))?.version.dataVersion == 1)
    }

    @Test func savedStatisticsAdvancementsAndNamesUseTheLastValue() throws {
        let stats = try PlayerStatistics(json: Data(#"{"stats":{"minecraft:custom":{"minecraft:play_time":2,"minecraft:play_time":9007199254740993}},"DataVersion":1,"DataVersion":999999}"#.utf8))
        // The last number is exact until the statistic codec narrows its low 32 bits.
        #expect(stats.dataVersion == 999999 && stats.playTime == 1)
        let advancements = try AdvancementProgress.list(json: Data(#"{"test:done":{"done":false,"done":true,"criteria":{"one":"2026-10-01 00:00:00 +0000","one":"2026-10-02 00:00:00 +0000"}}}"#.utf8))
        #expect(advancements.count == 1 && advancements[0].isDone && advancements[0].criteria.count == 1)
        let cache = #"[{"uuid":"bad","uuid":"52dfb519-de9c-47e6-bc6c-bb053cc423e7","name":"first","\u006eame":"last"}]"#
        #expect(try UserCache.parse(Data(cache.utf8)).map(\.name) == ["last"])
        let nullName = cache.replacingOccurrences(of: #""last""#, with: "null")
        #expect(try UserCache.parse(Data(nullName.utf8)).isEmpty)
        let wrongType = cache.replacingOccurrences(of: #""last""#, with: "false")
        #expect(throws: UserCache.ReadError.notAUserCache) { try UserCache.parse(Data(wrongType.utf8)) }
    }

    @Test func unicodeEncodingsAndDeepIgnoredMetadataShareMemberSelection() throws {
        let json = #"{"text":"first","\u0074ext":"last","unused":1.5}"#
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian,
                         .utf32LittleEndian, .utf32BigEndian] {
            let data = try #require(json.data(using: encoding))
            #expect(TextComponent.content(json: data) == .literal("last"))
        }

        let nested = String(repeating: "[", count: 510) + "true" + String(repeating: "]", count: 510)
        let cache = #"[{"uuid":"52dfb519-de9c-47e6-bc6c-bb053cc423e7","name":"first","name":"last","unused":"# + nested + "}]"
        #expect(try UserCache.parse(Data(cache.utf8)).map(\.name) == ["last"])
        let stats = #"{"stats":{"minecraft:custom":{"minecraft:play_time":42}},"unused":["# + nested + "]}"
        #expect(try PlayerStatistics(json: Data(stats.utf8)).playTime == 42)

        // An ignored metadata number is never consumed by a numeric codec. Sharing member
        // selection must not apply a converted field's bound to that unused value.
        let metadata = #"{"id":"old","id":"last","world_version":999999,"unused":"# +
            String(repeating: "1", count: 1_024) + "}"
        let entries = [TestZIP.Entry(path: "version.json", text: metadata)]
        let game = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        #expect(game.version.id == "last" && game.version.dataVersion == 999999)
    }
}
