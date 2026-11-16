@testable import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct DimensionBaseLightingTests {
    @Test func defaultsAndInlineOverridesDoNotDependOnDimensionNamesOrFixedTime() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "custom:sky": definition(),
            "minecraft:the_nether": definition(["has_fixed_time": .byte(1), "has_skylight": .byte(0)]),
            "custom:dark": definition(["attributes": .compound([
                "visual/sun_angle": .double(-72.5), "minecraft:visual/moon_angle": .int(450),
                "minecraft:visual/sky_light_factor": .float(0.25),
                "minecraft:visual/sky_light_color": .string("#123456"),
                "minecraft:visual/moon_phase": .string("new_moon")
            ])])
        ])
        let types = try world.dimensionTypes(assets: nil)
        #expect(types["custom:sky"]?.baseSkyLighting == defaults)
        #expect(types["minecraft:the_nether"]?.baseSkyLighting == defaults)
        let dark = try #require(types["custom:dark"]?.baseSkyLighting)
        #expect(dark.sunAngle == -72.5 && dark.moonAngle == 450 && dark.skyLightFactor == 0.25)
        #expect(dark.skyLightColor == SIMD3<Float>(18, 52, 86) / 255 && dark.moonPhase == .newMoon)
    }

    @Test func modifiersAndTimelinesComposeWithoutPrematureRangeClamping() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attributes: [String: NBT] = [
            "visual/sun_angle": operation("subtract", .float(25)),
            "visual/moon_angle": operation("maximum", .int(450)),
            "visual/sky_light_factor": operation("multiply", .int(2)),
            "visual/sky_light_color": operation("multiply", .list(.float, [.float(0.5), .float(-0.25), .float(1.5)])),
            "visual/moon_phase": operation("override", .string("waxing_crescent"))
        ]
        let world = try world(root, types: ["test:map": definition(["attributes": .compound(attributes)])])
        let base = try #require(try world.dimensionTypes(assets: nil)["test:map"]?.baseSkyLighting)
        #expect(base.sunAngle == -25 && base.moonAngle == 450 && base.skyLightFactor == 2)
        #expect(base.skyLightColor == SIMD3(0.5, -0.25, 1.5) && base.moonPhase == .waxingCrescent)
        let jar = try assets([.init(path: "data/test/timeline/day.json", text: #"{"clock":"test:clock","tracks":{"visual/sky_light_factor":{"modifier":"multiply","keyframes":[{"ticks":0,"value":0.25}]}}}"#)])
        let sampled = try #require(jar.lightingTimeline("test:day")?.applying(at: 0, to: base))
        #expect(sampled.skyLightFactor == 0.5 && sampled.sunAngle == base.sunAngle && sampled.moonPhase == base.moonPhase)
    }

    @Test func jsonDefaultsModifiersAndFloatColorPrecisionMatchInlineForms() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definitions = try [
            "missing": json(), "empty": json(["attributes": [:]]), "null": json(["attributes": NSNull()]),
            "changed": json(["attributes": [
                "visual/sun_angle": ["modifier": "add", "argument": -72.5],
                "visual/sky_light_color": [0.12345, -0.25, 1.5],
                "visual/moon_phase": ["modifier": "override", "argument": "third_quarter"],
                "visual/fog_color": ["unrelated": "not decoded"]
            ]])
        ]
        let world = try world(root, types: Dictionary(uniqueKeysWithValues: definitions.keys.map { ("test:" + $0, NBT.string("test:" + $0)) }))
        let jar = try assets(definitions.map { entry("test:" + $0.key, $0.value) })
        let types = try world.dimensionTypes(assets: jar)
        for name in ["missing", "empty", "null"] { #expect(types["test:" + name]?.baseSkyLighting == defaults) }
        let changed = try #require(types["test:changed"]?.baseSkyLighting)
        #expect(changed.sunAngle == -72.5 && changed.moonPhase == .thirdQuarter)
        #expect(changed.skyLightColor == SIMD3<Float>(0.12345, -0.25, 1.5))
    }

    @Test func nbtColorFormsUseSignedNumbersAndPreserveThreeChannels() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let colors: [(NBT, SIMD3<Float>)] = [
            (.string("#123456"), SIMD3<Float>(18, 52, 86) / 255),
            (.int(-15584170), SIMD3<Float>(18, 52, 86) / 255),
            (.list(.float, [.float(0.12345), .float(-0.25), .float(1.5)]), SIMD3(0.12345, -0.25, 1.5)),
            (.list(.compound, [.compound(["": .double(0.12345)]), .compound(["": .float(-0.25)]),
                               .compound(["": .float(1.5)])]), SIMD3(0.12345, -0.25, 1.5)),
            (.byteArray([-1, 0, 1]), SIMD3(-1, 0, 1)),
            (.intArray([-1, 0, 2]), SIMD3(-1, 0, 2)),
            (.longArray([-2, 1, 3]), SIMD3(-2, 1, 3))
        ]
        let types = Dictionary(uniqueKeysWithValues: colors.enumerated().map {
            ("test:color\($0.offset)", definition(["attributes": .compound(["visual/sky_light_color": $0.element.0])]))
        })
        let read = try world(root, types: types).dimensionTypes(assets: nil)
        for (index, color) in colors.enumerated() { #expect(read["test:color\(index)"]?.baseSkyLighting?.skyLightColor == color.1) }
    }

    @Test func nativePackedColorsChooseTheIntegerCodecBeforeFloatingConversion() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Actual EnvironmentAttributeMap.CODEC outputs from the #316 field proof. A large
        // Long retains its low bits; a fractional or nonfinite number is still a packed INT.
        let colors: [(NBT, SIMD3<Float>)] = [
            (.long(9_007_199_254_740_993), SIMD3(0, 0, Float(bitPattern: 0x3b808081))),
            (.float(1.5), SIMD3(0, 0, Float(bitPattern: 0x3b808081))),
            (.double(.infinity), SIMD3(repeating: 1)),
            (.double(.nan), SIMD3(repeating: 0))
        ]
        let types = Dictionary(uniqueKeysWithValues: colors.enumerated().map {
            ("test:numeric\($0.offset)", definition(["attributes": .compound(["visual/sky_light_color": $0.element.0])]))
        })
        let world = try world(root, types: types)
        let path = root.appendingPathComponent("level.dat")
        let saved = try Data(contentsOf: path)
        let read = try world.dimensionTypes(assets: nil)
        for (index, color) in colors.enumerated() {
            let type = try #require(read["test:numeric\(index)"])
            #expect(type.baseSkyLighting?.skyLightColor == color.1)
            #expect(type.buildRange == -64...319 && type.time?.hasSkylight == true)
        }
        #expect(try Data(contentsOf: path) == saved)
    }

    @Test func nativeAndJSONLargePackedColorsHaveTheSameMeaning() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let packed: Int64 = 9_007_199_254_740_993
        let world = try world(root, types: [
            "test:inline": definition(["attributes": .compound(["visual/sky_light_color": .long(packed)])]),
            "test:resource": .string("test:resource")
        ])
        let jar = try assets([entry("test:resource", json(["attributes": ["visual/sky_light_color": packed]]))])
        let types = try world.dimensionTypes(assets: jar)
        let inline = try #require(types["test:inline"]?.baseSkyLighting)
        #expect(types["test:resource"]?.baseSkyLighting == inline)
        #expect(inline.skyLightColor.z.bitPattern == 0x3b808081)
    }

    @Test func overflowingJSONAndNativeModifierArgumentsKeepTheSameFiniteResult() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let native: [String: NBT] = [
            "visual/sky_light_factor": operation("minimum", .float(.infinity)),
            "visual/sky_light_color": operation("subtract", .list(.float, [.float(.infinity), .float(0), .float(0)]))
        ]
        let world = try world(root, types: ["test:inline": definition(["attributes": .compound(native)]),
                                           "test:resource": .string("test:resource")])
        let jar = try assets([entry("test:resource", json(["attributes": [
            "visual/sky_light_factor": ["modifier": "minimum", "argument": 1e100],
            "visual/sky_light_color": ["modifier": "subtract", "argument": [1e100, 0, 0]]
        ]]))])
        let types = try world.dimensionTypes(assets: jar)
        let inline = try #require(types["test:inline"]?.baseSkyLighting)
        #expect(types["test:resource"]?.baseSkyLighting == inline)
        #expect(inline.skyLightFactor == 1 && inline.skyLightColor == SIMD3(0, 1, 1))
    }

    @Test func malformedNBTLightingDoesNotDiscardIndependentBuildAndTimeMetadata() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad: [NBT] = [
            .list(.int, []),
            .compound(["visual/sky_light_factor": .float(2)]),
            .compound(["visual/sky_light_factor": operation("override", .float(-1))]),
            .compound(["visual/sun_angle": .double(.nan)]),
            .compound(["visual/moon_angle": .double(.infinity)]),
            .compound(["visual/sun_angle": .double(Double.greatestFiniteMagnitude)]),
            .compound(["visual/moon_phase": .string("unknown")]),
            .compound(["visual/moon_phase": operation("add", .string("new_moon"))]),
            .compound(["visual/sun_angle": .compound(["argument": .int(1)])]),
            .compound(["visual/sun_angle": .compound(["modifier": .string("override")])]),
            .compound(["visual/sky_light_color": .list(.float, [.float(1), .float(2)])]),
            .compound(["visual/sky_light_color": .list(.compound, [.compound(["": .int(1), "extra": .int(2)]),
                                                                    .compound(["": .int(0)]), .compound(["": .int(0)])])]),
            .compound(["visual/sky_light_color": .list(.compound, [.compound(["": .compound(["": .int(1)])]),
                                                                    .compound(["": .int(0)]), .compound(["": .int(0)])])]),
            .compound(["visual/sky_light_color": operation("minimum", .string("#123456"))]),
            .compound(["visual/sun_angle": operation("alpha_blend", .compound(["value": .int(25), "alpha": .float(0.5)]))]),
            .compound(["visual/sun_angle": .float(1), "minecraft:visual/sun_angle": .float(2)])
        ]
        let types = Dictionary(uniqueKeysWithValues: bad.enumerated().map {
            ("test:bad\($0.offset)", definition(["attributes": $0.element]))
        })
        let read = try world(root, types: types).dimensionTypes(assets: nil)
        #expect(read.count == bad.count)
        #expect(read.values.allSatisfy { $0.baseSkyLighting == nil && $0.buildRange == -64...319 && $0.time?.hasSkylight == true })
    }

    @Test func malformedJSONLightingAndAmbiguousAliasesStayUnavailable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad: [Any] = [
            [], ["visual/sun_angle": true], ["visual/sun_angle": NSNull()],
            ["visual/sky_light_factor": 2], ["visual/moon_phase": "unknown"],
            ["visual/sun_angle": ["modifier": NSNull(), "argument": 1]],
            ["visual/sun_angle": ["argument": 1]], ["visual/sun_angle": ["modifier": "override"]],
            ["visual/sky_light_color": [true, 0, 1]], ["visual/sky_light_color": "#123"],
            ["visual/sky_light_color": ["modifier": "alpha_blend", "argument": "#80ff0000"]],
            ["visual/sun_angle": 1, ":visual/sun_angle": 2]
        ]
        let jar = try assets(bad.enumerated().map { entry("test:bad\($0.offset)", try json(["attributes": $0.element])) })
        let types = Dictionary(uniqueKeysWithValues: bad.indices.map { ("test:bad\($0)", NBT.string("test:bad\($0)")) })
        let read = try world(root, types: types).dimensionTypes(assets: jar)
        #expect(read.count == bad.count)
        #expect(read.values.allSatisfy { $0.baseSkyLighting == nil && $0.buildRange == -64...319 && $0.time?.hasSkylight == true })
    }

    @Test func readableDefinitionsSupplyLightingIndependentlyOfVersionLabels() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["overworld": .string("overworld"), "test:inline": definition()])
        let wrong = try assets([entry("minecraft:overworld", json())], version: 9999)
        #expect(try world.dimensionTypes(assets: nil)["minecraft:overworld"] == nil)
        for jar in [wrong, try assets([entry("minecraft:overworld", json())])] {
            let types = try world.dimensionTypes(assets: jar)
            #expect(types["minecraft:overworld"]?.baseSkyLighting == defaults)
            #expect(types["minecraft:overworld"]?.buildRange == -64...319)
            #expect(types["test:inline"]?.baseSkyLighting == defaults)
        }
        let correct = try assets([entry("minecraft:overworld", json())])
        #expect(try world.dimensionTypes(assets: correct)["minecraft:overworld"]?.baseSkyLighting == defaults)
        let empty = try assets([])
        #expect(try world.dimensionTypes(assets: empty)["minecraft:overworld"] == nil)
        let pack = root.appendingPathComponent("datapacks/Unknown")
        try Fixtures.write(Array(metadata.utf8), to: pack.appendingPathComponent("pack.mcmeta"))
        try Fixtures.write(Array(json().utf8), to: pack.appendingPathComponent("data/test/dimension_type/json.json"))
        let unknown = try self.world(root, types: ["test:inline": definition(), "test:json": .string("test:json")],
                                    packs: ["file/Unknown"], version: 9999)
        let unknownTypes = try unknown.dimensionTypes(assets: nil)
        #expect(unknownTypes.count == 2 && unknownTypes.values.allSatisfy { $0.baseSkyLighting == defaults && $0.buildRange == -64...319 })
    }

    @Test func folderAndZipPriorityNeverFallsBackBehindBadAttributesOrMissingPacks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "data/test/dimension_type/sky.json"
        let folder = root.appendingPathComponent("datapacks/Low")
        try Fixtures.write(Array(metadata.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        try Fixtures.write(Array(json(["attributes": ["visual/sun_angle": 1]]).utf8), to: folder.appendingPathComponent(path))
        let high = root.appendingPathComponent("datapacks/High.zip")
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata), .init(path: path, text: json(["attributes": ["visual/sun_angle": 2]]))]), to: high)
        let world = try world(root, types: ["test:map": .string("test:sky")], packs: ["vanilla", "file/Low", "file/High.zip"])
        let jar = try assets([entry("test:sky", json(["attributes": ["visual/sun_angle": 3]]))])
        #expect(try world.dimensionTypes(assets: jar)["test:map"]?.baseSkyLighting?.sunAngle == 2)
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata)]), to: high)
        #expect(try world.dimensionTypes(assets: jar)["test:map"]?.baseSkyLighting?.sunAngle == 1)
        try Fixtures.write(Array(json(["attributes": ["visual/sun_angle": "invalid"]]).utf8), to: folder.appendingPathComponent(path))
        let invalid = try world.dimensionTypes(assets: jar)["test:map"]
        #expect(invalid?.baseSkyLighting == nil && invalid?.time?.hasSkylight == true && invalid?.buildRange == -64...319)
        let missing = try self.world(root, types: ["test:map": .string("test:sky"), "test:inline": definition()], packs: ["vanilla", "file/Missing"])
        #expect(try missing.dimensionTypes(assets: jar)["test:map"] == nil)
        #expect(try missing.dimensionTypes(assets: jar)["test:inline"]?.baseSkyLighting == defaults)
    }

    @Test func attributeCountIsBoundedBeforeDecodingRelevantEntries() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attributes = Dictionary(uniqueKeysWithValues: (0..<256).map { ("custom:ignored\($0)", NBT.compound([:])) })
        let excessive = attributes.merging(["visual/sun_angle": .float(5)]) { _, new in new }
        let world = try world(root, types: ["test:limit": definition(["attributes": .compound(attributes)]),
                                          "test:excessive": definition(["attributes": .compound(excessive)])])
        #expect(try world.dimensionTypes(assets: nil)["test:limit"]?.baseSkyLighting == defaults)
        #expect(try world.dimensionTypes(assets: nil)["test:excessive"]?.baseSkyLighting == nil)
    }

    private var defaults: SkyLighting {
        SkyLighting(sunAngle: 0, moonAngle: 0, skyLightFactor: 1, skyLightColor: SIMD3(repeating: 1), moonPhase: .fullMoon)!
    }
    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Synthetic lighting"}}"#
    private func operation(_ modifier: String, _ argument: NBT) -> NBT {
        .compound(["modifier": .string(modifier), "argument": argument])
    }
    private func definition(_ extra: [String: NBT] = [:]) -> NBT {
        .compound(["min_y": .int(-64), "height": .int(384), "logical_height": .int(384),
                   "has_ceiling": .byte(0), "has_skylight": .byte(1)].merging(extra) { _, new in new })
    }
    private func json(_ extra: [String: Any] = [:]) throws -> String {
        let fields: [String: Any] = ["min_y": -64, "height": 384, "logical_height": 384, "has_ceiling": false, "has_skylight": true]
        return String(decoding: try JSONSerialization.data(withJSONObject: fields.merging(extra) { _, new in new }), as: UTF8.self)
    }
    private func entry(_ id: String, _ json: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":")
        return .init(path: "data/\(parts[0])/dimension_type/\(parts[1]).json", text: json)
    }
    private func assets(_ entries: [TestZIP.Entry], version: Int32 = 5023) throws -> GameAssets {
        let archive = try TestZIP.zip([.init(path: "version.json", text: #"{"id":"fixture","world_version":\#(version)}"#)] + entries)
        return try #require(GameAssets(data: Data(archive)))
    }
    private func world(_ root: URL, types: [String: NBT], packs: [String] = ["vanilla"], version: Int32 = 5023) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Base Lighting"), "DataVersion": .int(version),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))]),
            "WorldGenSettings": .compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        ])]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }
}
