import Foundation

/// Saved noise-generation bounds, separate from a dimension's build limits and logical height.
public struct NoiseGenerationSettings: Sendable, Equatable {
    public let minY: Int
    public let height: Int

    /// The noise settings' own range. A zero height is valid and produces an empty range.
    public var range: Range<Int> { minY ..< minY + height }

    /// The 26.3 WorldGenerationContext range used by surface-rule vertical anchors.
    /// Its start is the larger minimum and its count is the smaller height; this is not a
    /// general intersection of ranges and does not establish that a physical roof exists.
    public func surfaceRuleRange(in type: DimensionType) -> Range<Int> {
        let start = max(minY, type.minY)
        return start ..< start + min(height, type.height)
    }

    private init?(minY: Int, height: Int) {
        guard DimensionType.validYBounds(minY: minY, height: height) else { return nil }
        self.minY = minY
        self.height = height
    }

    init?(_ nbt: NBT) {
        guard let minY = nbt["noise"]?["min_y"]?.int,
              let height = nbt["noise"]?["height"]?.int else { return nil }
        self.init(minY: minY, height: height)
    }

    init?(json: Data) {
        guard let value = try? JSONDecoder().decode(Definition.self, from: json) else { return nil }
        self.init(minY: value.noise.minY, height: value.noise.height)
    }

    private struct Definition: Decodable {
        let noise: Bounds
        struct Bounds: Decodable {
            let minY: Int, height: Int
            enum CodingKeys: String, CodingKey { case minY = "min_y", height }
        }
    }

    static func vanilla(_ id: String, version: Int?) -> Self? {
        guard version == SaveVersion.java26_3 else { return nil }
        switch id {
        case "minecraft:overworld", "minecraft:amplified", "minecraft:large_biomes":
            return Self(minY: -64, height: 384)
        case "minecraft:nether", "minecraft:end": return Self(minY: 0, height: 128)
        case "minecraft:caves": return Self(minY: -64, height: 192)
        case "minecraft:floating_islands": return Self(minY: 0, height: 256)
        default: return nil
        }
    }
}
