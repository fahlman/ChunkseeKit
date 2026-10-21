import Foundation

/// Build limits and ceiling metadata from a dimension type, independent of generated terrain.
public struct DimensionType: Sendable, Equatable {
    public let minY: Int
    public let height: Int
    /// Minecraft's logical height can be smaller than its build height (128 versus 256 in the Nether).
    public let logicalHeight: Int
    public let hasCeiling: Bool

    public var maxY: Int { minY + height - 1 }
    public var buildRange: ClosedRange<Int> { minY...maxY }

    private init?(minY: Int, height: Int, logicalHeight: Int, hasCeiling: Bool) {
        guard height > 0, Self.validYBounds(minY: minY, height: height),
              (0...height).contains(logicalHeight) else { return nil }
        self.minY = minY; self.height = height; self.logicalHeight = logicalHeight; self.hasCeiling = hasCeiling
    }

    // DimensionType and NoiseSettings share the 26.3 packed-Y bounds. Noise alone permits
    // an empty height; a dimension's constructor above requires at least one section.
    static func validYBounds(minY: Int, height: Int) -> Bool {
        (-2032...2031).contains(minY) && (0...4064).contains(height)
            && minY.isMultiple(of: 16) && height.isMultiple(of: 16) && minY + height <= 2032
    }

    init?(_ nbt: NBT) {
        guard let minY = nbt["min_y"]?.int, let height = nbt["height"]?.int,
              let logical = nbt["logical_height"]?.int, let ceiling = nbt["has_ceiling"]?.bool else { return nil }
        self.init(minY: minY, height: height, logicalHeight: logical, hasCeiling: ceiling)
    }

    init?(json: Data) {
        guard let value = try? JSONDecoder().decode(Definition.self, from: json) else { return nil }
        self.init(minY: value.minY, height: value.height, logicalHeight: value.logicalHeight, hasCeiling: value.hasCeiling)
    }

    private struct Definition: Decodable {
        let minY: Int, height: Int, logicalHeight: Int
        let hasCeiling: Bool
        enum CodingKeys: String, CodingKey {
            case minY = "min_y", height, logicalHeight = "logical_height", hasCeiling = "has_ceiling"
        }
    }

    static func vanilla(_ id: String, version: Int?) -> Self? {
        guard version == SaveVersion.java26_3 else { return nil }
        switch id {
        case "minecraft:overworld": return Self(minY: -64, height: 384, logicalHeight: 384, hasCeiling: false)
        case "minecraft:overworld_caves": return Self(minY: -64, height: 384, logicalHeight: 384, hasCeiling: true)
        case "minecraft:the_nether": return Self(minY: 0, height: 256, logicalHeight: 128, hasCeiling: true)
        case "minecraft:the_end": return Self(minY: 0, height: 256, logicalHeight: 256, hasCeiling: false)
        default: return nil
        }
    }
}
