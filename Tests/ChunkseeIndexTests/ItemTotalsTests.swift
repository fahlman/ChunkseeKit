import ChunkseeIndex
import ChunkseeKit
import Testing

@Suite struct ItemTotalsTests {
    @Test func nestedMatchesKeepOuterAndInnerQuantitiesWithoutRequiringAnOuterMatch() {
        let items = [
            ItemStack(id: "minecraft:shulker_box", contents: [
                ItemStack(id: "minecraft:diamond", count: 3),
                ItemStack(id: "minecraft:bundle", contents: [ItemStack(id: "minecraft:diamond", count: 5)]),
            ]),
            ItemStack(id: "minecraft:diamond", count: 7),
        ]
        let query = SearchQuery(phrase: "DIAMOND")
        let found = ItemTotals(in: items, matching: { query.matches($0.id) }, groupingBy: \.id)
        #expect(found.quantities == ["minecraft:diamond": 15])
        #expect(found.count == 15 && !found.isEmpty)
        let all = ItemTotals(in: items, groupingBy: \.id)
        #expect(all.quantities == ["minecraft:diamond": 15, "minecraft:bundle": 1, "minecraft:shulker_box": 1])
        #expect(all.count == 17)
    }

    @Test func groupingKeysPreserveClientIdentityWithoutChangingTheTotalQuantity() {
        struct Key: Hashable, Sendable {
            var id: String
            var name: String?
        }
        let items = [
            ItemStack(id: "minecraft:diamond", count: 2, customName: "Shared"),
            ItemStack(id: "minecraft:stone", count: 3, customName: "Shared"),
            ItemStack(id: "minecraft:diamond", count: 4, customName: "Shared"),
        ]
        let byName = ItemTotals(in: items, groupingBy: { $0.customName ?? $0.id })
        let byKindAndName = ItemTotals(in: items, groupingBy: { Key(id: $0.id, name: $0.customName) })
        #expect(byName.quantities == ["Shared": 9])
        #expect(byKindAndName.quantities == [Key(id: "minecraft:diamond", name: "Shared"): 6,
                                           Key(id: "minecraft:stone", name: "Shared"): 3])
        #expect(byName.count == byKindAndName.count && byName.count == 9)
    }

    @Test func emptyResultsStayDistinctFromMatchingZeroQuantities() {
        let zero = ItemStack(id: "minecraft:diamond", count: 0)
        let found = ItemTotals(in: [zero], groupingBy: \.id)
        #expect(found.quantities == ["minecraft:diamond": 0] && found.count == 0 && !found.isEmpty)
        let unmatched = ItemTotals(in: [zero], matching: { _ in false }, groupingBy: \.id)
        #expect(unmatched.isEmpty && unmatched.count == 0)
        #expect(ItemTotals(in: [], groupingBy: \ItemStack.id).isEmpty)
    }
}
