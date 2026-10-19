/// Absolute chunk coordinates. A chunk is 16 by 16 blocks; negative coordinates round down.
public struct ChunkPosition: Sendable, Hashable, Codable {
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) { self.x = x; self.z = z }
    public init(containing block: BlockPosition) { self = block.chunk }

    public var region: RegionPosition { RegionPosition(x: x >> 5, z: z >> 5) }
    public var localX: Int { x & 31 }
    public var localZ: Int { z & 31 }

    /// The north-west block column, without inventing a Y. Nil if multiplication would overflow.
    public var blockOrigin: (x: Int, z: Int)? { scaledPosition(x: x, z: z, by: 16) }
}

/// Absolute region coordinates. A region contains 32 by 32 chunks.
public struct RegionPosition: Sendable, Hashable, Codable {
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) { self.x = x; self.z = z }
    public init(containing chunk: ChunkPosition) { self = chunk.region }

    public var chunkOrigin: ChunkPosition? {
        scaledPosition(x: x, z: z, by: 32).map { ChunkPosition(x: $0.x, z: $0.z) }
    }

    /// The north-west block column, without inventing a Y.
    public var blockOrigin: (x: Int, z: Int)? { scaledPosition(x: x, z: z, by: 512) }
}

private func scaledPosition(x: Int, z: Int, by side: Int) -> (x: Int, z: Int)? {
    let x = x.multipliedReportingOverflow(by: side), z = z.multipliedReportingOverflow(by: side)
    guard !x.overflow, !z.overflow else { return nil }
    return (x.partialValue, z.partialValue)
}
