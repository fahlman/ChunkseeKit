import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct StatisticsTests {
    @Test func currentFormat() throws {
        let json = #"{"stats":{"minecraft:custom":{"minecraft:play_time":72000,"minecraft:walk_one_cm":500,"minecraft:mob_kills":3},"minecraft:mined":{"minecraft:stone":12}},"DataVersion":5023}"#
        let stats = try PlayerStatistics(json: Data(json.utf8))
        #expect(stats.dataVersion == 5023 && stats.playTime == 72000)
        #expect(stats.value("minecraft:stone", in: "minecraft:mined") == 12)
        #expect(stats.distances == ["minecraft:walk_one_cm": 500])
        let older = try PlayerStatistics(json: Data(#"{"stats":{"minecraft:custom":{"minecraft:play_one_minute":20}},"DataVersion":2230}"#.utf8))
        #expect(older.playTime == 20)
    }

    @Test func flatFormatFromBefore1_7_6() throws {
        let json = #"{"stat.playOneMinute":1000,"stat.walkOneCm":250,"stat.leaveGame":2,"stat.useItem.7":3,"achievement.openInventory":1}"#
        let stats = try PlayerStatistics(json: Data(json.utf8))
        #expect(stats.values == ["minecraft:custom": ["minecraft:play_time": 1000, "minecraft:walk_one_cm": 250, "minecraft:leave_game": 2]])
    }

    @Test func advancements() throws {
        let json = #"""
        {"minecraft:story/obtain_armor":{"criteria":{"iron_boots":"2017-06-10 13:35:26 -0400","iron_helmet":"2017-06-11 09:00:00 -0400"},"done":true},
         "minecraft:recipes/tools/fishing_rod":{"criteria":{"has_string":"2017-06-17 12:29:21 -0400"},"done":true},
         "minecraft:nether/all_potions":{"criteria":{"speed":"2018-01-01 00:00:00 +0000"},"done":false},
         "DataVersion":5023}
        """#
        let list = try AdvancementProgress.list(json: Data(json.utf8))
        #expect(list.map(\.id) == ["minecraft:nether/all_potions", "minecraft:recipes/tools/fishing_rod", "minecraft:story/obtain_armor"])
        #expect(list[1].isRecipe && !list[2].isRecipe)
        #expect(list[0].completed == nil)
        #expect(list[2].completed == ISO8601DateFormatter().date(from: "2017-06-11T13:00:00Z"))
    }
}
