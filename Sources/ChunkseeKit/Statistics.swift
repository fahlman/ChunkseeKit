import Foundation

/// A player's statistics from `players/stats/<uuid>.json`: counts by category and id, e.g.
/// `minecraft:mined` → `minecraft:stone` → 1,204.
///
/// Also reads the flat format from before 1.7.6 (`stat.walkOneCm`, files named after the player),
/// mapping its general statistics to `minecraft:custom` ids; its per-item statistics use numeric
/// item ids that aren't mapped and are left out.
public struct PlayerStatistics: Sendable, Equatable {
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

    /// Distances by way of travel, in centimeters: `minecraft:walk_one_cm` and the like.
    public var distances: [String: Int] {
        (values["minecraft:custom"] ?? [:]).filter { $0.key.hasSuffix("_one_cm") }
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
