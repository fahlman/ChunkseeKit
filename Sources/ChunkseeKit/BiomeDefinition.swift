import Foundation

/// Data-defined climate and color facts. Image decoding and neighboring-biome blending are client-owned.
public struct BiomeDefinition: Sendable, Hashable, Encodable {
    /// Base climate values remain unclamped; color resolution clamps them when sampling its maps.
    public let temperature: Float
    public let downfall: Float
    /// Colors are 24-bit RGB. Missing overrides use the client's corresponding color map.
    public let waterColor: UInt32
    public let grassColor: UInt32?
    public let foliageColor: UInt32?
    public let dryFoliageColor: UInt32?
    public let grassColorModifier: GrassColorModifier

    public enum GrassColorModifier: RawRepresentable, Sendable, Hashable, Encodable {
        case none
        case darkForest
        case swamp
        /// Retains an unfamiliar modifier without discarding the biome's other facts.
        case unknown(String)

        public init?(rawValue: String) {
            self = switch rawValue {
            case "none": .none
            case "dark_forest": .darkForest
            case "swamp": .swamp
            default: .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .none: "none"
            case .darkForest: "dark_forest"
            case .swamp: "swamp"
            case .unknown(let value): value
            }
        }
    }

    init?(json: Data) {
        guard json.count <= ZipResources.maximumResourceSize else { return nil }
        do {
            let root = try AssetJSON.object(from: json)
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
    /// Reads biome color/climate facts from any supplied jar whose resource format parses.
    /// Missing, unsupported or malformed resources return nil. Other biome fields are not
    /// interpreted or validated. Hex strings, integer colors and RGB channel lists are supported;
    /// numeric fields use the same strict primitive conversion as the asset readers.
    public func biomeDefinition(_ identifier: String) -> BiomeDefinition? {
        biomeResource(identifier, decode: BiomeDefinition.init(json:))
    }
}

extension World {
    /// Resolves requested biome IDs from enabled folder/ZIP packs and the caller-selected game jar.
    /// Keys are canonical namespaced IDs. Save/jar version labels do not hide readable resources.
    /// A missing jar leaves vanilla unavailable,
    /// while higher-priority pack definitions can still resolve. No default pack list is invented.
    /// Uses dimensionSettings(assets:)'s priority, safe paths and unsupported-pack rules: a malformed
    /// present override or an unresolved higher pack blocks lower fallbacks. File errors propagate.
    /// Only resources registered by folder/ZIP listing participate, even for a subset of IDs.
    /// Linked category folders and descendants are skipped; contained namespace aliases are allowed.
    /// Queries with more than 64 enabled packs or 4,096 IDs return no definitions. Resources share
    /// the spawn reader's 16 MiB/file and 64 MiB/query limits. No world files are written,
    /// chunks scanned, images decoded or mutable caches introduced.
    public func biomeDefinitions(for identifiers: Set<String>, assets: GameAssets?) throws -> [String: BiomeDefinition] {
        try biomeResources(for: identifiers, assets: assets, decode: BiomeDefinition.init(json:))
    }

    /// Discovers and resolves all biome definitions in the selected game jar and enabled packs.
    /// Uses the same priority, path and invalid-override rules as the requested-ID query.
    /// No chunks are read. Clients can retain this color snapshot and derive their cache identity
    /// from its values, then reread it when the enabled packs or resources change.
    /// Registry discovery ignores symbolic links at or below the biome category folder.
    public func biomeDefinitions(assets: GameAssets?) throws -> [String: BiomeDefinition] {
        try biomeResources(assets: assets, decode: BiomeDefinition.init(json:))
    }
}
