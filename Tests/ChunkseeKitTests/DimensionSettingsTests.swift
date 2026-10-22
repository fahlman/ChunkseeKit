import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct DimensionSettingsTests {
    private func type(minY: Int32 = 0, height: Int32 = 256, logical: Int32 = 64) -> NBT {
        .compound(["min_y": .int(minY), "height": .int(height), "logical_height": .int(logical), "has_ceiling": .byte(1)])
    }

    private func noise(minY: Int32 = 0, height: Int32 = 128, seaLevel: NBT? = nil) -> NBT {
        var fields: [String: NBT] = ["noise": .compound(["min_y": .int(minY), "height": .int(height)])]
        fields["sea_level"] = seaLevel
        return .compound(fields)
    }

    private func definition(type: NBT, noise: NBT, generator: String = "minecraft:noise") -> NBT {
        .compound(["type": type, "generator": .compound(["type": .string(generator), "settings": noise])])
    }

    private func world(at root: URL, definitions: [String: NBT], packs: [String] = ["vanilla"],
                       version: Int32 = 5023, modern: Bool = true) throws -> World {
        let settings = NBT.compound(["dimensions": .compound(definitions)])
        var data: [String: NBT] = ["LevelName": .string("Generation Settings"), "DataVersion": .int(version),
                                  "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))])]
        if modern {
            try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(version), "data": settings]),
                                        to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        } else {
            data["WorldGenSettings"] = settings
        }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(data)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func pack(_ name: String, at root: URL, id: String = "example:custom",
                      json: String = "{\"noise\":{\"min_y\":-64,\"height\":192}}",
                      metadata: String = "{\"pack\":{\"min_format\":121,\"max_format\":121,\"description\":\"Test\"}}") throws -> URL {
        let folder = root.appendingPathComponent("datapacks/" + name)
        try Fixtures.write(Array(metadata.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        let id = try #require(Identifier(id))
        let file = folder.appendingPathComponent("data/\(id.namespace)/worldgen/noise_settings/\(id.path).json")
        try Fixtures.write(Array(json.utf8), to: file)
        return file
    }

    @Test func savedGeneratorReferencesAreIndependentOfDimensionNamesAndLogicalHeight() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, definitions: [
            "example:underground": definition(type: .string("the_nether"), noise: .string("nether")),
            "minecraft:the_nether": definition(type: .string("overworld"), noise: .string("floating_islands")),
            "example:inline": definition(type: type(logical: 16), noise: noise()),
        ])
        let files = ["level.dat", "data/minecraft/world_gen_settings.dat"].map { root.appendingPathComponent($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let settings = try world.dimensionSettings()
        let underground = try #require(settings["example:underground"])
        let dimensionType = try #require(underground.type)
        let generator = try #require(underground.noiseGeneration)
        #expect(dimensionType.buildRange == 0...255 && dimensionType.hasCeiling)
        #expect(generator.range == 0..<128)
        #expect(generator.seaLevel == 32)
        #expect(generator.surfaceRuleRange(in: dimensionType).upperBound - 1 == 127)
        #expect(settings["minecraft:the_nether"]?.type?.hasCeiling == false)
        #expect(settings["minecraft:the_nether"]?.noiseGeneration?.range == 0..<256)
        #expect(settings["minecraft:the_nether"]?.noiseGeneration?.seaLevel == -64)
        let inline = try #require(settings["example:inline"])
        #expect(inline.noiseGeneration?.surfaceRuleRange(in: try #require(inline.type)) == 0..<128)
        #expect(inline.noiseGeneration?.seaLevel == nil)
        #expect(try world.dimensionTypes() == settings.compactMapValues(\.type))
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func vanillaNoiseBoundsMatchTheSevenVerifiedDefinitions() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = ["overworld": -64..<320, "amplified": -64..<320, "large_biomes": -64..<320,
                        "nether": 0..<128, "end": 0..<128, "caves": -64..<128, "floating_islands": 0..<256]
        let definitions = expected.mapValues { _ in type() }
            .map { name, dimensionType in ("example:" + name, definition(type: dimensionType, noise: .string(name))) }
        let world = try world(at: root, definitions: Dictionary(uniqueKeysWithValues: definitions))
        let settings = try world.dimensionSettings()
        for (name, range) in expected { #expect(settings["example:" + name]?.noiseGeneration?.range == range) }
        let seaLevels = ["overworld": 63, "amplified": 63, "large_biomes": 63,
                         "nether": 32, "end": 0, "caves": 32, "floating_islands": -64]
        for (name, seaLevel) in seaLevels { #expect(settings["example:" + name]?.noiseGeneration?.seaLevel == seaLevel) }
    }

    @Test func surfaceAnchorsUseGenerationContextRatherThanAHeightIntersection() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, definitions: [
            "example:offset": definition(type: type(minY: -64, height: 128), noise: noise(minY: 0, height: 128)),
            "example:empty": definition(type: type(), noise: noise(minY: 16, height: 0)),
        ])
        let settings = try world.dimensionSettings()
        let offset = try #require(settings["example:offset"])
        #expect(offset.type?.buildRange == -64...63)
        // WorldGenerationContext takes max(minima) and min(heights), not intersected endpoints.
        #expect(offset.noiseGeneration?.surfaceRuleRange(in: try #require(offset.type)) == 0..<128)
        let empty = try #require(settings["example:empty"])
        #expect(empty.noiseGeneration?.range.isEmpty == true)
        #expect(empty.noiseGeneration?.surfaceRuleRange(in: try #require(empty.type)).isEmpty == true)
    }

    @Test func inlineLegacySettingsRemainReadableWithoutKnownVanillaDefaults() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, definitions: [
            "example:inline": definition(type: type(), noise: noise(minY: -2032, height: 4064, seaLevel: .int(47))),
            "example:reference": definition(type: .string("the_nether"), noise: .string("nether")),
        ], version: 9999, modern: false)
        let settings = try world.dimensionSettings()
        #expect(settings["example:inline"]?.noiseGeneration?.range == -2032..<2032)
        #expect(settings["example:inline"]?.noiseGeneration?.seaLevel == 47)
        #expect(settings["example:inline"]?.type?.buildRange == 0...255)
        #expect(settings["example:reference"]?.type == nil)
        #expect(settings["example:reference"]?.noiseGeneration == nil)
    }

    @Test func onlyTheSavedNoiseGeneratorUsesTheseSettingsAndAliasesRemainAmbiguous() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, definitions: [
            "example:short": definition(type: type(), noise: noise(), generator: "noise"),
            "example:empty_namespace": definition(type: type(), noise: noise(), generator: ":noise"),
            "example:foreign": definition(type: type(), noise: noise(), generator: "example:noise"),
            "example:flat": definition(type: type(), noise: noise(), generator: "minecraft:flat"),
            "example:invalid": definition(type: type(), noise: noise(), generator: "Bad ID"),
            "overworld": definition(type: type(), noise: noise()),
            "minecraft:overworld": definition(type: type(), noise: noise()),
            "invalid ID": definition(type: type(), noise: noise()),
        ])
        let settings = try world.dimensionSettings()
        #expect(settings.count == 5)
        #expect(settings["example:short"]?.noiseGeneration?.height == 128)
        #expect(settings["example:empty_namespace"]?.noiseGeneration?.height == 128)
        for id in ["foreign", "flat", "invalid"] {
            #expect(settings["example:" + id]?.noiseGeneration == nil)
            #expect(settings["example:" + id]?.type?.hasCeiling == true)
        }
    }

    @Test func malformedBoundsStayUnavailableWithoutDiscardingTheType() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid: [NBT] = [noise(minY: -2033), noise(minY: 2032, height: 0), noise(minY: 1),
                             noise(height: -16), noise(height: 17), noise(height: 4080),
                             noise(minY: 2016, height: 32), noise(minY: .max), noise(height: .max),
                             .compound([:]), .compound(["noise": .compound(["min_y": .float(0), "height": .int(128)])])]
        let world = try world(at: root, definitions: Dictionary(uniqueKeysWithValues: invalid.enumerated().map {
            ("example:bad\($0.offset)", definition(type: type(), noise: $0.element))
        }))
        let settings = try world.dimensionSettings()
        #expect(settings.count == invalid.count)
        #expect(settings.values.allSatisfy { $0.type != nil && $0.noiseGeneration == nil })
    }

    @Test func noiseResourcesSharePackPriorityAndMalformedOverridesBlockFallback() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try pack("Lower", at: root, json: "{\"noise\":{\"min_y\":-64,\"height\":192},\"sea_level\":-32}")
        let upper = try pack("Upper", at: root, json: "{\"noise\":{\"min_y\":0,\"height\":64},\"sea_level\":47}")
        let world = try world(at: root, definitions: ["example:mine": definition(type: type(), noise: .string("example:custom"))],
                              packs: ["vanilla", "file/Lower", "file/Upper"])
        #expect(try world.dimensionSettings()["example:mine"]?.noiseGeneration?.range == 0..<64)
        #expect(try world.dimensionSettings()["example:mine"]?.noiseGeneration?.seaLevel == 47)
        try FileManager.default.removeItem(at: upper)
        #expect(try world.dimensionSettings()["example:mine"]?.noiseGeneration?.range == -64..<128)
        #expect(try world.dimensionSettings()["example:mine"]?.noiseGeneration?.seaLevel == -32)
        for bad in ["{}", "{\"noise\":{\"min_y\":0.5,\"height\":128}}", "{\"noise\":{\"min_y\":0,\"height\":1e100}}"] {
            try Fixtures.write(Array(bad.utf8), to: upper)
            let value = try #require(try world.dimensionSettings()["example:mine"])
            #expect(value.type?.height == 256 && value.noiseGeneration == nil)
        }
    }

    @Test func inlineSeaLevelsKeepReadableBoundsAndDoNotClampToTheirRange() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(NBT?, Int?)] = [
            (.int(0), 0), (.int(-64), -64), (.int(10_000), 10_000),
            (.int(.min), Int(Int32.min)), (.long(Int64(Int32.max)), Int(Int32.max)),
            (nil, nil), (.string("63"), nil), (.float(63), nil), (.compound([:]), nil),
            (.long(Int64(Int32.min) - 1), nil), (.long(Int64(Int32.max) + 1), nil),
        ]
        let definitions = Dictionary(uniqueKeysWithValues: cases.enumerated().map {
            ("example:case\($0.offset)", definition(type: type(), noise: noise(seaLevel: $0.element.0)))
        })
        let settings = try world(at: root, definitions: definitions).dimensionSettings()
        for (index, entry) in cases.enumerated() {
            let generation = try #require(settings["example:case\(index)"]?.noiseGeneration)
            #expect(generation.range == 0..<128)
            #expect(generation.seaLevel == entry.1)
        }
    }

    @Test func JSONSeaLevelValidationNeverFallsBackToAnotherResource() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try pack("Lower", at: root, json: "{\"noise\":{\"min_y\":-64,\"height\":192},\"sea_level\":32}")
        let upper = try pack("Upper", at: root)
        let world = try world(at: root, definitions: ["example:mine": definition(type: type(), noise: .string("example:custom"))],
                              packs: ["vanilla", "file/Lower", "file/Upper"])
        let cases: [(String?, Int?)] = [
            ("-64", -64), ("0", 0), ("2147483647", Int(Int32.max)), ("-2147483648", Int(Int32.min)),
            (nil, nil), ("null", nil), ("true", nil), ("\"63\"", nil), ("1.5", nil),
            ("2147483648", nil), ("-2147483649", nil), ("{}", nil),
        ]
        for (raw, expected) in cases {
            let field = raw.map { ",\"sea_level\":\($0)" } ?? ""
            try Fixtures.write(Array("{\"noise\":{\"min_y\":0,\"height\":64}\(field)}".utf8), to: upper)
            let generation = try #require(try world.dimensionSettings()["example:mine"]?.noiseGeneration)
            #expect(generation.range == 0..<64)
            #expect(generation.seaLevel == expected)
        }
    }

    @Test(arguments: ["file/Missing", "file/Archive.zip", "unknown_builtin", "file/../Outside",
                      "file/Overlay", "file/Filtered"])
    func unsupportedHigherPacksLeaveReferencedNoiseUnknown(packID: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.write([0], to: root.appendingPathComponent("datapacks/Archive.zip"))
        _ = try pack("Overlay", at: root, metadata: "{\"pack\":{},\"overlays\":{\"entries\":[]}}")
        _ = try pack("Filtered", at: root, metadata: "{\"pack\":{},\"filter\":{\"block\":[]}}")
        let world = try world(at: root, definitions: ["example:mine": definition(type: type(), noise: .string("nether")),
                                                      "example:inline": definition(type: type(), noise: noise())],
                              packs: ["vanilla", packID])
        let settings = try world.dimensionSettings()
        #expect(settings["example:mine"]?.type != nil && settings["example:mine"]?.noiseGeneration == nil)
        #expect(settings["example:inline"]?.noiseGeneration?.height == 128)
    }

    @Test func noisePathsStayInThePackAndTypeOnlyReadsDoNotOpenGeneratorFiles() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try pack("Custom", at: root)
        let outside = root.appendingPathComponent("outside.json")
        try FileManager.default.copyItem(at: file, to: outside)
        try FileManager.default.createSymbolicLink(at: file.deletingLastPathComponent().appendingPathComponent("escape.json"),
                                                   withDestinationURL: outside)
        let directory = file.deletingLastPathComponent().appendingPathComponent("directory.json")
        let world = try world(at: root, definitions: [
            "example:escape": definition(type: type(), noise: .string("example:escape")),
            "example:dot": definition(type: type(), noise: .string("example:../outside")),
            "example:read_error": definition(type: type(), noise: .string("example:directory")),
        ], packs: ["file/Custom"])
        #expect(try world.dimensionSettings().values.allSatisfy { $0.noiseGeneration == nil })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        #expect(try world.dimensionTypes().count == 3)
        #expect(throws: (any Error).self) { try world.dimensionSettings() }
    }

    @Test func anExistingModernRecordDoesNotResurrectLegacyGenerationSettings() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, definitions: ["example:mine": definition(type: type(), noise: noise())], modern: false)
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5023), "data": .compound([:])]),
                                    to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        #expect(try world.dimensionSettings().isEmpty)
    }
}
