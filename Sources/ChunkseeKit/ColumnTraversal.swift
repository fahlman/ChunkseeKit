extension Chunk {
    /// Where a downward column traversal begins. Surface uses the same saved heightmap and
    /// actual-block fallback as `surfaceY`; an explicit Y does not look for a surface first.
    public enum ColumnStart: Sendable, Equatable {
        case surface(height: Int? = nil)
        case height(Int)
    }

    /// A vertical run of one saved block reference in one chunk-local column.
    /// Uniform sections produce a clipped range; nonuniform sections produce one block at a time.
    public struct ColumnRun: Sendable, Equatable {
        /// Index `z * 16 + x`, in 0..<256.
        public let column: Int
        /// Absolute block coordinates, inclusive. Runs descend within each column.
        public let y: ClosedRange<Int>
        /// Index into this chunk's `sections` array, including any light-only sections.
        public let sectionIndex: Int
        /// Index into that section's block palette, or nil for an invalid saved reference.
        public let paletteIndex: Int?

        @usableFromInline
        init(column: Int, y: ClosedRange<Int>, sectionIndex: Int, paletteIndex: Int?) {
            self.column = column
            self.y = y
            self.sectionIndex = sectionIndex
            self.paletteIndex = paletteIndex
        }
    }

    /// Visits saved blocks down all 256 columns. Return false to finish only the visited column;
    /// throwing stops the entire traversal. Each reached nonuniform section is unpacked once.
    /// Missing/light-only sections are gaps, not invented air or water. Compare run Y ranges when
    /// continuity matters. After the surface is found, air and invalid references are reported too.
    /// Colors, roof hiding and water-depth limits belong to the caller.
    @inlinable
    public func forEachColumnRun(from start: ColumnStart = .surface(),
                                 _ body: (ColumnRun) throws -> Bool) rethrows {
        guard let (starts, seekingSurface) = columnTraversalStart(start) else { return }
        try visitColumnRuns(at: Array(0..<256), starts: starts, seekingSurface: seekingSurface) { _, run in
            try body(run)
        }
    }

    @usableFromInline
    func columnTraversalStart(_ start: ColumnStart) -> (starts: [Int?]?, seekingSurface: Bool)? {
        switch start {
        case .height(let y):
            return (Array(repeating: y, count: 256), false)
        case .surface(let height):
            guard Self.validSurfaceHeight(height) else { return nil }
            return (surfaceStarts(heightmap: surfaceHeightmap(height: height)), true)
        }
    }

    // A nil array means there is no readable WORLD_SURFACE and blocks must establish the start.
    // Nil entries in a present array mean saved empty columns; they must not expose lower blocks.
    func surfaceStarts(heightmap: [Int]?) -> [Int?]? {
        guard let heightmap else { return nil }
        let bottom = minSectionY.multipliedReportingOverflow(by: 16)
        guard !bottom.overflow else { return Array(repeating: nil, count: 256) }
        return heightmap.map { $0 > bottom.partialValue ? $0 - 1 : nil }
    }

    /// The single owner of section order, Y clipping, palette lookup and independent column stops.
    /// Keep this loop in its caller so the nested nonescaping visitor can specialize there;
    /// otherwise Release can retain an indirect callback for every visited block.
    @inlinable @inline(__always)
    func visitColumnRuns(at columns: [Int], starts: [Int?]?, seekingSurface: Bool,
                         _ body: (Int, ColumnRun) throws -> Bool) rethrows {
        let bottom = minSectionY.multipliedReportingOverflow(by: 16)
        guard !bottom.overflow else { return }
        var next: [Int?] = columns.map { column in
            if let starts { return starts[column] }
            return Int.max
        }
        var seeking = [Bool](repeating: seekingSurface && starts == nil, count: columns.count)
        var remaining = next.count { $0 != nil }

        for s in sections.indices.reversed() {
            guard remaining > 0 else { break }
            guard let blocks = sections[s].blockStates else { continue }
            let low = sections[s].y.multipliedReportingOverflow(by: 16)
            let high = low.partialValue.addingReportingOverflow(15)
            guard !low.overflow, !high.overflow else { return }
            guard high.partialValue >= bottom.partialValue else { break }
            guard next.contains(where: { $0.map { $0 >= low.partialValue } ?? false }) else { continue }

            let uniform = blocks.isUniform
            let indices = uniform || columns.count == 1 ? nil : blocks.allPaletteIndices()
            let air = seeking.contains(true) ? blocks.palette.map(\.isAir) : []
            for offset in 0..<(uniform ? 1 : 16) {
                guard remaining > 0 else { break }
                let upper = high.partialValue - offset
                let lower = uniform ? max(low.partialValue, bottom.partialValue) : upper
                guard lower >= bottom.partialValue else { break }
                let plane = ChunkSection.blockIndex(x: 0, y: 15 - offset, z: 0)
                for i in columns.indices {
                    guard let nextY = next[i], nextY >= lower else { continue }
                    let p = uniform ? 0 : indices?[plane + columns[i]] ?? blocks.paletteIndex(at: plane + columns[i])
                    let valid = p < blocks.palette.count
                    if seeking[i] {
                        // An unreadable block cannot establish air or a surface below it.
                        guard valid else { next[i] = nil; remaining -= 1; continue }
                        if air[p] { continue }
                        seeking[i] = false
                    }
                    let run = ColumnRun(column: columns[i], y: lower...min(upper, nextY),
                                        sectionIndex: s, paletteIndex: valid ? p : nil)
                    if try body(i, run), lower > bottom.partialValue {
                        next[i] = lower - 1
                    } else {
                        next[i] = nil
                        remaining -= 1
                    }
                }
            }
        }
    }
}
