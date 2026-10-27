import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct TextNumberTests {
    // Exact bits from Gson 2.14.0 / DFU 10.0.21 Codec.DOUBLE shipped with the verified game.
    // Reproduction, dependency hashes and raw results: text-number-precision-evidence/codec-probe-1.
    @Test func jsonNumbersMatchTheGameAcrossEveryTextInputPath() throws {
        let cases: [(literal: String, bits: UInt64)] = [
            ("0.0", 0),
            ("-0.0", 9223372036854775808),
            ("1", 4607182418800017408),
            ("-1", 13830554455654793216),
            ("0.1", 4591870180066957722),
            ("0.001", 4562254508917369340),
            ("0.0009999999999999998", 4562254508917369339),
            ("0.0001", 4547007122018943789),
            ("9999999", 4711630319185297408),
            ("10000000", 4711630319722168320),
            ("10000000.000000002", 4711630319722168321),
            ("1e20", 4906019910204099648),
            ("1e23", 4950912855330343670),
            ("1.2345678901234567", 4608238818662570491),
            ("1.7976931348623157e308", 9218868437227405311),
            ("2.2250738585072014e-308", 4503599627370496),
            ("4.9e-324", 1),
            ("1e-323", 2),
            ("1.5e-323", 3),
            ("2e-323", 4),
            ("-4.9e-324", 9223372036854775809),
            ("3.141592653589793", 4614256656552045848),
            ("9007199254740991", 4845873199050653695),
            ("9007199254740992", 4845873199050653696),
            ("1.2345e-100", 3112347920550587138),
            ("-1.2345e100", 15327600592158625674),
            ("1.0000000000000001110223024625156540423631668090820312500001", 4607182418800017409),
            ("1.0000000000000001110223024625156540423631668090820312499999", 4607182418800017408),
        ]
        var entries = [TestZIP.Entry(path: "version.json", text: #"{"id":"fixture","world_version":999999}"#)]
        for (index, fixture) in cases.enumerated() {
            let component = "{\"translate\":\"test.number\",\"with\":[" + fixture.literal + "]}"
            let definition = "{\"display\":{\"title\":" + component + "}}"
            let data = Data(component.utf8)
            let standalone = TextComponent.content(json: data)
            let legacy = TextComponent.content(.string(component))
            let title = AdvancementDefinition(data: Data(definition.utf8))?.title
            for value in [standalone, legacy, title] {
                #expect(try number(in: value).bitPattern == fixture.bits, "\(fixture.literal)")
            }
            #expect(TextComponent.plainText(.string(component)) == "test.number")
            entries.append(.init(path: "data/test/advancement/number_\(index).json", text: definition))
        }
        let game = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        let titles = try game.advancementDefinitions(for: Set(cases.indices.map { "test:number_\($0)" }))
        for (index, fixture) in cases.enumerated() {
            #expect(try number(in: titles["test:number_\(index)"]?.title).bitPattern == fixture.bits, "Jar: \(fixture.literal)")
        }
    }

    @Test func primitiveTypesAndMalformedTextRemainDistinct() {
        func read(_ text: String) -> TextComponent.Content? { TextComponent.content(json: Data(text.utf8)) }
        #expect(read(#"{"translate":"test.types","with":[true,false,"1",1]}"#) ==
            .translated(key: "test.types", fallback: nil, arguments: [.boolean(true), .boolean(false), .string("1"), .number(1)]))
        for invalid in ["null", "1e9999", "NaN", "Infinity", "{", #"{"translate":"test.number","with":[null]}"#] {
            #expect(read(invalid) == nil)
        }
        // Both Foundation readers currently select the first duplicate member. #297 records
        // this pre-existing difference from Gson; the number fix must not change it silently.
        #expect(read(#"{"text":"first","text":"last"}"#) == .literal("first"))
        #expect(read(#"{"text":"title","unused":[true,null,1.5,{"other":"value"}]}"#) == .literal("title"))
        #expect(TextComponent.content(.compound(["translate": .string("test.number"), "with": .list([.double(.infinity)])])) == nil)
    }

    @Test func numericDecodingPreservesStringsAndBaselineDuplicateSelection() throws {
        let json = #"{"translate":"test.number","with":[2],"with":[0.0009999999999999998]}"#
        #expect(try number(in: TextComponent.content(json: Data(json.utf8))) == 2) // Existing #297 behavior.
        let strings = #"{"translate":"test.types","with":["0","-1.2e3","escaped \" 7 \\\\ end",{"text":"42","extra":[" -0"]},1.5]}"#
        #expect(TextComponent.content(json: Data(strings.utf8)) == .translated(key: "test.types", fallback: nil, arguments: [
            .string("0"), .string("-1.2e3"), .string("escaped \" 7 \\\\ end"),
            .component(.sequence([.literal("42"), .literal(" -0")])), .number(1.5),
        ]))
        let nulls = #"{"unused":null,"display":{"other":false,"title":{"translate":"test.number","with":[-0.0]}}}"#
        #expect(try number(in: AdvancementDefinition(data: Data(nulls.utf8))?.title).bitPattern == 1 << 63)
    }

    @Test func malformedNumbersAndEscapesRemainUnavailable() {
        for token in ["01", "-01", "1.2.3", "1e", "1e+", "1e-", "1.", "-.5", "+1", "--1", "0x1", "1true", "1:2", "1e9999"] {
            let json = "{\"translate\":\"test.number\",\"with\":[9," + token + "]}"
            #expect(TextComponent.content(json: Data(json.utf8)) == nil, "\(token)")
        }
        let unterminated = #"{"text":"an escaped closing quote\"}"#
        #expect(TextComponent.content(json: Data(unterminated.utf8)) == nil)
        let many = "{\"translate\":\"test.number\",\"with\":[" + Array(repeating: "0", count: 65_537).joined(separator: ",") + "]}"
        #expect(TextComponent.content(json: Data(many.utf8)) == nil)
    }

    private func number(in content: TextComponent.Content?) throws -> Double {
        let value = try #require(content)
        guard case .translated(_, _, let arguments) = value, arguments.count == 1,
              case .number(let number) = arguments[0] else {
            Issue.record("Expected one numeric argument, got \(value)")
            return .nan
        }
        return number
    }
}
