import Foundation

/// Build limits, ceiling and spawn-light metadata from a dimension type, independent of terrain.
public struct DimensionType: Sendable, Equatable {
    public let minY: Int
    public let height: Int
    /// Minecraft's logical height can be smaller than its build height (128 versus 256 in the Nether).
    public let logicalHeight: Int
    public let hasCeiling: Bool
    /// The independent block-light ceiling for the game's monster spawn-light check (0...15).
    /// Missing, invalid or unresolved values stay nil; a value of 15 disables this ceiling.
    public let monsterSpawnBlockLightLimit: Int?
    /// Inclusive bounds of the randomly sampled light threshold, for constant/uniform providers.
    /// Other providers stay nil. This is neither a spawn probability nor complete spawn eligibility.
    public let monsterSpawnLightLevel: ClosedRange<Int>?
    /// Time/sky metadata from a readable 26.3 definition. Nil for unverified versions,
    /// malformed metadata or the built-in build-limit fallback without a supplied game jar.
    public let time: DimensionTime?
    /// Registered defaults with this dimension's supported environment-attribute modifiers applied.
    /// Verified only for readable 26.3 definitions; nil for unsupported/malformed relevant entries,
    /// other versions or the no-jar build-limit fallback. Independent of build and time metadata.
    /// These intermediate values precede timelines, weather, spatial layers and final clamping.
    public let baseSkyLighting: SkyLighting?

    public var maxY: Int { minY + height - 1 }
    public var buildRange: ClosedRange<Int> { minY...maxY }

    private init?(minY: Int, height: Int, logicalHeight: Int, hasCeiling: Bool,
                  monsterSpawnBlockLightLimit: Int?, monsterSpawnLightLevel: ClosedRange<Int>?,
                  time: DimensionTime?, baseSkyLighting: SkyLighting?) {
        guard height > 0, Self.validYBounds(minY: minY, height: height),
              (0...height).contains(logicalHeight) else { return nil }
        self.minY = minY; self.height = height; self.logicalHeight = logicalHeight; self.hasCeiling = hasCeiling
        self.monsterSpawnBlockLightLimit = monsterSpawnBlockLightLimit.flatMap { (0...15).contains($0) ? $0 : nil }
        self.monsterSpawnLightLevel = monsterSpawnLightLevel
        self.time = time
        self.baseSkyLighting = baseSkyLighting
    }

    // DimensionType and NoiseSettings share the 26.3 packed-Y bounds. Noise alone permits
    // an empty height; a dimension's constructor above requires at least one section.
    static func validYBounds(minY: Int, height: Int) -> Bool {
        (-2032...2031).contains(minY) && (0...4064).contains(height)
            && minY.isMultiple(of: 16) && height.isMultiple(of: 16) && minY + height <= 2032
    }

    init?(_ nbt: NBT, version: Int?) {
        guard let minY = nbt["min_y"]?.int, let height = nbt["height"]?.int,
              let logical = nbt["logical_height"]?.int, let ceiling = nbt["has_ceiling"]?.bool else { return nil }
        self.init(minY: minY, height: height, logicalHeight: logical, hasCeiling: ceiling,
                  monsterSpawnBlockLightLimit: nbt["monster_spawn_block_light_limit"]?.int,
                  monsterSpawnLightLevel: SpawnLightRange(nbt: nbt["monster_spawn_light_level"])?.value,
                  time: version == SaveVersion.java26_3 ? DimensionTime(nbt: nbt) : nil,
                  baseSkyLighting: version == SaveVersion.java26_3 ? (try? DimensionBaseLighting(nbt: nbt))?.value : nil)
    }

    init?(json: Data, version: Int?) {
        guard json.count <= ZipResources.maximumResourceSize,
              let value = try? JSONDecoder().decode(Definition.self, from: json) else { return nil }
        self.init(minY: value.minY, height: value.height, logicalHeight: value.logicalHeight, hasCeiling: value.hasCeiling,
                  monsterSpawnBlockLightLimit: value.monsterSpawnBlockLightLimit,
                  monsterSpawnLightLevel: value.monsterSpawnLightLevel?.value,
                  time: version == SaveVersion.java26_3 ? value.time : nil,
                  baseSkyLighting: version == SaveVersion.java26_3 ? value.baseSkyLighting : nil)
    }

    private struct Definition: Decodable {
        let minY: Int, height: Int, logicalHeight: Int
        let hasCeiling: Bool
        let monsterSpawnBlockLightLimit: Int?
        let monsterSpawnLightLevel: SpawnLightRange?
        let time: DimensionTime?
        let baseSkyLighting: SkyLighting?
        enum CodingKeys: String, CodingKey {
            case minY = "min_y", height, logicalHeight = "logical_height", hasCeiling = "has_ceiling"
            case monsterSpawnBlockLightLimit = "monster_spawn_block_light_limit", monsterSpawnLightLevel = "monster_spawn_light_level"
        }

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            minY = try fields.decode(Int.self, forKey: .minY)
            height = try fields.decode(Int.self, forKey: .height)
            logicalHeight = try fields.decode(Int.self, forKey: .logicalHeight)
            hasCeiling = try fields.decode(Bool.self, forKey: .hasCeiling)
            // These independently available facts must not discard valid build limits.
            monsterSpawnBlockLightLimit = try? fields.decode(Int.self, forKey: .monsterSpawnBlockLightLimit)
            monsterSpawnLightLevel = try? fields.decode(SpawnLightRange.self, forKey: .monsterSpawnLightLevel)
            time = try? DimensionTime(from: decoder)
            baseSkyLighting = (try? DimensionBaseLighting(from: decoder))?.value
        }
    }

    static func vanilla(_ id: String, version: Int?) -> Self? {
        guard version == SaveVersion.java26_3 else { return nil }
        switch id {
        case "minecraft:overworld", "minecraft:overworld_caves":
            return Self(minY: -64, height: 384, logicalHeight: 384, hasCeiling: id == "minecraft:overworld_caves",
                        monsterSpawnBlockLightLimit: 0, monsterSpawnLightLevel: 0...7, time: nil, baseSkyLighting: nil)
        case "minecraft:the_nether":
            return Self(minY: 0, height: 256, logicalHeight: 128, hasCeiling: true,
                        monsterSpawnBlockLightLimit: 15, monsterSpawnLightLevel: 7...7, time: nil, baseSkyLighting: nil)
        case "minecraft:the_end":
            return Self(minY: 0, height: 256, logicalHeight: 256, hasCeiling: false,
                        monsterSpawnBlockLightLimit: 0, monsterSpawnLightLevel: 15...15, time: nil, baseSkyLighting: nil)
        default: return nil
        }
    }
}

/// The verified constant/uniform IntProvider shapes, with DimensionType's 0...15 bounds.
/// NBT and JSON adapters share validation; unsupported distributions stay unavailable.
private struct SpawnLightRange: Decodable {
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

    private enum Keys: String, CodingKey { case type, value, minimum = "min_inclusive", maximum = "max_inclusive" }

    init(from decoder: any Decoder) throws {
        let parsed: Self?
        if let constant = try? decoder.singleValueContainer().decode(Int.self) {
            parsed = Self(constant: constant, type: nil, minimum: nil, maximum: nil)
        } else {
            let fields = try decoder.container(keyedBy: Keys.self)
            let type = try fields.decode(String.self, forKey: .type)
            parsed = Self(constant: try? fields.decode(Int.self, forKey: .value), type: type,
                          minimum: try? fields.decode(Int.self, forKey: .minimum), maximum: try? fields.decode(Int.self, forKey: .maximum))
        }
        guard let parsed else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported spawn-light threshold"))
        }
        self = parsed
    }
}
