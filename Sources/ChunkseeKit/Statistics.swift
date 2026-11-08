import Foundation

/// A player's statistics from `players/stats/<uuid>.json`: counts by category and id, e.g.
/// `minecraft:mined` → `minecraft:stone` → 1,204.
/// Saved custom-statistic names follow the game's generated rename chain; counts are unchanged.
///
/// Also reads the flat format from before 1.7.6 (`stat.walkOneCm`, files named after the player),
/// mapping its general statistics to `minecraft:custom` ids. Numeric legacy item/block keys
/// are retained verbatim in that category because their identities cannot be inferred.
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
        guard let root = try AssetJSON.value(from: data, limitsNumbers: false) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        dataVersion = try? AssetJSON.integer(root["DataVersion"])
        if let stats = root["stats"] as? [String: Any] {
            // The game's map codec keeps readable entries after a member fails. Unknown
            // identifiers remain saved facts even when an installed registry lacks them.
            let readable = stats.compactMapValues { value -> [String: Int]? in
                (value as? [String: Any])?.compactMapValues { try? AssetJSON.integer($0) }
            }
            values = SaveDataUpgrade.statistics(readable, dataVersion: dataVersion)
            return
        }
        var custom: [String: Int] = [:]
        for (key, value) in root {
            guard key.hasPrefix("stat."), let count = try? AssetJSON.integer(value) else { continue }
            let id = key.contains(where: \.isNumber) ? key : Self.modernID(legacy: String(key.dropFirst(5)))
            custom[id] = count
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

    /// The game's formatter scale for a general statistic, including generated historical
    /// aliases. Code-only units apply independently of saved version labels. Nil means keep
    /// the raw number; a familiar name or suffix never establishes an unknown statistic's unit.
    public func unit(of id: String, in category: String = "minecraft:custom") -> Unit? {
        guard Identifier(category)?.description == "minecraft:custom",
              let id = Identifier(id) else { return nil }
        return GeneratedStatisticUnits.values[SaveDataUpgrade.currentStatisticIdentifier(id.description)]
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

    /// Reads every entry of an advancements file, upgrading saved names and sorting by id.
    /// Ambiguous name collisions retain their original keys and progress.
    public static func list(json data: Data) throws -> [AdvancementProgress] {
        guard let root = try AssetJSON.value(from: data, limitsNumbers: false) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let interpreted = SaveDataUpgrade.advancements(root, dataVersion: try? AssetJSON.integer(root["DataVersion"]))
        return interpreted.compactMap { id, value -> AdvancementProgress? in
            guard let entry = value as? [String: Any] else { return nil }
            let criteria = (entry["criteria"] as? [String: String] ?? [:]).compactMapValues(SavedDate.parse)
            return AdvancementProgress(id: id, isDone: (try? AssetJSON.boolean(entry["done"])) ?? false, criteria: criteria)
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
