import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct EnchantmentDefinitionTests {
    private let neutral = #"{"slots":["any"],"effects":{"minecraft:damage":[{"effect":{"type":"minecraft:add","value":1}}]}}"#
    private let health = #"{"slots":["head"],"effects":{"minecraft:attributes":[{"id":"example:health","attribute":"minecraft:max_health","amount":4,"operation":"add_value"}]}}"#
    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Fixture"}}"#

    private func assets(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"future","world_version":999999}"#),
        ] + entries))))
    }

    private func entry(_ id: String, _ text: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":", maxSplits: 1)
        return .init(path: "data/\(parts[0])/enchantment/\(parts[1]).json", text: text)
    }

    private func write(_ text: String, at path: String, under root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func world(_ root: URL, packs: [String]) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(5023), "DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))]),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        return try World(contentsOf: root)
    }

    private func saved(_ enchantment: String) -> NBT {
        Fixtures.mob(["id": .string("minecraft:zombie"), "DataVersion": .int(5023),
            "Pos": .list([.double(1), .double(64), .double(2)]), "Health": .float(17),
            "attributes": .list([.compound(["id": .string("minecraft:max_health"), "base": .double(20)])]),
            "equipment": .compound(["head": .compound(["id": .string("minecraft:iron_helmet"), "count": .int(1),
                "components": .compound(["minecraft:enchantments": .compound([enchantment: .int(1)])])])])])
    }

    @Test func directAndNestedAttributesAreDistinguishedFromUnrelatedEffects() throws {
        func read(_ text: String) throws -> EnchantmentDefinition { try #require(EnchantmentDefinition(data: Data(text.utf8))) }
        #expect(try read(neutral).hasMaximumHealthModifier == false)
        #expect(try read(health).hasMaximumHealthModifier == true)
        let conditional = #"{"effects":{"minecraft:location_changed":[{"effect":{"type":"minecraft:all_of","effects":[{"type":"minecraft:attribute","attribute":"max_health"}]},"requirements":{"condition":"example:unknown"}}]}}"#
        #expect(try read(conditional).hasMaximumHealthModifier == true)
        let movement = conditional.replacingOccurrences(of: "max_health", with: "movement_speed")
        #expect(try read(movement).hasMaximumHealthModifier == false)
        #expect(try read(#"{"effects":{"minecraft:damage":[{"effect":{"type":"minecraft:add","value":1},"requirements":{"attribute":"minecraft:max_health"}}]}}"#).hasMaximumHealthModifier == false)
        #expect(try read(#"{"effects":{"minecraft:trident_sound":["minecraft:item.trident.riptide_1",{"sound_id":"minecraft:item.trident.riptide_2"}]}}"#).hasMaximumHealthModifier == false)
        #expect(try read(#"{"description":{"text":"No effects"}}"#).hasMaximumHealthModifier == false)
    }

    @Test func unknownFormatsRemainUnknownWithoutDiscardingAProvenHealthModifier() throws {
        for effects in [#"{"example:future":{}}"#,
                        #"{"minecraft:attributes":[{"attribute":4}]}"#,
                        #"{"minecraft:location_changed":[{"effect":{"type":"example:future"}}]}"#,
                        #"{"minecraft:tick":[{"effect":{"type":"minecraft:run_function","function":"example:health"}}]}"#] {
            let definition = try #require(EnchantmentDefinition(data: Data("{\"effects\":\(effects)}".utf8)))
            #expect(definition.hasMaximumHealthModifier == nil)
        }
        let partial = #"{"effects":{"example:future":{},"minecraft:attributes":[{"attribute":"minecraft:max_health"}]}}"#
        #expect(EnchantmentDefinition(data: Data(partial.utf8))?.hasMaximumHealthModifier == true)
        #expect(EnchantmentDefinition(data: Data("invalid".utf8)) == nil)
    }

    @Test func jarFolderAndZIPDefinitionsRespectPriorityAndInvalidOverrides() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([entry("minecraft:protection", neutral), entry("minecraft:mending", neutral)])
        let original = try reader.enchantmentDefinitions()
        #expect(original.count == 2 && original.values.allSatisfy { $0.hasMaximumHealthModifier == false })
        let pack = root.appendingPathComponent("datapacks/custom")
        try write(metadata, at: "pack.mcmeta", under: pack)
        try write(health, at: "data/minecraft/enchantment/protection.json", under: pack)
        try write(neutral, at: "data/example/enchantment/nested/comfort.json", under: pack)
        let archive = try TestZIP.zip([.init(path: "pack.mcmeta", text: metadata), entry("minecraft:mending", "invalid")])
        try Fixtures.write(archive, to: root.appendingPathComponent("datapacks/high.zip"))
        let current = try world(root, packs: ["vanilla", "file/custom", "file/high.zip"])
        let definitions = try current.enchantmentDefinitions(assets: reader)
        #expect(Set(definitions.keys) == ["minecraft:protection", "example:nested/comfort"])
        #expect(definitions["minecraft:protection"]?.hasMaximumHealthModifier == true)
        #expect(definitions["example:nested/comfort"]?.hasMaximumHealthModifier == false)
        #expect(original["minecraft:protection"]?.hasMaximumHealthModifier == false)
        #expect(try current.enchantmentDefinitions(assets: nil) == definitions)
        let disabled = try world(root, packs: ["vanilla"])
        #expect(try disabled.enchantmentDefinitions(assets: reader) == original)
    }

    @Test func playersAndMobsUseTheSameResourceFactsIncludingSlotApplicability() throws {
        let definitions = try assets([entry("minecraft:protection", neutral), entry("example:comfort", neutral),
            entry("example:health", health), entry("example:boots", health.replacingOccurrences(of: "head", with: "feet")),
            entry("example:future_slot", health.replacingOccurrences(of: "head", with: "future"))]).enchantmentDefinitions()
        for (id, maximum) in [("minecraft:protection", 20.0), ("example:comfort", 20), ("example:health", nil),
                              ("example:missing", nil), ("example:boots", 20), ("example:future_slot", nil)] as [(String, Double?)] {
            let nbt = saved(id)
            let creature = try #require(Creature(nbt, dataVersion: 5023, enchantments: definitions))
            let player = PlayerInfo(uuid: UUID(), nbt: nbt, enchantments: definitions)
            #expect(creature.maxHealth == maximum && player.maxHealth == maximum)
            #expect(creature.health == 17 && player.health == 17)
        }
        #expect(Creature(saved("minecraft:protection"), dataVersion: 5023)?.maxHealth == nil)
        #expect(PlayerInfo(uuid: UUID(), nbt: saved("minecraft:protection")).maxHealth == nil)
    }

    @Test func publicWorldAndRegionPathsCarryTheSnapshotIntoHealthAndCacheIdentity() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try world(root, packs: ["vanilla"])
        let dimension = try #require(current.dimension("overworld"))
        let definitions = try current.enchantmentDefinitions(assets: assets([entry("minecraft:protection", neutral)]))
        let changed = try assets([entry("minecraft:protection", health)]).enchantmentDefinitions()
        let entity = saved("minecraft:protection"), region = RegionPosition(x: 0, z: 0)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound(["Entities": .list([entity])]))]),
                           to: dimension.regionURL(.entities, at: region))
        let options = RegionScanOptions(enchantments: definitions)
        let facts = try dimension.scan(region: region, options: options)
        #expect(facts.creatures.first?.maxHealth == 20)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0, enchantments: definitions) == facts.creatures)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0, enchantments: definitions) == facts.creatures)
        #expect(options != RegionScanOptions(enchantments: changed))
        #expect(try dimension.scan(region: region, options: .init(enchantments: changed)).creatures.first?.maxHealth == nil)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.options == options && restored.creatures == facts.creatures)
        let uuid = UUID(), playerPath = current.playerDataDirectory.appendingPathComponent(uuid.uuidString.lowercased() + ".dat")
        var player = entity.compound ?? [:]
        player["ShoulderEntityLeft"] = entity
        player["RootVehicle"] = .compound(["Entity": entity])
        try Fixtures.writeGzippedNBT(.compound(player), to: playerPath)
        let readPlayer = try #require(current.players(enchantments: definitions).first)
        #expect(readPlayer.maxHealth == 20)
        #expect(readPlayer.shoulderPets.first?.maxHealth == 20)
        #expect(readPlayer.rootVehicleCreatures.first?.maxHealth == 20)
    }

    @Test func effectTraversalAndDefinitionCountsAreBounded() throws {
        var effect: [String: Any] = ["type": "minecraft:attribute", "attribute": "minecraft:max_health"]
        for _ in 0..<64 { effect = ["type": "minecraft:all_of", "effects": [effect]] }
        let deep = try JSONSerialization.data(withJSONObject: ["effects": ["minecraft:location_changed": [["effect": effect]]]])
        #expect(EnchantmentDefinition(data: deep)?.hasMaximumHealthModifier == nil)
        let wide = try JSONSerialization.data(withJSONObject: ["effects": ["minecraft:attributes": Array(repeating: ["attribute": "minecraft:movement_speed"], count: 65_537)]])
        #expect(EnchantmentDefinition(data: wide)?.hasMaximumHealthModifier == nil)
        let reader = try assets((0..<4097).map { entry("example:e\($0)", neutral) })
        #expect(try reader.enchantmentDefinitions().isEmpty)
    }

    @Test func cancelledDefinitionReadsDoNotPublishPartialSnapshots() async throws {
        let reader = try assets([entry("minecraft:protection", neutral)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try reader.enchantmentDefinitions()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
