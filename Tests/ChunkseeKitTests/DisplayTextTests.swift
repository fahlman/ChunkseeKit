import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct DisplayTextTests {
    @Test func componentsRemoveCodesAfterJoiningWithoutLosingLayout() {
        let component = NBT.compound([
            "text": .string(" §aBack "),
            "extra": .list([.compound(["text": .string("§l side"),
                                      "extra": .list([.string("§r\nnext ")])])]),
        ])
        #expect(TextComponent.plainText(component) == " Back  side\nnext ")
        #expect(TextComponent.plainText(.string(#"{"text":"§aOld ","extra":[{"text":"§lBox§r"}]}"#)) == "Old Box")
        #expect(TextComponent.plainText(.list([.string("§"), .string("aSummer"), .string("§r")])) == "Summer")
        #expect(TextComponent.plainText(.string("§a§l§r")) == nil)
        #expect(TextComponent.plainText(.string(" §r ")) == "  ")
        #expect(TextComponent.plainText(.int(1)) == nil)
        #expect(TextComponent.plainText(.string("日本語 🐺")) == "日本語 🐺")
    }

    @Test func regionReadersShareDisplayTextForItemsContainersSignsAndCreatures() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = NBT.compound(["id": .string("minecraft:diamond"), "count": .int(2),
                                 "components": .compound(["minecraft:custom_name": .string("§bBright§r")])])
        let oldItem = NBT.compound(["id": .string("minecraft:diamond"), "Count": .byte(1),
                                    "tag": .compound(["display": .compound([
                                        "Name": .string(#"{"text":"§eOld ","extra":[{"text":"Gem§r"}]}"#),
                                    ])])])
        func block(_ id: String, _ extra: [String: NBT]) -> NBT {
            .compound(["id": .string(id), "x": .int(0), "y": .int(64), "z": .int(0)].merging(extra) { $1 })
        }
        let chunk = Fixtures.chunk(x: 0, z: 0, sections: [], extra: ["block_entities": .list([
            block("minecraft:chest", ["CustomName": .string("§6Treasure§r"), "Items": .list([item, oldItem])]),
            block("minecraft:sign", ["front_text": .compound(["messages": .list([.string("§aNorth§r")])])]),
            block("minecraft:sign", ["Text1": .string(#"{"text":"§eOld ","extra":["sign§r"]}"#)]),
            block("minecraft:sign", ["front_text": .compound(["messages": .list([.string("§r")])])]),
        ])])
        let entities = NBT.compound(["Entities": .list([
            .compound(["id": .string("minecraft:chest_minecart"),
                       "Pos": .list([.double(1), .double(64), .double(2)]),
                       "CustomName": .string("§cSupplies§r"), "Items": .list([item])]),
            Fixtures.mob(["id": .string("minecraft:wolf"),
                       "Pos": .list([.double(2), .double(64), .double(3)]),
                       "Health": .float(8),
                       "CustomName": .string(" §aSummer§r ")]),
        ])])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]),
                           to: dir.appendingPathComponent("region/r.0.0.mca"))
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: entities)]),
                           to: dir.appendingPathComponent("entities/r.0.0.mca"))
        let dimension = Dimension(id: "minecraft:overworld", url: dir)
        let found = try dimension.contents(regionX: 0, regionZ: 0)
        #expect(found.containers.map(\.customName) == ["Treasure", "Supplies"])
        #expect(found.containers[0].items.map(\.customName) == ["Bright", "Old Gem"])
        #expect(found.containers[1].items.first?.customName == "Bright")
        #expect(found.signs.map(\.front) == [["North"], ["Old sign", "", "", ""]])
        #expect(found.namedCreatures.map(\.customName) == ["Summer"])
    }

    @Test func mapBannersAndWrittenPagesUseComponentsButDraftPagesStayLiteral() throws {
        let map = try #require(MapItem(id: 1, nbt: .compound(["data": .compound([
            "dimension": .byte(0), "colors": .byteArray([Int8](repeating: 0, count: 128 * 128)),
            "banners": .list([.compound([
                "Pos": .compound(["X": .int(1), "Y": .int(64), "Z": .int(2)]),
                "Name": .string("§aHome§r"),
            ])]),
        ])])))
        #expect(map.banners.first?.name == "Home")
        let written = try #require(ItemStack(.compound([
            "id": .string("minecraft:written_book"), "count": .int(1),
            "components": .compound(["minecraft:written_book_content": .compound([
                "title": .string("§6Diary§r"), "author": .string("Writer"),
                "pages": .list([.string("§aDay one§r\n Day two ")]),
            ])]),
        ])))
        #expect(written.book?.title == "Diary")
        #expect(written.book?.pages == ["Day one\n Day two "])
        for modern in [false, true] {
            let literal = " §a[draft]\n "
            let fields: [String: NBT] = modern
                ? ["components": .compound(["minecraft:writable_book_content": .compound(["pages": .list([.string(literal)])])])]
                : ["tag": .compound(["pages": .list([.string(literal)])])]
            let draft = try #require(ItemStack(.compound(["id": .string("minecraft:writable_book"), "count": .int(1)].merging(fields) { $1 })))
            #expect(draft.book?.pages == [literal])
        }
    }
}
