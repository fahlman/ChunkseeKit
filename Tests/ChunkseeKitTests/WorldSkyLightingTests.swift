import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct WorldSkyLightingTests {
    @Test func supportedButMismatchedJarCannotSupplyAnotherVersionsTimeline() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let type = definition(.list(.string, [.string("test:day")]))
        let entries = [try timeline("test:day", tracks: ["visual/sun_angle": track([(0, 20)])])]
        let world = try world(root, types: ["test:sky": type], version: Int32(SaveVersion.java26_4Snapshot5))
        let matching = try assets(entries, version: Int32(SaveVersion.java26_4Snapshot5))
        let previous = try assets(entries, version: Int32(SaveVersion.java26_3))
        #expect(try world.savedSkyLighting(assets: matching)["test:sky"]?.sunAngle == 20)
        #expect(try world.savedSkyLighting(assets: previous)["test:sky"] == nil)
    }

    @Test(arguments: [Int32(SaveVersion.java26_3), Int32(SaveVersion.java26_4Snapshot5)])
    func eachTimelineUsesItsNamedClockEvenWhenDimensionTimeIsFixed(version: Int32) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let type = definition(.list(.string, [.string("test:sun"), .string("test:moon")]), extra: [
            "has_fixed_time": .byte(1), "default_clock": .string("test:wrong")
        ])
        let world = try world(root, types: ["custom:sky": type], clocks: ["test:sun": 25, "test:moon": 75, "test:wrong": 90], version: version)
        let jar = try assets([
            timeline("test:sun", clock: "test:sun", tracks: ["visual/sun_angle": track([(0, 0), (100, 100)])]),
            timeline("test:moon", clock: "test:moon", tracks: ["visual/moon_angle": track([(0, 0), (100, 100)])])
        ], version: version)
        let files = ["level.dat", "data/minecraft/world_clocks.dat"].map { root.appendingPathComponent($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let light = try #require(try world.savedSkyLighting(assets: jar)["custom:sky"])
        #expect(light.sunAngle == 25 && light.moonAngle == 75)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func nestedTagsKeepFirstOccurrenceWhileDirectListsKeepDuplicates() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "test:nested": definition(.string("#test:root")),
            "test:tag_duplicates": definition(.string("#test:duplicates")),
            "test:direct_duplicates": definition(.list(.string, [.string("test:a"), .string("test:a"), .string("test:b")]))
        ])
        let jar = try assets(operations() + [
            tag("test:root", ["test:a", "#test:child", "test:b"]),
            tag("test:child", ["test:c", "test:a", "test:d"]), tag("test:duplicates", ["test:a", "test:a", "test:b"])
        ])
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result["test:nested"]?.sunAngle == 3000) // a, c, d, b
        #expect(result["test:tag_duplicates"]?.sunAngle == 10)
        #expect(result["test:direct_duplicates"]?.sunAngle == 20)
    }

    @Test func folderZipAndJarTagsComposeInPackOrderAndReplaceResetsEarlierMembers() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try folder(root, name: "Low", entries: [tag("test:root", ["test:a"])])
        let high = root.appendingPathComponent("datapacks/High.zip")
        let override = try timeline("test:a", tracks: ["visual/sun_angle": track([(0, 5)], modifier: "add")])
        try zip(high, entries: [override, tag("test:root", ["test:b"])])
        let world = try world(root, types: ["test:map": definition(.string("#test:root"))], packs: ["vanilla", "file/Low", "file/High.zip"])
        let jar = try assets(operations() + [tag("test:root", ["test:c"])])
        #expect(try world.savedSkyLighting(assets: jar)["test:map"]?.sunAngle == 70) // c, overridden a, b
        try zip(high, entries: [override, tag("test:root", ["test:a", "test:b"], replace: true)])
        #expect(try world.savedSkyLighting(assets: jar)["test:map"]?.sunAngle == 50)
        try zip(high, entries: [override, tag("test:root", [], replace: true)])
        #expect(try world.savedSkyLighting(assets: jar)["test:map"]?.sunAngle == 0)
    }

    @Test func emptyLightingTracksAndStaticDimensionsDoNotReadUnrelatedClocks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "test:static": definition(.list(.string, [])),
            "test:empty": definition(.string("test:empty"))
        ])
        try Data([255, 1, 2]).write(to: root.appendingPathComponent("data/minecraft/world_clocks.dat"))
        let jar = try assets([timeline("test:empty", clock: "test:missing", tracks: ["visual/star_brightness": [:]])])
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result.count == 2 && result.values.allSatisfy { $0.sunAngle == 0 && $0.skyLightFactor == 1 })
        let noResources = try self.world(root, types: ["test:static": definition(.list(.string, []))], packs: ["file/Missing"])
        #expect(try noResources.savedSkyLighting(assets: nil)["test:static"]?.sunAngle == 0)
    }

    @Test func absentOptionalMembersAreSkippedButMissingRequiredMembersInvalidateTheirTag() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:optional": definition(.string("#test:optional")),
                                          "test:required": definition(.string("#test:required")),
                                          "test:optional_failed": definition(.string("#test:optional_failed"))])
        let jar = try assets(operations() + [
            tag("test:optional", [["id": "test:absent", "required": false], ["id": "#test:absent", "required": false], "test:a"]),
            tag("test:required", ["test:a", "test:absent"]),
            tag("test:optional_failed", [["id": "#test:required", "required": false], "test:c"])
        ])
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result["test:optional"]?.sunAngle == 1 && result["test:optional_failed"]?.sunAngle == 2)
        #expect(result["test:required"] == nil)
    }

    @Test func invalidOptionalResourcesAndCyclicTagsRemainUnavailable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["bad_timeline", "bad_tag", "optional_cycle", "required_cycle", "good"]
        let types = Dictionary(uniqueKeysWithValues: names.map { ("test:" + $0, definition(.string("#test:" + $0))) })
        let world = try world(root, types: types)
        let jar = try assets(operations() + [
            resource("timeline", "test:bad", "{invalid"), resource("tags/timeline", "test:bad", "{\"values\":[1]}"),
            tag("test:bad_timeline", [["id": "test:bad", "required": false], "test:a"]),
            tag("test:bad_tag", [["id": "#test:bad", "required": false], "test:a"]),
            tag("test:optional_cycle", [["id": "#test:optional_cycle", "required": false], "test:a"]),
            tag("test:required_cycle", ["#test:required_cycle", "test:a"]), tag("test:good", ["test:a"])
        ])
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result.count == 1 && result["test:good"]?.sunAngle == 1)
    }

    @Test func malformedHigherTagAndUnknownPacksNeverExposeLowerDefaultLighting() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try folder(root, name: "Bad", entries: [resource("tags/timeline", "test:root", "{\"values\":[1]}")])
        let jar = try assets(operations() + [tag("test:root", ["test:a"])])
        for packs in [["vanilla", "file/Bad"], ["vanilla", "file/Missing"], ["vanilla", "unknown_builtin"]] {
            let world = try world(root, types: ["test:map": definition(.string("#test:root")), "test:static": definition(.list(.string, []))], packs: packs)
            let result = try world.savedSkyLighting(assets: jar)
            #expect(result["test:map"] == nil && result["test:static"]?.sunAngle == 0)
        }
    }

    @Test func missingAndAmbiguousNamedClocksDoNotUseTheDimensionDefaultOrAnotherClock() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:missing": definition(.string("test:missing")),
                                          "test:ambiguous": definition(.string("test:ambiguous")),
                                          "test:good": definition(.string("test:good"))],
                              clocks: ["day": 10, "minecraft:day": 20, "test:clock": 25, "minecraft:overworld": 90])
        let jar = try assets([
            timeline("test:missing", clock: "test:absent", tracks: ["visual/sun_angle": track([(0, 1)])]),
            timeline("test:ambiguous", clock: "day", tracks: ["visual/sun_angle": track([(0, 1)])]),
            timeline("test:good", tracks: ["visual/sun_angle": track([(0, 0), (100, 100)])])
        ])
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result.count == 1 && result["test:good"]?.sunAngle == 25)
        try Data([255, 1, 2]).write(to: root.appendingPathComponent("data/minecraft/world_clocks.dat"))
        #expect(throws: (any Error).self) { try world.savedSkyLighting(assets: jar) }
    }

    @Test func nullOptionalFlagsUseCodecDefaultsAndNegativeClockTimesWrap() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:map": definition(.string("#test:root"))], clocks: ["test:clock": Int.min])
        let jar = try assets([
            timeline("test:cycle", period: 100, tracks: ["visual/sun_angle": track([(0, 0), (100, 100)])]),
            resource("tags/timeline", "test:root", "{\"replace\":null,\"values\":[{\"id\":\"test:cycle\",\"required\":null}]}")
        ])
        #expect(try world.savedSkyLighting(assets: jar)["test:map"]?.sunAngle == 92)
    }

    @Test func folderDefinitionsWorkWithoutAJarButUnverifiedVersionsRemainUnavailable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try folder(root, name: "Only", entries: operations() + [tag("test:root", ["test:a"])])
        let types = ["custom:map": definition(.string("#test:root"))]
        let world = try world(root, types: types, packs: ["file/Only"])
        #expect(try world.savedSkyLighting(assets: nil)["custom:map"]?.sunAngle == 1)
        let wrong = try assets([], version: 9999)
        #expect(try world.savedSkyLighting(assets: wrong)["custom:map"]?.sunAngle == 1)
        let unknown = try self.world(root, types: types, packs: ["file/Only"], version: 9999)
        #expect(try unknown.savedSkyLighting(assets: nil).isEmpty)
    }

    @Test func oversizedListsAndDeepTagsRemainBoundedWhileStaticDimensionsStayReadable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: [
            "test:direct": definition(.list(.string, Array(repeating: .string("test:a"), count: 4097))),
            "test:wide": definition(.string("#test:wide")), "test:deep": definition(.string("#test:deep0")),
            "test:static": definition(.list(.string, []))
        ])
        var entries = try operations() + [tag("test:wide", Array(repeating: "test:a", count: 4097))]
        for index in 0...64 { entries.append(try tag("test:deep\(index)", [index == 64 ? "test:a" : "#test:deep\(index + 1)"])) }
        let jar = try assets(entries)
        let result = try world.savedSkyLighting(assets: jar)
        #expect(result.count == 1 && result["test:static"]?.sunAngle == 0)
    }

    @Test func cancellationPropagatesBeforeReadingResources() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, types: ["test:map": definition(.string("#test:root"))])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try world.savedSkyLighting(assets: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Synthetic world lighting"}}"#
    private func definition(_ timelines: NBT, extra: [String: NBT] = [:]) -> NBT {
        .compound(["min_y": .int(-64), "height": .int(384), "logical_height": .int(384),
                   "has_ceiling": .byte(0), "has_skylight": .byte(1), "timelines": timelines].merging(extra) { _, new in new })
    }
    private func track(_ values: [(Int, Float)], modifier: String = "override") -> [String: Any] {
        ["modifier": modifier, "keyframes": values.map { ["ticks": $0.0, "value": $0.1] as [String: Any] }]
    }
    private func timeline(_ id: String, clock: String = "test:clock", period: Int? = nil, tracks: [String: Any]) throws -> TestZIP.Entry {
        var json: [String: Any] = ["clock": clock, "tracks": tracks]
        if let period { json["period_ticks"] = period }
        return resource("timeline", id, String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self))
    }
    private func operations() throws -> [TestZIP.Entry] {
        try [("a", "add", Float(1)), ("b", "multiply", 10), ("c", "add", 2), ("d", "multiply", 100)].map {
            try timeline("test:" + $0.0, tracks: ["visual/sun_angle": track([(0, $0.2)], modifier: $0.1)])
        }
    }
    private func tag(_ id: String, _ values: [Any], replace: Bool = false) throws -> TestZIP.Entry {
        resource("tags/timeline", id, String(decoding: try JSONSerialization.data(withJSONObject: ["values": values, "replace": replace]), as: UTF8.self))
    }
    private func resource(_ directory: String, _ id: String, _ json: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":")
        return .init(path: "data/\(parts[0])/\(directory)/\(parts[1]).json", text: json)
    }
    private func assets(_ entries: [TestZIP.Entry], version: Int32 = 5023) throws -> GameAssets {
        let data = try TestZIP.zip([.init(path: "version.json", text: #"{"id":"fixture","world_version":\#(version)}"#)] + entries)
        return try #require(GameAssets(data: Data(data)))
    }
    private func folder(_ root: URL, name: String, entries: [TestZIP.Entry]) throws {
        let pack = root.appendingPathComponent("datapacks/" + name)
        try Fixtures.write(Array(metadata.utf8), to: pack.appendingPathComponent("pack.mcmeta"))
        for entry in entries { try Fixtures.write(Array(entry.data ?? Data(entry.text.utf8)), to: pack.appendingPathComponent(entry.path)) }
    }
    private func zip(_ url: URL, entries: [TestZIP.Entry]) throws {
        try Fixtures.write(TestZIP.zip([.init(path: "pack.mcmeta", text: metadata)] + entries), to: url)
    }
    private func world(_ root: URL, types: [String: NBT], packs: [String] = ["vanilla"],
                       clocks: [String: Int] = ["test:clock": 0], version: Int32 = 5023) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("World Lighting"), "DataVersion": .int(version),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))]),
            "WorldGenSettings": .compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        ])]), to: root.appendingPathComponent("level.dat"))
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(version), "data": .compound(clocks.mapValues {
            .compound(["total_ticks": .long(Int64($0))])
        })]), to: root.appendingPathComponent("data/minecraft/world_clocks.dat"))
        return try World(contentsOf: root)
    }
}
