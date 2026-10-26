import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct DimensionTimeTests {
    @Test func inlineMetadataPreservesClocksFlagsAndTimelineReferences() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "test:sky": definition(["default_clock": .string("custom:moon"), "timelines": .string("#custom:night")]),
            "test:fixed": definition(["has_fixed_time": .byte(1), "has_skylight": .byte(0)]),
            "test:single": definition(["timelines": .string("day")]),
            "test:list": definition(["timelines": .list(.string, [.string("day"), .string("custom:moon"), .string("day")])])
        ], packs: ["file/Unavailable"])
        let types = try world.dimensionTypes(assets: nil)
        let sky = try #require(types["test:sky"]?.time)
        #expect(sky.hasSkylight && !sky.hasFixedTime)
        #expect(sky.defaultClock == "custom:moon" && sky.timelines == .tag("custom:night"))
        let fixed = try #require(types["test:fixed"]?.time)
        #expect(fixed.hasFixedTime && !fixed.hasSkylight && fixed.defaultClock == nil && fixed.timelines == .list([]))
        #expect(types["test:single"]?.time?.timelines == .list(["minecraft:day"]))
        #expect(types["test:list"]?.time?.timelines == .list(["minecraft:day", "custom:moon", "minecraft:day"]))
    }

    @Test func selectedJarSuppliesDefinitionsAndAbsentResourcesStayUnknown() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:sky": .string("overworld"), "test:moon": .string("test:moon")])
        let assets = try assets([entry("minecraft:overworld", json(["default_clock": "test:sun", "timelines": "#day"])),
                                 entry("test:moon", json(["has_fixed_time": true, "default_clock": "test:moon"]))])
        let paths = ["level.dat", "data/minecraft/world_gen_settings.dat"].map { root.appendingPathComponent($0) }
        let before = try paths.map { try Data(contentsOf: $0) }
        #expect(try world.dimensionTypes(assets: nil)["test:sky"]?.time == nil)
        #expect(try world.dimensionTypes(assets: nil)["test:sky"] == nil)
        let types = try world.dimensionTypes(assets: assets)
        #expect(types["test:sky"]?.time?.defaultClock == "test:sun")
        #expect(types["test:sky"]?.time?.timelines == .tag("minecraft:day"))
        #expect(types["test:moon"]?.time?.hasFixedTime == true)
        #expect(try world.dimensionSettings(assets: assets).mapValues(\.type) == types.mapValues(Optional.some))
        #expect(try paths.map { try Data(contentsOf: $0) } == before)
    }

    @Test(arguments: [nil, 1, 5023, Int32.max] as [Int32?])
    func readableTypesIgnoreWorldAndJarVersionLabels(version: Int32?) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["overworld": .string("overworld"), "custom:sky": .string("custom:sky"),
                                            "test:inline": definition()], version: version)
        #expect(try world.dimensionTypes(assets: nil)["minecraft:overworld"] == nil)
        for jarVersion: Int32 in [1, 5023, .max] {
            let jar = try assets([entry("minecraft:overworld", json())], version: jarVersion)
            let types = try world.dimensionTypes(assets: jar)
            #expect(types["minecraft:overworld"]?.time?.hasSkylight == true)
            #expect(types["minecraft:overworld"]?.buildRange == -64...319)
            #expect(types["custom:sky"] == nil)
            #expect(types["test:inline"]?.time?.hasSkylight == true)
            #expect(try world.dimensionSettings(assets: jar).compactMapValues(\.type) == types)
        }
        let missing = try assets([])
        #expect(try world.dimensionTypes(assets: missing).keys.sorted() == ["test:inline"])
    }

    @Test func folderAndZipOverridesKeepOnePriorityAndInvalidOverridesBlockFallbacks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "data/minecraft/dimension_type/overworld.json"
        let folder = root.appendingPathComponent("datapacks/Low")
        try Fixtures.write(Array(metadata.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        try Fixtures.write(Array(json(["default_clock": "custom:low"]).utf8), to: folder.appendingPathComponent(path))
        let high = root.appendingPathComponent("datapacks/High.zip")
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata),
                                       .init(path: path, text: json(["default_clock": "custom:high"]))]), to: high)
        let world = try world(root, types: ["custom:map": .string("overworld")], packs: ["vanilla", "file/Low", "file/High.zip"])
        let jar = try assets([entry("minecraft:overworld", json(["default_clock": "custom:jar"]))])
        #expect(try world.dimensionTypes(assets: jar)["custom:map"]?.time?.defaultClock == "custom:high")
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata)]), to: high)
        #expect(try world.dimensionTypes(assets: jar)["custom:map"]?.time?.defaultClock == "custom:low")
        try Fixtures.write(Array(json(["default_clock": "Invalid ID"]).utf8), to: folder.appendingPathComponent(path))
        let malformed = try world.dimensionTypes(assets: jar)["custom:map"]
        #expect(malformed?.buildRange == -64...319 && malformed?.time == nil)
        try Fixtures.write(Array("{}".utf8), to: folder.appendingPathComponent(path))
        #expect(try world.dimensionTypes(assets: jar).isEmpty)
    }

    @Test func malformedNBTTimeLeavesIndependentBuildLimitsReadable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad: [[String: NBT]] = [
            ["has_skylight": .string("true")], ["has_fixed_time": .float(1)],
            ["default_clock": .string("Bad ID")], ["default_clock": .compound([:])],
            ["timelines": .list(.string, [.string("#tag")])], ["timelines": .string("#Bad Tag")],
            ["timelines": .list(.int, [.int(1)])], ["timelines": .compound([:])]
        ]
        let types = Dictionary(uniqueKeysWithValues: bad.enumerated().map { ("test:bad\($0.offset)", definition($0.element)) })
        let world = try world(root, types: types)
        let read = try world.dimensionTypes(assets: nil)
        #expect(read.count == bad.count)
        #expect(read.values.allSatisfy { $0.time == nil && $0.buildRange == -64...319 })
    }

    @Test func malformedJSONTimeLeavesIndependentBuildLimitsReadable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad: [[String: Any]] = [
            ["has_skylight": "true"], ["has_skylight": NSNull()], ["has_fixed_time": 1],
            ["default_clock": "Bad ID"], ["timelines": ["#tag"]], ["timelines": [1]], ["timelines": [:]]
        ]
        let entries = try bad.enumerated().map { entry("test:bad\($0.offset)", try json($0.element)) }
        let types = Dictionary(uniqueKeysWithValues: bad.indices.map { ("test:bad\($0)", NBT.string("test:bad\($0)")) })
        let world = try world(root, types: types)
        let read = try world.dimensionTypes(assets: assets(entries))
        #expect(read.count == bad.count)
        #expect(read.values.allSatisfy { $0.time == nil && $0.buildRange == -64...319 })
    }

    @Test func optionalJSONNullsUseTheOfficialCodecDefaults() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:sky": .string("test:sky")])
        let jar = try assets([entry("test:sky", json(["has_fixed_time": NSNull(),
                                                    "default_clock": NSNull(), "timelines": NSNull()]))])
        let time = try #require(try world.dimensionTypes(assets: jar)["test:sky"]?.time)
        #expect(time.hasFixedTime == false && time.hasSkylight == true)
        #expect(time.defaultClock == nil && time.timelines == .list([]))
    }

    @Test func companionQueryUsesTheSameJarWithoutCouplingTypeAndGenerationAvailability() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [:])
        let definition = NBT.compound(["type": .string("test:sky"), "generator": .compound([
            "type": .string("noise"), "settings": .string("test:terrain")
        ])])
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5023), "data": .compound([
            "dimensions": .compound(["test:map": definition])
        ])]), to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        let noise = TestZIP.Entry(path: "data/test/worldgen/noise_settings/terrain.json",
                                  text: #"{"noise":{"min_y":16,"height":64},"sea_level":37}"#)
        let jar = try assets([entry("test:sky", json()), noise])
        let settings = try world.dimensionSettings(assets: jar)["test:map"]
        #expect(settings?.type?.time?.hasSkylight == true)
        #expect(settings?.noiseGeneration?.range == 16..<80 && settings?.noiseGeneration?.seaLevel == 37)
        let badType = try assets([entry("test:sky", "{}"), noise])
        #expect(try world.dimensionSettings(assets: badType)["test:map"]?.type == nil)
        #expect(try world.dimensionSettings(assets: badType)["test:map"]?.noiseGeneration?.seaLevel == 37)
        let badNoise = try assets([entry("test:sky", json()),
                                  .init(path: noise.path, text: "{}")])
        #expect(try world.dimensionTypes(assets: badNoise)["test:map"]?.time?.hasSkylight == true)
        #expect(try world.dimensionSettings(assets: badNoise)["test:map"]?.noiseGeneration == nil)
    }

    @Test func missingPackListAndUnavailableHigherPacksNeverExposeJarMetadata() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try assets([entry("minecraft:overworld", json(["default_clock": "overworld"]))])
        for packs in [[], ["vanilla", "file/Missing"], ["vanilla", "unknown_builtin"]] {
            let world = try world(root, types: ["overworld": .string("overworld"), "test:inline": definition()], packs: packs)
            let types = try world.dimensionTypes(assets: jar)
            #expect(types["minecraft:overworld"] == nil)
            #expect(types["test:inline"]?.time?.hasSkylight == true)
        }
    }

    @Test func savedSettingsTakePrecedenceWithoutVersionGatingAndLegacyLayoutStillResolves() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:sky": definition(["default_clock": .string(":sun")])], modern: false)
        #expect(try world.dimensionTypes(assets: nil)["test:sky"]?.time?.defaultClock == "minecraft:sun")
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(9999), "data": .compound([
            "dimensions": .compound(["test:sky": .compound(["type": definition()])])
        ])]), to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        #expect(try world.dimensionTypes(assets: nil)["test:sky"]?.time?.hasSkylight == true)
        #expect(try world.dimensionTypes(assets: nil)["test:sky"]?.time?.defaultClock == nil)
        #expect(try world.dimensionTypes(assets: nil)["test:sky"]?.buildRange == -64...319)
    }

    @Test func resourceBoundsPreserveInlineFactsAndCancellationStopsInlineOnlyQueries() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:inline": definition(), "test:reference": .string("overworld")],
                              packs: Array(repeating: "vanilla", count: 65))
        let jar = try assets([entry("minecraft:overworld", json())])
        #expect(try world.dimensionTypes(assets: jar).keys.sorted() == ["test:inline"])
        let inline = try self.world(root, types: ["test:inline": definition()])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try inline.dimensionSettings(assets: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Synthetic time metadata"}}"#

    private func definition(_ extra: [String: NBT] = [:]) -> NBT {
        .compound(["min_y": .int(-64), "height": .int(384), "logical_height": .int(384),
                   "has_ceiling": .byte(0), "has_skylight": .byte(1)].merging(extra) { _, new in new })
    }

    private func json(_ extra: [String: Any] = [:]) throws -> String {
        let fields: [String: Any] = ["min_y": -64, "height": 384, "logical_height": 384,
                                    "has_ceiling": false, "has_skylight": true]
        return String(decoding: try JSONSerialization.data(withJSONObject: fields.merging(extra) { _, new in new }), as: UTF8.self)
    }

    private func entry(_ id: String, _ json: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":")
        return .init(path: "data/\(parts[0])/dimension_type/\(parts[1]).json", text: json)
    }

    private func assets(_ entries: [TestZIP.Entry], version: Int32 = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":\#(version)}"#)
        ] + entries))))
    }

    private func world(_ root: URL, types: [String: NBT], packs: [String] = ["vanilla"],
                       version: Int32? = 5023, modern: Bool = true) throws -> World {
        let settings = NBT.compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        var fields: [String: NBT] = ["LevelName": .string("Dimension Time"),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))])]
        fields["DataVersion"] = version.map(NBT.int)
        if modern {
            var record = ["data": settings]
            record["DataVersion"] = version.map(NBT.int)
            try Fixtures.writeGzippedNBT(.compound(record),
                                         to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        } else { fields["WorldGenSettings"] = settings }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }
}
