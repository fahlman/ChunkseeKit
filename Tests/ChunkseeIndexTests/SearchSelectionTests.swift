import ChunkseeIndex
import ChunkseeKit
import Foundation
import Testing

@Suite struct SearchSelectionTests {
    @Test func inventoryIncludesSavedEquipmentWithoutRepeatingTheSelectedHotbarOrEnderChest() {
        func item(_ id: String, slot: Int8? = nil) -> NBT {
            var fields: [String: NBT] = ["id": .string("minecraft:" + id), "count": .int(1)]
            if let slot { fields["Slot"] = .byte(slot) }
            return .compound(fields)
        }
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Inventory": .list([item("diamond", slot: 0), item("stone", slot: 9)]),
            "SelectedItemSlot": .int(0), "EnderItems": .list([item("emerald")]),
            "equipment": .compound(["head": item("iron_helmet"), "offhand": item("shield")]),
        ]))
        #expect(player.searchableInventory.map(\.id) == ["minecraft:diamond", "minecraft:stone",
                                                        "minecraft:iron_helmet", "minecraft:shield"])
        #expect(player.enderChest.map(\.id) == ["minecraft:emerald"])
    }

    @Test func bookTextKeepsSavedFieldOrderAndPhraseBoundaries() {
        let book = BookContent(title: "Travels", author: "Writer", pages: ["Red", "Blue"])
        #expect(book.searchText == "Travels\nWriter\nRed\nBlue")
        #expect(SearchQuery("blue writer").matches(book.searchText))
        #expect(SearchQuery(phrase: "red\nblue").matches(book.searchText))
        #expect(!SearchQuery(phrase: "red blue").matches(book.searchText))
        #expect(BookContent(pages: ["Unsigned", ""]).searchText == "Unsigned\n")
        #expect(BookContent(pages: []).searchText.isEmpty)
    }

    @Test func signLinesKeepBothSidesAndWhitespaceButRemoveEmptyLines() {
        let sign = Sign(kind: "minecraft:sign", x: -1, y: 64, z: 2,
                        front: ["Red", "", "Blue"], back: ["  Green  ", ""])
        #expect(sign.searchLines == ["Red", "Blue", "  Green  "])
        let text = sign.searchLines.joined(separator: " ")
        #expect(SearchQuery(phrase: "red blue").matches(text))
        #expect(!SearchQuery(phrase: "blue green").matches(text))
        #expect(SearchQuery("blue green").matches(text))
    }

    @Test func parsedFiltersSelectTheExpectedCreatureCategories() throws {
        let queries: [(String, Set<CreatureEntry.Group>)] = [
            ("creature: Summer", [.named, .pet, .villager, .mob]), ("PET: Summer", [.pet]),
            ("villager:", [.villager]), ("trade: mending", [.villager]),
            ("structure:", []), ("place:", []), ("biome:", []), ("block:", []),
        ]
        for (text, expected) in queries {
            let filter = try #require(SearchQuery(text).filter)
            #expect(Set(CreatureEntry.Group.allCases.filter(filter.includes)) == expected)
        }
    }

}
