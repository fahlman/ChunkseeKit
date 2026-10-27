import Foundation
import Testing
import ChunkseeKit

@Suite struct JSONSyntaxTests {
    @Test func directAndEscapedStringsPreserveUnicodeAndLiteralCharacters() throws {
        let texts = ["", "plain", "日本語 🌊", "é e\u{301}", "quote\" slash/ backslash\\",
                     "\u{0000}\u{0001}\u{001F}\t\n\r", "12345 true false null [ ] { } , :"]
        for text in texts {
            let data = try JSONSerialization.data(withJSONObject: ["text": text, "unused": 1.5])
            #expect(TextComponent.content(json: data) == .literal(text))
        }
        for json in [#"{"text":"\uD83C\uDF0A"}"#, #"{"text":"🌊"}"#] {
            #expect(TextComponent.content(json: Data(json.utf8)) == .literal("🌊"))
        }
        let escapedKey = #"{"\u0074ext":"first","text":"second","unused":1.5}"#
        #expect(TextComponent.content(json: Data(escapedKey.utf8)) == .literal("first"))
    }

    @Test func completeContainersAndFoundationSyntaxRemainReadable() throws {
        let json = "\t\n {\"text\":\"root\",\"extra\":[{\"text\":\" leaf\",},],\"unused\":[true,false,null,{},[]],} \r\n"
        #expect(TextComponent.content(json: Data(json.utf8)) == .sequence([.literal("root"), .literal(" leaf")]))
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"text":"BOM","unused":1.5}"#.utf8)
        #expect(TextComponent.content(json: bom) == .literal("BOM"))
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            let data = try #require(#"{"text":"Unicode"}"#.data(using: encoding))
            #expect(TextComponent.content(json: data) == .literal("Unicode"))
        }
        #expect(TextComponent.content(json: Data(#"{"text":"ok","unused":{"value":null}}"#.utf8)) == .literal("ok"))
    }

    @Test func malformedTokensStringsAndContainerBoundariesAreRejected() {
        for json in ["", "true false", #"{"text":"ok"} false"#, #"{"text":"ok""unused":0}"#,
                     #"{"text" "ok"}"#, #"{"text":"ok",,"unused":0}"#, #"{"text":"ok","unused":[,]}"#,
                     #"{"text":"ok","unused":[true false]}"#, #"{"text":"ok","unused":tru}"#,
                     #"{"text":"ok","unused":NULL}"#, #"{"text":"ok","unused":+1}"#,
                     #"{"text":"ok","unused":01}"#, #"{"text":"ok","unused":1.}"#,
                     #"{"text":"ok","unused":1e+}"#, #"{"text":"bad\q"}"#,
                     #"{"text":"bad\u12X4"}"#, #"{"text":"\uD800"}"#, #"{"text":"\uDC00"}"#,
                     "{\"text\":\"raw\nnewline\"}", #"{"text":"ok",1:"bad key"}"#] {
            #expect(TextComponent.content(json: Data(json.utf8)) == nil, "\(json)")
        }
        let invalidUTF8 = Data(#"{"text":""#.utf8) + Data([0xFF]) + Data(#""}"#.utf8)
        #expect(TextComponent.content(json: invalidUTF8) == nil)
    }

    @Test func ignoredContainerNestingRetainsTheFoundationLimit() {
        func input(_ depth: Int, opening: String, closing: String) -> Data {
            Data((#"{"text":"ok","unused":"# + String(repeating: opening, count: depth) + "true" +
                  String(repeating: closing, count: depth) + "}").utf8)
        }
        for (opening, closing) in [("[", "]"), ("{\"nested\":", "}")] {
            #expect(TextComponent.content(json: input(511, opening: opening, closing: closing)) == .literal("ok"))
            #expect(TextComponent.content(json: input(512, opening: opening, closing: closing)) == nil)
        }
    }
}
