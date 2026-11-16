import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct NotableBlockTests {
    @Test func existingMembersKeepCountsAndSectionBounds() throws {
        let catalog = try NotableBlockFixtures.catalog()
        let ids = ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                   "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore",
                   "minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore",
                   "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore", "minecraft:ancient_debris",
                   "minecraft:spawner", "minecraft:trial_spawner", "minecraft:budding_amethyst"]
        let result = NotableBlock.Deposit.grouped(try scan([section(y: 0, ids: ids)]), using: catalog)
        #expect(Dictionary(uniqueKeysWithValues: result.map { ($0.block, $0.count) }) == [
            .diamond: 2, .emerald: 2, .gold: 2, .lapis: 2, .ancientDebris: 1,
            .buddingAmethyst: 1, .netherGold: 1, .spawner: 1, .trialSpawner: 1])
        #expect(result.map(\.block.id) == result.map(\.block.id).sorted())
        #expect(result.allSatisfy { $0.minY == 0 && $0.maxY == 15 })
        #expect(catalog.blockIDs == Set(ids))
        #expect(NotableBlock.Deposit.grouped([], using: catalog).isEmpty)
        let across = try scan([
            section(y: -2, ids: ["minecraft:diamond_ore", "minecraft:diamond_ore"]),
            section(y: 1, ids: ["minecraft:deepslate_diamond_ore", "minecraft:spawner"]),
        ])
        #expect(NotableBlock.Deposit.grouped(across, using: catalog) == [
            .init(block: .diamond, count: 3, minY: -32, maxY: 31),
            .init(block: .spawner, count: 1, minY: 16, maxY: 31)])
    }

    @Test func composedPackEntriesSupplyNewGroupsDirectIDsAndOverlaps() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("ores", ["#diamond_ores", "#gold_ores"]),
            NotableBlockFixtures.tag("diamond_ores", ["diamond_ore"]),
            NotableBlockFixtures.tag("gold_ores", ["gold_ore", "nether_gold_ore"]),
        ])
        let metadata = TestZIP.Entry(path: "pack.mcmeta", text: #"{"pack":{"description":"Fixture"}}"#)
        let folder = root.appendingPathComponent("datapacks/low")
        for entry in try [metadata,
            NotableBlockFixtures.tag("ores", ["#mod:glowing", "mod:direct", ["id": "#mod:absent", "required": false]]),
            NotableBlockFixtures.tag("mod:glowing", ["#mod:nested", "mod:shared"]),
            NotableBlockFixtures.tag("mod:nested", [["id": "mod:optional", "required": false]]),
            NotableBlockFixtures.tag("diamond_ores", ["mod:shared"]),
            NotableBlockFixtures.tag("gold_ores", ["mod:gold", "nether_gold_ore"], replace: true)
        ] {
            try Fixtures.write(Array(entry.text.utf8), to: folder.appendingPathComponent(entry.path))
        }
        let zip = root.appendingPathComponent("datapacks/high.zip")
        try Fixtures.write(TestZIP.zip([metadata, NotableBlockFixtures.tag("diamond_ores",
            ["mod:shared", "mod:zip_diamond"], replace: true)]), to: zip)
        let world = try world(root, packs: ["vanilla", "file/low", "file/high.zip"])
        let tags = try world.tags(for: NotableBlock.tagIDs, in: "block", assets: jar)
        let catalog = NotableBlock.Catalog(tags: tags)
        #expect(catalog.ids(for: .diamond) == ["mod:shared", "mod:zip_diamond"])
        #expect(catalog.ids(for: .gold) == ["mod:gold"])
        #expect(catalog.ids(for: .netherGold) == ["minecraft:nether_gold_ore"])
        #expect(catalog.ids(for: .tag("mod:glowing")) == ["mod:optional", "mod:shared"])
        #expect(catalog.ids(for: .block("mod:direct")) == ["mod:direct"])
        #expect(catalog.ids(for: .tag("mod:absent")) == nil)
        #expect(catalog.groups(for: "mod:shared") == [.diamond, .tag("mod:glowing")])
        let ids = ["minecraft:diamond_ore", "mod:shared", "mod:zip_diamond", "mod:optional",
                   "minecraft:gold_ore", "mod:gold", "minecraft:nether_gold_ore", "mod:direct"]
        let raw = try scan([section(y: -1, ids: ids)])
        let groups = NotableBlock.Deposit.grouped(raw, using: catalog)
        #expect(Dictionary(uniqueKeysWithValues: groups.map { ($0.block, $0.count) }) == [
            .diamond: 2, .gold: 1, .netherGold: 1, .tag("mod:glowing"): 2, .block("mod:direct"): 1])
        #expect(groups.allSatisfy { $0.minY == -16 && $0.maxY == -1 })
    }

    @Test func replacedRootDropsOldGroupsAndDoesNotInventCommonOres() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("ores", ["#diamond_ores"]),
            NotableBlockFixtures.tag("diamond_ores", ["diamond_ore"]),
        ])
        for entry in try [TestZIP.Entry(path: "pack.mcmeta", text: #"{"pack":{"description":"Fixture"}}"#),
            NotableBlockFixtures.tag("ores", ["mod:only"], replace: true)] {
            try Fixtures.write(Array(entry.text.utf8), to: root.appendingPathComponent("datapacks/top/" + entry.path))
        }
        let world = try world(root, packs: ["vanilla", "file/top"])
        let catalog = NotableBlock.Catalog(tags: try world.tags(for: NotableBlock.tagIDs, in: "block", assets: jar))
        #expect(catalog.hasOreDefinitions && catalog.ids(for: .diamond) == nil)
        #expect(catalog.ids(for: .block("mod:only")) == ["mod:only"])
        #expect(catalog.groups(for: "coal_ore").isEmpty && catalog.groups(for: "diamond_ore").isEmpty)
    }

    @Test func missingMalformedEmptyAndEmptyChildTagsRemainDifferent() throws {
        let missing = NotableBlock.Catalog(tags: [:])
        #expect(!missing.hasOreDefinitions && missing.blockIDs.count == 5)
        let emptyJar = try NotableBlockFixtures.assets([NotableBlockFixtures.tag("ores", [])])
        let empty = NotableBlock.Catalog(tags: ["minecraft:ores": try #require(emptyJar.tag("ores", in: "block"))])
        #expect(empty.hasOreDefinitions && empty.blockIDs == missing.blockIDs)
        let childJar = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("ores", ["#mod:empty"]), NotableBlockFixtures.tag("mod:empty", [])])
        let child = NotableBlock.Catalog(tags: ["minecraft:ores": try #require(childJar.tag("ores", in: "block"))])
        #expect(child.ids(for: .tag("mod:empty")) == [])
        let bad = try NotableBlockFixtures.assets([
            NotableBlockFixtures.tag("ores", ["#mod:broken"]),
            .init(path: "data/mod/tags/block/broken.json", text: "invalid")])
        #expect(try bad.tag("ores", in: "block") == nil)
    }

    @Test func regroupingKnownIDsReusesRawCountsWithoutRetiringCoreFacts() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla"])
        let path = root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca")
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt:
            Fixtures.chunk(x: 0, z: 0, sections: [section(y: 0, ids: ["mod:ore"])]))]), to: path)
        let dimension = try #require(world.dimension("overworld")), position = RegionPosition(x: 0, z: 0)
        let core = RegionIndex(try dimension.scan(region: position), caveBiomeIDs: [])
        let coreIndex = DimensionIndex(dimension: dimension.id, caveBiomeIDs: [])
            .updating(available: [position], selected: nil, replacements: [core])
        let counts = try dimension.countBlocks(region: position, matching: ["mod:ore"])
        let index = BlockCountIndex(dimension: dimension.id).updating(available: [position], replacements: [counts])
        let origin = try #require(BlockSearchOrigin(x: 8, z: 8))
        try FileManager.default.removeItem(at: path) // The following regroup queries have no reader input left.
        for name in ["mod:first", "mod:renamed"] {
            let jar = try NotableBlockFixtures.assets([
                NotableBlockFixtures.tag("ores", ["#" + name]), NotableBlockFixtures.tag(name, ["mod:ore"])])
            let catalog = NotableBlock.Catalog(tags: ["minecraft:ores": try #require(jar.tag("ores", in: "block"))])
            #expect(index.coverage(of: position, matching: ["mod:ore"]) == .complete)
            #expect(index.regionsToRead(available: [position], matching: ["mod:ore"], from: origin).isEmpty)
            #expect(index.nearestDeposits(matching: [.tag(name)], using: catalog, from: origin, limit: 200)
                .first?.deposit.count == 1)
        }
        #expect(index.coverage(of: position, matching: ["mod:ore", "mod:new"]) == .unsearched)
        #expect(index.regionsToRead(available: [position], matching: ["mod:ore", "mod:new"], from: origin) == [position])
        #expect(coreIndex.regions[position]?.paletteBlockIDs.contains("mod:ore") == true)
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
        let world = try world(root, packs: [])
        let chunk = Fixtures.chunk(x: 0, z: 0, sections: sections)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]),
            to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        let dimension = try #require(world.dimension("overworld"))
        let ids = Set(try Chunk(nbt: chunk).sections.flatMap { $0.blockStates?.palette.map(\.id) ?? [] })
        let facts = try dimension.countBlocks(region: .init(x: 0, z: 0), matching: ids)
        return facts.chunks[.init(x: 0, z: 0)] ?? []
    }
}
