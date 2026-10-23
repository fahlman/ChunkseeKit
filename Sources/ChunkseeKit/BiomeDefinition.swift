import Foundation

/// Data-defined climate and color facts. Image decoding and neighboring-biome blending are client-owned.
public struct BiomeDefinition: Sendable, Equatable {
    /// Base climate values remain unclamped; color resolution clamps them when sampling its maps.
    public let temperature: Float
    public let downfall: Float
    /// Colors are 24-bit RGB. Missing overrides use the client's corresponding color map.
    public let waterColor: UInt32
    public let grassColor: UInt32?
    public let foliageColor: UInt32?
    public let dryFoliageColor: UInt32?
    public let grassColorModifier: GrassColorModifier

    public enum GrassColorModifier: String, Sendable {
        case none
        case darkForest = "dark_forest"
        case swamp
    }

    init?(json: Data) {
        guard json.count <= ZipResources.maximumResourceSize else { return nil }
        do {
            let root = try AssetJSON.object(JSONSerialization.jsonObject(with: json))
            let effects = try AssetJSON.object(root["effects"])
            temperature = try AssetJSON.number(root["temperature"])
            downfall = try AssetJSON.number(root["downfall"])
            waterColor = try AssetJSON.stringColor(effects["water_color"])
            grassColor = try effects["grass_color"].map(AssetJSON.stringColor)
            foliageColor = try effects["foliage_color"].map(AssetJSON.stringColor)
            dryFoliageColor = try effects["dry_foliage_color"].map(AssetJSON.stringColor)
            if let raw = effects["grass_color_modifier"] {
                guard let name = raw as? String, let modifier = GrassColorModifier(rawValue: name) else { return nil }
                grassColorModifier = modifier
            } else {
                grassColorModifier = .none
            }
        } catch {
            return nil
        }
    }
}

extension GameAssets {
    /// Reads a supplied jar's biome color/climate facts, verified for 26.3 (data version 5023).
    /// Missing, unsupported or malformed resources return nil. Other biome fields are not
    /// interpreted or validated. Hex strings, integer colors and RGB channel lists are supported;
    /// numeric fields use the same strict primitive conversion as the asset readers.
    public func biomeDefinition(_ identifier: String) -> BiomeDefinition? {
        guard Int(version.dataVersion) == SaveVersion.java26_3, let id = Self.resourceID(identifier),
              let data = resources.read("data/\(id.namespace)/worldgen/biome/\(id.path).json") else { return nil }
        return BiomeDefinition(json: data)
    }
}

extension World {
    /// Resolves only the requested biome IDs from enabled folder/ZIP packs and a matching game jar.
    /// Keys are canonical namespaced IDs. This reader supports saved 26.3 worlds; missing or other
    /// data versions return no definitions. A missing or data-version-mismatched jar leaves vanilla unavailable,
    /// while higher-priority pack definitions can still resolve. No default pack list is invented.
    /// Uses dimensionSettings()'s priority, safe paths and unsupported-pack rules: a malformed
    /// present override or an unresolved higher pack blocks lower fallbacks. File errors propagate.
    /// No world files are written, chunks scanned, images decoded or mutable caches introduced.
    public func biomeDefinitions(for identifiers: Set<String>, assets: GameAssets?) throws -> [String: BiomeDefinition] {
        guard level.dataVersion == SaveVersion.java26_3 else { return [:] }
        let ids = Set(identifiers.compactMap { GameAssets.resourceID($0)?.description })
        guard !ids.isEmpty else { return [:] }
        return try Self.biomeDefinitions(for: ids, in: biomePacks(assets: assets))
    }

    /// Discovers and resolves all biome definitions in the matching game jar and enabled packs.
    /// Uses the same version, priority, path and invalid-override rules as the requested-ID query.
    /// No chunks are read. Clients can retain this color snapshot and derive their cache identity
    /// from its values, then reread it when the enabled packs or resources change.
    /// Registry discovery ignores symbolic links at or below the biome category folder.
    public func biomeDefinitions(assets: GameAssets?) throws -> [String: BiomeDefinition] {
        guard level.dataVersion == SaveVersion.java26_3 else { return [:] }
        return try WorldResourcePack.readAll(directory: "worldgen/biome", in: biomePacks(assets: assets), json: BiomeDefinition.init(json:))
    }

    private func biomePacks(assets: GameAssets?) throws -> [WorldResourcePack] {
        try Task.checkCancellation()
        let vanilla: WorldResourcePack
        if let assets, Int(assets.version.dataVersion) == level.dataVersion {
            vanilla = .zip(assets.resources)
        } else {
            vanilla = .unavailable
        }
        return try WorldResourcePack.load(enabled: level.enabledDataPacks, in: url, vanilla: vanilla)
    }

    private static func biomeDefinitions(for ids: Set<String>, in packs: [WorldResourcePack]) throws -> [String: BiomeDefinition] {
        var result: [String: BiomeDefinition] = [:]
        for id in ids.sorted() {
            try Task.checkCancellation()
            result[id] = try WorldResourcePack.read(id, directory: "worldgen/biome", in: packs,
                vanilla: { _ in nil }, json: BiomeDefinition.init(json:))
        }
        return result
    }
}
