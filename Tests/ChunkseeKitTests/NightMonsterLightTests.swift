import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct NightMonsterLightTests {
    private let point = BlockPosition(blockX: 0, blockY: 64, blockZ: 0)

    @Test func torchLightAndOpenNightSkyUseBothDimensionLimits() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:world": definition()])
        let rules = try #require(try world.nightMonsterLighting(assets: nil)["test:world"])
        #expect(rules.skyDarkening == 11)
        for light in 0...15 {
            #expect(rules.canPass(blockLight: light, skyLight: 15, at: point) == (light == 0))
        }
        let block: [Int8] = (0..<2048).map { index in
            let low = UInt8((index & 7) * 2)
            return Int8(bitPattern: low | ((low + 1) << 4))
        }
        let chunk = try lightChunk(block: block, sky: Array(repeating: -1, count: 2048))
        #expect(rules.canPass(in: chunk, x: 0, y: 0, z: 0) == true)
        #expect(rules.canPass(in: chunk, x: 1, y: 0, z: 0) == false)
        #expect(rules.canPass(in: chunk, x: 15, y: 0, z: 0) == false)
    }

    @Test func noSkyDimensionStillAppliesItsRawThresholdWithoutRequiringASkyArray() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:nether": definition(sky: false, limit: 15, threshold: 7,
            extra: ["timelines": .string("missing:timeline"), "attributes": .string("unreadable sky")])])
        let rules = try #require(try world.nightMonsterLighting(assets: nil)["test:nether"])
        #expect(rules.skyDarkening == nil)
        for light in 0...15 { #expect(rules.canPass(blockLight: light, skyLight: nil, at: point) == (light <= 7)) }
        let chunk = try lightChunk(block: Array(repeating: 0x77, count: 2048), sky: nil)
        #expect(rules.canPass(in: chunk, x: 0, y: 0, z: 0) == true)
    }

    @Test func missingStaleMalformedAndSkippedLightNeverBecomeDarkness() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rules = try #require(try world(root, types: ["test:a": definition()]).nightMonsterLighting(assets: nil)["test:a"])
        let zero = [Int8](repeating: 0, count: 2048)
        for invalid: [Int8]? in [nil, [], [0], Array(repeating: 0, count: 2049)] {
            #expect(try rules.canPass(in: lightChunk(block: invalid, sky: zero), x: 0, y: 0, z: 0) == nil)
            #expect(try rules.canPass(in: lightChunk(block: zero, sky: invalid), x: 0, y: 0, z: 0) == nil)
        }
        #expect(try rules.canPass(in: lightChunk(block: zero, sky: zero, valid: false), x: 0, y: 0, z: 0) == nil)
        let chunk = try lightChunk(block: zero, sky: zero)
        for (x, y, z) in [(-1, 0, 0), (16, 0, 0), (0, 0, -1), (0, 0, 16), (0, 16, 0), (0, Int.max, 0)] {
            #expect(rules.canPass(in: chunk, x: x, y: y, z: z) == nil)
        }
        #expect(rules.canPass(blockLight: nil, skyLight: 0, at: point) == nil)
        #expect(rules.canPass(blockLight: 0, skyLight: nil, at: point) == nil)
        #expect(rules.canPass(blockLight: -1, skyLight: 0, at: point) == nil)
        #expect(rules.canPass(blockLight: 0, skyLight: 16, at: point) == nil)
    }

    @Test func customMidnightAndGameplayTrackNeverUseSavedClockOrVisualBrightness() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:a": definition(extra: [
            "timelines": .string("test:night"), "attributes": .compound(["visual/sky_light_factor": .float(0)])
        ])])
        let path = root.appendingPathComponent("data/minecraft/world_clocks.dat")
        try Fixtures.write([255, 1, 2], to: path)
        let before = try Data(contentsOf: path)
        let jar = try assets([timeline("night", marker: 25, frames: [(0, 15), (50, 0)])])
        let rules = try #require(try world.nightMonsterLighting(assets: jar)["test:a"])
        #expect(rules.skyDarkening == 7) // 15 minus the declared 7.5 sky level, rounded as Java.
        #expect(rules.canPass(blockLight: 0, skyLight: 15, at: point) == false)
        let later = try assets([timeline("night", marker: ["ticks": 50, "show_in_commands": true], frames: [(0, 15), (50, 0)])])
        #expect(try world.nightMonsterLighting(assets: later)["test:a"]?.skyDarkening == 15)
        #expect(try Data(contentsOf: path) == before)
    }

    @Test func staticAttributesClampOnlyAfterCompositionAndStayIndependentOfVisualFields() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "test:low": definition(extra: ["attributes": .compound(["gameplay/sky_light_level": .compound([
                "modifier": .string("subtract"), "argument": .float(30)])])]),
            "test:high": definition(extra: ["attributes": .compound(["gameplay/sky_light_level": .compound([
                "modifier": .string("add"), "argument": .float(30)])])]),
            "test:bad_visual": definition(extra: ["attributes": .compound([
                "gameplay/sky_light_level": .float(4), "visual/sun_angle": .string("bad")])]),
            "test:bad_gameplay": definition(extra: ["attributes": .compound([
                "gameplay/sky_light_level": .string("bad"), "visual/sun_angle": .float(20)])])
        ])
        let types = try world.dimensionTypes(), night = try world.nightMonsterLighting(assets: nil)
        #expect(types["test:low"]?.baseSkyLightLevel == -15)
        #expect(night["test:low"]?.skyDarkening == 15 && night["test:high"]?.skyDarkening == 0)
        #expect(types["test:bad_visual"]?.baseSkyLighting == nil && night["test:bad_visual"]?.skyDarkening == 11)
        #expect(types["test:bad_gameplay"]?.baseSkyLighting?.sunAngle == 20 && night["test:bad_gameplay"] == nil)
    }

    @Test func missingAmbiguousAndDifferentClockMidnightsRemainUnknown() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["absent", "invalid", "aliases", "other_clock", "other_period", "two_nights", "good"]
        let world = try world(root, types: Dictionary(uniqueKeysWithValues: names.map { name in
            ("test:" + name, definition(extra: ["timelines": .string("#test:" + name)]))
        }))
        let jar = try assets([
            timeline("absent", marker: nil), timeline("invalid", marker: -1),
            timeline("aliases", marker: 50, extra: ["time_markers": ["midnight": 50, "minecraft:midnight": 60]]),
            timeline("first", marker: 50), timeline("second", marker: 60),
            timeline("other", clock: "test:other", marker: nil),
            timeline("other_period", marker: nil, extra: ["period_ticks": 200]),
            timeline("unrelated", clock: "test:other", marker: nil, extra: ["tracks": ["visual/sun_angle": "bad"]]),
            tag("absent", ["test:absent"]), tag("invalid", ["test:invalid"]), tag("aliases", ["test:aliases"]),
            tag("other_clock", ["test:first", "test:other"]), tag("other_period", ["test:first", "test:other_period"]),
            tag("two_nights", ["test:first", "test:second"]),
            tag("good", ["test:first", "test:unrelated"])
        ])
        #expect(try world.nightMonsterLighting(assets: jar).keys.sorted() == ["test:good"])
    }

    @Test func packOverridesAndTagMembershipUseTheExistingResourceOwner() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let duplicate = NBT.list(.string, [.string("test:a"), .string("test:a")])
        let world = try world(root, types: [
            "test:direct": definition(extra: ["timelines": duplicate, "attributes": .compound([:])]),
            "test:tag": definition(extra: ["timelines": .string("#test:a"), "attributes": .compound([:])])
        ], packs: ["vanilla", "file/Override"])
        let pack = root.appendingPathComponent("datapacks/Override")
        try Fixtures.write(Array(#"{"pack":{"min_format":121,"max_format":121,"description":"Night fixture"}}"#.utf8), to: pack.appendingPathComponent("pack.mcmeta"))
        let override = try timeline("a", marker: 50, frames: [(0, 0.5)], modifier: "multiply")
        try Fixtures.write(Array(override.text.utf8), to: pack.appendingPathComponent(override.path))
        let jar = try assets([timeline("a", marker: 50, frames: [(0, 1)], modifier: "multiply"), tag("a", ["test:a", "test:a"])])
        let result = try world.nightMonsterLighting(assets: jar)
        #expect(result["test:direct"]?.skyDarkening == 11 && result["test:tag"]?.skyDarkening == 7)
        try Fixtures.write(Array("{bad".utf8), to: pack.appendingPathComponent(override.path))
        #expect(try world.nightMonsterLighting(assets: jar).isEmpty)
    }

    @Test func optionalLightProfileRetainsLightWithoutChangingOrdinaryTerrainOrOtherSkippedFacts() throws {
        let source = Fixtures.chunk(x: -1, z: 2, sections: [.compound([
            "Y": .byte(0), "BlockLight": .byteArray(Array(repeating: 0, count: 2048)),
            "SkyLight": .byteArray(Array(repeating: -1, count: 2048))
        ])], extra: ["isLightOn": .byte(1), "block_entities": .list(.compound, [.compound(["id": .string("minecraft:chest")])])]).serialized()
        let ordinary = try Chunk(nbt: NBT.read(source, skipping: Chunk.keysNotNeededForTerrain).value)
        let light = try Chunk(nbt: NBT.read(source, skipping: Chunk.keysNotNeededForTerrainAndLight).value)
        #expect(!ordinary.isLightOn && ordinary.sections[0].blockLight == nil)
        #expect(light.isLightOn && light.blockLight(x: 0, y: 0, z: 0) == 0 && light.skyLight(x: 0, y: 0, z: 0) == 15)
        #expect(light.blockEntities.isEmpty && light.x == ordinary.x && light.z == ordinary.z)
    }

    @Test func lightCheckKeepsTheGamesHorizontalBrightnessBoundary() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rules = try #require(try world(root, types: ["test:a": definition()]).nightMonsterLighting(assets: nil)["test:a"])
        for x in [-30_000_001, -30_000_000, 29_999_999, 30_000_000, Int.min, Int.max] {
            let expected = (-30_000_000..<30_000_000).contains(x)
            #expect(rules.canPass(blockLight: 0, skyLight: 0, at: BlockPosition(blockX: x, blockY: 0, blockZ: 0)) == expected)
        }
    }

    @Test func unverifiedVersionAndMissingSkyMetadataNeverAcquireVanillaAssumptions() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try world(root, types: ["test:a": definition()], version: 5024)
        #expect(try old.nightMonsterLighting(assets: nil).isEmpty)
        let modern = try world(root, types: ["test:a": definition()])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try modern.nightMonsterLighting(assets: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func definition(sky: Bool = true, limit: Int32 = 0, threshold: Int32 = 7, extra: [String: NBT] = [:]) -> NBT {
        .compound(["min_y": .int(-64), "height": .int(384), "logical_height": .int(384), "has_ceiling": .byte(0),
            "has_skylight": .byte(sky ? 1 : 0), "monster_spawn_block_light_limit": .int(limit),
            "monster_spawn_light_level": .int(threshold), "attributes": .compound(["gameplay/sky_light_level": .float(4)])
        ].merging(extra) { _, new in new })
    }

    private func world(_ root: URL, types: [String: NBT], packs: [String] = ["vanilla"], version: Int32 = 5023) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Night light"), "DataVersion": .int(version),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))]),
            "WorldGenSettings": .compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        ])]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func assets(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#)
        ] + entries))))
    }

    private func timeline(_ id: String, clock: String = "test:clock", marker: Any?, frames: [(Int, Float)] = [(0, 4)],
                          modifier: String = "override", extra: [String: Any] = [:]) throws -> TestZIP.Entry {
        var json: [String: Any] = ["clock": clock, "period_ticks": 100, "tracks": ["gameplay/sky_light_level": [
            "modifier": modifier, "keyframes": frames.map { ["ticks": $0.0, "value": $0.1] as [String: Any] }
        ]]]
        if let marker { json["time_markers"] = ["minecraft:midnight": marker] }
        return .init(path: "data/test/timeline/\(id).json", text: String(decoding: try JSONSerialization.data(
            withJSONObject: json.merging(extra) { _, new in new }), as: UTF8.self))
    }

    private func tag(_ id: String, _ values: [String]) throws -> TestZIP.Entry {
        .init(path: "data/test/tags/timeline/\(id).json", text: String(decoding: try JSONSerialization.data(withJSONObject: ["values": values]), as: UTF8.self))
    }

    private func lightChunk(block: [Int8]?, sky: [Int8]?, valid: Bool = true) throws -> Chunk {
        var section: [String: NBT] = ["Y": .byte(0)]
        section["BlockLight"] = block.map(NBT.byteArray)
        section["SkyLight"] = sky.map(NBT.byteArray)
        return try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [.compound(section)], extra: ["isLightOn": .byte(valid ? 1 : 0)]))
    }
}
