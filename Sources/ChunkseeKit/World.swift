import Foundation

public enum WorldError: Error, Equatable {
    case missingLevelDat
    case invalidLevelDat
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

    /// The saved worlds under a Minecraft folder: each folder with a `level.dat` inside a `saves`
    /// folder. The launcher gives every installation its own game folder (`saves` directly under
    /// `~/Library/Application Support/minecraft`, or deeper, such as `vanilla/release/saves`), so
    /// `saves` folders up to `depth` levels below `folder` are found. A `saves` folder chosen
    /// directly counts too. `backups` folders, which hold copies of worlds, aren't searched.
    public static func saved(under folder: URL, depth: Int = 3) -> [URL] {
        let fileManager = FileManager.default
        func folders(in dir: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        func worlds(in saves: URL) -> [URL] {
            folders(in: saves).filter { fileManager.fileExists(atPath: $0.appendingPathComponent("level.dat").path) }
        }
        if folder.lastPathComponent == "saves" { return worlds(in: folder).sorted { $0.path < $1.path } }
        var found: [URL] = []
        var level = [folder]
        for _ in 0...max(0, depth) {
            var next: [URL] = []
            for dir in level {
                for child in folders(in: dir) {
                    switch child.lastPathComponent {
                    case "saves": found += worlds(in: child)
                    case "backups": continue
                    default: next.append(child)
                    }
                }
            }
            level = next
        }
        return found.sorted { $0.path < $1.path }
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
        try Self.readSavedData(name, namespace: namespace, at: url, includingFlatFile: true)
    }

    /// The border/fight file readers support the namespaced layout. They opt out of the older
    /// world-file fallback rather than reinterpret a flat dimension file.
    static func readSavedData(_ name: String, namespace: String = "minecraft", at root: URL,
                              includingFlatFile: Bool) throws -> NBT? {
        let modern = "data/\(namespace)/\(name).dat"
        for relative in includingFlatFile ? [modern, "data/\(name).dat"] : [modern] {
            let file = root.appendingPathComponent(relative)
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
