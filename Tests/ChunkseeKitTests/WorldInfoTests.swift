import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct WorldInfoTests {
    @Test func modernDataFiles() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("New"), "WasModded": .byte(1), "ServerBrands": .list([.string("vanilla"), .string("fabric")]),
            "DataPacks": .compound(["Enabled": .list([.string("vanilla")]), "Disabled": .list([.string("trade_rebalance")])]),
        ])]), to: dir.appendingPathComponent("level.dat"))
        func data(_ path: String, _ contents: [String: NBT]) throws {
            try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5023), "data": .compound(contents)]), to: dir.appendingPathComponent(path))
        }
        try data("data/minecraft/game_rules.dat", ["minecraft:keep_inventory": .byte(1), "minecraft:random_tick_speed": .int(3)])
        try data("data/minecraft/wandering_trader.dat", ["spawn_delay": .int(20_400), "spawn_chance": .int(75)])
        try data("data/minecraft/weather.dat", ["raining": .byte(1), "thundering": .byte(0), "rain_time": .int(100), "thunder_time": .int(200), "clear_weather_time": .int(0)])
        try data("data/minecraft/world_clocks.dat", ["minecraft:overworld": .compound(["total_ticks": .long(318_388_245)])])
        try data("dimensions/minecraft/overworld/data/minecraft/world_border.dat", ["center_x": .double(10), "center_z": .double(-20), "size": .double(5000),
                                                                                  "lerp_target": .double(5000), "lerp_time": .long(0)])
        try data("dimensions/minecraft/the_end/data/minecraft/ender_dragon_fight.dat", ["dragon_killed": .byte(1), "previously_killed": .byte(1),
                                                                                       "needs_state_scanning": .byte(0),
                                                                                       "gateways": .list((0..<19).map { NBT.int(Int32($0)) })])
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/minecraft/overworld/region"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/minecraft/the_end/region"), withIntermediateDirectories: true)

        let world = try World(contentsOf: dir)
        #expect(world.level.wasModded && world.level.serverBrands == ["vanilla", "fabric"] && world.level.disabledDataPacks == ["trade_rebalance"])
        #expect(try world.gameRules() == ["minecraft:keep_inventory": .bool(true), "minecraft:random_tick_speed": .int(3)])
        #expect(try world.weather() == Weather(isRaining: true, isThundering: false, rainTime: 100, thunderTime: 200, clearTime: 0))
        #expect(try world.dayTime() == 318_388_245)
        #expect(try world.wanderingTrader() == WanderingTraderTimer(spawnDelay: 20_400, spawnChance: 75))
        let overworld = try #require(world.dimension("overworld"))
        let border = try #require(try world.worldBorder(of: overworld))
        #expect(border.centerX == 10 && border.centerZ == -20 && border.size == 5000 && border.isLimited)
        #expect(try world.enderDragonFight() == EnderDragonFight(dragonKilled: true, previouslyKilled: true, remainingGateways: 19,
                                                                 needsStateScanning: false))
        #expect(try world.enderDragonFight()?.isDefeated == true)
    }

    @Test func olderLevelDatFields() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Old"),
            "GameRules": .compound(["keepInventory": .string("false"), "randomTickSpeed": .string("3"), "odd": .string("x")]),
            "raining": .byte(0), "thundering": .byte(1), "rainTime": .int(5), "thunderTime": .int(6), "DayTime": .long(6000), "WanderingTraderSpawnDelay": .int(24_000), "WanderingTraderSpawnChance": .int(25),
            "BorderSize": .double(60_000_000), "BorderCenterX": .double(0), "BorderCenterZ": .double(0),
            "DragonFight": .compound(["DragonKilled": .byte(0), "PreviouslyKilled": .byte(0), "Gateways": .list((0..<20).map { NBT.int(Int32($0)) })]),
        ])]), to: dir.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("region"), withIntermediateDirectories: true)

        let world = try World(contentsOf: dir)
        #expect(try world.gameRules() == ["keepInventory": .bool(false), "randomTickSpeed": .int(3)])
        #expect(try world.weather()?.isThundering == true)
        #expect(try world.dayTime() == 6000)
        #expect(try world.wanderingTrader() == WanderingTraderTimer(spawnDelay: 24_000, spawnChance: 25))
        let overworld = try #require(world.dimension("overworld"))
        let border = try #require(try world.worldBorder(of: overworld))
        #expect(!border.isLimited)
        #expect(try world.enderDragonFight()?.remainingGateways == 20)
        #expect(try world.enderDragonFight()?.needsStateScanning == true)   // missing means not yet checked, as in the game
        #expect(!world.level.wasModded && world.level.serverBrands.isEmpty)
    }

    /// Ryan's Realm's real file: nobody has been to the End, yet both kill flags are set. The game
    /// hasn't checked the End, so they aren't a kill.
    @Test func anUncheckedFightIsNotADefeat() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Realm"), "DataVersion": .int(5023)])]),
                                     to: dir.appendingPathComponent("level.dat"))
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(4772), "data": .compound([
            "dragon_killed": .byte(1), "previously_killed": .byte(1), "needs_state_scanning": .byte(1),
            "gateways": .list((0..<20).map { NBT.int(Int32($0)) }),
        ])]), to: dir.appendingPathComponent("dimensions/minecraft/the_end/data/minecraft/ender_dragon_fight.dat"))
        for folder in ["overworld", "the_end"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/minecraft/\(folder)/region"),
                                                    withIntermediateDirectories: true)
        }
        let fight = try #require(try World(contentsOf: dir).enderDragonFight())
        #expect(fight.needsStateScanning && fight.previouslyKilled && !fight.isDefeated && fight.remainingGateways == 20)
    }
}
