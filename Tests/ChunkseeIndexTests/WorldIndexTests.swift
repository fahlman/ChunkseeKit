import ChunkseeIndex
import Testing

@Suite struct WorldIndexTests {
    private struct Content: Sendable {
        var markers: [String] = []
        var counts: [Int] = []
    }

    @Test func matchingRecordsKeepTheirDimensionsAndMemberOrder() {
        let index = WorldIndex(dimensions: [
            "minecraft:overworld": Content(markers: ["first", "same", "last"], counts: [3]),
            "custom:caves": Content(markers: ["same"], counts: [1]),
            "minecraft:the_end": Content(),
        ])
        let markers = index.all(\.markers)
        #expect(markers.count == 4)
        #expect(markers.filter { $0.dimension == "minecraft:overworld" }.map(\.value) == ["first", "same", "last"])
        #expect(markers.filter { $0.dimension == "custom:caves" }.map(\.value) == ["same"])
        #expect(Set(markers.filter { $0.value == "same" }.map(\.dimension)) == ["minecraft:overworld", "custom:caves"])
        let counts = Dictionary(uniqueKeysWithValues: index.all(\.counts).map { ($0.dimension, $0.value) })
        #expect(counts == ["minecraft:overworld": 3, "custom:caves": 1])
    }

    @Test func replacingOneDimensionPreservesOtherDimensionsAndEarlierSnapshots() {
        let previous = WorldIndex(dimensions: [
            "minecraft:overworld": Content(markers: ["old"]),
            "minecraft:the_nether": Content(markers: ["portal"]),
        ])
        var current = previous
        current.dimensions["minecraft:overworld"] = Content(markers: ["new"])
        current.dimensions["custom:caves"] = Content(markers: ["cave"])
        current.dimensions["minecraft:the_nether"]?.markers.append("second portal")
        #expect(previous.dimensions["minecraft:overworld"]?.markers == ["old"])
        #expect(previous.dimensions["minecraft:the_nether"]?.markers == ["portal"])
        #expect(previous.dimensions["custom:caves"] == nil)
        #expect(current.dimensions["minecraft:overworld"]?.markers == ["new"])
        #expect(current.dimensions["minecraft:the_nether"]?.markers == ["portal", "second portal"])
        current.dimensions["minecraft:overworld"] = nil
        #expect(current.all(\.markers).count == 3)
        #expect(WorldIndex<Content>().all(\.markers).isEmpty)
    }
}
