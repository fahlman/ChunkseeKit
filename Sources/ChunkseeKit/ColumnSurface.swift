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
    public func surfaceHeights(height: Int? = nil) -> [Int?] {
        guard Self.validSurfaceHeight(height) else { return [Int?](repeating: nil, count: 256) }
        return surfaceHeights(at: Array(0..<256), heightmap: surfaceHeightmap(height: height))
    }

    /// Region scans already decoded the heightmaps for their typed facts.
    func surfaceY(x: Int, z: Int, heightmap: [Int]?) -> Int? {
        surfaceHeights(at: [ChunkSection.blockIndex(x: x, y: 0, z: z)], heightmap: heightmap)[0]
    }

    private static func validSurfaceHeight(_ height: Int?) -> Bool {
        height.map { heightmapBitWidth(for: $0) != nil } ?? true
    }

    private func surfaceHeightmap(height: Int?) -> [Int]? {
        if let height { return heightmap("WORLD_SURFACE", height: height) }
        return heightmap("WORLD_SURFACE")
    }

    private func surfaceHeights(at columns: [Int], heightmap: [Int]?) -> [Int?] {
        var result = [Int?](repeating: nil, count: columns.count)
        let bottom = minSectionY.multipliedReportingOverflow(by: 16)
        guard !bottom.overflow else { return result }
        if let heightmap {
            // A height equal to the dimension's bottom represents an empty column, not a block
            // below the build range. Other saved values are first-free-block Y, hence minus one.
            return columns.map { heightmap[$0] > bottom.partialValue ? heightmap[$0] - 1 : nil }
        }

        var pending = [Bool](repeating: true, count: columns.count)
        var remaining = columns.count
        for section in sections.reversed() {
            guard remaining > 0 else { break }
            guard let blocks = section.blockStates else { continue }
            let low = section.y.multipliedReportingOverflow(by: 16)
            let high = low.partialValue.addingReportingOverflow(15)
            guard !low.overflow, !high.overflow else { return result }
            guard high.partialValue >= bottom.partialValue else { break }
            if blocks.isUniform {
                if blocks.palette[0].isAir { continue }
                for i in columns.indices where pending[i] { result[i] = high.partialValue }
                return result
            }

            let air = blocks.palette.map(\.isAir)
            let indices = columns.count == 1 ? nil : blocks.allPaletteIndices()
            for y in stride(from: 15, through: 0, by: -1) {
                guard remaining > 0, low.partialValue + y >= bottom.partialValue else { break }
                let plane = ChunkSection.blockIndex(x: 0, y: y, z: 0)
                for i in columns.indices where pending[i] {
                    let p = indices?[plane + columns[i]] ?? blocks.paletteIndex(at: plane + columns[i])
                    // An invalid reference cannot establish air or a lower surface.
                    if p >= air.count || !air[p] {
                        if p < air.count { result[i] = low.partialValue + y }
                        pending[i] = false
                        remaining -= 1
                    }
                }
            }
        }
        return result
    }
}
