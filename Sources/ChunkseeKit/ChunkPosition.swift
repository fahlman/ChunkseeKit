/// Absolute chunk coordinates. A chunk is 16 by 16 blocks; negative coordinates round down.
public struct ChunkPosition: Sendable, Hashable, Codable {
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) { self.x = x; self.z = z }
    public init(containing block: BlockPosition) { self = block.chunk }

    /// The chunk containing a whole block column, without requiring or inventing a Y.
    public init(containingBlockX x: Int, blockZ z: Int) {
        self.init(x: x >> 4, z: z >> 4)
    }

    /// The column's index in a chunk's 256-entry heightmap/top-column array (local Z then X).
    /// Accepts absolute block coordinates, including negative coordinates and Int extremes.
    public static func localColumnIndex(blockX x: Int, blockZ z: Int) -> Int {
        (z & 15) * 16 + (x & 15)
    }

    public var region: RegionPosition { RegionPosition(x: x >> 5, z: z >> 5) }
    public var localX: Int { x & 31 }
    public var localZ: Int { z & 31 }

    /// The north-west block column, without inventing a Y. Nil if multiplication would overflow.
    public var blockOrigin: (x: Int, z: Int)? { scaledPosition(x: x, z: z, by: 16) }
}

/// Absolute region coordinates. A region contains 32 by 32 chunks.
public struct RegionPosition: Sendable, Hashable, Codable {
    /// Width/depth in blocks, for continuous geometry that cannot use an integer origin.
    public static let sideInBlocks = 512
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) { self.x = x; self.z = z }
    public init(containing chunk: ChunkPosition) { self = chunk.region }

    public var chunkOrigin: ChunkPosition? {
        scaledPosition(x: x, z: z, by: 32).map { ChunkPosition(x: $0.x, z: $0.z) }
    }

    /// The north-west block column, without inventing a Y.
    public var blockOrigin: (x: Int, z: Int)? { scaledPosition(x: x, z: z, by: Self.sideInBlocks) }
}

private func scaledPosition(x: Int, z: Int, by side: Int) -> (x: Int, z: Int)? {
    let x = x.multipliedReportingOverflow(by: side), z = z.multipliedReportingOverflow(by: side)
    guard !x.overflow, !z.overflow else { return nil }
    return (x.partialValue, z.partialValue)
}
