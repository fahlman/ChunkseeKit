import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct WorldClockTests {
    @Test func namedClocksKeepTheirOwnWholeTicksAndDoNotWriteTheSave() throws {
        let root = try Self.world()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data/minecraft/world_clocks.dat")
        try Self.write([
            "minecraft:overworld": .compound(["total_ticks": .long(48_125), "partial_tick": .float(0.25)]),
            "minecraft:the_end": .compound(["total_ticks": .long(6_000), "paused": .byte(1)]),
            "mod:night": .compound(["total_ticks": .long(-12_000), "rate": .float(2)])
        ], to: file)
        let original = try Data(contentsOf: file)
        let world = try World(contentsOf: root)
        #expect(try world.clockTimes() == ["minecraft:overworld": 48_125, "minecraft:the_end": 6_000, "mod:night": -12_000])
        #expect(try world.dayTime() == 48_125)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func integralTagsStayExactWhileMissingAndMalformedClocksStayUnknown() throws {
        let root = try Self.world()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write([
            "test:byte": .compound(["total_ticks": .byte(-8)]),
            "test:short": .compound(["total_ticks": .short(32_000)]),
            "test:int": .compound(["total_ticks": .int(Int32.max)]),
            "test:long": .compound(["total_ticks": .long(Int64.max)]),
            "test:min": .compound(["total_ticks": .long(Int64.min)]),
            "test:missing": .compound([:]), "test:float": .compound(["total_ticks": .float(1.5)]),
            "test:nan": .compound(["total_ticks": .double(.nan)]),
            "test:text": .compound(["total_ticks": .string("12000")]),
            "test:scalar": .long(12_000), "Invalid ID": .compound(["total_ticks": .int(4)])
        ], to: root.appendingPathComponent("data/minecraft/world_clocks.dat"))
        let world = try World(contentsOf: root)
        #expect(try world.clockTimes() == ["test:byte": -8, "test:short": 32_000, "test:int": Int(Int32.max),
                                         "test:long": Int.max, "test:min": Int.min])
        #expect(try world.dayTime() == nil)
    }

    @Test func legacyDayTimeFillsOnlyTheOverworldAndValidModernTicksWin() throws {
        let root = try Self.world(legacy: 9_000)
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try World(contentsOf: root)
        #expect(try world.clockTimes() == ["minecraft:overworld": 9_000])
        let file = root.appendingPathComponent("data/minecraft/world_clocks.dat")
        try Self.write(["test:moon": .compound(["total_ticks": .long(1_000)])], to: file)
        #expect(try world.clockTimes() == ["minecraft:overworld": 9_000, "test:moon": 1_000])
        try Self.write(["minecraft:overworld": .compound(["total_ticks": .string("bad")])], to: file)
        #expect(try world.dayTime() == 9_000) // Preserve dayTime's established legacy fallback.
        try Self.write(["minecraft:overworld": .compound(["total_ticks": .long(13_000)])], to: file)
        #expect(try world.dayTime() == 13_000)
    }

    @Test func aliasesNormalizeAndAmbiguousNamesDoNotChooseByDictionaryOrder() throws {
        let root = try Self.world(legacy: 7_000)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data/minecraft/world_clocks.dat")
        try Self.write(["overworld": .compound(["total_ticks": .int(2)]),
                        "other": .compound(["total_ticks": .int(3)])], to: file)
        let world = try World(contentsOf: root)
        #expect(try world.clockTimes() == ["minecraft:overworld": 2, "minecraft:other": 3])
        try Self.write(["overworld": .compound(["total_ticks": .int(2)]),
                        "minecraft:overworld": .compound([:]),
                        "other": .compound(["total_ticks": .int(3)])], to: file)
        #expect(try world.clockTimes() == ["minecraft:other": 3])
        #expect(try world.dayTime() == nil)
    }

    @Test func savedDataLayoutPriorityAndReadErrorsAreSharedWithOtherMetadata() throws {
        let root = try Self.world()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try World(contentsOf: root)
        #expect(try world.clockTimes().isEmpty)
        let flat = root.appendingPathComponent("data/world_clocks.dat")
        let modern = root.appendingPathComponent("data/minecraft/world_clocks.dat")
        try Self.write(["test:clock": .compound(["total_ticks": .int(1)])], to: flat)
        #expect(try world.clockTimes() == ["test:clock": 1])
        try Self.write(["test:clock": .compound(["total_ticks": .int(2)])], to: modern)
        #expect(try world.clockTimes() == ["test:clock": 2])
        try Data([255, 1, 2]).write(to: modern)
        #expect(throws: (any Error).self) { try world.clockTimes() }
        #expect(throws: (any Error).self) { try world.dayTime() }
    }

    private static func world(legacy: Int64? = nil) throws -> URL {
        let root = try Fixtures.tempDirectory()
        var fields: [String: NBT] = ["LevelName": .string("Clock Check"), "DataVersion": .int(5023)]
        if let legacy { fields["DayTime"] = .long(legacy) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return root
    }

    private static func write(_ clocks: [String: NBT], to url: URL) throws {
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5023), "data": .compound(clocks)]), to: url)
    }
}
