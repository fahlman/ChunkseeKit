import Foundation
import ChunkseeKit
import ChunkseeIndex

/// Commands that search containers, players, signs and books.

func findCommand(_ world: World, _ arguments: Arguments) {
        let query = SearchQuery(phrase: arguments.text(1))
        func matches(_ item: ItemStack) -> Bool {
            query.matches(item.id) || (item.customName.map(query.matches) ?? false)
        }
        func summary(_ items: [ItemStack]) -> String {
            let totals = ItemTotals(in: items, matching: matches) {
                $0.customName.map { "\"\($0)\"" } ?? $0.id
            }
            return totals.quantities.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        }
        for player in world.players() {
            for (label, items) in [("inventory", player.searchableInventory), ("ender chest", player.enderChest)] {
                let found = summary(items)
                if !found.isEmpty { print("player \(player.uuid.uuidString.prefix(8).lowercased()) \(label): \(found)") }
            }
        }
        let dims = arguments.dimensions(2, in: world)
        var total = 0
        for dim in dims {
            for region in searchRegions(in: dim) {
                for container in (try? dim.containers(regionX: region.x, regionZ: region.z)) ?? [] {
                    let found = summary(container.items)
                    guard !found.isEmpty else { continue }
                    total += 1
                    let name = container.customName.map { " \"\($0)\"" } ?? ""
                    print("\(dim.id) \(container.kind)\(name) at (\(container.x), \(container.y), \(container.z)): \(found)")
                }
            }
        }
        print("\(total) containers")
}

func textCommand(_ world: World, _ arguments: Arguments) {
        let query = SearchQuery(phrase: arguments.text(1))
        func books(_ items: [ItemStack]) -> [String] {
            items.flatMap(\.allItems).compactMap { item in
                guard let book = item.book else { return nil }
                let text = ([book.title, book.author].compactMap(\.self) + book.pages).joined(separator: "\n")
                guard query.matches(text) else { return nil }
                return book.title.map { "\"\($0)\" by \(book.author ?? "?")" } ?? "book and quill"
            }
        }
        for player in world.players() {
            for book in books(player.searchableInventory + player.enderChest) {
                print("player \(player.uuid.uuidString.prefix(8).lowercased()): \(book)")
            }
        }
        let dims = arguments.dimensions(2, in: world)
        var total = 0
        for dim in dims {
            for region in searchRegions(in: dim) {
                guard let contents = try? dim.contents(regionX: region.x, regionZ: region.z) else { continue }
                for sign in contents.signs {
                    let lines = (sign.front + sign.back).filter { !$0.isEmpty }
                    guard query.matches(lines.joined(separator: " ")) else { continue }
                    total += 1
                    print("\(dim.id) \(sign.kind) at (\(sign.x), \(sign.y), \(sign.z)): \(lines.joined(separator: " / "))")
                }
                for container in contents.containers {
                    for book in books(container.items) {
                        total += 1
                        print("\(dim.id) \(container.kind) at (\(container.x), \(container.y), \(container.z)): \(book)")
                    }
                }
            }
        }
        print("\(total) matches")
}
