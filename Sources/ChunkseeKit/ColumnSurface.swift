extension Chunk {
    /// Absolute Y of the highest non-air block in a column. X/Z wrap to 0..<16, like `block`.
    /// Uses WORLD_SURFACE when decodable; otherwise reads the column's actual block references.
    /// A missing/all-air column or an invalid build height is unavailable. An explicit height
    /// disambiguates packed heightmaps; it is not inferred from occupied sections.
    public func surfaceY(x: Int, z: Int, height: Int? = nil) -> Int? {
        guard Self.validSurfaceHeight(height) else { return nil }
        return surfaceY(x: x, z: z, heightmap: surfaceHeightmap(height: height))
    }

    /// The same surface query for all 256 columns, indexed by z * 16 + x.
    /// Without a usable heightmap, each reached nonuniform section is unpacked once, and columns
    /// stop at their first non-air block. Water is a surface; this does not strip roofs or shade it.
    func surfaceHeights(height: Int? = nil) -> [Int?] {
        guard Self.validSurfaceHeight(height) else { return [Int?](repeating: nil, count: 256) }
        return surfaceHeights(at: Array(0..<256), heightmap: surfaceHeightmap(height: height))
    }

    /// Reuses a decoded surface map for the column traversal.
    func surfaceY(x: Int, z: Int, heightmap: [Int]?) -> Int? {
        surfaceHeights(at: [ChunkSection.blockIndex(x: x, y: 0, z: z)], heightmap: heightmap)[0]
    }

    static func validSurfaceHeight(_ height: Int?) -> Bool {
        height.map { heightmapBitWidth(for: $0) != nil } ?? true
    }

    func surfaceHeightmap(height: Int?) -> [Int]? {
        if let height { return heightmap("WORLD_SURFACE", height: height) }
        return heightmap("WORLD_SURFACE")
    }

    private func surfaceHeights(at columns: [Int], heightmap: [Int]?) -> [Int?] {
        var result = [Int?](repeating: nil, count: columns.count)
        if let starts = surfaceStarts(heightmap: heightmap) {
            return columns.map { starts[$0] }
        }
        visitColumnRuns(at: columns, starts: nil, seekingSurface: true) { i, run in
            result[i] = run.y.upperBound
            return false
        }
        return result
    }
}
