import Foundation

/// Independently available facts from one saved dimension definition.
public struct DimensionSettings: Sendable, Equatable {
    public let type: DimensionType?
    /// Nil for non-noise generators or missing, malformed or unresolved settings.
    public let noiseGeneration: NoiseGenerationSettings?
}

extension World {
    /// Resolves saved dimension-to-type links, not dimension folder names or occupied sections.
    ///
    /// Reads modern world_gen_settings or legacy WorldGenSettings, including inline definitions.
    /// References resolve through enabled folder/ZIP data packs, in priority order, and verified
    /// 26.3 vanilla definitions. Built-in experimental packs, overlays and resource filters
    /// are unsupported: an unresolved higher-priority pack prevents falling back to lower ones.
    /// Missing/malformed/unresolved types are omitted. Read errors propagate. No files are written.
    /// This type-only query does not load generator resources.
    public func dimensionTypes() throws -> [String: DimensionType] {
        try readDimensionSettings(includeGeneration: false).compactMapValues(\.type)
    }

    /// Reads each saved dimension's type and noise-generation bounds together. The two facts
    /// resolve independently; an unavailable generator does not discard a known dimension type.
    /// Uses the same version, pack priority and unsupported-resource rules as dimensionTypes().
    /// Only minecraft:noise generators have noiseGeneration. No roof or biome is inferred.
    public func dimensionSettings() throws -> [String: DimensionSettings] {
        try readDimensionSettings(includeGeneration: true)
    }

    private func readDimensionSettings(includeGeneration: Bool) throws -> [String: DimensionSettings] {
        let settings: NBT?, version: Int?
        if let saved = try savedData("world_gen_settings") {
            settings = saved["data"]
            version = saved["DataVersion"]?.int ?? level.dataVersion
        } else {
            settings = level.nbt["WorldGenSettings"]
            version = level.dataVersion
        }
        guard let dimensions = settings?["dimensions"]?.compound else { return [:] }
        let hasReferences = dimensions.values.contains {
            $0["type"]?.string != nil || (includeGeneration && Self.noiseSettings(in: $0)?.string != nil)
        }
        let packs = try hasReferences ? level.enabledDataPacks.reversed().map { try DimensionResourcePack.load($0, in: url) } : []
        var result: [String: DimensionSettings] = [:]
        var seen = Set<String>()
        var duplicates = Set<String>()
        for (key, dimension) in dimensions {
            guard let id = Identifier(key), !id.path.isEmpty else { continue }
            if !seen.insert(id.description).inserted { duplicates.insert(id.description); continue }
            guard dimension.compound != nil else { continue }
            let type: DimensionType? = try DimensionResourcePack.read(dimension["type"], directory: "dimension_type",
                in: packs, version: version, vanilla: DimensionType.vanilla, inline: DimensionType.init, json: DimensionType.init(json:))
            let noise: NoiseGenerationSettings?
            if includeGeneration {
                noise = try DimensionResourcePack.read(Self.noiseSettings(in: dimension), directory: "worldgen/noise_settings",
                    in: packs, version: version, vanilla: NoiseGenerationSettings.vanilla,
                    inline: NoiseGenerationSettings.init, json: NoiseGenerationSettings.init(json:))
            } else {
                noise = nil
            }
            result[id.description] = DimensionSettings(type: type, noiseGeneration: noise)
        }
        for id in duplicates { result[id] = nil }
        return result
    }

    private static func noiseSettings(in dimension: NBT) -> NBT? {
        guard let generator = dimension["generator"], let raw = generator["type"]?.string,
              Identifier(raw)?.description == "minecraft:noise" else { return nil }
        return generator["settings"]
    }
}

/// Dimension types and noise settings use the same enabled resource-pack order and safe paths.
private enum DimensionResourcePack {
    case vanilla
    case folder(URL)
    case zip(ZipResources)
    case unavailable

    static func read<Value>(_ saved: NBT?, directory: String, in packs: [Self], version: Int?,
                            vanilla: (String, Int?) -> Value?, inline: (NBT) -> Value?,
                            json: (Data) -> Value?) throws -> Value? {
        guard let saved else { return nil }
        guard let reference = saved.string else { return inline(saved) }
        guard let id = Identifier(reference), !id.path.isEmpty else { return nil }
        let path = "data/\(id.namespace)/\(directory)/\(id.path).json"
        guard validPath(path) else { return nil }
        for pack in packs {
            switch pack {
            case .vanilla:
                guard version == SaveVersion.java26_3 else { return nil }
                if let value = vanilla(id.description, version) { return value }
            case .unavailable: return nil
            case .folder(let root):
                guard let file = Self.file(path, under: root) else { return nil }
                if FileManager.default.fileExists(atPath: file.path) {
                    // An invalid override is still an override, never a reason to try a lower pack.
                    return json(try Data(contentsOf: file))
                }
            case .zip(let resources):
                if resources.contains(path) {
                    guard let data = resources.read(path) else { return nil }
                    return json(data)
                }
            }
        }
        return nil
    }

    static func load(_ id: String, in world: URL) throws -> Self {
        if id == "vanilla" { return .vanilla }
        guard id.hasPrefix("file/") else { return .unavailable }
        let name = String(id.dropFirst(5))
        guard !name.isEmpty, !name.contains("/"), let root = file("datapacks", under: world),
              let folder = file(name, under: root) else { return .unavailable }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { return .unavailable }
        let result: Self, data: Data
        if isDirectory.boolValue {
            guard let metadata = file("pack.mcmeta", under: folder), FileManager.default.fileExists(atPath: metadata.path) else { return .unavailable }
            data = try Data(contentsOf: metadata)
            result = .folder(folder)
        } else {
            guard name.hasSuffix(".zip"), let resources = ZipResources(data: try Data(contentsOf: folder)),
                  let metadata = resources.read("pack.mcmeta") else { return .unavailable }
            data = metadata
            result = .zip(resources)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["pack"] is [String: Any], json["overlays"] == nil, json["filter"] == nil else { return .unavailable }
        return result
    }

    static func validPath(_ path: String) -> Bool {
        !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Identifier syntax permits dot segments; file lookup must separately stay inside the pack.
    static func file(_ path: String, under root: URL) -> URL? {
        guard validPath(path) else { return nil }
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.pathComponents.starts(with: root.pathComponents), file.pathComponents.count > root.pathComponents.count else { return nil }
        return file
    }
}
