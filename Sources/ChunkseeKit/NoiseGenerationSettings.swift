import Foundation

/// Saved noise-generation facts, separate from a dimension's build limits and logical height.
public struct NoiseGenerationSettings: Sendable, Equatable {
    public let minY: Int
    public let height: Int
    /// The saved sea level, or nil when absent or not a readable signed 32-bit integer.
    /// It can be outside the generation/build range; no water surface is inferred from it.
    public let seaLevel: Int?

    /// The noise settings' own range. A zero height is valid and produces an empty range.
    public var range: Range<Int> { minY ..< minY + height }

    /// The WorldGenerationContext range used by surface-rule vertical anchors.
    /// Its start is the larger minimum and its count is the smaller height; this is not a
    /// general intersection of ranges and does not establish that a physical roof exists.
    public func surfaceRuleRange(in type: DimensionType) -> Range<Int> {
        let start = max(minY, type.minY)
        return start ..< start + min(height, type.height)
    }

    private init?(minY: Int, height: Int, seaLevel: Int?) {
        guard DimensionType.validYBounds(minY: minY, height: height) else { return nil }
        self.minY = minY
        self.height = height
        self.seaLevel = seaLevel
    }

    init?(_ nbt: NBT) {
        guard let minY = nbt["noise"]?["min_y"]?.int,
              let height = nbt["noise"]?["height"]?.int else { return nil }
        self.init(minY: minY, height: height,
                  seaLevel: nbt["sea_level"]?.int.flatMap(Int32.init(exactly:)).map(Int.init))
    }

    init?(json: Data) {
        guard json.count <= ZipResources.maximumResourceSize,
              let value = try? AssetJSON.object(from: json), let noise = value["noise"] as? [String: Any],
              let minY = try? AssetJSON.integer(noise["min_y"]),
              let height = try? AssetJSON.integer(noise["height"]) else { return nil }
        // A bad sea level must not discard independently readable generation bounds.
        self.init(minY: minY, height: height, seaLevel: try? AssetJSON.integer(value["sea_level"]))
    }

}
