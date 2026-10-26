import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct GameVersionMetadataTests {
    private func assets(_ metadata: String) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: metadata),
            .init(path: "assets/example/models/item/token.json", text:
                ##"{"parent":"builtin/generated","textures":{"layer0":"example:item/token"}}"##)
        ]))))
    }

    @Test func releaseClassificationComesFromTheBooleanNotTheName() throws {
        for stable in [false, true] {
            let game = try assets("""
                {"id":"arbitrary-name","world_version":42,"stable":\(stable),"build_time":"2000-01-01T00:00:00+00:00"}
                """)
            #expect(game.version.isStable == stable)
            #expect(game.version.buildTime == Date(timeIntervalSince1970: 946684800))
            #expect(game.model("example:item/token") != nil)
        }
    }

    @Test func buildInstantsHonorOffsetsAndFractionalSeconds() throws {
        for (text, fraction) in [("1999-12-31T19:00:00-05:00", 0.0),
                                 ("2000-01-01T00:00:00.125Z", 0.125)] {
            let game = try assets("""
                {"id":"fixture","world_version":42,"build_time":"\(text)"}
                """)
            #expect(game.version.isStable == nil)
            #expect(game.version.buildTime == Date(timeIntervalSince1970: 946684800 + fraction))
        }
    }

    @Test func missingMetadataDoesNotDiscardReadableGameFiles() throws {
        for fields in ["", ##", "stable": null, "build_time": null"##,
                       ##", "stable": "true", "build_time": 42"##,
                       ##", "stable": 1, "build_time": "not-a-date""##] {
            let game = try assets("""
                {"id":"fixture","world_version":42\(fields)}
                """)
            #expect(game.version.id == "fixture" && game.version.dataVersion == 42)
            #expect(game.version.isStable == nil && game.version.buildTime == nil)
            #expect(game.model("example:item/token") != nil)
        }
    }

    @Test func optionalMetadataFieldsRemainIndependent() throws {
        let stable = try assets(##"{"id":"fixture","world_version":42,"stable":false,"build_time":"invalid"}"##)
        #expect(stable.version.isStable == false && stable.version.buildTime == nil)
        let date = try assets(##"{"id":"fixture","world_version":42,"stable":{},"build_time":"2000-01-01T00:00:00Z"}"##)
        #expect(date.version.isStable == nil)
        #expect(date.version.buildTime == Date(timeIntervalSince1970: 946684800))
    }
}
