import Foundation

/// Build limits and ceiling metadata from a dimension type, independent of generated terrain.
public struct DimensionType: Sendable, Equatable {
    public let minY: Int
    public let height: Int
    /// Minecraft's logical height can be smaller than its build height (128 versus 256 in the Nether).
    public let logicalHeight: Int
    public let hasCeiling: Bool

    public var maxY: Int { minY + height - 1 }
    public var buildRange: ClosedRange<Int> { minY...maxY }

    private init?(minY: Int, height: Int, logicalHeight: Int, hasCeiling: Bool) {
        // DimensionType's 26.3 codec/constructor: 12 packed Y bits, less two reserved sections.
        guard (-2032...2031).contains(minY), (16...4064).contains(height),
              minY.isMultiple(of: 16), height.isMultiple(of: 16),
              minY + height <= 2032, (0...height).contains(logicalHeight) else { return nil }
        self.minY = minY; self.height = height; self.logicalHeight = logicalHeight; self.hasCeiling = hasCeiling
    }

    init?(_ nbt: NBT) {
        guard let minY = nbt["min_y"]?.int, let height = nbt["height"]?.int,
              let logical = nbt["logical_height"]?.int, let ceiling = nbt["has_ceiling"]?.bool else { return nil }
        self.init(minY: minY, height: height, logicalHeight: logical, hasCeiling: ceiling)
    }

    init?(json: Data) {
        guard let value = try? JSONDecoder().decode(Definition.self, from: json) else { return nil }
        self.init(minY: value.minY, height: value.height, logicalHeight: value.logicalHeight, hasCeiling: value.hasCeiling)
    }

    private struct Definition: Decodable {
        let minY: Int, height: Int, logicalHeight: Int
        let hasCeiling: Bool
        enum CodingKeys: String, CodingKey {
            case minY = "min_y", height, logicalHeight = "logical_height", hasCeiling = "has_ceiling"
        }
    }

    static func vanilla(_ id: String, version: Int?) -> Self? {
        guard version == SaveVersion.java26_3 else { return nil }
        switch id {
        case "minecraft:overworld": return Self(minY: -64, height: 384, logicalHeight: 384, hasCeiling: false)
        case "minecraft:overworld_caves": return Self(minY: -64, height: 384, logicalHeight: 384, hasCeiling: true)
        case "minecraft:the_nether": return Self(minY: 0, height: 256, logicalHeight: 128, hasCeiling: true)
        case "minecraft:the_end": return Self(minY: 0, height: 256, logicalHeight: 256, hasCeiling: false)
        default: return nil
        }
    }
}

extension World {
    /// Resolves saved dimension-to-type links, not dimension folder names or occupied sections.
    ///
    /// Reads modern world_gen_settings or legacy WorldGenSettings, including inline definitions.
    /// References resolve through enabled folder data packs, in priority order, and verified
    /// 26.3 vanilla definitions. ZIP/built-in experimental packs, overlays and resource filters
    /// are unsupported: an unresolved higher-priority pack prevents falling back to lower ones.
    /// Missing/malformed/unresolved types are omitted. Read errors propagate. No files are written.
    public func dimensionTypes() throws -> [String: DimensionType] {
        let settings: NBT?, version: Int?
        if let saved = try savedData("world_gen_settings") {
            settings = saved["data"]
            version = saved["DataVersion"]?.int ?? level.dataVersion
        } else {
            settings = level.nbt["WorldGenSettings"]
            version = level.dataVersion
        }
        guard let dimensions = settings?["dimensions"]?.compound else { return [:] }
        let hasReferences = dimensions.values.contains { $0["type"]?.string != nil }
        let packs = try hasReferences ? level.enabledDataPacks.reversed().map { try DimensionTypePack.load($0, in: url) } : []
        var result: [String: DimensionType] = [:]
        var seen = Set<String>()
        var duplicates = Set<String>()
        for (key, dimension) in dimensions {
            guard let id = Identifier(key), !id.path.isEmpty else { continue }
            if !seen.insert(id.description).inserted { duplicates.insert(id.description); continue }
            guard let saved = dimension["type"] else { continue }
            if let reference = saved.string {
                guard let typeID = Identifier(reference), !typeID.path.isEmpty else { continue }
                result[id.description] = try Self.resolve(typeID, in: packs, version: version)
            } else {
                result[id.description] = DimensionType(saved)
            }
        }
        for id in duplicates { result[id] = nil }
        return result
    }

    private static func resolve(_ id: Identifier, in packs: [DimensionTypePack], version: Int?) throws -> DimensionType? {
        for pack in packs {
            switch pack {
            case .vanilla:
                guard version == SaveVersion.java26_3 else { return nil }
                if let value = DimensionType.vanilla(id.description, version: version) { return value }
            case .unavailable: return nil
            case .folder(let root):
                guard let file = DimensionTypePack.file("data/\(id.namespace)/dimension_type/\(id.path).json", under: root) else { return nil }
                if FileManager.default.fileExists(atPath: file.path) {
                    // A malformed override is still an override; never substitute a lower definition.
                    return DimensionType(json: try Data(contentsOf: file))
                }
            }
        }
        return nil
    }
}

private enum DimensionTypePack {
    case vanilla
    case folder(URL)
    case unavailable

    static func load(_ id: String, in world: URL) throws -> Self {
        if id == "vanilla" { return .vanilla }
        guard id.hasPrefix("file/") else { return .unavailable }
        let name = String(id.dropFirst(5))
        guard !name.isEmpty, !name.contains("/"), let root = file("datapacks", under: world),
              let folder = file(name, under: root) else { return .unavailable }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let metadata = file("pack.mcmeta", under: folder), FileManager.default.fileExists(atPath: metadata.path) else { return .unavailable }
        let data = try Data(contentsOf: metadata)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["pack"] is [String: Any], json["overlays"] == nil, json["filter"] == nil else { return .unavailable }
        return .folder(folder)
    }

    /// Identifier syntax permits dot segments; file lookup must separately stay inside the pack.
    static func file(_ path: String, under root: URL) -> URL? {
        guard !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.pathComponents.starts(with: root.pathComponents), file.pathComponents.count > root.pathComponents.count else { return nil }
        return file
    }
}
