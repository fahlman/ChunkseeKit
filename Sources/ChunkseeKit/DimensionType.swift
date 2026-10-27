import Foundation

/// Build limits, ceiling and spawn-light metadata from a dimension type, independent of terrain.
public struct DimensionType: Sendable, Equatable {
    public let minY: Int
    public let height: Int
    /// Minecraft's logical height can be smaller than its build height (128 versus 256 in the Nether).
    public let logicalHeight: Int
    public let hasCeiling: Bool
    /// The dimension's travel-coordinate scale. Missing or invalid metadata stays unavailable
    /// independently of readable build limits and lighting.
    public let coordinateScale: Double?
    /// The independent block-light ceiling for the game's monster spawn-light check (0...15).
    /// Missing, invalid or unresolved values stay nil; a value of 15 disables this ceiling.
    public let monsterSpawnBlockLightLimit: Int?
    /// Inclusive bounds of the randomly sampled light threshold, for constant/uniform providers.
    /// Other providers stay nil. This is neither a spawn probability nor complete spawn eligibility.
    public let monsterSpawnLightLevel: ClosedRange<Int>?
    /// Time/sky metadata from a readable definition. Nil for missing or malformed metadata.
    public let time: DimensionTime?
    /// Registered defaults with this dimension's supported environment-attribute modifiers applied.
    /// Nil for unsupported/malformed relevant entries. Independent of build and time metadata.
    /// These intermediate values precede timelines, weather, spatial layers and final clamping.
    public let baseSkyLighting: SkyLighting?
    /// The separate gameplay sky-light attribute before timelines and final 0...15 clamping.
    /// Malformed values do not invalidate visual lighting.
    public let baseSkyLightLevel: Float?
    /// Static natural-spawn candidates before biome overlays and dynamic environment layers.
    /// Unreadable spawn metadata is independent of build bounds, time and lighting.
    public let baseMobSpawnSettings: MobSpawnSettings?

    public var maxY: Int { minY + height - 1 }
    public var buildRange: ClosedRange<Int> { minY...maxY }

    private init?(minY: Int, height: Int, logicalHeight: Int, hasCeiling: Bool, coordinateScale: Double?,
                  monsterSpawnBlockLightLimit: Int?, monsterSpawnLightLevel: ClosedRange<Int>?,
                  time: DimensionTime?, baseSkyLighting: SkyLighting?, baseSkyLightLevel: Float?,
                  baseMobSpawnSettings: MobSpawnSettings?) {
        guard height > 0, Self.validYBounds(minY: minY, height: height),
              (0...height).contains(logicalHeight) else { return nil }
        self.minY = minY; self.height = height; self.logicalHeight = logicalHeight; self.hasCeiling = hasCeiling
        self.coordinateScale = coordinateScale.flatMap {
            $0.isFinite && (GeneratedPortalFacts.minimumScale...GeneratedPortalFacts.maximumScale).contains($0) ? $0 : nil
        }
        self.monsterSpawnBlockLightLimit = monsterSpawnBlockLightLimit.flatMap { (0...15).contains($0) ? $0 : nil }
        self.monsterSpawnLightLevel = monsterSpawnLightLevel
        self.time = time
        self.baseSkyLighting = baseSkyLighting
        self.baseSkyLightLevel = baseSkyLightLevel
        self.baseMobSpawnSettings = baseMobSpawnSettings
    }

    // DimensionType and NoiseSettings share the packed-Y bounds. Noise alone permits
    // an empty height; a dimension's constructor above requires at least one section.
    static func validYBounds(minY: Int, height: Int) -> Bool {
        (-2032...2031).contains(minY) && (0...4064).contains(height)
            && minY.isMultiple(of: 16) && height.isMultiple(of: 16) && minY + height <= 2032
    }

    init?(_ nbt: NBT) {
        guard let minY = nbt["min_y"]?.int, let height = nbt["height"]?.int,
              let logical = nbt["logical_height"]?.int, let ceiling = nbt["has_ceiling"]?.bool else { return nil }
        self.init(minY: minY, height: height, logicalHeight: logical, hasCeiling: ceiling,
                  coordinateScale: nbt["coordinate_scale"]?.double,
                  monsterSpawnBlockLightLimit: nbt["monster_spawn_block_light_limit"]?.int,
                  monsterSpawnLightLevel: SpawnLightRange(nbt: nbt["monster_spawn_light_level"])?.value,
                  time: DimensionTime(nbt: nbt),
                  baseSkyLighting: (try? DimensionBaseLighting(nbt: nbt))?.value,
                  baseSkyLightLevel: (try? DimensionMonsterLighting(nbt: nbt))?.value,
                  baseMobSpawnSettings: MobSpawnSettings.dimension(nbt))
    }

    init?(json: Data) {
        guard json.count <= ZipResources.maximumResourceSize,
              let value = try? AssetJSON.object(from: json),
              let minY = try? AssetJSON.integer(value["min_y"]),
              let height = try? AssetJSON.integer(value["height"]),
              let logicalHeight = try? AssetJSON.integer(value["logical_height"]),
              let hasCeiling = try? AssetJSON.boolean(value["has_ceiling"]) else { return nil }
        // Optional projections stay independent: malformed light/time facts do not erase bounds.
        self.init(minY: minY, height: height, logicalHeight: logicalHeight, hasCeiling: hasCeiling,
                  coordinateScale: try? AssetJSON.double(value["coordinate_scale"]),
                  monsterSpawnBlockLightLimit: try? AssetJSON.integer(value["monster_spawn_block_light_limit"]),
                  monsterSpawnLightLevel: SpawnLightRange(json: value["monster_spawn_light_level"])?.value,
                  time: DimensionTime(json: value), baseSkyLighting: (try? DimensionBaseLighting(json: value))?.value,
                  baseSkyLightLevel: (try? DimensionMonsterLighting(json: value))?.value,
                  baseMobSpawnSettings: MobSpawnSettings.dimension(jsonObject: value))
    }

}

/// The verified constant/uniform IntProvider shapes, with DimensionType's 0...15 bounds.
/// NBT and JSON adapters share validation; unsupported distributions stay unavailable.
private struct SpawnLightRange {
    let value: ClosedRange<Int>

    private init?(constant: Int?, type: String?, minimum: Int?, maximum: Int?) {
        let low: Int?, high: Int?
        if let type {
            switch Identifier(type)?.description {
            case "minecraft:constant": low = constant; high = constant
            case "minecraft:uniform": low = minimum; high = maximum
            default: return nil
            }
        } else { low = constant; high = constant }
        guard let low, let high, (0...15).contains(low), (low...15).contains(high) else { return nil }
        value = low...high
    }

    init?(nbt: NBT?) {
        if nbt?.compound != nil {
            guard let type = nbt?["type"]?.string else { return nil }
            self.init(constant: nbt?["value"]?.int, type: type,
                      minimum: nbt?["min_inclusive"]?.int, maximum: nbt?["max_inclusive"]?.int)
        } else { self.init(constant: nbt?.int, type: nil, minimum: nil, maximum: nil) }
    }

    init?(json: Any?) {
        if let fields = json as? [String: Any] {
            guard let type = fields["type"] as? String else { return nil }
            self.init(constant: try? AssetJSON.integer(fields["value"]), type: type,
                      minimum: try? AssetJSON.integer(fields["min_inclusive"]),
                      maximum: try? AssetJSON.integer(fields["max_inclusive"]))
        } else {
            self.init(constant: try? AssetJSON.integer(json), type: nil, minimum: nil, maximum: nil)
        }
    }
}
