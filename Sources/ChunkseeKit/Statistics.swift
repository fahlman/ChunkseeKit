import Foundation

/// A player's statistics from `players/stats/<uuid>.json`: counts by category and id, e.g.
/// `minecraft:mined` → `minecraft:stone` → 1,204.
///
/// Also reads the flat format from before 1.7.6 (`stat.walkOneCm`, files named after the player),
/// mapping its general statistics to `minecraft:custom` ids; its per-item statistics use numeric
/// item ids that aren't mapped and are left out.
public struct PlayerStatistics: Sendable, Equatable {
    /// A scaled statistic's saved unit. Unscaled counts and unknown units have no unit value.
    public enum Unit: Sendable, Equatable {
        case centimeters
        case ticks
        case tenthsOfDamagePoint
    }

    public var dataVersion: Int?
    /// Category → statistic id → value.
    public var values: [String: [String: Int]]

    public init(dataVersion: Int? = nil, values: [String: [String: Int]]) {
        self.dataVersion = dataVersion
        self.values = values
    }

    public init(json data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        dataVersion = root["DataVersion"] as? Int
        if let stats = root["stats"] as? [String: [String: Int]] {
            values = stats
            return
        }
        var custom: [String: Int] = [:]
        for (key, value) in root {
            guard let count = value as? Int, key.hasPrefix("stat."), !key.contains(where: \.isNumber) else { continue }
            custom[Self.modernID(legacy: String(key.dropFirst(5)))] = count
        }
        values = custom.isEmpty ? [:] : ["minecraft:custom": custom]
    }

    /// `walkOneCm` → `minecraft:walk_one_cm`; `playOneMinute`, which counted ticks, → `minecraft:play_time`.
    static func modernID(legacy name: String) -> String {
        if name == "playOneMinute" { return "minecraft:play_time" }
        var snake = ""
        for character in name {
            if character.isUppercase { snake += "_" + character.lowercased() } else { snake.append(character) }
        }
        return "minecraft:" + snake
    }

    public func value(_ id: String, in category: String = "minecraft:custom") -> Int? {
        values[category]?[id]
    }

    /// Time played in ticks (20 a second). Named `play_one_minute` from 1.13 to 1.16.
    public var playTime: Int? {
        value("minecraft:play_time") ?? value("minecraft:play_one_minute")
    }

    /// The saved scale for a known vanilla general statistic; nil means keep its raw number.
    /// Time and distance include the supported legacy IDs. Damage scaling is verified for 26.3
    /// and 26.4 Snapshot 5; unknown versions must not acquire a conversion from their names.
    public func unit(of id: String, in category: String = "minecraft:custom") -> Unit? {
        guard Identifier(category)?.description == "minecraft:custom",
              let id = Identifier(id), id.namespace == "minecraft" else { return nil }
        switch id.path {
        case "play_time", "play_one_minute", "total_world_time", "time_since_death", "time_since_rest", "sneak_time":
            return .ticks
        case "walk_one_cm", "crouch_one_cm", "sprint_one_cm", "walk_on_water_one_cm", "fall_one_cm",
             "climb_one_cm", "fly_one_cm", "walk_under_water_one_cm", "minecart_one_cm", "boat_one_cm",
             "pig_one_cm", "happy_ghast_one_cm", "horse_one_cm", "aviate_one_cm", "swim_one_cm",
             "strider_one_cm", "nautilus_one_cm", "dive_one_cm":
            return .centimeters
        case "damage_dealt", "damage_dealt_absorbed", "damage_dealt_resisted", "damage_taken",
             "damage_blocked_by_shield", "damage_absorbed", "damage_resisted":
            return SaveVersion.isVerifiedModern(dataVersion) ? .tenthsOfDamagePoint : nil
        default:
            return nil
        }
    }

    /// Known vanilla travel distances, in centimeters, including the legacy diving statistic.
    /// Unknown IDs are retained in `values` without inferring a unit from their suffix.
    public var distances: [String: Int] {
        (values["minecraft:custom"] ?? [:]).filter { unit(of: $0.key) == .centimeters }
    }
}

/// One advancement's progress from `players/advancements/<uuid>.json`.
public struct AdvancementProgress: Sendable, Equatable {
    /// e.g. `minecraft:story/mine_diamond`; recipe unlocks are `minecraft:recipes/…`.
    public var id: String
    public var isDone: Bool
    /// When each criterion was met.
    public var criteria: [String: Date]

    /// Recipe unlocks are stored as advancements but aren't shown as advancements in the game.
    public var isRecipe: Bool { id.split(separator: ":").last?.hasPrefix("recipes/") ?? false }

    /// When the advancement was completed: its last criterion's date.
    public var completed: Date? { isDone ? criteria.values.max() : nil }

    /// Reads every entry of an advancements file, sorted by id.
    public static func list(json data: Data) throws -> [AdvancementProgress] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return root.compactMap { id, value -> AdvancementProgress? in
            guard let entry = value as? [String: Any] else { return nil }
            let criteria = (entry["criteria"] as? [String: String] ?? [:]).compactMapValues(SavedDate.parse)
            return AdvancementProgress(id: id, isDone: entry["done"] as? Bool ?? false, criteria: criteria)
        }.sorted { $0.id < $1.id }
    }
}

extension World {
    /// A player's statistics, or `nil` if they have no statistics file.
    public func statistics(for uuid: UUID) throws -> PlayerStatistics? {
        guard let file = playerJSON(uuid, kind: "stats") else { return nil }
        return try PlayerStatistics(json: Data(contentsOf: file))
    }

    /// Statistics from before 1.7.6, stored under the player's name rather than their UUID.
    public func statistics(forName name: String) throws -> PlayerStatistics? {
        for dir in ["players/stats", "stats"] {
            let file = url.appendingPathComponent(dir).appendingPathComponent(name + ".json")
            if FileManager.default.fileExists(atPath: file.path) { return try PlayerStatistics(json: Data(contentsOf: file)) }
        }
        return nil
    }

    /// A player's advancements, or `nil` if they have no advancements file.
    public func advancements(for uuid: UUID) throws -> [AdvancementProgress]? {
        guard let file = playerJSON(uuid, kind: "advancements") else { return nil }
        return try AdvancementProgress.list(json: Data(contentsOf: file))
    }
}
