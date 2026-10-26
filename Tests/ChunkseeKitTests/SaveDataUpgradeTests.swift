import Foundation
import CoreFoundation
import Testing
import ChunkseeKitTestSupport
@testable import ChunkseeKit

@Suite struct SaveDataUpgradeTests {
    private func item(_ id: String, extra: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string(id), "Count": .byte(1)].merging(extra) { _, new in new })
    }

    private func chunk(version: Int, block: String = "minecraft:stone", biome: String = "minecraft:plains") -> NBT {
        Fixtures.chunk(x: 0, z: 0, dataVersion: version, sections: [
            Fixtures.section(y: 4, palette: [.compound(["Name": .string(block)])], biomes: [biome]),
        ], extra: ["Status": .string("minecraft:full")])
    }

    @Test(arguments: GeneratedSaveRenameProofs.samples)
    func matchesMinecraftFullFixChain(_ sample: GeneratedSaveRenameProofs.Sample) throws {
        let actual: String?
        switch sample.kind {
        case "block": actual = try Chunk(nbt: chunk(version: sample.version, block: sample.input)).block(x: 0, y: 64, z: 0)?.id
        case "biome": actual = try Chunk(nbt: chunk(version: sample.version, biome: sample.input)).biome(x: 0, y: 64, z: 0)
        case "item": actual = ItemStack(item(sample.input), dataVersion: sample.version)?.id
        default: Issue.record("Unexpected generated proof kind"); return
        }
        #expect(actual == sample.expected)
    }

    @Test func simultaneousAndLaterRenamesAreDistinct() throws {
        // One step renames melon_block -> melon and melon -> melon_slice. It must run once.
        #expect(ItemStack(item("minecraft:melon_block"), dataVersion: 1489)?.id == "minecraft:melon")
        #expect(ItemStack(item("minecraft:melon"), dataVersion: 1489)?.id == "minecraft:melon_slice")
        // Two different steps rename this shard in sequence.
        #expect(ItemStack(item("minecraft:pottery_shard_archer"), dataVersion: 3437)?.id == "minecraft:archer_pottery_sherd")
        #expect(ItemStack(item("minecraft:pottery_shard_archer"), dataVersion: 3438)?.id == "minecraft:pottery_shard_archer")
    }

    @Test(arguments: GeneratedSaveRenameProofs.legacyItems)
    func matchesMinecraftLegacyNamedItemIdentity(_ sample: GeneratedSaveRenameProofs.LegacyItem) {
        let input = item(sample.input, extra: ["Damage": .int(Int32(sample.damage))])
        #expect(ItemStack(input, dataVersion: sample.version)?.id == sample.expected)
    }

    @Test func legacyNamesPrecedeLaterAliasesAndRespectDamageVariants() {
        #expect(ItemStack(item("minecraft:grass"), dataVersion: nil)?.id == "minecraft:grass_block")
        #expect(ItemStack(item("minecraft:grass"), dataVersion: 2865)?.id == "minecraft:short_grass")
        #expect(ItemStack(item("minecraft:stone", extra: ["Damage": .short(1)]), dataVersion: 1343)?.id == "minecraft:granite")
        #expect(ItemStack(item("minecraft:stone", extra: ["Damage": .short(99)]), dataVersion: 1343)?.id == "minecraft:stone")
        #expect(ItemStack(item("minecraft:bed"), dataVersion: nil)?.id == "minecraft:red_bed")
        #expect(ItemStack(item("minecraft:bed"), dataVersion: 1125)?.id == "minecraft:white_bed")
        #expect(ItemStack(item("minecraft:stone", extra: ["Damage": .double(1.9)]), dataVersion: 1343)?.id == "minecraft:granite")
        #expect(ItemStack(item("minecraft:stone", extra: ["Damage": .long(4_294_967_297)]), dataVersion: 1343)?.id == "minecraft:granite")
        #expect(ItemStack(item("minecraft:stone", extra: ["Damage": .double(.nan)]), dataVersion: 1343)?.id == "minecraft:stone")
    }

    @Test func missingFutureAndCurrentVersionsKeepTheirMeaning() throws {
        var fields = try #require(chunk(version: 3691, block: "minecraft:grass").compound)
        fields["DataVersion"] = nil
        let missing = try Chunk(nbt: .compound(fields))
        #expect(missing.dataVersion == nil && missing.block(x: 0, y: 64, z: 0)?.id == "minecraft:short_grass")
        for version in [3692, 5023, Int(Int32.max)] {
            let result = try Chunk(nbt: chunk(version: version, block: "minecraft:grass"))
            #expect(result.block(x: 0, y: 64, z: 0)?.id == "minecraft:grass")
            #expect(result.dataVersion == version)
        }
        #expect(ItemStack(item("minecraft:chain"), dataVersion: nil)?.id == "minecraft:iron_chain")
    }

    @Test func unrelatedNamesMalformedFieldsAndStatePropertiesArePreserved() throws {
        let custom = item("example:grass", extra: ["tag": .compound([
            "display": .compound(["Name": .string("minecraft:grass")]),
            "custom": .compound(["id": .string("minecraft:grass"), "Items": .list([item("minecraft:grass")])]),
        ])])
        let unchanged = try #require(ItemStack(custom, dataVersion: 3691))
        #expect(unchanged.id == "example:grass" && unchanged.customName == "minecraft:grass")
        #expect(unchanged.components?["custom"]?["id"] == .string("minecraft:grass"))
        #expect(unchanged.components?["custom"]?["Items"]?[0]?["id"] == .string("minecraft:grass"))
        let malformed = item("minecraft:grass", extra: ["components": .string("not a compound")])
        #expect(ItemStack(malformed, dataVersion: 3691)?.components == .string("not a compound"))
        let state = NBT.compound(["Name": .string("minecraft:chain"), "Properties": .compound([
            "axis": .string("z"), "custom": .string("minecraft:chain")])])
        let saved = Fixtures.chunk(x: 0, z: 0, dataVersion: 4540, sections: [Fixtures.section(y: 4, palette: [state])])
        let block = try #require(Chunk(nbt: saved).block(x: 0, y: 64, z: 0))
        #expect(block.id == "minecraft:iron_chain")
        #expect(block.properties == ["axis": "z", "custom": "minecraft:chain"])
    }

    @Test func itemNamespaceAndStateNameFollowTheirDifferentGameCodecs() throws {
        #expect(ItemStack(item("grass"), dataVersion: 3691)?.id == "minecraft:short_grass")
        let saved = Fixtures.chunk(x: 0, z: 0, dataVersion: 3691, sections: [Fixtures.section(y: 4,
            palette: [.compound(["Name": .string("grass")])])])
        #expect(try Chunk(nbt: saved).block(x: 0, y: 64, z: 0)?.id == "grass")
    }

    @Test func nestedLegacyAndComponentInventoriesUpgradeOnce() throws {
        let legacy = item("minecraft:chest", extra: ["tag": .compound(["BlockEntityTag": .compound([
            "Items": .list([item("minecraft:melon_block"), item("minecraft:melon")]),
        ])])])
        let bundle = item("minecraft:bundle", extra: ["components": .compound([
            "minecraft:bundle_contents": .list([legacy]),
        ])])
        let outer = item("minecraft:shulker_box", extra: ["components": .compound([
            "minecraft:container": .list([.compound(["slot": .int(7), "item": bundle])]),
        ])])
        let value = try #require(ItemStack(outer, dataVersion: 1489))
        #expect(value.contents.first?.slot == 7)
        #expect(value.allItems.map(\.id) == ["minecraft:shulker_box", "minecraft:bundle", "minecraft:chest", "minecraft:melon", "minecraft:melon_slice"])
        #expect(outer["components"]?["minecraft:container"]?[0]?["item"] == bundle)
    }

    @Test func nestedPlayerCreaturesReceiveExactlyOneUpgrade() {
        let mob = Fixtures.mob([
            "id": .string("example:carrier"), "Pos": .list([.double(1), .double(64), .double(2)]),
            "HandItems": .list([item("minecraft:melon_block")]),
        ])
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "DataVersion": .int(1489), "ShoulderEntityLeft": mob,
            "RootVehicle": .compound(["Entity": .compound(["id": .string("minecraft:boat"), "Passengers": .list([mob])])]),
        ]))
        #expect(player.shoulderPets.first?.equipment?["mainhand"]?.id == "minecraft:melon")
        #expect(player.rootVehicleCreatures.first?.equipment?["mainhand"]?.id == "minecraft:melon")
    }

    @Test func potDecorationsAndTradesKeepTheirNamesInTheSameContext() throws {
        let pot = item("minecraft:decorated_pot", extra: ["tag": .compound(["BlockEntityTag": .compound([
            "sherds": .list([.string("minecraft:pottery_shard_archer")]),
        ])])])
        let interpreted = try #require(ItemStack(pot, dataVersion: 3437))
        #expect(interpreted.potDecorations?.back?.itemID.description == "minecraft:archer_pottery_sherd")
        let mob = Fixtures.mob([
            "id": .string("minecraft:villager"), "Pos": .list([.double(0), .double(64), .double(0)]),
            "Offers": .compound(["Recipes": .list([.compound([
                "buy": item("minecraft:scute"), "sell": item("minecraft:grass"),
            ])])]),
        ])
        let creature = try #require(Creature(mob, dataVersion: 3691))
        #expect(creature.villager?.trades.first?.buy.id == "minecraft:turtle_scute")
        #expect(creature.villager?.trades.first?.sell.id == "minecraft:short_grass")
    }

    @Test(arguments: [true, false]) func playerFileAndEmbeddedPlayerUseTheirOwnSavedVersion(hasEmbeddedVersion: Bool) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let embeddedID = UUID(), fileID = UUID()
        let levelURL = root.appendingPathComponent("level.dat")
        let playerURL = root.appendingPathComponent("playerdata/\(fileID.uuidString.lowercased()).dat")
        var embeddedFields: [String: NBT] = [
            "UUID": Fixtures.uuidInts(embeddedID), "Inventory": .list([item("minecraft:chain")]),
        ]
        if hasEmbeddedVersion { embeddedFields["DataVersion"] = .int(4540) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(4541), "Player": .compound(embeddedFields),
        ])]), to: levelURL)
        try Fixtures.writeGzippedNBT(.compound([
            "DataVersion": .int(3437), "Inventory": .list([item("minecraft:pottery_shard_archer")]),
            "EnderItems": .list([item("minecraft:scute")]),
        ]), to: playerURL)
        let before = try [Data(contentsOf: levelURL), Data(contentsOf: playerURL)]
        let world = try World(contentsOf: root)
        let players = world.players()
        let embedded = try #require(players.first { $0.uuid == embeddedID })
        let file = try #require(players.first { $0.uuid == fileID })
        #expect(embedded.dataVersion == (hasEmbeddedVersion ? 4540 : nil))
        #expect(embedded.inventory.first?.id == "minecraft:iron_chain")
        #expect(file.dataVersion == 3437 && file.inventory.first?.id == "minecraft:archer_pottery_sherd")
        #expect(file.enderChest.first?.id == "minecraft:turtle_scute")
        #expect(try world.playerData(fileID)?["Inventory"]?[0]?["id"] == .string("minecraft:pottery_shard_archer"))
        #expect(try before == [Data(contentsOf: levelURL), Data(contentsOf: playerURL)])
    }

    @Test(arguments: GeneratedSaveRenameProofs.records)
    func matchesNamesFromMinecraftWholeRecordUpgrades(_ record: GeneratedSaveRenameProofs.Record) throws {
        let input = try jsonNBT(record.input), output = try jsonNBT(record.output)
        func ids(_ items: [ItemStack]) -> [String] { items.flatMap(\.allItems).map(\.id) }
        func counts(_ items: [ItemStack]) -> [Int] { items.flatMap(\.allItems).map(\.count) }
        switch record.kind {
        case "item":
            let actual = try #require(ItemStack(input, dataVersion: record.version))
            let expected = try #require(ItemStack(output))
            #expect(ids([actual]) == ids([expected]) && counts([actual]) == counts([expected]))
        case "entity":
            let actual = try #require(Creature(input, dataVersion: record.version))
            // Minecraft leaves DataVersion unchanged in its dynamic result; its caller writes
            // the current version on save. Read that expected result as already upgraded.
            let expected = try #require(Creature(output, dataVersion: Int.max))
            #expect(actual.equipment?["mainhand"]?.id == expected.equipment?["mainhand"]?.id)
        case "player":
            let actual = PlayerInfo(uuid: UUID(), nbt: input)
            var fields = try #require(output.compound); fields["DataVersion"] = .int(Int32.max)
            let expected = PlayerInfo(uuid: UUID(), nbt: .compound(fields))
            #expect(ids(actual.inventory) == ids(expected.inventory) && counts(actual.inventory) == counts(expected.inventory))
            #expect(ids(actual.enderChest) == ids(expected.enderChest))
        case "chunk":
            let actual = try Chunk(nbt: input)
            var fields = try #require(output.compound); fields["DataVersion"] = .int(Int32.max)
            let expected = try Chunk(nbt: .compound(fields))
            #expect(actual.block(x: 0, y: 64, z: 0) == expected.block(x: 0, y: 64, z: 0))
            #expect(actual.biome(x: 0, y: 64, z: 0) == expected.biome(x: 0, y: 64, z: 0))
            #expect(ItemContainer.containers(inChunk: input).flatMap(\.items).map(\.id)
                    == ItemContainer.containers(inChunk: .compound(fields)).flatMap(\.items).map(\.id))
        case "level":
            let root = try Fixtures.tempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            var fields = try #require(input.compound), player = try #require(input["Player"]?.compound)
            player["UUID"] = Fixtures.uuidInts(UUID()); fields["Player"] = .compound(player)
            try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
            let actual = try #require(World(contentsOf: root).players().first)
            var expectedFields = try #require(output["Player"]?.compound); expectedFields["DataVersion"] = .int(Int32.max)
            let expected = PlayerInfo(uuid: UUID(), nbt: .compound(expectedFields))
            #expect(ids(actual.inventory) == ids(expected.inventory) && counts(actual.inventory) == counts(expected.inventory))
            #expect(ids(actual.enderChest) == ids(expected.enderChest))
        default: Issue.record("Unexpected generated record kind")
        }
    }

    private func jsonNBT(_ text: String) throws -> NBT {
        func convert(_ object: Any) -> NBT {
            if let string = object as? String { return .string(string) }
            if let number = object as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return .byte(number.boolValue ? 1 : 0) }
                if String(cString: number.objCType) == "d" { return .double(number.doubleValue) }
                return .long(number.int64Value)
            }
            if let list = object as? [Any] { return .list(list.map(convert)) }
            return .compound((object as! [String: Any]).mapValues(convert))
        }
        return convert(try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }

    @Test func publicRegionReadersShareTheSameUpgradeAndLeaveTheFilesAlone() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let region = RegionPosition(x: 0, z: 0)
        var terrain = try #require(chunk(version: 3691, block: "minecraft:grass", biome: "minecraft:deep_warm_ocean").compound)
        terrain["block_entities"] = .list([.compound([
            "id": .string("minecraft:chest"), "x": .int(0), "y": .int(64), "z": .int(0),
            "Items": .list([item("minecraft:grass")]),
        ])])
        let passenger = Fixtures.mob([
            "id": .string("example:carrier"), "Pos": .list([.double(1), .double(64), .double(2)]),
            "equipment": .compound(["mainhand": item("minecraft:grass")]),
        ])
        let entities = NBT.compound(["DataVersion": .int(3691), "Entities": .list([
            .compound(["id": .string("minecraft:boat"), "Passengers": .list([passenger])]),
        ])])
        for (folder, nbt) in [(Dimension.Folder.terrain, NBT.compound(terrain)), (.entities, entities)] {
            try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]), to: dimension.regionURL(folder, at: region))
        }
        let terrainURL = dimension.regionURL(.terrain, at: region)
        let entityURL = dimension.regionURL(.entities, at: region)
        let before = try [Data(contentsOf: terrainURL), Data(contentsOf: entityURL)]
        let facts = try dimension.scan(region: region)
        #expect(facts.paletteBlockIDs == ["minecraft:short_grass"])
        #expect(facts.chunks.first?.blockDeposits.first?.id == "minecraft:short_grass")
        #expect(facts.chunks.first?.biomes == ["minecraft:deep_warm_ocean"]) // The earlier biome step is already past.
        #expect(facts.containers.count == 2 && facts.containers.allSatisfy { $0.items.first?.id == "minecraft:short_grass" })
        #expect(facts.creatures.first?.equipment?["mainhand"]?.id == "minecraft:short_grass")
        #expect(try dimension.block(x: 0, y: 64, z: 0)?.id == "minecraft:short_grass")
        #expect(try dimension.containers(regionX: 0, regionZ: 0) == facts.containers)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == facts.creatures)
        #expect(try RegionFile(contentsOf: terrainURL).chunkNBT(localX: 0, localZ: 0) == .compound(terrain))
        #expect(try before == [Data(contentsOf: terrainURL), Data(contentsOf: entityURL)])
    }

    @Test func deeplyNestedUpgradeUsesAnExplicitTraversalStack() {
        var value = item("minecraft:chain")
        for _ in 0..<150 {
            value = item("minecraft:bundle", extra: ["components": .compound(["minecraft:bundle_contents": .list([value])])])
        }
        var upgraded = SaveDataUpgrade.item(value, dataVersion: 4540)
        for _ in 0..<150 { upgraded = upgraded["components"]!["minecraft:bundle_contents"]![0]! }
        #expect(upgraded["id"] == .string("minecraft:iron_chain"))
    }
}
