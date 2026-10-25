import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct TimelineTimingTests {
    @Test func headersKeepClockAndPeriodWithoutARegistryOrVersionInventory() throws {
        for version in [1, 5023, 999999] {
            let assets = try assets([entry(#"{"clock":":custom","period_ticks":100,"tracks":{"example:new_feature":{"future":"value"}}}"#)], version: version)
            let timing = try #require(assets.timelineTiming("day"))
            #expect(timing.clockID == "minecraft:custom" && timing.periodTicks == 100)
            #expect(assets.timelineTiming("test:missing") == nil)
            #expect(assets.timelineTiming("../day") == nil)
        }
        for body in [#"{"clock":"test:clock"}"#, #"{"clock":"test:clock","period_ticks":null}"#] {
            let timing = try #require(try assets([entry(body)]).timelineTiming("day"))
            #expect(timing.periodTicks == nil && timing.position(at: 100) == nil)
        }
        for body in [#"{}"#, #"{"clock":1}"#, #"{"clock":"Bad ID"}"#,
                     #"{"clock":"test:clock","period_ticks":0}"#, #"{"clock":"test:clock","period_ticks":-1}"#,
                     #"{"clock":"test:clock","period_ticks":1.5}"#, #"{"clock":"test:clock","period_ticks":true}"#,
                     #"{"clock":"test:clock","period_ticks":2147483648}"#, #"{"clock":"test:clock","tracks":[]}"#] {
            #expect(try assets([entry(body)]).timelineTiming("day") == nil)
        }
    }

    @Test func periodicPositionsMatchSignedDivisionAndKeepExtremeSavedTicksExactly() throws {
        let timing = try #require(try assets([entry(#"{"clock":"test:clock","period_ticks":100}"#)]).timelineTiming("day"))
        for (ticks, cycle, tick): (Int, Int, Int) in [(0, 0, 0), (99, 0, 99), (100, 1, 0),
                (-1, 0, -1), (-100, -1, 0), (-101, -1, -1),
                (.min, -92233720368547758, -8), (.max, 92233720368547758, 7)] {
            let position = try #require(timing.position(at: ticks))
            #expect(position.cycle == cycle && position.tick == tick)
        }
        let unit = try #require(try assets([entry(#"{"clock":"test:clock","period_ticks":1}"#)]).timelineTiming("day"))
        #expect(unit.position(at: .min)?.cycle == Int.min && unit.position(at: .max)?.cycle == Int.max)
    }

    @Test func worldTimingUsesFolderZipAndJarPriorityAndPreservesUnknownOverrides() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try assets([entry(#"{"clock":"test:game","period_ticks":24000}"#)], version: 1)
        try folder(root, body: #"{"clock":"test:folder","period_ticks":100}"#)
        let zip = root.appendingPathComponent("datapacks/high.zip")
        try Fixtures.write(TestZIP.zip([metadata, entry(#"{"clock":"test:zip","period_ticks":40}"#)]), to: zip)
        let world = try world(root, packs: ["vanilla", "file/override", "file/high.zip"], version: nil)
        let file = root.appendingPathComponent("level.dat"), before = try Data(contentsOf: file)
        let timing = try #require(try world.timelineTiming("day", assets: jar))
        #expect(timing.clockID == "test:zip" && timing.periodTicks == 40)
        #expect(try world.timelineTiming("test:missing", assets: jar) == nil)
        try Fixtures.write(TestZIP.zip([metadata, entry("invalid")]), to: zip)
        #expect(try world.timelineTiming("day", assets: jar) == nil)
        #expect(try Data(contentsOf: file) == before)
        let missing = try self.world(root, packs: ["vanilla", "file/missing"])
        #expect(try missing.timelineTiming("day", assets: jar) == nil)
        let disabled = try self.world(root, packs: [])
        #expect(try disabled.timelineTiming("day", assets: jar) == nil)
    }

    @Test func cliUsesTheSelectedTimelineClockAndPackPeriod() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try world(root)
        let jar = root.appendingPathComponent("game.jar")
        try writeJar(jar, body: #"{"clock":"test:clock","period_ticks":100}"#)
        let result = try Fixtures.runCLI(root, command: "summary", arguments: [jar.path])
        #expect(result.status == 0 && result.output.contains("Day:             3, time of day 51"))
        try folder(root, body: #"{"clock":"test:clock","period_ticks":40}"#)
        _ = try world(root, packs: ["vanilla", "file/override"])
        for arguments in [[], [jar.path]] {
            let overridden = try Fixtures.runCLI(root, command: "summary", arguments: arguments)
            #expect(overridden.status == 0 && overridden.output.contains("Day:             7, time of day 11"))
        }
    }

    @Test func cliKeepsSavedTicksWhenTimingOrItsClockIsUnavailable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try world(root)
        let plain = try Fixtures.runCLI(root)
        #expect(plain.status == 0 && plain.output.contains("Overworld clock: 48001 ticks"))
        #expect(!plain.output.contains("Day:"))
        let jar = root.appendingPathComponent("game.jar")
        for body in [#"{"clock":"test:missing","period_ticks":100}"#, "invalid"] {
            try writeJar(jar, body: body)
            let result = try Fixtures.runCLI(root, command: "summary", arguments: [jar.path])
            #expect(result.status == 0 && result.output.contains("Overworld clock: 48001 ticks"))
            #expect(!result.output.contains("Day:"))
        }
        try writeJar(jar, body: #"{"clock":"test:clock"}"#)
        let nonperiodic = try Fixtures.runCLI(root, command: "summary", arguments: [jar.path])
        #expect(nonperiodic.status == 0 && nonperiodic.output.contains("Clock:           test:clock, 251 ticks"))
        try writeJar(jar, body: #"{"clock":"test:clock","period_ticks":1}"#)
        _ = try world(root, ticks: .max)
        let extreme = try Fixtures.runCLI(root, command: "summary", arguments: [jar.path])
        #expect(extreme.status == 0 && extreme.output.contains("test:clock, 9223372036854775807 ticks"))
        #expect(!extreme.output.contains("Day:"))
    }

    private var metadata: TestZIP.Entry { .init(path: "pack.mcmeta", text: #"{"pack":{"description":"Fixture"}}"#) }

    private func entry(_ body: String) -> TestZIP.Entry {
        .init(path: "data/minecraft/timeline/day.json", text: body)
    }

    private func assets(_ entries: [TestZIP.Entry], version: Int = 999999) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}")
        ] + entries))))
    }

    private func writeJar(_ url: URL, body: String) throws {
        try Fixtures.write(TestZIP.zip([.init(path: "version.json", text: #"{"id":"fixture","world_version":1}"#), entry(body)]), to: url)
    }

    private func folder(_ root: URL, body: String) throws {
        for resource in [metadata, entry(body)] {
            try Fixtures.write(Array(resource.text.utf8), to: root.appendingPathComponent("datapacks/override/" + resource.path))
        }
    }

    private func world(_ root: URL, packs: [String] = ["vanilla"], version: Int32? = 999999, ticks: Int64 = 251) throws -> World {
        var fields: [String: NBT] = ["LevelName": .string("Timeline"),
            "DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))])]
        fields["DataVersion"] = version.map(NBT.int)
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        try Fixtures.writeGzippedNBT(.compound(["data": .compound([
            "minecraft:overworld": .compound(["total_ticks": .long(48001)]),
            "test:clock": .compound(["total_ticks": .long(ticks)]),
        ])]), to: root.appendingPathComponent("data/minecraft/world_clocks.dat"))
        return try World(contentsOf: root)
    }
}
