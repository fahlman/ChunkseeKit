import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct NotableBlockTests {
    @Test func everyExistingIDKeepsItsGroupAndStableOrdering() throws {
        let catalog = try NotableBlockFixtures.catalog()
        let ids = ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                   "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore",
                   "minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore",
                   "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore", "minecraft:ancient_debris",
                   "minecraft:spawner", "minecraft:trial_spawner", "minecraft:budding_amethyst"]
        let result = NotableBlock.Deposit.grouped(try scan([section(y: 0, ids: ids)]), using: catalog)
        #expect(result.map(\.block) == [.ancientDebris, .buddingAmethyst, .diamond, .emerald, .gold,
                                       .lapis, .netherGold, .spawner, .trialSpawner])
        #expect(result.map(\.count) == [1, 1, 2, 2, 2, 2, 1, 1, 1])
        #expect(result.allSatisfy { $0.minY == 0 && $0.maxY == 15 })
        #expect(catalog.blockIDs == Set(ids))
        #expect(NotableBlock.Deposit.grouped([], using: catalog).isEmpty)
    }

    @Test func variantsCombineCountsAndEncloseNegativeAndPositiveSections() throws {
        let facts = try scan([
            section(y: -2, ids: ["minecraft:diamond_ore", "minecraft:diamond_ore"]),
            section(y: 1, ids: ["minecraft:deepslate_diamond_ore", "minecraft:deepslate_diamond_ore",
                                "minecraft:deepslate_diamond_ore", "minecraft:spawner"]),
        ])
        #expect(NotableBlock.Deposit.grouped(facts, using: try NotableBlockFixtures.catalog()) == [
            .init(block: .diamond, count: 5, minY: -32, maxY: 31),
            .init(block: .spawner, count: 1, minY: 16, maxY: 31),
        ])
    }

    @Test func untaggedCustomAndCommonBlocksStayOutsideTheSelectedGroups() throws {
        let facts = try scan([section(y: 0, ids: ["example:diamond_ore", "minecraft:coal_ore",
            "minecraft:iron_ore", "minecraft:copper_ore", "minecraft:redstone_ore", "minecraft:stone"])])
        #expect(!facts.isEmpty)
        #expect(NotableBlock.Deposit.grouped(facts, using: try NotableBlockFixtures.catalog()).isEmpty)
    }

    @Test func worldTagsDrivePublicScanAndIndexIncludingCustomOptionalAndOverlappingMembers() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("diamond_ores", ["diamond_ore"]),
            NotableBlockFixtures.tag("emerald_ores", ["mod:shared"]),
            NotableBlockFixtures.tag("gold_ores", ["gold_ore", "nether_gold_ore"]),
            NotableBlockFixtures.tag("lapis_ores", ["lapis_ore"])
        ])
        let metadata = TestZIP.Entry(path: "pack.mcmeta", text: #"{"pack":{"description":"Fixture"}}"#)
        let folder = root.appendingPathComponent("datapacks/low")
        for entry in try [metadata,
            NotableBlockFixtures.tag("diamond_ores", ["#mod:extended"]),
            NotableBlockFixtures.tag("mod:extended", ["mod:diamond", ["id": "mod:shared", "required": false]]),
            NotableBlockFixtures.tag("gold_ores", ["mod:gold", "nether_gold_ore"], replace: true)
        ] {
            try Fixtures.write(Array(entry.text.utf8), to: folder.appendingPathComponent(entry.path))
        }
        let zip = root.appendingPathComponent("datapacks/high.zip")
        try Fixtures.write(TestZIP.zip([metadata, NotableBlockFixtures.tag("diamond_ores",
            ["#mod:extended", "mod:zip_diamond"], replace: true)]), to: zip)
        let world = try world(root, packs: ["vanilla", "file/low", "file/high.zip"])
        let tags = try world.tags(for: NotableBlock.tagIDs, in: "block", assets: jar)
        let catalog = NotableBlock.Catalog(tags: tags)
        #expect(catalog.ids(for: .diamond) == ["mod:diamond", "mod:shared", "mod:zip_diamond"])
        #expect(catalog.ids(for: .gold) == ["mod:gold"])
        #expect(catalog.ids(for: .netherGold) == ["minecraft:nether_gold_ore"])
        #expect(catalog.groups(for: "mod:shared") == [.diamond, .emerald])
        let ids = ["minecraft:diamond_ore", "mod:diamond", "mod:shared", "mod:zip_diamond",
                   "minecraft:gold_ore", "mod:gold", "minecraft:nether_gold_ore", "minecraft:lapis_ore"]
        let path = root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca")
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt:
            Fixtures.chunk(x: 0, z: 0, dataVersion: 999_999, sections: [section(y: -1, ids: ids)]))]), to: path)
        let files = [path, zip, root.appendingPathComponent("level.dat")]
        let before = try files.map { try Data(contentsOf: $0) }
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let facts = try dimension.scan(region: .init(x: 0, z: 0), options: .init(blockIDs: catalog.blockIDs))
        let region = RegionIndex(facts, caveBiomeIDs: [], notableBlocks: catalog)
        let index = DimensionIndex(dimension: dimension.id, caveBiomeIDs: [], notableBlocks: catalog)
            .updating(available: [facts.region], selected: nil, replacements: [region])
        let counts = Dictionary(uniqueKeysWithValues: index.blocks.map { ($0.deposit.block, $0.deposit.count) })
        #expect(counts == [.diamond: 3, .emerald: 1, .gold: 1, .netherGold: 1, .lapis: 1])
        #expect(index.blocks.allSatisfy { $0.deposit.minY == -16 && $0.deposit.maxY == -1 })
        #expect(index.paletteBlockIDs.isSuperset(of: ids))
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func missingMalformedAndEmptyTagsHaveDistinctAnswersWithoutFallbackLists() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("diamond_ores", ["diamond_ore"]),
            NotableBlockFixtures.tag("emerald_ores", [])
        ])
        try Fixtures.write(Array(#"{"pack":{"description":"Fixture"}}"#.utf8),
                           to: root.appendingPathComponent("datapacks/bad/pack.mcmeta"))
        try Fixtures.write(Array("invalid".utf8),
                           to: root.appendingPathComponent("datapacks/bad/data/minecraft/tags/block/diamond_ores.json"))
        let world = try world(root, packs: ["vanilla", "file/bad"])
        let catalog = NotableBlock.Catalog(tags: try world.tags(for: NotableBlock.tagIDs, in: "block", assets: jar))
        #expect(catalog.ids(for: .diamond) == nil && catalog.ids(for: .gold) == nil && catalog.ids(for: .lapis) == nil)
        #expect(catalog.ids(for: .emerald) == [])
        #expect(catalog.groups(for: "diamond_ore").isEmpty)
        #expect(catalog.groups(for: "nether_gold_ore") == [.netherGold])
        #expect(catalog.blockIDs.count == 5)
    }

    @Test func aChangedTagSnapshotCannotReplaceRegionsInThePreviousIndex() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla"])
        let jar = try NotableBlockFixtures.assets([NotableBlockFixtures.tag("diamond_ores", ["mod:new_ore"])])
        let known = NotableBlock.Catalog(tags: try world.tags(for: NotableBlock.tagIDs, in: "block", assets: jar))
        let unavailable = NotableBlock.Catalog(tags: [:])
        let path = root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca")
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt:
            Fixtures.chunk(x: 0, z: 0, dataVersion: 999_999, sections: [section(y: 0, ids: ["mod:new_ore"])]))]), to: path)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let facts = try dimension.scan(region: .init(x: 0, z: 0), options: .init(blockIDs: known.blockIDs))
        let region = RegionIndex(facts, caveBiomeIDs: [], notableBlocks: known)
        let prior = DimensionIndex(dimension: dimension.id, caveBiomeIDs: [], notableBlocks: unavailable)
        #expect(prior.updating(available: [facts.region], selected: nil, replacements: [region]).regions.isEmpty)
        let fresh = DimensionIndex(dimension: dimension.id, caveBiomeIDs: [], notableBlocks: known)
        #expect(fresh.regionsToRead(available: [facts.region], selected: []) == [facts.region])
        #expect(fresh.updating(available: [facts.region], selected: nil, replacements: [region]).blocks.first?.deposit.count == 1)
    }

    private func world(_ root: URL, packs: [String]) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(999_999), "DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))])
        ])]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
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
