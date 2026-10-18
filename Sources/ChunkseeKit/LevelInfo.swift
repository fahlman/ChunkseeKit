import Foundation

/// Global world metadata from `level.dat`.
public struct LevelInfo: Sendable {
    public let name: String?
    public let dataVersion: Int?
    public let versionName: String?
    public let isSnapshot: Bool?
    /// Data versions the world has been saved with, oldest first (26.3+).
    public let versionHistory: [Int]
    public let lastPlayed: Date?
    public let time: Int?
    public let gameType: Int?
    /// e.g. `"normal"`. Older numeric values are mapped to the same names.
    public let difficulty: String?
    public let isHardcore: Bool?
    public let difficultyLocked: Bool?
    public let allowCommands: Bool?
    /// The singleplayer player's UUID; their data is in the players folder (26.1+).
    public let singleplayerUUID: UUID?
    /// World spawn fields are available together, from a complete modern location or legacy XYZ.
    public let spawnDimension: String?
    public let spawnPosition: (x: Int, y: Int, z: Int)?
    public let enabledFeatures: [String]
    public let enabledDataPacks: [String]
    /// The `Data` compound, for fields this type doesn't model.
    public let nbt: NBT

    init(_ root: NBT) throws {
        guard let data = root["Data"] else { throw WorldError.invalidLevelDat }
        nbt = data
        name = data["LevelName"]?.string
        dataVersion = data["DataVersion"]?.int ?? data["Version"]?["Id"]?.int
        versionName = data["Version"]?["Name"]?.string
        isSnapshot = data["Version"]?["Snapshot"]?.bool
        versionHistory = data["version_history"]?.list?.compactMap(\.int) ?? []
        lastPlayed = data["LastPlayed"]?.int.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        time = data["Time"]?.int
        gameType = data["GameType"]?.int
        allowCommands = data["allowCommands"]?.bool
        enabledFeatures = data["enabled_features"]?.list?.compactMap(\.string) ?? []
        enabledDataPacks = data["DataPacks"]?["Enabled"]?.list?.compactMap(\.string) ?? []

        if let settings = data["difficulty_settings"] {
            difficulty = settings["difficulty"]?.string
            isHardcore = settings["hardcore"]?.bool
            difficultyLocked = settings["locked"]?.bool
        } else {
            let names = ["peaceful", "easy", "normal", "hard"]
            difficulty = data["Difficulty"]?.int.flatMap { names.indices.contains($0) ? names[$0] : nil }
            isHardcore = data["hardcore"]?.bool
            difficultyLocked = data["DifficultyLocked"]?.bool
        }

        // 26.1+ stores a UUID reference; older worlds embed the whole player compound.
        singleplayerUUID = data["singleplayer_uuid"]?.uuid ?? data["Player"].flatMap { player in
            player.compound == nil ? nil : player.uuid
        }

        if let spawn = data["spawn"] {
            let location = SavedBlockLocation(spawn)
            spawnDimension = location?.dimension
            spawnPosition = location?.position
        } else if let x = data["SpawnX"]?.int, let y = data["SpawnY"]?.int, let z = data["SpawnZ"]?.int {
            spawnDimension = "minecraft:overworld"
            spawnPosition = (x, y, z)
        } else {
            spawnDimension = nil
            spawnPosition = nil
        }
    }
}
