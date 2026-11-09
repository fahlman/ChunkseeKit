@testable import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct TextNumberTests {
    // Actual TranslatableContents.PRIMITIVE_ARG_CODEC / JsonOps outcomes, including kind.
    // Raw results and pinned official hashes: text-number-precision-evidence/strict-primitive-probe-1.
    @Test func jsonNumbersMatchTheGameAcrossEveryTextInputPath() throws {
        let cases: [(literal: String, argument: TextComponent.Argument)] = [
            ("0.0", .integer(0)),
            ("-0.0", .integer(0)),
            ("1", .integer(1)),
            ("-1", .integer(-1)),
            ("0.1", .number(Double(bitPattern: 4591870180066957722))),
            ("0.001", .number(Double(bitPattern: 4562254508917369340))),
            ("0.0009999999999999998", .number(Double(bitPattern: 4562254508917369339))),
            ("0.0001", .number(Double(bitPattern: 4547007122018943789))),
            ("9999999", .integer(9999999)),
            ("10000000", .integer(10000000)),
            ("10000000.000000002", .number(Double(bitPattern: 4711630319722168321))),
            ("1e20", .number(Double(bitPattern: 4906019910204099648))),
            ("1e23", .number(Double(bitPattern: 4950912855330343670))),
            ("1.2345678901234567", .number(Double(bitPattern: 4608238818662570491))),
            ("1.7976931348623157e308", .number(Double(bitPattern: 9218868437227405311))),
            ("2.2250738585072014e-308", .number(Double(bitPattern: 4503599627370496))),
            ("4.9e-324", .number(Double(bitPattern: 1))),
            ("1e-323", .number(Double(bitPattern: 2))),
            ("1.5e-323", .number(Double(bitPattern: 3))),
            ("2e-323", .number(Double(bitPattern: 4))),
            ("-4.9e-324", .number(Double(bitPattern: 9223372036854775809))),
            ("3.141592653589793", .number(Double(bitPattern: 4614256656552045848))),
            ("9007199254740991", .integer(9007199254740991)),
            ("9007199254740992", .integer(9007199254740992)),
            ("1.2345e-100", .number(Double(bitPattern: 3112347920550587138))),
            ("-1.2345e100", .number(Double(bitPattern: 15327600592158625674))),
            ("1.0000000000000001110223024625156540423631668090820312500001", .number(Double(bitPattern: 4607182418800017409))),
            ("1.0000000000000001110223024625156540423631668090820312499999", .float(Float(bitPattern: 1065353216))),
            ("5.0", .integer(5)),
            ("9007199254740993", .integer(9007199254740993)),
            ("9223372036854775807", .integer(9223372036854775807)),
            ("-9223372036854775808", .integer(-9223372036854775808)),
            ("9223372036854775808", .float(Float(bitPattern: 1593835520))),
            ("1e309", .float(Float(bitPattern: 2139095040))),
            ("-1e309", .float(Float(bitPattern: 4286578688))),
            ("1e-999", .float(Float(bitPattern: 0))),
        ]
        var entries = [TestZIP.Entry(path: "version.json", text: #"{"id":"fixture","world_version":999999}"#)]
        for (index, fixture) in cases.enumerated() {
            let component = "{\"translate\":\"test.number\",\"with\":[" + fixture.literal + "]}"
            let definition = "{\"display\":{\"title\":" + component + "}}"
            let data = Data(component.utf8)
            let standalone = TextComponent.content(json: data)
            let saved = NBT.compound(["id": .string("minecraft:stone"), "count": .int(1),
                                      "components": .compound(["minecraft:custom_name": .string(component)])])
            let upgraded = SaveDataUpgrade.item(saved, dataVersion: GeneratedSavedText.boundary - 1)
            let legacyNBT = try #require(upgraded["components"]?["minecraft:custom_name"])
            let legacy = TextComponent.content(legacyNBT)
            let title = AdvancementDefinition(data: Data(definition.utf8))?.title
            for value in [standalone, legacy, title] {
                #expect(try argument(in: value) == fixture.argument, "\(fixture.literal)")
            }
            #expect(TextComponent.plainText(legacyNBT) == "test.number")
            entries.append(.init(path: "data/test/advancement/number_\(index).json", text: definition))
        }
        let game = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        let titles = try game.advancementDefinitions(for: Set(cases.indices.map { "test:number_\($0)" }))
        for (index, fixture) in cases.enumerated() {
            #expect(try argument(in: titles["test:number_\(index)"]?.title) == fixture.argument, "Jar: \(fixture.literal)")
        }
    }

    @Test func primitiveTypesAndMalformedTextRemainDistinct() {
        func read(_ text: String) -> TextComponent.Content? { TextComponent.content(json: Data(text.utf8)) }
        #expect(read(#"{"translate":"test.types","with":[true,false,"1",1]}"#) ==
            .translated(key: "test.types", fallback: nil, arguments: [.boolean(true), .boolean(false), .string("1"), .integer(1)]))
        for invalid in ["null", "1e9999", "NaN", "Infinity", "{", #"{"translate":"test.number","with":[null]}"#] {
            #expect(read(invalid) == nil)
        }
        #expect(read(#"{"text":"first","text":"last"}"#) == .literal("last"))
        #expect(read(#"{"text":"title","unused":[true,null,1.5,{"other":"value"}]}"#) == .literal("title"))
    }

    @Test func numericDecodingPreservesStringsAndSelectsTheLastDuplicate() throws {
        let json = #"{"translate":"test.number","with":[2],"with":[0.0009999999999999998]}"#
        #expect(try argument(in: TextComponent.content(json: Data(json.utf8))) == .number(Double(bitPattern: 4562254508917369339)))
        let strings = #"{"translate":"test.types","with":["0","-1.2e3","escaped \" 7 \\\\ end",{"text":"42","extra":[" -0"]},1.5]}"#
        #expect(TextComponent.content(json: Data(strings.utf8)) == .translated(key: "test.types", fallback: nil, arguments: [
            .string("0"), .string("-1.2e3"), .string("escaped \" 7 \\\\ end"),
            .component(.sequence([.literal("42"), .literal(" -0")])), .float(1.5),
        ]))
        let nulls = #"{"unused":null,"display":{"other":false,"title":{"translate":"test.number","with":[-0.0]}}}"#
        #expect(try argument(in: AdvancementDefinition(data: Data(nulls.utf8))?.title) == .integer(0))
    }

    @Test func malformedNumbersAndEscapesRemainUnavailable() {
        for token in ["01", "-01", "1.2.3", "1e", "1e+", "1e-", "1.", "-.5", "+1", "--1", "0x1", "1true", "1:2", "1e10000", "1e2147483648"] {
            let json = "{\"translate\":\"test.number\",\"with\":[9," + token + "]}"
            #expect(TextComponent.content(json: Data(json.utf8)) == nil, "\(token)")
        }
        let unterminated = #"{"text":"an escaped closing quote\"}"#
        #expect(TextComponent.content(json: Data(unterminated.utf8)) == nil)
        let many = "{\"translate\":\"test.number\",\"with\":[" + Array(repeating: "0", count: 65_537).joined(separator: ",") + "]}"
        #expect(TextComponent.content(json: Data(many.utf8)) == nil)
    }

    @Test func nativeNBTKindsAndExceptionalValuesMatchTheGame() throws {
        // Actual NbtOps / primitive codec outcomes: nbt-primitive-probe-1, plus FloatTag.load's
        // matching zero canonicalization. Numeric kind must not be inferred from rounded values.
        let cases: [(NBT, TextComponent.Argument)] = [
            (.byte(1), .integer(1)), (.short(300), .integer(300)), (.int(70_000), .integer(70_000)),
            (.long(9_007_199_254_740_993), .integer(9_007_199_254_740_993)),
            (.float(0.1), .float(0.1)), (.float(.leastNonzeroMagnitude), .float(.leastNonzeroMagnitude)),
            (.float(.leastNormalMagnitude), .float(.leastNormalMagnitude)),
            (.float(.greatestFiniteMagnitude), .float(.greatestFiniteMagnitude)),
            (.float(.infinity), .float(.infinity)), (.float(.nan), .float(.nan)),
            (.double(Double(Float(0.1))), .number(Double(Float(0.1)))),
            (.double(.infinity), .number(.infinity)), (.double(.nan), .number(.nan)),
            (.float(-0.0), .float(0)), (.double(-0.0), .number(0)),
        ]
        for (tag, expected) in cases {
            let nbt = NBT.compound(["translate": .string("test.number"), "with": .list([tag])])
            let actual = try argument(in: TextComponent.content(nbt))
            switch (actual, expected) {
            case (.float(let a), .float(let b)):
                #expect(a.isNaN && b.isNaN || a.bitPattern == b.bitPattern)
            case (.number(let a), .number(let b)):
                #expect(a.isNaN && b.isNaN || a.bitPattern == b.bitPattern)
            default: #expect(actual == expected)
            }
            #expect(TextComponent.plainText(nbt) == "test.number")
        }
    }

    @Test func originalStringsCannotCollideWithNumericMarkers() {
        let json = #"{"translate":"N1","with":["N1","S","","\u004e5","escaped \" 7",{"text":"Scontent","N5":1},5.0]}"#
        #expect(TextComponent.content(json: Data(json.utf8)) == .translated(key: "N1", fallback: nil, arguments: [
            .string("N1"), .string("S"), .string(""), .string("N5"), .string("escaped \" 7"),
            .component(.literal("Scontent")), .integer(5),
        ]))
        // Numeric spellings may become protected values, never legalize malformed object keys.
        for json in [#"{1 :"value","text":"bad"}"#, #"{1:"value","text":"bad"}"#,
                     #"{"text":"bad",1 :2}"#, #"{"text":"bad","extra":[1 2]}"#] {
            #expect(TextComponent.content(json: Data(json.utf8)) == nil)
        }
    }

    @Test func numericFormatBoundsApplyOnlyToInterpretedArguments() throws {
        func read(_ literal: String) -> TextComponent.Content? {
            TextComponent.content(json: Data(("{\"translate\":\"test.number\",\"with\":[" + literal + "]}").utf8))
        }
        #expect(try argument(in: read("0.10000000149011612")) == .float(Float(bitPattern: 1036831949)))
        #expect(try argument(in: read("1e9999")) == .float(.infinity))
        #expect(try argument(in: read("1e-9999")) == .float(0))
        #expect(try argument(in: read("1000e-3")) == .integer(1))
        #expect(try argument(in: read("-1000e-3")) == .integer(-1))
        #expect(try argument(in: read("1000000000000000000.01")) == .number(1e18))
        #expect(try argument(in: read("0." + String(repeating: "0", count: 1_020) + "1")) == .float(0))
        for literal in ["1e10000", "1e-10000", "0e10000"] {
            #expect(read(literal) == nil)
            let ignored = "{\"text\":\"Readable\",\"unused\":" + literal + "}"
            #expect(TextComponent.content(json: Data(ignored.utf8)) == .literal("Readable"))
        }
        #expect(try argument(in: read("0e9999")) == .integer(0))
        #expect(try argument(in: read("1.0e10000")) == .float(.infinity))
        // Strict resource parsing rejects these tokens before the argument codec runs.
        for literal in ["1" + String(repeating: "0", count: 1_022),
                        "0." + String(repeating: "0", count: 1_021) + "1",
                        "1" + String(repeating: "0", count: 10_000)] {
            #expect(read(literal) == nil)
            let ignored = "{\"text\":\"Unreadable\",\"unused\":" + literal + "}"
            #expect(TextComponent.content(json: Data(ignored.utf8)) == nil)
        }
        guard case .float(let negativeZero) = try argument(in: read("-1e-999")) else {
            Issue.record("Expected floating negative underflow"); return
        }
        #expect(negativeZero.bitPattern == 1 << 31)
    }

    private func argument(in content: TextComponent.Content?) throws -> TextComponent.Argument {
        let value = try #require(content)
        guard case .translated(_, _, let arguments) = value, arguments.count == 1 else {
            Issue.record("Expected one numeric argument, got \(value)")
            return .number(.nan)
        }
        return arguments[0]
    }
}
