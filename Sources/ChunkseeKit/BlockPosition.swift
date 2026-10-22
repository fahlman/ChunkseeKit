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

    public var chunk: ChunkPosition { ChunkPosition(containingBlockX: x, blockZ: z) }
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

    /// Checked coordinates supported by the map index: containing-block X/Z fit Int32, and a
    /// supplied Y fits Int. An unknown Y stays nil. This does not enforce Minecraft's world border.
    /// General saved-position callers can continue using the wider Int-valued initializer above.
    public static func mapCoordinates(x: Double, y: Double?, z: Double) -> (x: Int32, y: Int?, z: Int32)? {
        guard let blockX = coordinate(containing: x), let blockZ = coordinate(containing: z),
              let x = Int32(exactly: blockX), let z = Int32(exactly: blockZ) else { return nil }
        let blockY: Int?
        if let y {
            guard let value = coordinate(containing: y) else { return nil }
            blockY = value
        } else { blockY = nil }
        return (x, blockY, z)
    }
}
