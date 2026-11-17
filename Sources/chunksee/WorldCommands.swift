import Foundation
import ChunkseeKit

/// Commands about the world as a whole and its players.

func summaryAssetsCommand(_ world: World, _ arguments: Arguments) throws {
    try summaryCommand(world, assets: suppliedGameAssets(arguments))
}

func suppliedGameAssets(_ arguments: Arguments) throws -> GameAssets? {
    guard arguments.words.count <= 2 else { fail(usage) }
    let assets: GameAssets?
    if arguments.words.count == 2 {
        let path = arguments.words[1]
        guard let supplied = try GameAssets(contentsOf: URL(fileURLWithPath: path)) else {
            fail("could not read game files: \(path)")
        }
        assets = supplied
    } else { assets = nil }
    return assets
}

func summaryCommand(_ world: World, assets: GameAssets? = nil) throws {
        let l = world.level
        print("Name:            \(l.name ?? "?")")
        print("Version:         \(l.versionName ?? "?") (data version \(l.dataVersion.map(String.init) ?? "?"))")
        if !l.versionHistory.isEmpty { print("Version history: \(l.versionHistory.map(String.init).joined(separator: ", "))") }
        print("Layout:          \(world.usesDimensionsFolderForVanilla ? "26.1+ (dimensions/)" : "legacy")")
        print("Difficulty:      \(l.difficulty ?? "?")\(l.isHardcore == true ? " (hardcore)" : "")")
        if let seed = try? world.seed() { print("Seed:            \(seed)") }
        if let p = l.spawnPosition { print("Spawn:           \(p.x) \(p.y) \(p.z) in \(l.spawnDimension ?? "?")") }
        if let uuid = l.singleplayerUUID { print("Player:          \(uuid.uuidString.lowercased())") }
        if let date = l.lastPlayed { print("Last played:     \(date)") }
        if let time = l.time { print("World age:       \(time / 72_000) hours (\(time) ticks)") }
        if let timing = try? world.timelineTiming("minecraft:day", assets: assets),
           let ticks = try? world.clockTimes()[timing.clockID] {
            if let position = timing.position(at: ticks) {
                print("Day:             \(position.cycle), time of day \(position.tick)")
            } else {
                print("Clock:           \(timing.clockID), \(ticks) ticks")
            }
        } else if let ticks = try? world.dayTime() {
            print("Overworld clock: \(ticks) ticks")
        }
        if let trader = try? world.wanderingTrader() {
            print("Trader:          next try in \(trader.spawnDelay / 1200) min of play, \(trader.spawnChance)% chance")
        }
        if let w = try? world.weather() { print("Weather:         \(w.isThundering ? "thunder" : w.isRaining ? "rain" : "clear")") }
        if let fight = try? world.enderDragonFight() {
            let state = fight.needsStateScanning ? "not checked yet" : fight.isDefeated ? "defeated" : "not defeated"
            print("Ender Dragon:    \(state), \(fight.remainingGateways) of 20 gateways unopened")
        }
        if l.wasModded { print("Modded:          yes (\(l.serverBrands.joined(separator: ", ")))") }
        print("Dimensions:")
        var discovery = RegionDiscovery()
        for d in world.dimensions() {
            guard let regions = discovery.files(in: d) else { continue }
            let border = (try? world.worldBorder(of: d)).flatMap { $0?.isLimited == true ? $0 : nil }
                .map { ", border \(Int($0.size)) blocks around \(Int($0.centerX)), \(Int($0.centerZ))" } ?? ""
            print("  \(d.id): \(regions.count) region files\(border)")
        }
        print("Players with data: \(world.playerUUIDs().count)")
        try discovery.finish()
}

func rulesCommand(_ world: World, _ arguments: Arguments) throws {
        for (rule, value) in try world.gameRules().sorted(by: { $0.key < $1.key }) {
            switch value {
            case .bool(let b): print("\(rule) \(b)")
            case .int(let i): print("\(rule) \(i)")
            }
        }
}

func mapsCommand(_ world: World, _ arguments: Arguments) {
        for map in world.mapItems() {
            let place = map.dimension ?? "unknown dimension \(map.unrecognizedDimension ?? "?")"
            let state = map.isBlank ? "blank" : map.isLocked ? "locked" : "drawn"
            print("map \(map.id): \(place) centered \(map.centerX), \(map.centerZ), scale 1:\(map.blocksPerPixel), \(state)\(map.banners.isEmpty ? "" : ", \(map.banners.count) banners")")
        }
}

func playersCommand(_ world: World, _ arguments: Arguments) {
        func show(_ location: PlayerInfo.Location?) -> String {
            guard let l = location else { return "-" }
            guard let position = BlockPosition(x: l.x, y: l.y, z: l.z) else { return "\(l.dimension) (unknown position)" }
            return "\(l.dimension) \(position.x) \(position.y) \(position.z)"
        }
        // The game folder holding this world's saves folder keeps the local name cache.
        let gameFolder = world.url.deletingLastPathComponent().deletingLastPathComponent()
        let names = UserCache.names(under: gameFolder, depth: 0)
        for player in world.players() {
            let you = player.uuid == world.level.singleplayerUUID ? " (singleplayer)" : ""
            let name = names[player.uuid].map { " \($0.name)" } ?? ""
            print("\(player.uuid.uuidString.lowercased())\(name)\(you)")
            print("  saved:    \(player.lastSaved.map { "\($0)" } ?? "?")  data version \(player.dataVersion.map(String.init) ?? "none")")
            print("  position: \(player.position.map { show($0) } ?? "unknown dimension \(player.unrecognizedDimension ?? "?")")")
            print("  death:    \(show(player.lastDeath))")
            print("  respawn:  \(show(player.respawn))")
            func number(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "?" }
            print("  status:   \(player.gameMode.map { "\($0)" } ?? "?"), health \(number(player.health)), food \(player.foodLevel.map(String.init) ?? "?"), level \(player.experienceLevel.map(String.init) ?? "?")")
            let worn = player.equipment.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.id)" }.joined(separator: ", ")
            let stats = (try? world.statistics(for: player.uuid)) ?? names[player.uuid].flatMap { try? world.statistics(forName: $0.name) }
            let done = ((try? world.advancements(for: player.uuid)) ?? nil)?.filter { $0.isDone && !$0.isRecipe }.count
            print("  played:   \(stats?.playTime.map { "\($0 / 72_000) hours" } ?? "?"), \(done.map { "\($0) advancements" } ?? "no advancements file")")
            print("  items:    \(player.inventory.count) inventory stacks, \(player.enderChest.count) in the ender chest\(worn.isEmpty ? "" : "; wearing \(worn)")")
        }
}
