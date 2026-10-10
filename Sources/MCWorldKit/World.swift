import Foundation

public enum WorldError: Error, Equatable {
    case missingLevelDat
    case invalidLevelDat
}

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
        singleplayerUUID = data["singleplayer_uuid"]?.uuid ?? data["Player"]?["UUID"]?.uuid

        if let spawn = data["spawn"] {
            spawnDimension = spawn["dimension"]?.string
            spawnPosition = spawn["pos"]?.intArray.flatMap { $0.count == 3 ? (Int($0[0]), Int($0[1]), Int($0[2])) : nil }
        } else if let x = data["SpawnX"]?.int, let y = data["SpawnY"]?.int, let z = data["SpawnZ"]?.int {
            spawnDimension = "minecraft:overworld"
            spawnPosition = (x, y, z)
        } else {
            spawnDimension = nil
            spawnPosition = nil
        }
    }
}

/// One dimension's folder: terrain (`region`), entities, and points of interest, each a set of region files.
public struct Dimension: Sendable {
    /// Namespaced ID, e.g. `minecraft:the_nether`.
    public let id: String
    public let url: URL

    public var regionDirectory: URL { url.appendingPathComponent("region") }
    public var entitiesDirectory: URL { url.appendingPathComponent("entities") }
    public var poiDirectory: URL { url.appendingPathComponent("poi") }
    /// Per-dimension saved data (raids, world border, chunk tickets), 26.1+.
    public var dataDirectory: URL { url.appendingPathComponent("data") }

    /// Coordinates and URLs of every terrain region file.
    public func regionFiles() -> [(x: Int, z: Int, url: URL)] {
        Self.regionFiles(in: regionDirectory)
    }

    static func regionFiles(in directory: URL) -> [(x: Int, z: Int, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            RegionFile.parseCoordinates(name).map { ($0.x, $0.z, directory.appendingPathComponent(name)) }
        }.sorted { ($0.x, $0.z) < ($1.x, $1.z) }
    }

    /// The terrain region file containing the given region coordinates, if it exists.
    public func region(x: Int, z: Int) throws -> RegionFile? {
        try Self.region(in: regionDirectory, x: x, z: z)
    }

    static func region(in directory: URL, x: Int, z: Int) throws -> RegionFile? {
        let url = directory.appendingPathComponent("r.\(x).\(z).mca")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RegionFile(contentsOf: url)
    }

    /// The chunk at absolute chunk coordinates, or `nil` if it hasn't been generated.
    public func chunk(x: Int, z: Int) throws -> Chunk? {
        guard let region = try region(x: x >> 5, z: z >> 5),
              let nbt = try region.chunkNBT(localX: x & 31, localZ: z & 31) else { return nil }
        return try Chunk(nbt: nbt)
    }

    /// The block at absolute world coordinates. Loads the chunk each call; cache `Chunk`s for bulk reads.
    public func block(x: Int, y: Int, z: Int) throws -> BlockState? {
        try chunk(x: x >> 4, z: z >> 4)?.block(x: x & 15, y: y, z: z & 15)
    }

    /// Entities saved in the given chunk (stored separately from terrain since 1.17).
    public func entities(chunkX: Int, chunkZ: Int) throws -> [NBT] {
        guard let region = try Self.region(in: entitiesDirectory, x: chunkX >> 5, z: chunkZ >> 5),
              let nbt = try region.chunkNBT(localX: chunkX & 31, localZ: chunkZ & 31) else { return [] }
        return nbt["Entities"]?.list ?? []
    }
}

/// A Java Edition world folder. Supports the 26.1+ layout (`dimensions/minecraft/overworld`,
/// `players/data`) and falls back to the older layout (`region/`, `DIM-1`, `playerdata/`).
public struct World: Sendable {
    public let url: URL
    public let level: LevelInfo

    public init(contentsOf url: URL) throws {
        self.url = url
        let levelDat = url.appendingPathComponent("level.dat")
        guard FileManager.default.fileExists(atPath: levelDat.path) else { throw WorldError.missingLevelDat }
        level = try LevelInfo(NBT.read(contentsOf: levelDat))
    }

    /// True when the world uses the 26.1+ folder layout.
    public var usesDimensionsFolderForVanilla: Bool {
        exists("dimensions/minecraft/overworld")
    }

    private func exists(_ relative: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// All dimensions with a folder on disk, vanilla first.
    public func dimensions() -> [Dimension] {
        var result = [Dimension]()
        var seen = Set<String>()
        for id in ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end"] {
            if let d = dimension(id) { result.append(d); seen.insert(id) }
        }
        // Everything under dimensions/<namespace>/<path>/. Paths may contain '/', so walk for region-like folders.
        let root = url.appendingPathComponent("dimensions")
        let fm = FileManager.default
        for ns in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
            var stack = [(path: "", dir: root.appendingPathComponent(ns))]
            while let (path, dir) = stack.popLast() {
                let children = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
                if !path.isEmpty, children.contains(where: { ["region", "entities", "poi"].contains($0) }) {
                    let id = "\(ns):\(path)"
                    if seen.insert(id).inserted { result.append(Dimension(id: id, url: dir)) }
                    continue
                }
                for child in children.reversed() where child != "data" {
                    var isDir: ObjCBool = false
                    let childURL = dir.appendingPathComponent(child)
                    if fm.fileExists(atPath: childURL.path, isDirectory: &isDir), isDir.boolValue {
                        stack.append((path.isEmpty ? child : path + "/" + child, childURL))
                    }
                }
            }
        }
        return result
    }

    /// Looks up a dimension by namespaced ID (`minecraft:overworld`, `overworld`, `mymod:mining`).
    public func dimension(_ id: String) -> Dimension? {
        let full = id.contains(":") ? id : "minecraft:" + id
        let parts = full.split(separator: ":", maxSplits: 1).map(String.init)
        let modern = "dimensions/\(parts[0])/\(parts[1])"
        if exists(modern) { return Dimension(id: full, url: url.appendingPathComponent(modern)) }
        // Pre-26.1 locations of the vanilla dimensions.
        switch full {
        case "minecraft:overworld" where exists("region"): return Dimension(id: full, url: url)
        case "minecraft:the_nether" where exists("DIM-1"): return Dimension(id: full, url: url.appendingPathComponent("DIM-1"))
        case "minecraft:the_end" where exists("DIM1"): return Dimension(id: full, url: url.appendingPathComponent("DIM1"))
        default: return nil
        }
    }

    // MARK: Players

    /// Directory of `<uuid>.dat` player files: `players/data` (26.1+) or `playerdata`.
    public var playerDataDirectory: URL {
        exists("players/data") || !exists("playerdata")
            ? url.appendingPathComponent("players/data")
            : url.appendingPathComponent("playerdata")
    }

    /// UUIDs of every player with saved data.
    public func playerUUIDs() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: playerDataDirectory.path)) ?? []
        return names.compactMap { $0.hasSuffix(".dat") ? UUID(uuidString: String($0.dropLast(4))) : nil }
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// A player's saved data. For older singleplayer worlds without a file, falls back to `level.dat`'s `Player`.
    public func playerData(_ uuid: UUID) throws -> NBT? {
        let file = playerDataDirectory.appendingPathComponent(uuid.uuidString.lowercased() + ".dat")
        if FileManager.default.fileExists(atPath: file.path) { return try NBT.read(contentsOf: file) }
        if let embedded = level.nbt["Player"], embedded["UUID"]?.uuid == uuid { return embedded }
        return nil
    }

    /// A player's advancements or statistics JSON (`kind` is `"advancements"` or `"stats"`).
    public func playerJSON(_ uuid: UUID, kind: String) -> URL? {
        let name = uuid.uuidString.lowercased() + ".json"
        for dir in ["players/\(kind)", kind] {
            let file = url.appendingPathComponent(dir).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    // MARK: Saved data

    /// Reads a world-level saved-data file, e.g. `savedData("game_rules")` → `data/minecraft/game_rules.dat`.
    /// Falls back to the pre-26.1 flat `data/<name>.dat` location.
    public func savedData(_ name: String, namespace: String = "minecraft") throws -> NBT? {
        for relative in ["data/\(namespace)/\(name).dat", "data/\(name).dat"] {
            let file = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: file.path) { return try NBT.read(contentsOf: file) }
        }
        return nil
    }

    /// The world seed: from `data/minecraft/world_gen_settings.dat` (26.1+) or `level.dat` (older).
    public func seed() throws -> Int64? {
        func find(_ nbt: NBT?) -> Int64? {
            guard let nbt else { return nil }
            if case .long(let v)? = nbt["seed"] { return v }
            return nbt.compound?.values.lazy.compactMap { $0.compound != nil ? find($0) : nil }.first
        }
        return find(try savedData("world_gen_settings")) ?? find(level.nbt["WorldGenSettings"])
    }
}
