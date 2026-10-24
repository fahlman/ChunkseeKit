import Foundation

/// The ordinary 26.3 monster light check at a chosen clear-night sky level. A true result
/// means some random draws can pass this check, not a probability or complete spawnability.
/// Terrain, space, biome lists, difficulty and mobs with different light rules are not tested.
public struct MonsterSpawnLight: Sendable, Equatable {
    public let blockLightLimit: Int
    public let maximumRawLight: Int
    public let hasSkylight: Bool
    /// Final clamped gameplay sky level converted to the game's integer darkening. Nil when
    /// the dimension has no sky-light engine; that engine contributes zero, not missing data.
    public let skyDarkening: Int?

    init?(type: DimensionType, skyLightLevel: Float?) {
        guard let time = type.time, let limit = type.monsterSpawnBlockLightLimit,
              let threshold = type.monsterSpawnLightLevel else { return nil }
        blockLightLimit = limit
        maximumRawLight = threshold.upperBound
        hasSkylight = time.hasSkylight
        if hasSkylight {
            guard let skyLightLevel, skyLightLevel.isFinite else { return nil }
            skyDarkening = Int(15 - min(15, max(0, skyLightLevel)))
        } else { skyDarkening = nil }
    }

    /// Saved block light must be valid 0...15. Sky light is required only when this
    /// dimension has it and block light has not already ruled out spawning. The first random
    /// sky check can pass for every such sky value (0...31 random range); the threshold's
    /// upper bound answers whether the later check can pass.
    public func canPass(blockLight: Int?, skyLight: Int?, at position: BlockPosition) -> Bool? {
        guard let blockLight, (0...15).contains(blockLight) else { return nil }
        if blockLightLimit < 15, blockLight > blockLightLimit { return false }
        if blockLight > maximumRawLight { return false }
        let sky: Int
        if hasSkylight {
            guard let skyLight, (0...15).contains(skyLight), let skyDarkening else { return nil }
            sky = skyLight - skyDarkening
        } else { sky = 0 }
        // LevelReader uses brightness 15 outside these horizontal bounds, independently of
        // the saved light and the later full spawn-position checks.
        let inBounds = (-30_000_000..<30_000_000).contains(position.x)
            && (-30_000_000..<30_000_000).contains(position.z)
        return (inBounds ? max(blockLight, sky) : 15) <= maximumRawLight
    }

    /// Reads valid light at local X/Z and absolute Y through Chunk.resolvedBlockLight.
    /// Verified omitted block layers resolve to zero; stale/malformed light remains unknown.
    /// This never propagates light or treats a missing sky array as darkness.
    public func canPass(in chunk: Chunk, x: Int, y: Int, z: Int) -> Bool? {
        guard chunk.isLightOn, (0..<16).contains(x), (0..<16).contains(z),
              let origin = ChunkPosition(x: chunk.x, z: chunk.z).blockOrigin,
              origin.x <= Int.max - x, origin.z <= Int.max - z else { return nil }
        return canPass(blockLight: chunk.resolvedBlockLight(x: x, y: y, z: z),
                       skyLight: hasSkylight ? chunk.skyLight(x: x, y: y, z: z) : nil,
                       at: BlockPosition(blockX: origin.x + x, blockY: y, blockZ: origin.z + z))
    }
}

enum MonsterLightAttribute: String {
    case skyLevel = "minecraft:gameplay/sky_light_level"
}

struct DimensionMonsterLighting: Decodable {
    let value: Float

    private init(_ entries: EnvironmentAttributeMap<MonsterLightAttribute>) throws {
        value = try entries.applying(.skyLevel, to: Float(15), overrideRange: 0...15)
        guard value.isFinite else { throw InvalidLighting.data }
    }

    init(nbt: NBT) throws { try self.init(EnvironmentAttributeMap(nbt: nbt)) }
    init(from decoder: any Decoder) throws { try self.init(EnvironmentAttributeMap(from: decoder)) }
}
