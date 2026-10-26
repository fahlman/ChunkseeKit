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
    /// References resolve through enabled folder/ZIP data packs, in priority order.
    /// Pass nil explicitly when no game is available; missing definitions remain unavailable.
    /// Built-in packs, overlays and resource filters
    /// are unsupported: an unresolved higher-priority pack prevents falling back to lower ones.
    /// Missing/malformed/unresolved types are omitted. Read errors propagate. No files are written.
    /// Folder references use registered resources: linked category folders and descendants are
    /// skipped, while contained namespace aliases are allowed. Inline values need no registry read.
    /// This type-only query does not load generator resources.
    ///
    /// Uses the caller's supplied jar for vanilla definitions, including time/sky metadata.
    /// Version labels do not gate readable definitions. Enabled folder/ZIP overrides retain
    /// priority; a bad override never falls back to the jar. No jar artwork is read or retained here.
    public func dimensionTypes(assets: GameAssets?) throws -> [String: DimensionType] {
        try readDimensionSettings(includeGeneration: false, assets: assets).compactMapValues(\.type)
    }

    /// Reads each saved dimension's type and noise-generation facts together. The two values
    /// resolve independently; an unavailable generator does not discard a known dimension type.
    /// Uses the same pack priority and unsupported-resource rules as dimensionTypes(assets:).
    /// Only minecraft:noise generators have noiseGeneration. No roof or biome is inferred.
    /// Pass nil explicitly when no game is available; missing definitions remain unavailable.
    public func dimensionSettings(assets: GameAssets?) throws -> [String: DimensionSettings] {
        try readDimensionSettings(includeGeneration: true, assets: assets)
    }

    private func readDimensionSettings(includeGeneration: Bool, assets: GameAssets?) throws -> [String: DimensionSettings] {
        try Task.checkCancellation()
        let settings: NBT?
        if let saved = try savedData("world_gen_settings") {
            settings = saved["data"]
        } else {
            settings = level.nbt["WorldGenSettings"]
        }
        guard let dimensions = settings?["dimensions"]?.compound else { return [:] }
        let hasTypes = dimensions.values.contains { $0["type"]?.string != nil }
        let hasNoise = includeGeneration && dimensions.values.contains { Self.noiseSettings(in: $0)?.string != nil }
        let packs = try hasTypes || hasNoise ? resourcePacks(assets: assets) ?? [.unavailable] : []
        let types = try WorldResourcePack.Registry(directory: "dimension_type", in: hasTypes ? packs : [])
        let generators = try WorldResourcePack.Registry(directory: "worldgen/noise_settings", in: hasNoise ? packs : [])
        var result: [String: DimensionSettings] = [:]
        var seen = Set<String>()
        var duplicates = Set<String>()
        for (key, dimension) in dimensions {
            try Task.checkCancellation()
            guard let id = Identifier(key), !id.path.isEmpty else { continue }
            if !seen.insert(id.description).inserted { duplicates.insert(id.description); continue }
            guard dimension.compound != nil else { continue }
            let type: DimensionType? = try types.read(dimension["type"],
                inline: DimensionType.init, json: DimensionType.init(json:))
            let noise: NoiseGenerationSettings?
            if includeGeneration {
                noise = try generators.read(Self.noiseSettings(in: dimension),
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
