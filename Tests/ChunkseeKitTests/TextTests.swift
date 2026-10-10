import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct TextTests {
    func side(_ lines: [NBT]) -> NBT { .compound(["messages": .list(lines), "color": .string("black")]) }

    @Test func signsFromBlockEntities() {
        let chunk = NBT.compound(["block_entities": .list([
            .compound(["id": .string("minecraft:sign"), "x": .int(-2895), "y": .int(68), "z": .int(2245),
                       "front_text": side([.string("East"), .string("Northeast"), .string("to"), .string("Desert Village")]),
                       "back_text": side([.string(""), .string(""), .string(""), .string("")])]),
            .compound(["id": .string("minecraft:hanging_sign"), "x": .int(1), "y": .int(2), "z": .int(3),
                       "front_text": side([.string(""), .string(""), .string(""), .string("")]),
                       "back_text": side([.compound(["text": .string("Back "), "extra": .list([.string("side")])]), .string(""), .string(""), .string("")])]),
            // Blank signs aren't worth listing.
            .compound(["id": .string("minecraft:oak_sign"), "x": .int(0), "y": .int(0), "z": .int(0),
                       "front_text": side([.string(" "), .string(""), .string(""), .string("")])]),
            // Before 1.20, one side, as JSON.
            .compound(["id": .string("minecraft:sign"), "x": .int(5), "y": .int(6), "z": .int(7),
                       "Text1": .string(#"{"text":"Old"}"#), "Text2": .string(#""""#), "Text3": .string(#"{"text":""}"#), "Text4": .string(#""sign""#)]),
            .compound(["id": .string("minecraft:chest"), "x": .int(0), "y": .int(0), "z": .int(0)]),
        ])])
        let signs = Sign.signs(inChunk: chunk)
        #expect(signs.map(\.kind) == ["minecraft:sign", "minecraft:hanging_sign", "minecraft:sign"])
        #expect(signs[0].front == ["East", "Northeast", "to", "Desert Village"] && signs[0].x == -2895)
        #expect(signs[1].back.first == "Back side")
        #expect(signs[2].front == ["Old", "", "", "sign"] && signs[2].back.isEmpty)
    }

    @Test func writtenAndWritableBooks() throws {
        let written = try #require(ItemStack(.compound(["id": .string("minecraft:written_book"), "count": .int(1), "components": .compound([
            "minecraft:written_book_content": .compound([
                "title": .compound(["raw": .string("Diary")]),
                "author": .string("fahlman"),
                "pages": .list([.compound(["raw": .string("Day one")]), .compound(["text": .string("Day "), "extra": .list([.string("two")])])]),
            ]),
        ])])))
        #expect(written.book == BookContent(title: "Diary", author: "fahlman", pages: ["Day one", "Day two"]))

        let quill = try #require(ItemStack(.compound(["id": .string("minecraft:writable_book"), "count": .int(1), "components": .compound([
            "minecraft:writable_book_content": .compound(["pages": .list([.compound(["raw": .string("[draft]")]), .string("notes")])]),
        ])])))
        #expect(quill.book == BookContent(pages: ["[draft]", "notes"]))

        let legacy = try #require(ItemStack(.compound(["id": .string("minecraft:written_book"), "Count": .byte(1), "tag": .compound([
            "title": .string("Old Tales"), "author": .string("Notch"), "pages": .list([.string(#"{"text":"Once"}"#)]),
        ])])))
        #expect(legacy.book == BookContent(title: "Old Tales", author: "Notch", pages: ["Once"]))

        #expect(ItemStack(.compound(["id": .string("minecraft:diamond"), "count": .int(1)]))?.book == nil)
    }
}
