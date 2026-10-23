import Foundation

/// Independently available facts from one saved dimension definition.
public struct DimensionSettings: Sendable, Equatable {
    public let type: DimensionType?
    /// Nil for non-noise generators or missing, unreadable or unresolved generation bounds.
    /// Other facts, such as sea level, can be independently unavailable.
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
    /// Folder references use registered resources: linked category folders and descendants are
    /// skipped, while contained namespace aliases are allowed. Inline values need no registry read.
    /// This type-only query does not load generator resources.
    public func dimensionTypes() throws -> [String: DimensionType] {
        try readDimensionSettings(includeGeneration: false).compactMapValues(\.type)
    }

    /// Reads each saved dimension's type and noise-generation facts together. The two values
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
        let hasTypes = dimensions.values.contains { $0["type"]?.string != nil }
        let hasNoise = includeGeneration && dimensions.values.contains { Self.noiseSettings(in: $0)?.string != nil }
        let packs = try hasTypes || hasNoise ? WorldResourcePack.load(enabled: level.enabledDataPacks, in: url,
            vanilla: version == SaveVersion.java26_3 ? .vanilla : .unavailable) : []
        let types = try WorldResourcePack.Registry(directory: "dimension_type", in: hasTypes ? packs : [])
        let generators = try WorldResourcePack.Registry(directory: "worldgen/noise_settings", in: hasNoise ? packs : [])
        var result: [String: DimensionSettings] = [:]
        var seen = Set<String>()
        var duplicates = Set<String>()
        for (key, dimension) in dimensions {
            guard let id = Identifier(key), !id.path.isEmpty else { continue }
            if !seen.insert(id.description).inserted { duplicates.insert(id.description); continue }
            guard dimension.compound != nil else { continue }
            let type: DimensionType? = try types.read(dimension["type"],
                vanilla: { DimensionType.vanilla($0, version: version) }, inline: DimensionType.init, json: DimensionType.init(json:))
            let noise: NoiseGenerationSettings?
            if includeGeneration {
                noise = try generators.read(Self.noiseSettings(in: dimension),
                    vanilla: { NoiseGenerationSettings.vanilla($0, version: version) },
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
