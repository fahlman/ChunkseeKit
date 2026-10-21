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

    /// Visits saved blocks down all 256 columns. Order between columns is unspecified.
    /// Return false to finish only the visited column;
    /// throwing stops the entire traversal. Each reached nonuniform section is unpacked once.
    /// Missing/light-only sections are gaps, not invented air or water. Compare run Y ranges when
    /// continuity matters. After the surface is found, air and invalid references are reported too.
    /// Colors, roof hiding and water-depth limits belong to the caller.
    @inlinable @inline(__always)
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
            // Finish each eligible column in this section before moving to the next. Its saved
            // start skips higher blocks directly, and completed columns need no per-plane checks.
            for i in columns.indices {
                guard let nextY = next[i], nextY >= low.partialValue else { continue }
                var y = min(high.partialValue, nextY)
                var lookingForSurface = seeking[i]
                var continuing = true
                repeat {
                    let lower = uniform ? max(low.partialValue, bottom.partialValue) : y
                    let index = ChunkSection.blockIndex(x: 0, y: y - low.partialValue, z: 0) + columns[i]
                    let p = uniform ? 0 : indices?[index] ?? blocks.paletteIndex(at: index)
                    let valid = p < blocks.palette.count
                    if lookingForSurface {
                        // An unreadable block cannot establish air or a surface below it.
                        guard valid else { continuing = false; break }
                        lookingForSurface = air[p]
                    }
                    if !lookingForSurface {
                        let run = ColumnRun(column: columns[i], y: lower...y,
                                            sectionIndex: s, paletteIndex: valid ? p : nil)
                        guard try body(i, run) else { continuing = false; break }
                    }
                    guard lower > bottom.partialValue else { continuing = false; break }
                    y = lower - 1
                } while y >= low.partialValue
                next[i] = continuing ? y : nil
                seeking[i] = lookingForSurface
                if !continuing { remaining -= 1 }
            }
        }
    }
}
