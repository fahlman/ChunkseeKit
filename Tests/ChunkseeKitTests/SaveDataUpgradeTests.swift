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

    @Test(arguments: GeneratedSaveRenameProofs.entitySamples)
    func matchesMinecraftEntityNamesAcrossEverySchemaInterval(_ sample: GeneratedSaveRenameProofs.EntitySample) {
        for version in sample.versions {
            let entity = NBT.compound([
                "id": .string(sample.input), "x": .int(1), "y": .int(64), "z": .int(2),
                "Pos": .list([.double(1), .double(64), .double(2)]),
                "Items": .list([item("example:unchanged")]),
            ])
            let chunk = NBT.compound(["DataVersion": .int(Int32(version)),
                                      "block_entities": .list([entity]), "Entities": .list([entity])])
            let entries = sample.kind == "entity" ? ItemContainer.containers(inEntityChunk: chunk)
                : ItemContainer.containers(inChunk: chunk)
            #expect(entries.first?.kind == sample.expected, "Saved version \(version)")
            #expect(entries.first?.items.first?.id == "example:unchanged")
        }
    }

    @Test func entityAliasesPreserveUnknownAndInapplicableNames() throws {
        func mob(_ id: String) -> NBT {
            Fixtures.mob(["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)])])
        }
        #expect(Creature(mob("zombie_pigman"), dataVersion: 2508)?.id == "minecraft:zombified_piglin")
        #expect(Creature(mob("minecraft:zombie_pigman"), dataVersion: nil)?.id == "minecraft:zombie_pigman")
        #expect(Creature(mob("example:zombie_pigman"), dataVersion: 2508)?.id == "example:zombie_pigman")
        #expect(Creature(mob("minecraft:new_mob"), dataVersion: 2508)?.id == "minecraft:new_mob")
        for version in [2509, 5023, Int.max] {
            #expect(Creature(mob("minecraft:zombie_pigman"), dataVersion: version)?.id == "minecraft:zombie_pigman")
        }
        let id = NBT.string("minecraft:zombie_pigman")
        let egg = item("example:egg", extra: ["tag": .compound([
            "EntityTag": .compound(["id": id, "CustomName": id, "custom": .compound(["id": id])]),
        ])])
        let result = try #require(ItemStack(egg, dataVersion: 2508))
        #expect(result.components?["EntityTag"]?["id"] == .string("minecraft:zombified_piglin"))
        #expect(result.components?["EntityTag"]?["CustomName"] == id)
        #expect(result.components?["EntityTag"]?["custom"]?["id"] == id)
        #expect(egg["tag"]?["EntityTag"]?["id"] == id)
    }

    @Test func attributeRulesPreserveUnknownFactsAndModifierIdentity() throws {
        let modifier = NBT.compound([
            "type": .string("generic.nameplate_distance"), "id": .string("minecraft:generic.keep_this_modifier"),
            "amount": .double(3), "operation": .string("add_value"),
            "custom": .compound(["type": .string("generic.nameplate_distance")]),
        ])
        let stack = item("example:wand", extra: ["components": .compound([
            "minecraft:attribute_modifiers": .compound(["modifiers": .list([modifier])]),
        ])])
        let interpreted = try #require(ItemStack(stack, dataVersion: 4054))
        let result = try #require(interpreted.components?["minecraft:attribute_modifiers"]?["modifiers"]?[0])
        #expect(result["type"] == .string("minecraft:name_tag_distance"))
        #expect(result["id"] == modifier["id"] && result["amount"] == modifier["amount"])
        #expect(result["custom"] == modifier["custom"])
        #expect(stack["components"]?["minecraft:attribute_modifiers"]?["modifiers"]?[0] == modifier)
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "DataVersion": .int(4054), "attributes": .list([
                .compound(["id": .string("example:generic.custom"), "base": .double(7)]),
                .compound(["id": .string("minecraft:generic.custom"), "base": .double(8)]),
                .compound(["id": .int(99), "base": .double(9)]),
            ]),
        ]))
        #expect(player.nbt["attributes"]?[0]?["id"] == .string("example:generic.custom"))
        #expect(player.nbt["attributes"]?[1]?["id"] == .string("minecraft:custom"))
        #expect(player.nbt["attributes"]?[2]?["id"] == .int(99))
        let old = NBT.compound(["Attributes": .list([.compound(["Name": .string("Max Health"), "Base": .double(30)])])])
        #expect(PlayerInfo(uuid: UUID(), nbt: old).nbt["Attributes"]?[0]?["Name"] == .string("minecraft:max_health"))
        #expect(SaveDataUpgrade.player(old, dataVersion: Int.max) == old)
    }

    @Test func nestedEquippedEnchantmentNamesUseTheirContainingVersion() throws {
        let sword = item("minecraft:diamond_sword", extra: ["tag": .compound([
            "Enchantments": .list([.compound(["id": .string("minecraft:sweeping"), "lvl": .short(2)])]),
            "AttributeModifiers": .list([.compound([
                "AttributeName": .string("minecraft:horse.jump_strength"),
                "Name": .string("minecraft:horse.jump_strength"), "Amount": .double(0.5),
            ])]),
        ])])
        let mob = Fixtures.mob([
            "id": .string("example:mob"), "Pos": .list([.double(0), .double(64), .double(0)]),
            "HandItems": .list([sword]),
        ])
        let creature = try #require(Creature(mob, dataVersion: 3802))
        let equipped = try #require(creature.equipment?["mainhand"])
        #expect(equipped.enchantments == ["minecraft:sweeping_edge": 2])
        let modifier = try #require(equipped.components?["AttributeModifiers"]?[0])
        #expect(modifier["AttributeName"] == .string("minecraft:jump_strength"))
        #expect(modifier["Name"] == .string("minecraft:horse.jump_strength"))
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "DataVersion": .int(3802), "Inventory": .list([sword]), "ShoulderEntityLeft": mob,
        ]))
        #expect(player.inventory.first?.enchantments == equipped.enchantments)
        #expect(player.shoulderPets.first?.equipment?["mainhand"]?.enchantments == equipped.enchantments)
        #expect(mob["HandItems"]?[0]?["tag"]?["Enchantments"]?[0]?["id"] == .string("minecraft:sweeping"))
    }

    @Test func playerProgressPreservesLiteralKeysUnknownFactsAndCollisions() throws {
        let advancements = Data(#"""
        {"DataVersion":1500,
         "recipes/brewing/speckled_melon":{"done":true},
         "minecraft:recipes/brewing/speckled_melon":{"done":false},
         "example:recipes/brewing/speckled_melon":{"done":true}}
        """#.utf8)
        let progress = try AdvancementProgress.list(json: advancements)
        #expect(Set(progress.map(\.id)) == ["recipes/brewing/speckled_melon",
                                            "minecraft:recipes/brewing/glistering_melon_slice",
                                            "example:recipes/brewing/speckled_melon"])
        #expect(progress.first { $0.id == "minecraft:recipes/brewing/glistering_melon_slice" }?.isDone == false)
        let collision = Data(#"""
        {"DataVersion":2099,"minecraft:recipes/misc/sugar":{"done":true},
         "minecraft:recipes/misc/sugar_from_sugar_cane":{"done":false}}
        """#.utf8)
        #expect(try AdvancementProgress.list(json: collision).map(\.id)
                == ["minecraft:recipes/misc/sugar", "minecraft:recipes/misc/sugar_from_sugar_cane"])
        let stats = try PlayerStatistics(json: Data(#"""
        {"DataVersion":2709,"stats":{"minecraft:custom":{
          "minecraft:play_one_minute":17,"minecraft:play_time":23},
          "example:custom":{"minecraft:play_one_minute":41}}}
        """#.utf8))
        #expect(stats.values["minecraft:custom"] == ["minecraft:play_one_minute": 17, "minecraft:play_time": 23])
        #expect(stats.values["example:custom"] == ["minecraft:play_one_minute": 41])
        let recipe = NBT.string("minecraft:sugar")
        let book = NBT.compound(["recipes": .list([recipe, recipe, .string("example:new_recipe")]),
                                 "toBeDisplayed": .list([recipe]), "custom": recipe])
        let input = NBT.compound(["DataVersion": .int(2099), "recipeBook": book, "custom": book])
        let player = PlayerInfo(uuid: UUID(), nbt: input)
        #expect(player.nbt["recipeBook"]?["recipes"] == .list([
            .string("minecraft:sugar_from_sugar_cane"), .string("minecraft:sugar_from_sugar_cane"), .string("example:new_recipe"),
        ]))
        #expect(player.nbt["recipeBook"]?["custom"] == recipe && player.nbt["custom"] == book)
        #expect(input["recipeBook"] == book)
        #expect(SaveDataUpgrade.player(input, dataVersion: Int.max) == input)
        #expect(SaveDataUpgrade.statistics(stats.values, dataVersion: Int.max) == stats.values)
    }

    @Test func playerProgressFileReadsKeepEveryOriginalByte() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let uuid = UUID()
        let levelURL = root.appendingPathComponent("level.dat")
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(5023)])]), to: levelURL)
        let statsURL = root.appendingPathComponent("players/stats/\(uuid.uuidString.lowercased()).json")
        let progressURL = root.appendingPathComponent("players/advancements/\(uuid.uuidString.lowercased()).json")
        let statistics = Data(#"{"DataVersion":2709,"stats":{"minecraft:custom":{"minecraft:play_one_minute":17}}}"#.utf8)
        let advancements = Data(#"{"DataVersion":2099,"minecraft:recipes/misc/sugar":{"done":true,"criteria":{"proof":"2020-01-01 00:00:00 +0000"}}}"#.utf8)
        for (url, data) in [(statsURL, statistics), (progressURL, advancements)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let before = try [Data(contentsOf: levelURL), Data(contentsOf: statsURL), Data(contentsOf: progressURL)]
        let world = try World(contentsOf: root)
        let stats = try #require(world.statistics(for: uuid))
        #expect(stats.dataVersion == 2709 && stats.values["minecraft:custom"] == ["minecraft:play_time": 17])
        let progress = try #require(world.advancements(for: uuid)?.first)
        #expect(progress.id == "minecraft:recipes/misc/sugar_from_sugar_cane" && progress.isDone)
        #expect(progress.completed == ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z"))
        #expect(try before == [Data(contentsOf: levelURL), Data(contentsOf: statsURL), Data(contentsOf: progressURL)])
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
        func upgradedJSON() throws -> Data {
            var fields = try #require(JSONSerialization.jsonObject(with: Data(record.output.utf8)) as? [String: Any])
            fields["DataVersion"] = Int.max
            return try JSONSerialization.data(withJSONObject: fields)
        }
        switch record.kind {
        case "recipeProgress":
            let actual = PlayerInfo(uuid: UUID(), nbt: input).nbt
            func identifiers(_ nbt: NBT?) -> [String] {
                (nbt?.list ?? []).compactMap(\.string).map { Identifier($0)?.description ?? $0 }
            }
            for field in ["recipes", "toBeDisplayed"] {
                #expect(identifiers(actual["recipeBook"]?[field]) == identifiers(output["recipeBook"]?[field]))
                #expect(actual["recipeBook"]?[field]?.list?.count == 1)
            }
        case "statProgress":
            let actual = try PlayerStatistics(json: Data(record.input.utf8))
            let expected = try PlayerStatistics(json: upgradedJSON())
            func identifiers(_ values: [String: [String: Int]]) -> [String: [String: Int]] {
                values.mapValues { Dictionary(uniqueKeysWithValues: $0.map { (Identifier($0.key)?.description ?? $0.key, $0.value) }) }
            }
            #expect(identifiers(actual.values) == identifiers(expected.values))
            #expect(actual.dataVersion == record.version)
        case "advancementProgress":
            #expect(try AdvancementProgress.list(json: Data(record.input.utf8))
                    == AdvancementProgress.list(json: upgradedJSON()))
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
        case "entityNames":
            func creatures(_ nbt: NBT, version: Int) -> [Creature] {
                Creature.creatures(inEntityChunk: .compound([
                    "DataVersion": .int(Int32(version)), "Entities": .list([nbt]),
                ]))
            }
            let actual = creatures(input, version: record.version)
            let expected = creatures(output, version: Int(Int32.max))
            #expect(actual.count == 2 && actual.map(\.id) == expected.map(\.id))
            #expect(actual.map(\.x) == expected.map(\.x) && actual.map(\.z) == expected.map(\.z))
        case "entityPlayer":
            let uuid = UUID()
            let actual = PlayerInfo(uuid: uuid, nbt: input)
            var fields = try #require(output.compound); fields["DataVersion"] = .int(Int32.max)
            let expected = PlayerInfo(uuid: uuid, nbt: .compound(fields))
            #expect(actual.shoulderPets.count == 1 && actual.shoulderPets.map(\.id) == expected.shoulderPets.map(\.id))
            #expect(actual.rootVehicleCreatures.count == 2 && actual.rootVehicleCreatures.map(\.id) == expected.rootVehicleCreatures.map(\.id))
        case "entityItem":
            let actual = try #require(ItemStack(input, dataVersion: record.version))
            let expected = try #require(ItemStack(output))
            #expect(actual.components?["EntityTag"]?["id"] == expected.components?["minecraft:entity_data"]?["id"])
        case "attributePlayer":
            let actual = PlayerInfo(uuid: UUID(), nbt: input).nbt
            func attributes(_ value: NBT) -> [NBT] { (value["attributes"] ?? value["Attributes"])?.list ?? [] }
            func names(_ values: [NBT]) -> [String] { values.compactMap { ($0["id"] ?? $0["Name"])?.string } }
            #expect(names(attributes(actual)) == names(attributes(output)))
            #expect(attributes(actual).count == 1)
            #expect((attributes(actual)[0]["base"] ?? attributes(actual)[0]["Base"])?.double == 9.5)
        case "attributeItem":
            func modifiers(_ stack: ItemStack) -> [NBT] {
                let current = stack.components?["minecraft:attribute_modifiers"]
                return current?.list ?? current?["modifiers"]?.list ?? stack.components?["AttributeModifiers"]?.list ?? []
            }
            func names(_ values: [NBT]) -> [String] { values.compactMap { ($0["type"] ?? $0["AttributeName"])?.string } }
            let actual = modifiers(try #require(ItemStack(input, dataVersion: record.version)))
            let expected = modifiers(try #require(ItemStack(output)))
            #expect(actual.count == 1 && names(actual) == names(expected))
            #expect((actual[0]["amount"] ?? actual[0]["Amount"])?.double == 0.5)
        case "enchantmentItem":
            let actual = try #require(ItemStack(input, dataVersion: record.version))
            // Compare identities with the game's raw fix output across its layout conversion.
            // Keep an omitted namespace intact when that boundary does not rename the ID.
            var expected: [String: Int] = [:]
            for key in ["minecraft:enchantments", "minecraft:stored_enchantments"] {
                for (id, level) in output["components"]?[key]?.compound ?? [:] {
                    if let value = level.int { expected[id] = value }
                }
            }
            for key in ["Enchantments", "StoredEnchantments"] {
                for entry in output["tag"]?[key]?.list ?? [] {
                    if let id = entry["id"]?.string, let level = entry["lvl"]?.int { expected[id] = level }
                }
            }
            #expect(expected.count == 1 && actual.enchantments == expected)
        case "beehiveNames":
            let actual = SaveDataUpgrade.blockEntity(input, dataVersion: record.version)
            #expect(actual["Bees"]?[0]?["EntityData"]?["id"] == output["bees"]?[0]?["entity_data"]?["id"])
            #expect(actual["Bees"]?[0]?["EntityData"]?["id"] != nil)
        case "spawnerNames", "blockEntityNames":
            func chunk(_ entity: NBT, version: Int) -> NBT {
                .compound(["DataVersion": .int(Int32(version)), "block_entities": .list([entity])])
            }
            let actual = chunk(input, version: record.version)
            let expected = chunk(output, version: Int(Int32.max))
            if record.kind == "spawnerNames" {
                #expect(Spawner.spawners(inChunk: actual) == Spawner.spawners(inChunk: expected))
                #expect(Spawner.spawners(inChunk: actual).count == 1)
                #expect(SaveDataUpgrade.blockEntities(inChunk: actual).first?["SpawnPotentials"]?[0]?["Entity"]?["id"]
                    == output["SpawnPotentials"]?[0]?["data"]?["entity"]?["id"])
            } else {
                #expect(ItemContainer.containers(inChunk: actual) == ItemContainer.containers(inChunk: expected))
                #expect(ItemContainer.containers(inChunk: actual).count == 1)
            }
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

    @Test func regionEntityIdentitiesUseEachFilesVersionWithoutWriting() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root), region = RegionPosition(x: 0, z: 0)
        var terrain = try #require(chunk(version: 3437).compound)
        terrain["block_entities"] = .list([.compound([
            "id": .string("minecraft:suspicious_sand"), "x": .int(0), "y": .int(64), "z": .int(0),
            "LootTable": .string("example:loot"),
        ])])
        let uuid = UUID()
        let mob = Fixtures.mob([
            "id": .string("minecraft:zombie_pigman"), "UUID": Fixtures.uuidInts(uuid),
            "Pos": .list([.double(1), .double(64), .double(2)]),
        ])
        let entities = NBT.compound(["DataVersion": .int(2508), "Entities": .list([mob])])
        let terrainURL = dimension.regionURL(.terrain, at: region), entityURL = dimension.regionURL(.entities, at: region)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound(terrain))]), to: terrainURL)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: entities)]), to: entityURL)
        let before = try [Data(contentsOf: terrainURL), Data(contentsOf: entityURL)]
        let facts = try dimension.scan(region: region)
        #expect(facts.containers.count == 1 && facts.containers.first?.kind == "minecraft:brushable_block")
        #expect(facts.containers.first?.lootTable == "example:loot")
        #expect(facts.creatures.count == 1 && facts.creatures.first?.id == "minecraft:zombified_piglin")
        #expect(facts.creatures.first?.uuid == uuid)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == facts.creatures)
        #expect(try dimension.containers(regionX: 0, regionZ: 0) == facts.containers)
        #expect(try RegionFile(contentsOf: entityURL).chunkNBT(localX: 0, localZ: 0) == entities)
        #expect(try before == [Data(contentsOf: terrainURL), Data(contentsOf: entityURL)])
    }
}
