import ChunkseeKit
import ChunkseeIndex
import Testing

@Suite struct StorageTotalsTests {
    @Test func nestedItemsCountWithTheirOuterContainer() throws {
        var chest = try container()
        chest.items = [
            ItemStack(id: "minecraft:diamond", count: 3),
            ItemStack(id: "minecraft:shulker_box", contents: [
                ItemStack(id: "minecraft:diamond", count: 64),
                ItemStack(id: "minecraft:bundle", contents: [ItemStack(id: "minecraft:diamond", count: 5)]),
            ]),
        ]
        var barrel = try container()
        barrel.items = [ItemStack(id: "minecraft:diamond", count: 10), ItemStack(id: "minecraft:dirt", count: 64)]
        let totals = StoredItemTotal.totals(in: [chest, barrel])
        #expect(totals.map(\.id) == ["minecraft:bundle", "minecraft:diamond", "minecraft:dirt", "minecraft:shulker_box"])
        let diamonds = try #require(totals.first { $0.id == "minecraft:diamond" })
        #expect(diamonds.count == 82 && diamonds.containers == 2)
        for id in ["minecraft:shulker_box", "minecraft:bundle"] {
            let box = try #require(totals.first { $0.id == id })
            #expect(box.count == 1 && box.containers == 1)
        }
        #expect(totals.first { $0.id == "minecraft:dirt" }?.count == 64)
    }

    @Test func savedIDsGroupRenamedStacksAndColocatedContainersRemainDistinct() throws {
        var first = try container()
        first.items = [ItemStack(id: "minecraft:diamond", count: 2, customName: "Treasure"),
                       ItemStack(id: "minecraft:diamond", count: 3, customName: "Other name"),
                       ItemStack(id: "custom:diamond", count: 7, customName: "Treasure")]
        var second = first
        second.items = [ItemStack(id: "minecraft:diamond", count: 4)]
        let totals = StoredItemTotal.totals(in: [first, second])
        #expect(totals.map(\.id) == ["custom:diamond", "minecraft:diamond"])
        #expect(totals.map(\.count) == [7, 9])
        #expect(totals.map(\.containers) == [1, 2])
        #expect(StoredItemTotal.totals(in: [second, first]) == totals)
    }

    @Test func emptyAndUnopenedContainersDoNotInventItems() throws {
        var empty = try container()
        empty.items = []
        let sealed = try #require(ItemContainer.containers(inChunk: .compound(["block_entities": .list([
            .compound(["id": .string("minecraft:chest"), "x": .int(0), "y": .int(64), "z": .int(0),
                       "LootTable": .string("minecraft:chests/simple_dungeon")]),
        ])])).first)
        #expect(sealed.isSealedLoot)
        #expect(StoredItemTotal.totals(in: []).isEmpty)
        #expect(StoredItemTotal.totals(in: [empty, sealed]).isEmpty)
    }

    private func container() throws -> ItemContainer {
        try #require(ItemContainer.containers(inChunk: .compound(["block_entities": .list([
            .compound(["id": .string("minecraft:chest"), "x": .int(0), "y": .int(64), "z": .int(0),
                       "Items": .list([.compound(["id": .string("minecraft:diamond"), "count": .int(1)])])]),
        ])])).first)
    }
}
