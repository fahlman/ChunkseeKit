/// The whole block containing an exact saved position, when all three coordinates are representable.
public struct BlockPosition: Sendable, Hashable, Codable {
    public let x: Int
    public let y: Int
    public let z: Int

    public init(blockX: Int, blockY: Int, blockZ: Int) {
        x = blockX
        y = blockY
        z = blockZ
    }

    public var chunk: ChunkPosition { ChunkPosition(x: x >> 4, z: z >> 4) }
    public var region: RegionPosition { chunk.region }

    /// Floors each axis, including negative fractions. Returns nil for a nonfinite or out-of-range axis.
    public init?(x: Double, y: Double, z: Double) {
        guard let x = Self.coordinate(containing: x),
              let y = Self.coordinate(containing: y),
              let z = Self.coordinate(containing: z) else { return nil }
        self.x = x
        self.y = y
        self.z = z
    }

    /// The containing coordinate on one axis. This also serves callers with only an X/Z location.
    public static func coordinate(containing value: Double) -> Int? {
        Int(exactly: value.rounded(.down))
    }
}
