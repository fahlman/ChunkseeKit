import ChunkseeKit
import Foundation

/// Edge-connected chunks with one biome ID. Names, colors and drawing paths belong to clients.
public struct BiomeArea: Sendable {
    public let biomeID: String
    public let chunks: [ChunkPosition]
    /// The member nearest the mean chunk position, with ties ordered by X, then Z.
    public let representative: ChunkPosition
    public let boundary: [Edge]

    public var id: String { "\(biomeID)@\(representative.x),\(representative.z)" }
    public var chunkCount: Int { chunks.count }

    public enum Side: Sendable, Hashable {
        case north, east, south, west
    }

    /// An exposed side of a member chunk. No height is inferred for this horizontal boundary.
    public struct Edge: Sendable, Hashable {
        public let chunk: ChunkPosition
        public let side: Side
    }

    /// Groups chunks sharing an edge and the exact saved biome ID. Corner-only neighbors stay
    /// separate, every area is retained, and chunks without a representable block origin are omitted.
    /// Area, member and edge order is unspecified. Callers choose surface or cave membership.
    public static func connected(in biomes: [ChunkPosition: String]) -> [BiomeArea] {
        let biomes = biomes.filter { $0.key.blockOrigin != nil }
        let neighbors: [(Int, Int, Side)] = [(1, 0, .east), (-1, 0, .west), (0, 1, .south), (0, -1, .north)]
        var visited = Set<ChunkPosition>()
        var areas: [BiomeArea] = []
        for (start, biome) in biomes where !visited.contains(start) {
            var chunks: [ChunkPosition] = []
            var boundary: [Edge] = []
            var stack = [start]
            visited.insert(start)
            while let chunk = stack.popLast() {
                chunks.append(chunk)
                for (dx, dz, side) in neighbors {
                    // A representable block origin bounds each chunk coordinate far inside Int.
                    let next = ChunkPosition(x: chunk.x + dx, z: chunk.z + dz)
                    if biomes[next] == biome {
                        if visited.insert(next).inserted { stack.append(next) }
                    } else {
                        boundary.append(Edge(chunk: chunk, side: side))
                    }
                }
            }
            let middleX = chunks.reduce(0.0) { $0 + Double($1.x) } / Double(chunks.count)
            let middleZ = chunks.reduce(0.0) { $0 + Double($1.z) } / Double(chunks.count)
            let inside = chunks.min {
                let a = hypot(Double($0.x) - middleX, Double($0.z) - middleZ)
                let b = hypot(Double($1.x) - middleX, Double($1.z) - middleZ)
                return a == b ? ($0.x, $0.z) < ($1.x, $1.z) : a < b
            }!
            areas.append(BiomeArea(biomeID: biome, chunks: chunks, representative: inside, boundary: boundary))
        }
        return areas
    }
}
