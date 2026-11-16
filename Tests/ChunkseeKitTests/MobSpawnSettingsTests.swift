@testable import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct MobSpawnSettingsTests {
    @Test func biomeOverlayReplacesDeclaredCategoriesAndInheritsTheRest() throws {
        let base = try baseSettings([
            "monster": [["type": "slime", "weight": 100]],
            "creature": [["type": "example:grazer", "weight": 3]]
        ])
        let assets = try jar([
            biome("test:overlay", modifier: "overlay", categories: ["monster": []]),
            biome("test:replace", modifier: "override", categories: ["monster": []]),
            .init(path: "data/test/worldgen/biome/inherit.json", text: "{}")
        ])
        let overlay = try #require(assets.biomeSpawnSettings("test:overlay", base: base))
        #expect(overlay.contains("slime", in: "monster") == false)
        #expect(overlay.contains("example:grazer", in: "creature") == true)
        let replacement = try #require(assets.biomeSpawnSettings("test:replace", base: base))
        #expect(replacement.contains("example:grazer", in: "creature") == false)
        #expect(assets.biomeSpawnSettings("test:inherit", base: base) == base)
    }

    @Test func anOverlaySettlesItsCategoriesEvenWhenTheDimensionIsUnknown() throws {
        let assets = try jar([
            biome("test:biome", modifier: "overlay", categories: ["monster": [["type": "example:slime", "weight": 1]]]),
            biome("test:empty", modifier: "overlay", categories: ["monster": []]),
            .init(path: "data/test/worldgen/biome/inherit.json", text: "{}")
        ])
        let spawns = try #require(assets.biomeSpawnSettings("test:biome", base: nil))
        #expect(spawns.contains("example:slime", in: "monster") == true)
        #expect(spawns.contains("minecraft:slime", in: "monster") == false)
        #expect(spawns.contains("example:grazer", in: "creature") == nil)
        #expect(assets.biomeSpawnSettings("test:empty", base: nil)?.contains("slime", in: "monster") == false)
        #expect(assets.biomeSpawnSettings("test:inherit", base: nil) == nil)
        #expect(assets.biomeDefinition("test:biome") == nil)
    }

    @Test func malformedEntriesDoNotHideKnownCandidatesOrInventNegatives() throws {
        let assets = try jar([biome("test:biome", modifier: "override", categories: [
            "monster": [["type": "slime", "weight": 1], ["type": "bad identifier", "weight": 1]],
            "creature": [["type": "example:zero", "weight": 0], ["type": "example:unknown"]],
            "bad": "invalid"
        ])])
        let spawns = try #require(assets.biomeSpawnSettings("test:biome", base: nil))
        #expect(spawns.contains(":slime", in: "monster") == true)
        #expect(spawns.contains("zombie", in: "monster") == nil)
        #expect(spawns.contains("example:zero", in: "creature") == false)
        #expect(spawns.contains("example:unknown", in: "creature") == nil)
        #expect(spawns.contains("example:other", in: "creature") == false)
        #expect(spawns.contains("slime", in: "bad") == nil)
        #expect(spawns.contains("slime", in: "missing") == false)
        #expect(spawns.contains("bad id", in: "monster") == nil)
        #expect(spawns.candidatesByCategory["creature"]?.map(\.entityType) == ["example:zero", "example:unknown"])
    }

    @Test func inlineAndReferencedDimensionAttributesShareTheSameInterpretation() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attributes: [String: Any] = ["gameplay/natural_mob_spawns": [
            "modifier": "overlay", "argument": ["spawns_by_category": ["monster": [["type": ":slime", "weight": 2]]]]
        ]]
        let assets = try jar([try entry("data/test/dimension_type/known.json", typeJSON(attributes))])
        let inline: NBT = .compound([
            "min_y": .int(0), "height": .int(256), "logical_height": .int(256), "has_ceiling": .byte(0),
            "attributes": .compound(["gameplay/natural_mob_spawns": .compound([
                "modifier": .string("overlay"), "argument": .compound(["spawns_by_category": .compound([
                    "monster": .list([.compound(["type": .string(":slime"), "weight": .int(2)])])
                ])])
            ])])
        ])
        try writeWorld(root, dimensions: ["test:reference": .compound(["type": .string("test:known")]),
                                         "test:inline": .compound(["type": inline])])
        let settings = try World(contentsOf: root).dimensionTypes(assets: assets)
        #expect(settings["test:reference"]?.baseMobSpawnSettings == settings["test:inline"]?.baseMobSpawnSettings)
        #expect(settings["test:reference"]?.baseMobSpawnSettings?.contains("slime", in: "monster") == true)
        let defaults = try baseSettings(nil)
        #expect(defaults.contains("slime", in: "monster") == false)
    }

    @Test func invalidSpawnAttributesLeaveOtherDimensionFactsAvailable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attrs: [String: Any] = ["minecraft:gameplay/natural_mob_spawns": ["modifier": "new_modifier", "argument": ["spawns_by_category": [:]]]]
        let assets = try jar([try entry("data/test/dimension_type/known.json", typeJSON(attrs))])
        try writeWorld(root, dimensions: ["test:place": .compound(["type": .string("test:known")])])
        let dimension = try #require(try World(contentsOf: root).dimensionTypes(assets: assets)["test:place"])
        #expect(dimension.maxY == 255 && dimension.logicalHeight == 256)
        #expect(dimension.baseMobSpawnSettings == nil)
    }

    @Test func nativeWeightsUseGameIntegerConversionBeforeCheckingTheirRange() throws {
        // NbtOps/Codec.INT and MobSpawnSettings.CODEC give these values. The game drops
        // invalid candidates; the reader keeps their saved type with an unavailable weight.
        let cases: [(String, NBT?, Int?)] = [
            ("byte", .byte(1), 1), ("short", .short(2), 2),
            ("int", .int(3), 3), ("long", .long(4), 4),
            ("long_wrap_one", .long(4_294_967_297), 1),
            ("long_wrap_negative", .long(2_147_483_648), nil),
            ("long_max", .long(.max), nil), ("long_min", .long(.min), 0),
            ("float_fraction", .float(1.5), 1), ("double_fraction", .double(2.9), 2),
            ("negative_fraction", .double(-0.5), 0), ("negative_weight", .double(-1.5), nil),
            ("double_above_int", .double(2_147_483_648), Int(Int32.max)),
            ("double_below_int", .double(-2_147_483_649), nil),
            ("nan", .double(.nan), 0), ("positive_infinity", .double(.infinity), Int(Int32.max)),
            ("negative_infinity", .float(-.infinity), nil),
            ("string", .string("2"), nil), ("compound", .compound([:]), nil),
            ("list", .list([]), nil), ("missing", nil, nil),
        ]
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var dimensions: [String: NBT] = [:]
        for (name, value, _) in cases {
            var entry: [String: NBT] = ["type": .string("minecraft:slime")]
            entry["weight"] = value
            dimensions["test:" + name] = .compound(["type": .compound([
                "min_y": .int(0), "height": .int(256), "logical_height": .int(256), "has_ceiling": .byte(0),
                "attributes": .compound(["minecraft:gameplay/natural_mob_spawns": .compound([
                    "spawns_by_category": .compound(["monster": .list([
                        .compound(entry), .compound(["type": .string("minecraft:creeper"), "weight": .int(1)])
                    ])])
                ])])
            ])])
        }
        try writeWorld(root, dimensions: dimensions)
        let file = root.appendingPathComponent("level.dat"), before = try Data(contentsOf: file)
        let types = try World(contentsOf: root).dimensionTypes(assets: nil)
        for (name, _, expected) in cases {
            let type = try #require(types["test:" + name])
            let settings = try #require(type.baseMobSpawnSettings)
            let candidate = try #require(settings.candidatesByCategory["monster"]?.first)
            #expect(candidate.entityType == "minecraft:slime")
            #expect(candidate.weight == expected, "Native case: \(name)")
            #expect(settings.contains("slime", in: "monster") == expected.map { $0 > 0 }, "Native case: \(name)")
            #expect(settings.contains("creeper", in: "monster") == true)
            #expect(type.logicalHeight == 256)
        }
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func enabledPackOverridesAreVersionIndependentAndNeverRewriteTheWorld() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try jar([biome("test:biome", modifier: "override", categories: ["monster": [["type": "slime", "weight": 10]]])])
        try writeWorld(root, dimensions: [:], packs: ["vanilla", "file/override"])
        let folder = root.appendingPathComponent("datapacks/override")
        try Fixtures.write(Array(#"{"pack":{"description":"test"}}"#.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        let file = root.appendingPathComponent("level.dat"), before = try Data(contentsOf: file)
        let world = try World(contentsOf: root)
        #expect(try world.biomeSpawnSettings(for: ["test:biome"], base: nil, assets: assets)["test:biome"]?.contains("slime", in: "monster") == true)
        let replacement = try biome("test:biome", modifier: "override", categories: ["monster": []])
        let override = folder.appendingPathComponent(replacement.path)
        try Fixtures.write(Array(replacement.text.utf8), to: override)
        #expect(try world.biomeSpawnSettings(for: ["test:biome"], base: nil, assets: assets)["test:biome"]?.contains("slime", in: "monster") == false)
        try Fixtures.write(Array("invalid".utf8), to: override)
        #expect(try world.biomeSpawnSettings(for: ["test:biome"], base: nil, assets: assets).isEmpty)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func conflictingAttributeAliasesAndOversizedCategoriesKeepAnswersUnknown() throws {
        let table: [String: Any] = ["spawns_by_category": ["monster": []]]
        let conflict = try entry("data/test/worldgen/biome/conflict.json", ["attributes": [
            "gameplay/natural_mob_spawns": table, "minecraft:gameplay/natural_mob_spawns": table
        ]])
        let large = try biome("test:large", modifier: "override", categories: [
            "monster": Array(repeating: ["type": "slime", "weight": 1], count: 4097),
            "creature": [["type": "pig", "weight": 1]]
        ])
        let assets = try jar([conflict, large])
        #expect(assets.biomeSpawnSettings("test:conflict", base: nil) == nil)
        let spawns = try #require(assets.biomeSpawnSettings("test:large", base: nil))
        #expect(spawns.contains("slime", in: "monster") == nil)
        #expect(spawns.contains("pig", in: "creature") == true)
    }

    @Test func cancelledWorldQueriesPropagateCancellation() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWorld(root, dimensions: [:])
        let world = try World(contentsOf: root)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try world.biomeSpawnSettings(for: ["plains"], base: nil, assets: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func colorsAndSpawnsShareResourceSelectionAndRequestLimits() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWorld(root, dimensions: [:])
        let world = try World(contentsOf: root)
        let json = #"{"temperature":0.5,"downfall":0.5,"effects":{"water_color":123},"attributes":{"minecraft:gameplay/natural_mob_spawns":{"spawns_by_category":{"monster":[{"type":"slime","weight":1}]}}}}"#
        let ids = Set((0..<4097).map { "test:biome_\($0)" })
        let entries = ids.sorted().map {
            TestZIP.Entry(path: "data/test/worldgen/biome/\(Identifier($0)!.path).json", text: json)
        }
        let assets = try jar(entries)
        #expect(try world.biomeDefinitions(for: ids, assets: assets).isEmpty)
        #expect(try world.biomeDefinitions(assets: assets).isEmpty)
        #expect(try world.biomeSpawnSettings(for: ids, base: nil, assets: assets).isEmpty)
        let selected: Set<String> = ["test:biome_0", "test:biome_1"]
        let colors = try world.biomeDefinitions(for: selected, assets: assets)
        let spawns = try world.biomeSpawnSettings(for: selected, base: nil, assets: assets)
        #expect(Set(colors.keys) == selected && Set(spawns.keys) == selected)
        #expect(colors["test:biome_0"] == assets.biomeDefinition("test:biome_0"))
        #expect(spawns["test:biome_0"] == assets.biomeSpawnSettings("test:biome_0", base: nil))
        #expect(spawns["test:biome_0"]?.contains("slime", in: "monster") == true)
    }

    private func baseSettings(_ categories: [String: Any]?) throws -> MobSpawnSettings {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attributes = categories.map { ["minecraft:gameplay/natural_mob_spawns": ["spawns_by_category": $0]] } ?? [:]
        let assets = try jar([try entry("data/test/dimension_type/known.json", typeJSON(attributes))])
        try writeWorld(root, dimensions: ["test:place": .compound(["type": .string("test:known")])])
        return try #require(try World(contentsOf: root).dimensionTypes(assets: assets)["test:place"]?.baseMobSpawnSettings)
    }

    private func typeJSON(_ attributes: [String: Any]) -> [String: Any] {
        ["min_y": 0, "height": 256, "logical_height": 256, "has_ceiling": false, "attributes": attributes]
    }
    private func biome(_ id: String, modifier: String, categories: [String: Any]) throws -> TestZIP.Entry {
        let name = Identifier(id)!
        return try entry("data/\(name.namespace)/worldgen/biome/\(name.path).json", ["attributes": [
            "minecraft:gameplay/natural_mob_spawns": ["modifier": modifier, "argument": ["spawns_by_category": categories]]
        ]])
    }
    private func entry(_ path: String, _ value: [String: Any]) throws -> TestZIP.Entry {
        .init(path: path, text: String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
    }
    private func jar(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"any","world_version":999999}"#)
        ] + entries))))
    }
    private func writeWorld(_ root: URL, dimensions: [String: NBT], packs: [String] = ["vanilla"]) throws {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(1), "DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))]),
            "WorldGenSettings": .compound(["dimensions": .compound(dimensions)])
        ])]), to: root.appendingPathComponent("level.dat"))
    }
}
