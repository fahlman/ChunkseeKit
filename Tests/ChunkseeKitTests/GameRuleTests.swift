import Foundation
import Testing
import ChunkseeKit

@Suite struct GameRuleTests {
    @Test(arguments: [true, false])
    func readsLegacyValuesThroughTheWorldReader(_ enabled: Bool) throws {
        let directory = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Legacy Rules"),
            "GameRules": .compound(["doTraderSpawning": .string(enabled ? "true" : "false")]),
        ])]), to: directory.appendingPathComponent("level.dat"))

        let rules = try World(contentsOf: directory).gameRules()
        #expect(GameRule.wanderingTraderSpawning.value(in: rules) == .bool(enabled))
        #expect(rules == ["doTraderSpawning": .bool(enabled)])
    }

    @Test(arguments: [true, false])
    func readsModernValuesWithoutFallingBackToOldWorldFields(_ enabled: Bool) throws {
        let directory = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Modern Rules"),
            "GameRules": .compound(["doTraderSpawning": .string(enabled ? "false" : "true")]),
        ])]), to: directory.appendingPathComponent("level.dat"))
        let file = directory.appendingPathComponent("data/minecraft/game_rules.dat")
        try Fixtures.writeGzippedNBT(.compound(["data": .compound([
            "minecraft:spawn_wandering_traders": .byte(enabled ? 1 : 0),
        ])]), to: file)
        let world = try World(contentsOf: directory)
        let rules = try world.gameRules()
        #expect(GameRule.wanderingTraderSpawning.value(in: rules) == .bool(enabled))
        #expect(rules == ["minecraft:spawn_wandering_traders": .bool(enabled)])

        try Fixtures.writeGzippedNBT(.compound(["data": .compound([
            "example:spawn_wandering_traders": .byte(0),
        ])]), to: file)
        #expect(try GameRule.wanderingTraderSpawning.value(in: world.gameRules()) == nil)
    }

    @Test func missingMalformedAndDisplayNamesDoNotBecomeBooleanSettings() {
        let rule = GameRule.wanderingTraderSpawning
        let invalid: [[String: GameRuleValue]] = [[:],
            ["example:spawn_wandering_traders": .bool(false)],
            ["Spawn Wandering Traders": .bool(false)],
            ["Do Trader Spawning": .bool(false)],
            [rule.rawValue: .int(0)],
            ["doTraderSpawning": .int(0)],
            [rule.rawValue: .int(0), "doTraderSpawning": .bool(false)]]
        for rules in invalid {
            #expect(rule.value(in: rules) == nil)
        }
        #expect(rule.value(in: [rule.rawValue: .bool(true), "doTraderSpawning": .bool(false)]) == .bool(true))
        #expect(rule.value(in: [rule.rawValue: .bool(false), "doTraderSpawning": .bool(true)]) == .bool(false))
    }
}
