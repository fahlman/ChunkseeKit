import CryptoKit
import Foundation

/// Selects the saved four-block biome cell used at a block, following 26.3 BiomeManager.
/// Construct once with the world's unmodified seed. This does not read chunks or blend colors.
/// Per-block biome palettes do not use this four-block-cell rule.
public struct BiomeSampler: Sendable {
    private let zoomSeed: Int64

    public init(seed: Int64) {
        // Guava hashLong/asLong use little-endian bytes at both ends of SHA-256.
        let bits = UInt64(bitPattern: seed)
        let bytes = (0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        let digest = SHA256.hash(data: Data(bytes))
        let hash = digest.prefix(8).enumerated().reduce(UInt64(0)) {
            $0 | UInt64($1.element) << ($1.offset * 8)
        }
        zoomSeed = Int64(bitPattern: hash)
    }

    /// Returns the selected cell's origin in block coordinates, suitable for Chunk.biome.
    /// The cell may belong to a neighboring chunk or section; the caller supplies that data.
    /// Inputs outside the game's signed 32-bit coordinates return nil. Java's wrapped subtraction
    /// is preserved at the endpoints; the returned origin uses Int so a cell is not aliased by
    /// narrowing its coordinates back to Int32. This does not impose a world border or height limit.
    public func cellOrigin(at block: BlockPosition) -> BlockPosition? {
        guard let blockX = Int32(exactly: block.x), let blockY = Int32(exactly: block.y),
              let blockZ = Int32(exactly: block.z) else { return nil }
        let x = blockX &- 2, y = blockY &- 2, z = blockZ &- 2
        let baseX = x >> 2, baseY = y >> 2, baseZ = z >> 2
        let fractionX = Double(x & 3) / 4, fractionY = Double(y & 3) / 4, fractionZ = Double(z & 3) / 4
        var nearest = 0
        var distance = Double.infinity
        for corner in 0..<8 {
            let dx = Int32((corner >> 2) & 1), dy = Int32((corner >> 1) & 1), dz = Int32(corner & 1)
            let candidate = fiddledDistance(x: baseX + dx, y: baseY + dy, z: baseZ + dz,
                                           dx: fractionX - Double(dx), dy: fractionY - Double(dy), dz: fractionZ - Double(dz))
            if candidate < distance { nearest = corner; distance = candidate }
        }
        return BlockPosition(blockX: (Int(baseX) + ((nearest >> 2) & 1)) * 4,
                             blockY: (Int(baseY) + ((nearest >> 1) & 1)) * 4,
                             blockZ: (Int(baseZ) + (nearest & 1)) * 4)
    }

    /// Applies the source chunk's 26.3 build-height clamp after selecting the cell. DimensionType
    /// supplies validated, section-aligned limits; its logical height is not the build height.
    /// Missing data inside those limits still remains the caller's unavailable source.
    public func cellOrigin(at block: BlockPosition, in dimension: DimensionType) -> BlockPosition? {
        guard let cell = cellOrigin(at: block) else { return nil }
        // A cell spans four blocks, so the last cell begins three below the inclusive top.
        return BlockPosition(blockX: cell.x, blockY: min(max(cell.y, dimension.minY), dimension.maxY - 3), blockZ: cell.z)
    }

    private func fiddledDistance(x: Int32, y: Int32, z: Int32, dx: Double, dy: Double, dz: Double) -> Double {
        var state = zoomSeed
        for _ in 0..<2 {
            state = Self.next(state, salt: Int64(x))
            state = Self.next(state, salt: Int64(y))
            state = Self.next(state, salt: Int64(z))
        }
        let shiftedX = dx + Self.fiddle(state)
        state = Self.next(state, salt: zoomSeed)
        let shiftedY = dy + Self.fiddle(state)
        state = Self.next(state, salt: zoomSeed)
        let shiftedZ = dz + Self.fiddle(state)
        return shiftedZ * shiftedZ + shiftedY * shiftedY + shiftedX * shiftedX
    }

    private static func next(_ state: Int64, salt: Int64) -> Int64 {
        state &* (state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407) &+ salt
    }

    private static func fiddle(_ state: Int64) -> Double {
        (Double((state >> 24) & 1023) / 1024 - 0.5) * 0.9
    }
}
