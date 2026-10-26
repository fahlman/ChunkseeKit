import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct BiomeDefinitionTests {
    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Fixture"}}"#
    private let plain = ##"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":"#3f76e4"}}"##

    @Test func worldResourceQueriesRejectOversizedPackListsWithoutTruncatingThem() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([resource(plain), .init(
            path: "data/minecraft/tags/worldgen/biome/is_overworld.json", text: #"{"values":["plains"]}"#)])
        for count in [64, 65] {
            let world = try world(root, packs: Array(repeating: "vanilla", count: count))
            let expected: Set<String> = count == 64 ? ["minecraft:plains"] : []
            #expect(Set(try world.biomeDefinitions(assets: reader).keys) == expected)
            #expect(Set(try world.biomeDefinitions(for: ["plains"], assets: reader).keys) == expected)
            #expect(try world.tags(for: ["is_overworld"], in: "worldgen/biome", assets: reader).isEmpty == (count == 65))
        }
    }

    @Test func completeCatalogUsesTheRequestedReaderPriorityAndKeepsNestedIDs() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let low = plain.replacingOccurrences(of: "#3f76e4", with: "#102030")
        let high = plain.replacingOccurrences(of: "#3f76e4", with: "#abcdef")
        _ = try folder("low", at: root, entries: [resource(low), resource("example:nested/meadow", low),
                                                resource("example:blocked", low)])
        var corrupt = resource("example:corrupt", plain)
        corrupt.wrongCRC = true
        try zip("high.zip", at: root, entries: [resource(high), resource("example:blocked", "invalid JSON"), corrupt])
        let reader = try assets([resource(plain), resource("example:vanilla_only", plain), resource("example:corrupt", plain)])
        let world = try world(root, packs: ["vanilla", "file/low", "file/high.zip"])
        let files = ["level.dat", "datapacks/low/pack.mcmeta", "datapacks/low/data/minecraft/worldgen/biome/plains.json", "datapacks/high.zip"]
            .map { root.appendingPathComponent($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let result = try world.biomeDefinitions(assets: reader)
        #expect(Set(result.keys) == ["minecraft:plains", "example:nested/meadow", "example:vanilla_only"])
        #expect(result["minecraft:plains"]?.waterColor == 0xabcdef)
        #expect(result["example:nested/meadow"]?.waterColor == 0x102030)
        #expect(try result == world.biomeDefinitions(for: ["plains", "example:nested/meadow", "example:vanilla_only",
                                                       "example:blocked", "example:corrupt"], assets: reader))
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func completeCatalogDoesNotInventVanillaOrEnabledPacks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try folder("override", at: root, entries: [resource("example:custom", plain)])
        let world = try world(root, packs: ["vanilla", "file/override"])
        #expect(Set(try world.biomeDefinitions(assets: nil).keys) == ["example:custom"])
        for version: Int32 in [1, 9999] {
            #expect(Set(try world.biomeDefinitions(assets: assets([resource(plain)], version: version)).keys)
                == ["example:custom", "minecraft:plains"])
        }
        let reader = try assets([resource(plain)])
        for version in [nil, 1000, 9999] as [Int32?] {
            let old = try self.world(root, packs: ["vanilla", "file/override"], version: version)
            #expect(try old.biomeDefinitions(assets: reader).isEmpty)
        }
        let disabled = try self.world(root, packs: [])
        #expect(try disabled.biomeDefinitions(assets: reader).isEmpty)
        let blocked = try self.world(root, packs: ["vanilla", "file/override", "experiment"])
        #expect(try blocked.biomeDefinitions(assets: reader).isEmpty)
        let higher = try self.world(root, packs: ["vanilla", "experiment", "file/override"])
        #expect(Set(try higher.biomeDefinitions(assets: reader).keys) == ["example:custom"])
    }

    @Test func discoveryAcceptsOnlyCanonicalBiomeResourcePaths() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unrelated = ["data/minecraft/worldgen/noise_settings/fake.json", "assets/minecraft/worldgen/biome/fake.json",
                         "data/Bad/worldgen/biome/fake.json", "data/./worldgen/biome/fake.json",
                         "data/minecraft/worldgen/biome/../fake.json", "data/minecraft/worldgen/biome//fake.json",
                         "data/minecraft/worldgen/biome/.json", "data/minecraft/worldgen/biome/fake.json.extra"]
        let reader = try assets([resource("example:nested/real", plain)] + unrelated.map { .init(path: $0, text: plain) })
        let world = try world(root, packs: ["vanilla"])
        #expect(Set(try world.biomeDefinitions(assets: reader).keys) == ["example:nested/real"])
    }

    @Test func folderCatalogSkipsCategoryAndDescendantLinksButAllowsNamespaceAliases() throws {
        let root = try Fixtures.tempDirectory(), outside = try Fixtures.tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let pack = try folder("links", at: root, entries: [resource("example:nested/meadow", plain)])
        let biomes = pack.appendingPathComponent("data/example/worldgen/biome")
        let fm = FileManager.default
        try fm.createSymbolicLink(at: biomes.appendingPathComponent("alias"), withDestinationURL: biomes.appendingPathComponent("nested"))
        try fm.createSymbolicLink(at: biomes.appendingPathComponent("nested/cycle"), withDestinationURL: biomes)
        try fm.createSymbolicLink(at: biomes.appendingPathComponent("escape"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: biomes.appendingPathComponent("link.json"), withDestinationURL: biomes.appendingPathComponent("nested/meadow.json"))
        try fm.createSymbolicLink(at: pack.appendingPathComponent("data/namespace_alias"), withDestinationURL: pack.appendingPathComponent("data/example"))
        let linkedCategory = pack.appendingPathComponent("data/category_alias/worldgen/biome")
        try fm.createDirectory(at: linkedCategory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkedCategory, withDestinationURL: biomes)
        let external = outside.appendingPathComponent("outside.json")
        try Fixtures.write(Array(plain.utf8), to: external)
        try fm.createSymbolicLink(at: biomes.appendingPathComponent("blocked.json"), withDestinationURL: external)
        let world = try world(root, packs: ["vanilla", "file/links"])
        let reader = try assets([resource("example:blocked", plain)])
        let result = try world.biomeDefinitions(assets: reader)
        #expect(Set(result.keys) == ["example:nested/meadow", "namespace_alias:nested/meadow", "example:blocked"])
        #expect(result["example:nested/meadow"] == result["namespace_alias:nested/meadow"])
        #expect(result["example:blocked"]?.waterColor == 0x3f76e4)
        let subset = try world.biomeDefinitions(for: ["example:alias/meadow", "example:link",
            "category_alias:nested/meadow", "example:nested/meadow", "namespace_alias:nested/meadow", "example:blocked"], assets: reader)
        #expect(subset == result)
        #expect(try Data(contentsOf: external) == Data(plain.utf8))
    }

    @Test func catalogLinksCannotOverrideLowerResourcesButMalformedRegularFilesCan() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let low = plain.replacingOccurrences(of: "#3f76e4", with: "#102030")
        let high = plain.replacingOccurrences(of: "#3f76e4", with: "#abcdef")
        _ = try folder("low", at: root, entries: [resource("example:linked", low), resource("example:invalid", low)])
        let pack = try folder("high", at: root, entries: [resource("example:target", high), resource("example:invalid", "invalid JSON")])
        let biomes = pack.appendingPathComponent("data/example/worldgen/biome")
        try FileManager.default.createSymbolicLink(at: biomes.appendingPathComponent("linked.json"), withDestinationURL: biomes.appendingPathComponent("target.json"))
        let world = try world(root, packs: ["file/low", "file/high"])
        let catalog = try world.biomeDefinitions(assets: nil)
        #expect(Set(catalog.keys) == ["example:linked", "example:target"])
        #expect(catalog["example:linked"]?.waterColor == 0x102030)
        #expect(catalog["example:target"]?.waterColor == 0xabcdef)
        #expect(try world.biomeDefinitions(for: ["example:linked", "example:target", "example:invalid"], assets: nil) == catalog)
    }

    @Test func changedGameArchiveDoesNotExposeLowerPackDefinitions() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try folder("low", at: root, entries: [resource(plain)])
        let jar = root.appendingPathComponent("fixture.jar")
        let bytes = try TestZIP.zip([.init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#), resource(plain)])
        try Fixtures.write(bytes, to: jar)
        let reader = try #require(try GameAssets(contentsOf: jar))
        let world = try world(root, packs: ["file/low", "vanilla"])
        #expect(Set(try world.biomeDefinitions(assets: reader).keys) == ["minecraft:plains"])
        try Fixtures.write(Array("truncated".utf8), to: jar)
        #expect(try world.biomeDefinitions(assets: reader).isEmpty)
        #expect(try world.biomeDefinitions(for: ["plains"], assets: reader).isEmpty)
    }

    @Test func cancelledRegistryReadsStopWithoutPublishingPartialDefinitions() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla"]), reader = try assets([resource(plain)])
        for all in [true, false] {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try all ? world.biomeDefinitions(assets: reader)
                    : world.biomeDefinitions(for: ["plains"], assets: reader)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func resource(_ id: String, _ json: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":", maxSplits: 1)
        return .init(path: "data/\(parts[0])/worldgen/biome/\(parts[1]).json", text: json)
    }

    private func resource(_ json: String) -> TestZIP.Entry { resource("minecraft:plains", json) }

    private func assets(_ entries: [TestZIP.Entry], version: Int32 = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":\#(version)}"#)
        ] + entries))))
    }

    private func world(_ root: URL, packs: [String] = ["vanilla"], version: Int32? = 5023) throws -> World {
        var fields: [String: NBT] = [
            "LevelName": .string("Biome Definitions"),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))])
        ]
        fields["DataVersion"] = version.map(NBT.int)
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func folder(_ name: String, at root: URL, entries: [TestZIP.Entry], metadata: String? = nil) throws -> URL {
        let folder = root.appendingPathComponent("datapacks/" + name)
        try Fixtures.write(Array((metadata ?? self.metadata).utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        for entry in entries {
            try Fixtures.write(Array(entry.text.utf8), to: folder.appendingPathComponent(entry.path))
        }
        return folder
    }

    private func zip(_ name: String, at root: URL, entries: [TestZIP.Entry]) throws {
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata)] + entries),
                           to: root.appendingPathComponent("datapacks/" + name))
    }

    @Test func jarReadsClimateOverridesAndAllThreeColorForms() throws {
        let reader = try assets([
            resource(plain),
            resource("example:full", ##"""
            {"temperature":2.0,"downfall":-0.2,"effects":{"water_color":"#01AbEF",
            "grass_color":-1,"foliage_color":[0.5,0.25,1],"dry_foliage_color":66051,
            "grass_color_modifier":"swamp"},"unrelated_generation_fields":false}
            """##),
            resource("example:forest", ##"{"temperature":0.7,"downfall":0.8,"effects":{"water_color":"#000000","grass_color_modifier":"dark_forest"}}"##)
        ])
        let basic = try #require(reader.biomeDefinition("plains"))
        #expect(basic.temperature == 0.8 && basic.downfall == 0.4)
        #expect(basic.waterColor == 0x3f76e4)
        #expect(basic.grassColor == nil && basic.foliageColor == nil && basic.dryFoliageColor == nil)
        #expect(basic.grassColorModifier == .none)
        let full = try #require(reader.biomeDefinition("example:full"))
        #expect(full.temperature == 2 && full.downfall == -0.2)
        #expect(full.waterColor == 0x01abef)
        #expect(full.grassColor == 0xffffff && full.foliageColor == 0x7f3fff)
        #expect(full.dryFoliageColor == 0x010203 && full.grassColorModifier == .swamp)
        #expect(reader.biomeDefinition("example:forest")?.grassColorModifier == .darkForest)
    }

    @Test func malformedFieldsDoNotBecomeDefaultsOrFabricatedColors() throws {
        let invalidColors = [#""ffffff""#, ##""#fff""##, ##""#12345678""##, ##""#12zz00""##,
                             ##""#+12345""##, ##""#１２３４５６""##, "true", "null", "1.5", "2147483648",
                             "[0,1]", "[0,1,2]", "[true,0,1]"]
        var invalid = invalidColors.map { #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":\#($0)}}"# }
        invalid += [
            #"{"temperature":true,"downfall":0.4,"effects":{"water_color":1}}"#,
            #"{"temperature":1e100,"downfall":0.4,"effects":{"water_color":1}}"#,
            #"{"temperature":0.8,"effects":{"water_color":1}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1,"grass_color":null}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1,"foliage_color":false}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1,"dry_foliage_color":"bad"}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1,"grass_color_modifier":null}}"#,
            #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1,"grass_color_modifier":42}}"#
        ]
        let reader = try assets(invalid.enumerated().map { resource("example:bad\($0.offset)", $0.element) })
        for index in invalid.indices { #expect(reader.biomeDefinition("example:bad\(index)") == nil) }
    }

    @Test func unknownGrassModifierPreservesOtherColorsAndClimate() throws {
        let reader = try assets([resource("example:future", #"""
        {"temperature":0.8,"downfall":0.4,"effects":{"water_color":1193046,
        "grass_color":16777215,"foliage_color":11259375,"dry_foliage_color":66051,
        "grass_color_modifier":"example:future"}}
        """#)])
        let biome = try #require(reader.biomeDefinition("example:future"))
        #expect(biome.temperature == 0.8 && biome.downfall == 0.4)
        #expect(biome.grassColorModifier == .unknown("example:future"))
        #expect(biome.grassColorModifier.rawValue == "example:future" && biome.grassColor == 0xffffff)
        for (source, expected) in [(BiomeColor.water, UInt32(0x123456)), (.foliage, 0xabcdef), (.dryFoliage, 0x010203)] {
            #expect(biome.color(source, x: 0, z: 0) { _, _ in nil } == expected)
        }
        #expect(biome.color(.grass, x: 0, z: 0) { _, _ in
            Issue.record("An unknown modifier cannot be resolved by sampling a colormap")
            return 0xffffff
        } == nil)
    }

    @Test func jarPathsVersionsAndPayloadFailuresStayUnavailable() throws {
        var corrupt = resource("example:corrupt", plain)
        corrupt.wrongCRC = true
        let reader = try assets([resource(plain), corrupt])
        for id in ["", "Bad ID", "minecraft:../plains", "minecraft:a/../plains", "minecraft:a//plains",
                   ".:plains", "minecraft:missing", "example:corrupt"] {
            #expect(reader.biomeDefinition(id) == nil)
        }
        #expect(try assets([resource(plain)], version: 9999).biomeDefinition("plains") == nil)
    }

    @Test func folderAndZIPOverridesUseOnePriorityOrderAndCanonicalIDs() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let low = plain.replacingOccurrences(of: "#3f76e4", with: "#102030")
        let high = plain.replacingOccurrences(of: "#3f76e4", with: "#abcdef")
        _ = try folder("low", at: root, entries: [resource(low), resource("example:nested/meadow", low)])
        try zip("high.zip", at: root, entries: [resource(high), resource("example:unrequested", "invalid JSON")])
        let world = try world(root, packs: ["vanilla", "file/low", "file/high.zip"])
        let reader = try assets([resource(plain)])
        let files = ["level.dat", "datapacks/low/pack.mcmeta", "datapacks/low/data/minecraft/worldgen/biome/plains.json", "datapacks/high.zip"]
            .map { root.appendingPathComponent($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let result = try world.biomeDefinitions(for: ["plains", "minecraft:plains", "example:nested/meadow", "missing", "bad ID"], assets: reader)
        #expect(Set(result.keys) == ["minecraft:plains", "example:nested/meadow"])
        #expect(result["minecraft:plains"]?.waterColor == 0xabcdef)
        #expect(result["example:nested/meadow"]?.waterColor == 0x102030)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        let reversed = try self.world(root, packs: ["vanilla", "file/high.zip", "file/low"])
        #expect(try reversed.biomeDefinitions(for: ["plains"], assets: reader)["minecraft:plains"]?.waterColor == 0x102030)
    }

    @Test func dataPackOverridesDriveTheSameTintResolverWithoutVanillaDefaults() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1193046,"grass_color":11259375,"foliage_color":1122867,"dry_foliage_color":4478310,"grass_color_modifier":"dark_forest"}}"#
        _ = try folder("colors", at: root, entries: [resource(definition), resource("example:custom", definition)])
        let world = try world(root, packs: ["vanilla", "file/colors"])
        let values = try world.biomeDefinitions(for: ["plains", "example:custom"], assets: assets([resource(plain)]))
        for id in ["minecraft:plains", "example:custom"] {
            let value = try #require(values[id])
            #expect(value.color(.grass, x: -5, z: 10) { _, _ in nil } == 0x69807c)
            #expect(value.color(.foliage, x: -5, z: 10) { _, _ in nil } == 0x112233)
            #expect(value.color(.dryFoliage, x: -5, z: 10) { _, _ in nil } == 0x445566)
            #expect(value.color(.water, x: -5, z: 10) { _, _ in nil } == 0x123456)
        }
        let withoutJar = try world.biomeDefinitions(for: ["example:custom"], assets: nil)
        #expect(withoutJar["example:custom"]?.color(.grass, x: 0, z: 0) { _, _ in nil } == 0x69807c)
    }

    @Test func malformedPresentOverridesNeverFallThrough() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try folder("override", at: root, entries: [resource("invalid JSON")])
            .appendingPathComponent(resource(plain).path)
        let reader = try assets([resource(plain)])
        let world = try world(root, packs: ["vanilla", "file/override"])
        #expect(try world.biomeDefinitions(for: ["plains"], assets: reader).isEmpty)
        try FileManager.default.removeItem(at: file)
        #expect(try world.biomeDefinitions(for: ["plains"], assets: reader)["minecraft:plains"]?.waterColor == 0x3f76e4)

        var corrupt = resource(plain)
        corrupt.wrongCRC = true
        try zip("bad.zip", at: root, entries: [corrupt])
        let zipped = try self.world(root, packs: ["vanilla", "file/bad.zip"])
        #expect(try zipped.biomeDefinitions(for: ["plains"], assets: reader).isEmpty)

        // A present corrupt vanilla resource must also shadow a lower-priority pack.
        _ = try folder("lower", at: root, entries: [resource(plain)])
        let vanillaFirst = try self.world(root, packs: ["file/lower", "vanilla"])
        #expect(try vanillaFirst.biomeDefinitions(for: ["plains"], assets: assets([corrupt])).isEmpty)
    }

    @Test func unsupportedHigherPacksBlockLowerFallbacks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([resource(plain)])
        _ = try folder("filtered", at: root, entries: [], metadata: #"{"pack":{},"filter":{}}"#)
        _ = try folder("overlaid", at: root, entries: [], metadata: #"{"pack":{},"overlays":{}}"#)
        try Fixtures.write(Array("not a zip".utf8), to: root.appendingPathComponent("datapacks/broken.zip"))
        for pack in ["file/filtered", "file/overlaid", "file/missing", "file/broken.zip", "experiment", "file/../escape"] {
            let world = try world(root, packs: ["vanilla", pack])
            #expect(try world.biomeDefinitions(for: ["plains"], assets: reader).isEmpty)
        }
        _ = try folder("highest", at: root, entries: [resource(plain)])
        let known = try world(root, packs: ["vanilla", "experiment", "file/highest"])
        #expect(try known.biomeDefinitions(for: ["plains"], assets: reader)["minecraft:plains"]?.waterColor == 0x3f76e4)
    }

    @Test func missingJarsKeepHigherPackDefinitionsAndOlderJarsSupplyTheirResources() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try folder("override", at: root, entries: [resource("example:custom", plain)])
        let world = try world(root, packs: ["vanilla", "file/override"])
        let ids: Set<String> = ["plains", "example:custom"]
        #expect(Set(try world.biomeDefinitions(for: ids, assets: nil).keys) == ["example:custom"])
        for version: Int32 in [1, 9999] {
            let result = try world.biomeDefinitions(for: ids, assets: assets([resource(plain)], version: version))
            #expect(Set(result.keys) == ["example:custom", "minecraft:plains"])
        }
        for version in [nil, 1000, 9999] as [Int32?] {
            let old = try self.world(root, packs: ["vanilla", "file/override"], version: version)
            #expect(try old.biomeDefinitions(for: ids, assets: assets([resource(plain)])).isEmpty)
        }
        let disabled = try self.world(root, packs: [])
        #expect(try disabled.biomeDefinitions(for: ids, assets: assets([resource(plain)])).isEmpty)
    }

    @Test func pathsCannotEscapeWorldOrPackAndReadErrorsPropagate() throws {
        let root = try Fixtures.tempDirectory(), outside = try Fixtures.tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let pack = try folder("safe", at: root, entries: [])
        let leaf = pack.appendingPathComponent(resource(plain).path)
        try FileManager.default.createDirectory(at: leaf.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = outside.appendingPathComponent("plains.json")
        try Fixtures.write(Array(plain.utf8), to: target)
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: target)
        let world = try world(root, packs: ["vanilla", "file/safe"])
        let reader = try assets([resource(plain)])
        #expect(try world.biomeDefinitions(for: ["plains", "minecraft:../../outside"], assets: reader)["minecraft:plains"]?.waterColor == 0x3f76e4)
        try FileManager.default.removeItem(at: leaf)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: false)
        #expect(try world.biomeDefinitions(for: ["plains"], assets: reader)["minecraft:plains"]?.waterColor == 0x3f76e4)
        try FileManager.default.removeItem(at: leaf)
        try Fixtures.write(Array(plain.utf8), to: leaf)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: leaf.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaf.path) }
        #expect(throws: (any Error).self) { try world.biomeDefinitions(for: ["plains"], assets: reader) }
        #expect(try world.biomeDefinitions(for: [], assets: reader).isEmpty)
        #expect(try Data(contentsOf: target) == Data(plain.utf8))
    }
}
