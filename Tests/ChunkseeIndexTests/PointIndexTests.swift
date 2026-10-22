import ChunkseeIndex
import Testing

@Suite(.timeLimit(.minutes(1))) struct PointIndexTests {
    private struct Record: Sendable {
        let id: Int
        let position: (x: Double, z: Double)?
        init(_ id: Int, _ x: Double? = nil, _ z: Double = 0) {
            self.id = id
            position = x.map { ($0, z) }
        }
    }

    @Test func negativeFractionsAndRegionEdgesUseContainingRegions() {
        let records = [Record(0, -512.25, -0.25), Record(1, -512, -0.25), Record(2, -0.25, -0.25),
                       Record(3, 0), Record(4, 511.75), Record(5, 512)]
        let index = PointIndex(records, position: \.position)
        #expect(index.candidates(minX: -512, maxX: -0.25, minZ: -0.25, maxZ: -0.25).map(\.id) == [1, 2])
        #expect(index.candidates(minX: 0, maxX: 511.75, minZ: 0, maxZ: 0).map(\.id) == [3, 4])
        // Candidates cover whole touched regions, leaving exact bounds to the caller.
        #expect(index.candidates(minX: 511.75, maxX: 512, minZ: 0, maxZ: 0).map(\.id) == [3, 4, 5])
        #expect(index.candidates(minX: -513, maxX: -513, minZ: -1, maxZ: -1).map(\.id) == [0])
    }

    @Test func sparseAndSmallViewsPreserveInputOrderAndUnlocatedEntries() {
        let records = [Record(90), Record(70, 1024), Record(30, 0), Record(80, -1024), Record(60, 513), Record(20, 1)]
        let index = PointIndex(records, position: \.position)
        #expect(index.candidates(minX: 0, maxX: 0, minZ: 0, maxZ: 0).map(\.id) == [90, 30, 20])
        #expect(index.candidates(minX: 0, maxX: 512, minZ: 0, maxZ: 0).map(\.id) == [90, 30, 60, 20])
        #expect(index.candidates(minX: -1e12, maxX: 1e12, minZ: -1e12, maxZ: 1e12).map(\.id) == records.map(\.id))
        #expect(index.candidates(minX: 5_000, maxX: 5_000, minZ: 0, maxZ: 0).map(\.id) == [90])
    }

    @Test func nonfiniteOrUnrepresentableValuesNeverTrapOrSilentlyDisappear() {
        let records = [Record(0, 0), Record(1, .nan), Record(2, .infinity), Record(3, .greatestFiniteMagnitude),
                       Record(4), Record(5, 0, -.infinity), Record(6, 512)]
        let index = PointIndex(records, position: \.position)
        #expect(index.candidates(minX: 0, maxX: 0, minZ: 0, maxZ: 0).map(\.id) == [0, 1, 2, 3, 4, 5])
        for bounds in [(Double.nan, 0.0, 0.0, 0.0), (0, .infinity, 0, 0), (0, 0, -.infinity, 0),
                       (0, 0, 0, .greatestFiniteMagnitude), (1024, -1024, 0, 0), (0, 0, 1024, -1024)] {
            #expect(index.candidates(minX: bounds.0, maxX: bounds.1, minZ: bounds.2, maxZ: bounds.3).map(\.id) == records.map(\.id))
        }
    }

    @Test func extremeRepresentableRegionsStayBucketed() {
        let low = Double(Int.min) * 512, high = Double(Int.max).nextDown * 512
        let index = PointIndex([Record(0, low), Record(1, high), Record(2, 0), Record(3, .infinity)], position: \.position)
        #expect(index.candidates(minX: low, maxX: low, minZ: 0, maxZ: 0).map(\.id) == [0, 3])
        #expect(index.candidates(minX: high, maxX: high, minZ: 0, maxZ: 0).map(\.id) == [1, 3])
    }

    @Test func snapshotsAreIndependentAndEmptyInputsStayEmpty() {
        var records = [Record(1, 0)]
        let before = PointIndex(records, position: \.position)
        records[0] = Record(2, 1024)
        records.append(Record(3, 0))
        let after = PointIndex(records, position: \.position)
        #expect(before.elements.map(\.id) == [1])
        #expect(before.candidates(minX: 0, maxX: 0, minZ: 0, maxZ: 0).map(\.id) == [1])
        #expect(after.elements.map(\.id) == [2, 3])
        #expect(after.candidates(minX: 0, maxX: 0, minZ: 0, maxZ: 0).map(\.id) == [3])
        let empty = PointIndex([Record](), position: \.position)
        #expect(empty.candidates(minX: .nan, maxX: .infinity, minZ: 0, maxZ: 0).isEmpty)
    }
}
