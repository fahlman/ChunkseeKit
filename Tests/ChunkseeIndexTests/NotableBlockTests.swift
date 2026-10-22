import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct NotableBlockTests {
    @Test func everyExistingIDKeepsItsGroupAndStableOrdering() throws {
        let ids = ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                   "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore",
                   "minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore",
                   "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore", "minecraft:ancient_debris",
                   "minecraft:spawner", "minecraft:trial_spawner", "minecraft:budding_amethyst"]
        let result = NotableBlock.Deposit.grouped(try scan([section(y: 0, ids: ids)]))
        #expect(result.map(\.block) == [.ancientDebris, .buddingAmethyst, .diamond, .emerald, .gold,
                                       .lapis, .netherGold, .spawner, .trialSpawner])
        #expect(result.map(\.count) == [1, 1, 2, 2, 2, 2, 1, 1, 1])
        #expect(result.allSatisfy { $0.minY == 0 && $0.maxY == 15 })
        #expect(Set(NotableBlock.byID.keys) == Set(ids))
        #expect(NotableBlock.Deposit.grouped([]).isEmpty)
    }

    @Test func variantsCombineCountsAndEncloseNegativeAndPositiveSections() throws {
        let facts = try scan([
            section(y: -2, ids: ["minecraft:diamond_ore", "minecraft:diamond_ore"]),
            section(y: 1, ids: ["minecraft:deepslate_diamond_ore", "minecraft:deepslate_diamond_ore",
                                "minecraft:deepslate_diamond_ore", "minecraft:spawner"]),
        ])
        #expect(NotableBlock.Deposit.grouped(facts) == [
            .init(block: .diamond, count: 5, minY: -32, maxY: 31),
            .init(block: .spawner, count: 1, minY: 16, maxY: 31),
        ])
    }

    @Test func unknownNamespacesAndCommonBlocksStayOutsideTheCatalog() throws {
        let facts = try scan([section(y: 0, ids: ["example:diamond_ore", "minecraft:coal_ore",
            "minecraft:iron_ore", "minecraft:copper_ore", "minecraft:redstone_ore", "minecraft:stone"])])
        #expect(!facts.isEmpty)
        #expect(NotableBlock.Deposit.grouped(facts).isEmpty)
    }

    private func section(y: Int, ids: [String]) -> NBT {
        let palette = ["minecraft:air"] + Array(Set(ids)).sorted()
        var indices = [Int](repeating: 0, count: 4096)
        for (offset, id) in ids.enumerated() { indices[offset] = palette.firstIndex(of: id)! }
        return Fixtures.section(y: y, palette: palette.map { .compound(["Name": .string($0)]) }, indices: indices)
    }

    private func scan(_ sections: [NBT]) throws -> [ChunkseeKit.BlockDeposit] {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Grouped deposits"),
            "DataVersion": .int(5023)])]), to: root.appendingPathComponent("level.dat"))
        let chunk = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: sections)
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        let dimension = try #require(try World(contentsOf: root).dimension("overworld"))
        let facts = try dimension.scan(region: .init(x: 0, z: 0))
        return try #require(facts.chunks.first).blockDeposits
    }
}
