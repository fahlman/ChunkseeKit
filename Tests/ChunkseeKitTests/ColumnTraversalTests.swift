import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct ColumnTraversalTests {
    @Test func explicitHeightMatchesIndependentBlockReadsAcrossSectionsAndGaps() throws {
        let palette: [NBT] = [.string("minecraft:air"), .string("minecraft:stone"), .string("minecraft:water")]
        let mixed = Fixtures.section(y: 1, palette: palette, indices: (0..<4096).map { ($0 * 7 + $0 / 256) % 3 })
        let chunk = try decode([
            Fixtures.section(y: -2, palette: [.string("minecraft:dirt")]),
            Fixtures.section(y: -1, palette: [.string("minecraft:air")]),
            .compound(["Y": .int(0)]), // A light-only section is not a saved block.
            mixed,
            Fixtures.section(y: 3, palette: [.string("minecraft:stone")]),
        ], bottom: -2)
        for start in [-40, -17, -8, 0, 21, 53, 200] {
            var actual = [[Int: String]](repeating: [:], count: 256)
            try chunk.forEachColumnRun(from: .height(start)) { run in
                let p = try #require(run.paletteIndex)
                let block = try #require(chunk.sections[run.sectionIndex].blockStates?.palette[p])
                for y in run.y {
                    #expect(actual[run.column][y] == nil, "A coordinate must be visited only once")
                    actual[run.column][y] = block.id
                }
                return true
            }
            for i in 0..<256 {
                var expected = [Int: String]()
                if start >= -32 {
                    for y in -32...min(start, 63) {
                        if let block = chunk.block(x: i % 16, y: y, z: i / 16) { expected[y] = block.id }
                    }
                }
                #expect(actual[i] == expected)
            }
        }
    }

    @Test func surfaceStartsOnceAtEachReferencedNonAirBlock() throws {
        var indices = [Int](repeating: 0, count: 4096)
        for i in 1..<256 { indices[(i % 16) * 256 + i] = i.isMultiple(of: 2) ? 1 : 2 }
        indices[15 * 256] = 7 // A damaged top block cannot expose the lower stone.
        indices[0] = 1
        let chunk = try decode([
            Fixtures.section(y: 0, palette: [.string("air"), .string("minecraft:short_grass"),
                                            .string("minecraft:water")], indices: indices),
            Fixtures.section(y: 1, palette: [.string("void_air")]),
        ])
        var first = [Int?](repeating: nil, count: 256)
        var visits = [Int](repeating: 0, count: 256)
        chunk.forEachColumnRun { run in
            first[run.column] = run.y.upperBound
            visits[run.column] += 1
            return false
        }
        #expect(first == (0..<256).map { $0 == 0 ? nil : $0 % 16 })
        #expect(first == chunk.surfaceHeights())
        #expect(visits == (0..<256).map { $0 == 0 ? 0 : 1 })
        for i in 0..<256 { #expect(first[i] == chunk.surfaceY(x: i % 16, z: i / 16)) }
    }

    @Test func savedSurfaceClipsRunsAndKeepsSavedEmptyColumnsEmpty() throws {
        let heights = (0..<256).map { $0 % 17 }
        let chunk = try decode([Fixtures.section(y: 0, palette: [.string("minecraft:stone")])], extra: [
            "Heightmaps": .compound(["WORLD_SURFACE": .longArray(Fixtures.pack(heights, bits: 9))]),
        ])
        var ranges = [ClosedRange<Int>?](repeating: nil, count: 256)
        chunk.forEachColumnRun(from: .surface(height: 384)) { run in
            #expect(ranges[run.column] == nil)
            ranges[run.column] = run.y
            return true
        }
        #expect(ranges == heights.map { $0 == 0 ? nil : 0...($0 - 1) })
        #expect(ranges.map { $0?.upperBound } == chunk.surfaceHeights(height: 384))
    }

    @Test func uniformWaterSpansKeepGapsAndIndependentStopping() throws {
        let water = NBT.string("minecraft:water")
        let chunk = try decode([
            Fixtures.section(y: 0, palette: [water]),
            Fixtures.section(y: 2, palette: [water]),
            Fixtures.section(y: 3, palette: [water]),
        ])
        var runs = [[ClosedRange<Int>]](repeating: [], count: 256)
        chunk.forEachColumnRun(from: .height(53)) { run in
            runs[run.column].append(run.y)
            return run.column != 0
        }
        #expect(runs[0] == [48...53])
        #expect(runs[1...].allSatisfy { $0 == [48...53, 32...47, 0...15] })
        // A caller can stop counting contiguous water at the missing section rather than invent it.
        #expect(runs[1][0].count + runs[1][1].count == 22)
    }

    @Test func traversalReportsAirAndBadReferencesBelowTheStartingSurface() throws {
        var indices = [Int](repeating: 0, count: 4096)
        indices[5 * 256] = 1
        indices[3 * 256] = 7
        indices[0] = 1
        let chunk = try decode([Fixtures.section(y: 0, palette: [.string("air"), .string("stone")], indices: indices)])
        var refs = [Int: Int?]()
        chunk.forEachColumnRun { run in
            if run.column == 0 { refs.updateValue(run.paletteIndex, forKey: run.y.upperBound) }
            return true
        }
        #expect(refs.count == 6)
        #expect(refs[5] == .some(1) && refs[4] == .some(0))
        #expect(refs[3] == .some(nil) && refs[0] == .some(1))
        var explicit: Chunk.ColumnRun?
        chunk.forEachColumnRun(from: .height(3)) { run in
            if run.column == 0 { explicit = run }
            return false
        }
        #expect(explicit?.y == 3...3 && explicit?.paletteIndex == nil)
    }

    @Test func heightContextDisambiguatesSurfaceWithoutChangingExplicitCutaways() throws {
        let section = Fixtures.section(y: 0, palette: [.string("stone")])
        let chunk = try decode([section], extra: ["Heightmaps": .compound([
            "WORLD_SURFACE": .longArray(Fixtures.pack([Int](repeating: 8, count: 256), bits: 12)),
        ])])
        for (start, expected) in [(Chunk.ColumnStart.surface(), 15), (.surface(height: 4000), 7), (.height(11), 11)] {
            var ys = [Int]()
            chunk.forEachColumnRun(from: start) { run in ys.append(run.y.upperBound); return false }
            #expect(ys == [Int](repeating: expected, count: 256))
        }
        for height in [0, -1, Int.max] {
            var called = false
            chunk.forEachColumnRun(from: .surface(height: height)) { _ in called = true; return true }
            #expect(!called)
        }
    }

    @Test func traversalPreservesCheckedExtremeBounds() throws {
        for sectionY in [Int64.min, Int64.max] {
            let bad = try decode([.compound(["Y": .long(sectionY), "block_states": .compound([
                "palette": .list([.string("stone")]),
            ])])])
            var called = false
            bad.forEachColumnRun(from: .height(Int.max)) { _ in called = true; return true }
            #expect(!called)
        }
        let stone = Fixtures.section(y: 0, palette: [.string("stone")])
        for bottom in [Int64.min, Int64.max] {
            let bad = try decode([stone], extra: ["yPos": .long(bottom)])
            var called = false
            bad.forEachColumnRun { _ in called = true; return true }
            #expect(!called)
        }
        let chunk = try decode([stone])
        var calls = 0
        chunk.forEachColumnRun(from: .height(Int.min)) { _ in calls += 1; return true }
        #expect(calls == 0)
        chunk.forEachColumnRun(from: .height(Int.max)) { run in
            #expect(run.y == 0...15)
            calls += 1
            return true
        }
        #expect(calls == 256)
    }

    @Test func throwingStopsTheWholeTraversal() throws {
        enum Stop: Error { case requested }
        let chunk = try decode([Fixtures.section(y: 0, palette: [.string("stone")])])
        var calls = 0
        #expect(throws: Stop.requested) {
            try chunk.forEachColumnRun { _ in calls += 1; throw Stop.requested }
        }
        #expect(calls == 1)
    }

    private func decode(_ sections: [NBT], bottom: Int32 = 0, extra: [String: NBT] = [:]) throws -> Chunk {
        var fields = ["yPos": NBT.int(bottom)]
        fields.merge(extra) { _, new in new }
        return try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: sections, extra: fields))
    }
}
