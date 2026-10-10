import Foundation
import ChunkseeKit

/// Commands that search containers, players, signs and books.

func findCommand(_ world: World, _ arguments: Arguments) {
        let query = arguments.text(1).lowercased()
        func matches(_ item: ItemStack) -> Bool {
            item.id.lowercased().contains(query) || (item.customName?.lowercased().contains(query) ?? false)
        }
        func summary(_ items: [ItemStack]) -> String {
            let hits = items.flatMap(\.allItems).filter(matches)
            let byID = Dictionary(grouping: hits, by: { $0.customName.map { "\"\($0)\"" } ?? $0.id }).mapValues { $0.reduce(0) { $0 + $1.count } }
            return byID.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        }
        for player in world.players() {
            for (label, items) in [("inventory", player.inventory + Array(player.equipment.values)), ("ender chest", player.enderChest)] {
                let found = summary(items)
                if !found.isEmpty { print("player \(player.uuid.uuidString.prefix(8).lowercased()) \(label): \(found)") }
            }
        }
        let dims = arguments.dimensions(2, in: world)
        var total = 0
        for dim in dims {
            for (rx, rz, _) in dim.regionFiles() {
                for container in (try? dim.containers(regionX: rx, regionZ: rz)) ?? [] {
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
        let query = arguments.text(1).lowercased()
        func books(_ items: [ItemStack]) -> [String] {
            items.flatMap(\.allItems).compactMap { item in
                guard let book = item.book else { return nil }
                let text = ([book.title, book.author].compactMap(\.self) + book.pages).joined(separator: "\n")
                guard text.lowercased().contains(query) else { return nil }
                return book.title.map { "\"\($0)\" by \(book.author ?? "?")" } ?? "book and quill"
            }
        }
        for player in world.players() {
            for book in books(player.inventory + player.enderChest) {
                print("player \(player.uuid.uuidString.prefix(8).lowercased()): \(book)")
            }
        }
        let dims = arguments.dimensions(2, in: world)
        var total = 0
        for dim in dims {
            for (rx, rz, _) in dim.regionFiles() {
                guard let contents = try? dim.contents(regionX: rx, regionZ: rz) else { continue }
                for sign in contents.signs {
                    let lines = (sign.front + sign.back).filter { !$0.isEmpty }
                    guard lines.joined(separator: " ").lowercased().contains(query) else { continue }
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
