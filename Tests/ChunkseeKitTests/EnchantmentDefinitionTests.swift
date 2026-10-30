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

    @Test func maximumLevelsComeFromDefinitionsIncludingUnfamiliarEnchantments() throws {
        let definitions = try assets([
            entry("minecraft:mending", #"{"max_level":4}"#),
            entry("example:single", #"{"max_level":1}"#),
            entry("example:highest", #"{"max_level":255}"#),
            entry("example:whole_number", #"{"max_level":5.0}"#),
        ]).enchantmentDefinitions()
        #expect(definitions["minecraft:mending"]?.maximumLevel == 4)
        #expect(definitions["example:single"]?.maximumLevel == 1)
        #expect(definitions["example:highest"]?.maximumLevel == 255)
        #expect(definitions["example:whole_number"]?.maximumLevel == 5)
    }

    @Test func unreadableMaximumLevelsPreserveOtherDefinitionFacts() throws {
        for value in ["null", "true", "false", "0", "-1", "256", "0.9", "1e100", #""1""#, "[]", "{}"] {
            let json = #"{"max_level":\#(value),"slots":["head"],"effects":{"minecraft:attributes":[{"attribute":"minecraft:max_health"}]}}"#
            let definition = try #require(EnchantmentDefinition(data: Data(json.utf8)))
            #expect(definition.maximumLevel == nil)
            #expect(definition.slots == ["head"])
            #expect(definition.hasMaximumHealthModifier == true)
        }
        #expect(EnchantmentDefinition(data: Data(neutral.utf8))?.maximumLevel == nil)
    }

    @Test func maximumLevelsUseEnabledPackPriorityWithoutFallingBackThroughInvalidFields() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([
            entry("minecraft:mending", #"{"max_level":1}"#),
            entry("example:missing", #"{"max_level":3}"#),
            entry("example:invalid", #"{"max_level":5}"#),
        ])
        let pack = root.appendingPathComponent("datapacks/custom")
        try write(metadata, at: "pack.mcmeta", under: pack)
        try write(#"{"max_level":2}"#, at: "data/minecraft/enchantment/mending.json", under: pack)
        try write(neutral, at: "data/example/enchantment/missing.json", under: pack)
        try write(#"{"max_level":256}"#, at: "data/example/enchantment/invalid.json", under: pack)
        let archive = try TestZIP.zip([
            .init(path: "pack.mcmeta", text: metadata),
            entry("minecraft:mending", #"{"max_level":4}"#),
        ])
        try Fixtures.write(archive, to: root.appendingPathComponent("datapacks/high.zip"))
        let folderWorld = try world(root, packs: ["vanilla", "file/custom"])
        let folder = try folderWorld.enchantmentDefinitions(assets: reader)
        #expect(folder["minecraft:mending"]?.maximumLevel == 2)
        #expect(folder["example:missing"]?.maximumLevel == nil)
        #expect(folder["example:invalid"]?.maximumLevel == nil)
        #expect(folder.count == 3)
        let zipWorld = try world(root, packs: ["vanilla", "file/custom", "file/high.zip"])
        #expect(try zipWorld.enchantmentDefinitions(assets: reader)["minecraft:mending"]?.maximumLevel == 4)
        #expect(try zipWorld.enchantmentDefinitions(assets: nil)["minecraft:mending"]?.maximumLevel == 4)
        let disabled = try world(root, packs: ["vanilla"])
        #expect(try disabled.enchantmentDefinitions(assets: reader)["minecraft:mending"]?.maximumLevel == 1)
    }

    @Test func maximumLevelRoundTripsAndOldSnapshotsStillDecode() throws {
        let legacy = Data(#"{"hasMaximumHealthModifier":false,"slots":["any"]}"#.utf8)
        let old = try JSONDecoder().decode(EnchantmentDefinition.self, from: legacy)
        #expect(old.description == nil && old.maximumLevel == nil
                && old.hasMaximumHealthModifier == false && old.slots == ["any"])
        let current = try #require(EnchantmentDefinition(data: Data(#"{"max_level":1,"slots":["any"]}"#.utf8)))
        #expect(try JSONDecoder().decode(EnchantmentDefinition.self, from: JSONEncoder().encode(current)) == current)
        #expect(RegionScanOptions(enchantments: ["example:single": old]) !=
                RegionScanOptions(enchantments: ["example:single": current]))
    }

    @Test func descriptionsRetainTheDeclaredComponentInsteadOfInventingATranslationKey() throws {
        let definitions = try assets([
            entry("minecraft:mending", #"{"max_level":1,"description":{"translate":"enchantment.minecraft.mending"}}"#),
            entry("example:custom", #"{"max_level":4,"description":{"translate":"pack.other_name","fallback":"Fallback %s","with":[17,1.25,0.1,true,{"text":"Guest"}],"extra":[{"text":"!"}]}}"#),
            entry("example:literal", #"{"description":"{\"text\":\"literal JSON-looking name\"}"}"#),
            entry("example:empty", #"{"description":""}"#),
        ]).enchantmentDefinitions()
        #expect(definitions["minecraft:mending"]?.description ==
                .translated(key: "enchantment.minecraft.mending", fallback: nil, arguments: []))
        let custom: TextComponent.Content = .sequence([
            .translated(key: "pack.other_name", fallback: "Fallback %s",
                        arguments: [.integer(17), .float(1.25), .number(0.1), .boolean(true), .component(.literal("Guest"))]),
            .literal("!"),
        ])
        #expect(definitions["example:custom"]?.description == custom)
        #expect(definitions["example:custom"]?.maximumLevel == 4)
        #expect(definitions["example:literal"]?.description == .literal(#"{"text":"literal JSON-looking name"}"#))
        #expect(definitions["example:empty"]?.description == .literal(""))
    }

    @Test func unreadableDescriptionsPreserveIndependentLevelAndHealthFacts() throws {
        for value in ["null", "true", "42", "[]", "{}", #"{"translate":false}"#,
                      #"{"selector":"@s"}"#, #"{"keybind":"key.jump"}"#,
                      #"{"text":"Partial","extra":[{"selector":"@s"}]}"#] {
            let text = #"{"description":\#(value),"max_level":3,"slots":["head"],"effects":{"minecraft:attributes":[{"attribute":"minecraft:max_health"}]}}"#
            let definition = try #require(EnchantmentDefinition(data: Data(text.utf8)))
            #expect(definition.description == nil)
            #expect(definition.maximumLevel == 3 && definition.slots == ["head"])
            #expect(definition.hasMaximumHealthModifier == true)
        }
        #expect(EnchantmentDefinition(data: Data(neutral.utf8))?.description == nil)
    }

    @Test func descriptionsFollowEnabledFolderAndZIPPriorityIncludingInvalidOverrides() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([
            entry("example:changed", #"{"description":{"translate":"game.changed"},"max_level":1}"#),
            entry("example:invalid", #"{"description":"Lower name","max_level":5}"#),
            entry("example:absent", #"{"description":"Lower absent name","max_level":2}"#),
        ])
        let pack = root.appendingPathComponent("datapacks/custom")
        try write(metadata, at: "pack.mcmeta", under: pack)
        try write(#"{"description":"Folder name","max_level":3}"#,
                  at: "data/example/enchantment/changed.json", under: pack)
        try write(#"{"description":{"selector":"@s"},"max_level":4}"#,
                  at: "data/example/enchantment/invalid.json", under: pack)
        try write(#"{"max_level":6}"#, at: "data/example/enchantment/absent.json", under: pack)
        let folderWorld = try world(root, packs: ["vanilla", "file/custom"])
        let folder = try folderWorld.enchantmentDefinitions(assets: reader)
        #expect(folder["example:changed"]?.description == .literal("Folder name"))
        #expect(folder["example:invalid"]?.description == nil && folder["example:invalid"]?.maximumLevel == 4)
        #expect(folder["example:absent"]?.description == nil && folder["example:absent"]?.maximumLevel == 6)
        let archive = try TestZIP.zip([
            .init(path: "pack.mcmeta", text: metadata),
            entry("example:changed", #"{"description":{"translate":"pack.zip_name","fallback":"ZIP fallback"},"max_level":7}"#),
        ])
        try Fixtures.write(archive, to: root.appendingPathComponent("datapacks/high.zip"))
        let zipWorld = try world(root, packs: ["vanilla", "file/custom", "file/high.zip"])
        let zip = try zipWorld.enchantmentDefinitions(assets: reader)
        #expect(zip["example:changed"]?.description ==
                .translated(key: "pack.zip_name", fallback: "ZIP fallback", arguments: []))
        #expect(zip["example:changed"]?.maximumLevel == 7)
        #expect(try zipWorld.enchantmentDefinitions(assets: nil) == zip)
        let disabled = try world(root, packs: ["vanilla"])
        #expect(try disabled.enchantmentDefinitions(assets: reader)["example:changed"]?.description ==
                .translated(key: "game.changed", fallback: nil, arguments: []))
    }

    @Test func descriptionArchivesPreserveComponentsAndTypedArguments() throws {
        let definition = try #require(EnchantmentDefinition(data: Data(
            #"{"description":["Name ",{"translate":"pack.name","fallback":"%s","with":["literal",9223372036854775807,1.25,0.1,false,{"text":"Nested"}]}],"max_level":2,"slots":["any"]}"#.utf8)))
        #expect(try JSONDecoder().decode(EnchantmentDefinition.self, from: JSONEncoder().encode(definition)) == definition)
        #expect(try PropertyListDecoder().decode(EnchantmentDefinition.self, from: PropertyListEncoder().encode(definition)) == definition)
        let nonfinite = try #require(EnchantmentDefinition(data: Data(
            #"{"description":{"translate":"pack.name","with":[1e9999,-1e9999]}}"#.utf8)))
        #expect(nonfinite.description != nil)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        #expect(try decoder.decode(EnchantmentDefinition.self, from: encoder.encode(nonfinite)) == nonfinite)
    }

    @Test func descriptionBudgetsAreSharedWithoutHidingOtherMetadata() throws {
        var deep: Any = "Leaf"
        for _ in 0..<64 { deep = ["text": "Parent", "extra": [deep]] }
        let deepData = try JSONSerialization.data(withJSONObject: ["description": deep, "max_level": 3])
        let deepDefinition = try #require(EnchantmentDefinition(data: deepData))
        #expect(deepDefinition.description == nil && deepDefinition.maximumLevel == 3)

        let wide = String(decoding: try JSONSerialization.data(withJSONObject: [
            "description": Array(repeating: "Leaf", count: 32_768), "max_level": 4,
        ]), as: UTF8.self)
        let definitions = try assets([entry("example:a", wide), entry("example:b", wide)]).enchantmentDefinitions()
        #expect(definitions["example:a"]?.description != nil)
        #expect(definitions["example:b"]?.description == nil)
        #expect(definitions.count == 2 && definitions.values.allSatisfy {
            $0.maximumLevel == 4 && $0.hasMaximumHealthModifier == false
        })
    }

    @Test func nonfiniteDescriptionsKeepCompleteScanInputsIdentifiable() throws {
        func options(_ argument: String) throws -> RegionScanOptions {
            let source = #"{"description":{"translate":"pack.name","with":[\#(argument)]},"max_level":3,"slots":["head"]}"#
            return try RegionScanOptions(enchantments: assets([entry("example:large", source)]).enchantmentDefinitions())
        }
        let positive = try options("1e9999"), negative = try options("-1e9999")
        let literal = try options(#""Infinity""#), finite = try options("1")
        #expect(positive.enchantments["example:large"]?.description ==
            .translated(key: "pack.name", fallback: nil, arguments: [.float(.infinity)]))
        let identity = try InterpretationKey.identity(of: positive)
        #expect(try identity == InterpretationKey.identity(of: options("1e9999")))
        let keys = try [positive, negative, literal, finite].map { try InterpretationKey.identity(of: $0) }
        #expect(Set(keys).count == keys.count)

        let facts = RegionFacts(dimension: "example:world", region: .init(x: 0, z: 0), options: positive)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let reopened = try decoder.decode(RegionFacts.self, from: encoder.encode(facts))
        #expect(reopened.options == positive)
        #expect(try InterpretationKey.identity(of: reopened.options) == identity)
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
        let named = try current.enchantmentDefinitions(assets: assets([
            entry("minecraft:protection", neutral.replacingOccurrences(of: #""slots""#, with: #""description":"A pack name","slots""#)),
        ]))
        let namedOptions = RegionScanOptions(enchantments: named)
        let namedFacts = try dimension.scan(region: region, options: namedOptions)
        #expect(namedFacts.creatures == facts.creatures && namedOptions != options)
        let namedArchive = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(namedFacts))
        #expect(namedArchive.options == namedOptions && namedArchive.creatures == facts.creatures)
        #expect(namedArchive.options.enchantments["minecraft:protection"]?.description == .literal("A pack name"))
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
