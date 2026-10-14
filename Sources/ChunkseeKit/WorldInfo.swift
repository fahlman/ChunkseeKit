import Foundation

/// A game rule's value: most rules are on/off, some are numbers.
public enum GameRuleValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
}

/// Rain and thunder, with ticks until each changes.
public struct Weather: Sendable, Equatable {
    public var isRaining: Bool
    public var isThundering: Bool
    public var rainTime: Int
    public var thunderTime: Int
    /// Ticks of clear weather set by `/weather clear`, 0 when the weather is natural.
    public var clearTime: Int
}

/// A dimension's world border.
public struct WorldBorder: Sendable, Equatable {
    public var centerX: Double
    public var centerZ: Double
    /// Side length in blocks; Minecraft's default is 60,000,000 (no practical border).
    public var size: Double
    /// The size the border is moving to, over `lerpTime` milliseconds.
    public var targetSize: Double
    public var lerpTime: Int
    public var damagePerBlock: Double
    public var safeZone: Double
    public var warningBlocks: Int
    public var warningTime: Int

    public static let defaultSize = 60_000_000.0

    /// Whether the border is closer than the default, so it matters to players.
    public var isLimited: Bool { size < Self.defaultSize }
}

/// The state of the Ender Dragon fight.
public struct EnderDragonFight: Sendable, Equatable {
    public var dragonKilled: Bool
    public var previouslyKilled: Bool
    /// End gateways not yet opened; each dragon kill opens one of the 20.
    public var remainingGateways: Int
    /// True until the game first loads the End's central island and checks it. It then sets
    /// `dragonKilled` and `previouslyKilled` from what's there (an active exit portal, a living
    /// dragon), so until then they aren't confirmed either way: a world saved by an older version
    /// may have killed the dragon and still be waiting for this check. A missing value means true,
    /// as the game reads it.
    public var needsStateScanning: Bool

    /// Whether the game has confirmed a kill. False while `needsStateScanning` is true means the
    /// fight's outcome is unknown, not that the dragon is alive.
    public var isDefeated: Bool { previouslyKilled && !needsStateScanning }
}

/// When the game next tries to spawn a wandering trader.
public struct WanderingTraderTimer: Sendable, Equatable {
    /// Ticks of play until the next attempt (20 a second).
    public var spawnDelay: Int
    /// Percent chance that attempt succeeds; it rises after each failed attempt.
    public var spawnChance: Int
}

extension LevelInfo {
    /// Whether the world has ever been opened with a modded client or server.
    public var wasModded: Bool { nbt["WasModded"]?.bool ?? false }
    /// Brands of the clients and servers that have opened the world, e.g. `vanilla`, `fabric`.
    public var serverBrands: [String] { nbt["ServerBrands"]?.list?.compactMap(\.string) ?? [] }
    public var disabledDataPacks: [String] { nbt["DataPacks"]?["Disabled"]?.list?.compactMap(\.string) ?? [] }
}

extension World {
    /// Game rules by id: `minecraft:keep_inventory` in 26.1+ (`data/minecraft/game_rules.dat`), or
    /// `keepInventory` from `level.dat` in older worlds, where values are stored as strings.
    public func gameRules() throws -> [String: GameRuleValue] {
        if let rules = try savedData("game_rules")?["data"]?.compound {
            return rules.compactMapValues { value in
                if case .byte(let b) = value { return .bool(b != 0) }
                return value.int.map(GameRuleValue.int)
            }
        }
        return (level.nbt["GameRules"]?.compound ?? [:]).compactMapValues { value in
            switch value.string {
            case "true": .bool(true)
            case "false": .bool(false)
            case let s?: Int(s).map(GameRuleValue.int)
            case nil: nil
            }
        }
    }

    /// Weather from `data/minecraft/weather.dat` (26.1+) or `level.dat`.
    public func weather() throws -> Weather? {
        if let data = try savedData("weather")?["data"] {
            return Weather(isRaining: data["raining"]?.bool ?? false, isThundering: data["thundering"]?.bool ?? false,
                           rainTime: data["rain_time"]?.int ?? 0, thunderTime: data["thunder_time"]?.int ?? 0,
                           clearTime: data["clear_weather_time"]?.int ?? 0)
        }
        let data = level.nbt
        guard data["raining"] != nil else { return nil }
        return Weather(isRaining: data["raining"]?.bool ?? false, isThundering: data["thundering"]?.bool ?? false,
                       rainTime: data["rainTime"]?.int ?? 0, thunderTime: data["thunderTime"]?.int ?? 0,
                       clearTime: data["clearWeatherTime"]?.int ?? 0)
    }

    /// The Overworld's day clock in ticks (24,000 per day; 0 is sunrise): `world_clocks.dat` in
    /// 26.1+, `DayTime` in `level.dat` before.
    public func dayTime() throws -> Int? {
        try savedData("world_clocks")?["data"]?["minecraft:overworld"]?["total_ticks"]?.int ?? level.nbt["DayTime"]?.int
    }

    /// A dimension's world border: its own `data/minecraft/world_border.dat` in 26.1+, or the
    /// single border in `level.dat` before.
    public func worldBorder(of dimension: Dimension) throws -> WorldBorder? {
        let file = dimension.dataDirectory.appendingPathComponent("minecraft/world_border.dat")
        if FileManager.default.fileExists(atPath: file.path), let d = try NBT.read(contentsOf: file)["data"] {
            return WorldBorder(centerX: d["center_x"]?.double ?? 0, centerZ: d["center_z"]?.double ?? 0,
                               size: d["size"]?.double ?? WorldBorder.defaultSize, targetSize: d["lerp_target"]?.double ?? WorldBorder.defaultSize,
                               lerpTime: d["lerp_time"]?.int ?? 0, damagePerBlock: d["damage_per_block"]?.double ?? 0.2,
                               safeZone: d["safe_zone"]?.double ?? 5, warningBlocks: d["warning_blocks"]?.int ?? 5,
                               warningTime: d["warning_time"]?.int ?? 15)
        }
        let d = level.nbt
        guard let size = d["BorderSize"]?.double else { return nil }
        return WorldBorder(centerX: d["BorderCenterX"]?.double ?? 0, centerZ: d["BorderCenterZ"]?.double ?? 0, size: size,
                           targetSize: d["BorderSizeLerpTarget"]?.double ?? size, lerpTime: d["BorderSizeLerpTime"]?.int ?? 0,
                           damagePerBlock: d["BorderDamagePerBlock"]?.double ?? 0.2, safeZone: d["BorderSafeZone"]?.double ?? 5,
                           warningBlocks: d["BorderWarningBlocks"]?.int ?? 5, warningTime: d["BorderWarningTime"]?.int ?? 15)
    }

    /// The wandering trader timer, from `data/minecraft/wandering_trader.dat` (26.1+) or
    /// `level.dat` before.
    public func wanderingTrader() throws -> WanderingTraderTimer? {
        if let data = try savedData("wandering_trader")?["data"] {
            return WanderingTraderTimer(spawnDelay: data["spawn_delay"]?.int ?? 0, spawnChance: data["spawn_chance"]?.int ?? 0)
        }
        guard let delay = level.nbt["WanderingTraderSpawnDelay"]?.int else { return nil }
        return WanderingTraderTimer(spawnDelay: delay, spawnChance: level.nbt["WanderingTraderSpawnChance"]?.int ?? 0)
    }

    /// The Ender Dragon fight, from the End's `ender_dragon_fight.dat` (26.1+) or `level.dat`'s
    /// `DragonFight` before; `nil` if the world has no record of the fight.
    public func enderDragonFight() throws -> EnderDragonFight? {
        var data: NBT?
        if let end = dimension("the_end") {
            let file = end.dataDirectory.appendingPathComponent("minecraft/ender_dragon_fight.dat")
            if FileManager.default.fileExists(atPath: file.path) { data = try NBT.read(contentsOf: file)["data"] }
        }
        if let data {
            return EnderDragonFight(dragonKilled: data["dragon_killed"]?.bool ?? false, previouslyKilled: data["previously_killed"]?.bool ?? false,
                                    remainingGateways: data["gateways"]?.list?.count ?? 0,
                                    needsStateScanning: data["needs_state_scanning"]?.bool ?? true)
        }
        guard let fight = level.nbt["DragonFight"] ?? level.nbt["DimensionData"]?["1"]?["DragonFight"] else { return nil }
        return EnderDragonFight(dragonKilled: fight["DragonKilled"]?.bool ?? false, previouslyKilled: fight["PreviouslyKilled"]?.bool ?? false,
                                remainingGateways: fight["Gateways"]?.list?.count ?? 0,
                                needsStateScanning: fight["NeedsStateScanning"]?.bool ?? true)
    }
}
