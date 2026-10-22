import ChunkseeKit
import ChunkseeIndex
import Testing

@Suite struct BiomeAreaTests {
    private func position(_ x: Int, _ z: Int) -> ChunkPosition { ChunkPosition(x: x, z: z) }

    @Test func edgesConnectButCornersAndDifferentIDsDoNot() throws {
        let samples = [position(0, 0): "minecraft:forest", position(1, 0): "minecraft:forest",
                       position(1, 1): "minecraft:forest", position(2, 2): "minecraft:forest",
                       position(8, 8): "minecraft:forest", position(0, 1): "custom:forest"]
        let areas = BiomeArea.connected(in: samples)
        #expect(areas.count == 4)
        #expect(areas.map(\.chunkCount).sorted() == [1, 1, 1, 3])
        #expect(areas.reduce(0) { $0 + $1.chunkCount } == samples.count)
        let joined = try #require(areas.first { $0.chunkCount == 3 })
        #expect(joined.biomeID == "minecraft:forest")
        #expect(Set(joined.chunks) == Set([position(0, 0), position(1, 0), position(1, 1)]))
        #expect(joined.representative == position(1, 0))
        #expect(joined.id == "minecraft:forest@1,0")
        #expect(joined.boundary.count == 8 && Set(joined.boundary).count == 8)
        #expect(Set(joined.boundary.filter { $0.side == .north }.map(\.chunk)) == Set([position(0, 0), position(1, 0)]))
        #expect(Set(joined.boundary.filter { $0.side == .east }.map(\.chunk)) == Set([position(1, 0), position(1, 1)]))
        #expect(Set(joined.boundary.filter { $0.side == .south }.map(\.chunk)) == Set([position(0, 0), position(1, 1)]))
        #expect(Set(joined.boundary.filter { $0.side == .west }.map(\.chunk)) == Set([position(0, 0), position(1, 1)]))
    }

    @Test func aHoleKeepsItsBoundaryAndRepresentativeInsideTheArea() throws {
        let chunks = (0..<3).flatMap { z in (0..<3).compactMap { x in x == 1 && z == 1 ? nil : position(x, z) } }
        let samples = Dictionary(uniqueKeysWithValues: chunks.map { ($0, "minecraft:plains") })
        let area = try #require(BiomeArea.connected(in: samples).first)
        #expect(area.chunkCount == 8 && area.boundary.count == 16)
        #expect(area.representative == position(0, 1))
        #expect(area.chunks.contains(area.representative))
        #expect(area.boundary.contains { $0.chunk == position(1, 0) && $0.side == .south })
        #expect(area.boundary.contains { $0.chunk == position(0, 1) && $0.side == .east })
        #expect(area.boundary.contains { $0.chunk == position(2, 1) && $0.side == .west })
        #expect(area.boundary.contains { $0.chunk == position(1, 2) && $0.side == .north })
    }

    @Test func groupingCrossesNegativeAndRegionBoundaries() throws {
        let negative = [position(-1, -1): "minecraft:river", position(0, -1): "minecraft:river",
                        position(-1, 0): "minecraft:river"]
        let area = try #require(BiomeArea.connected(in: negative).first)
        #expect(area.chunkCount == 3 && area.representative == position(-1, -1))
        let crossing = [position(31, 0): "custom:caves", position(32, 0): "custom:caves"]
        let across = try #require(BiomeArea.connected(in: crossing).first)
        #expect(across.chunkCount == 2 && across.boundary.count == 6)
        #expect(across.representative == position(31, 0))
        #expect(across.biomeID == "custom:caves")
    }

    @Test func invalidOriginsAreOmittedWithoutLosingExtremeValidChunks() {
        let valid = [position(Int.min / 16, 0): "minecraft:plains", position(Int.max / 16, 0): "minecraft:plains"]
        let invalid = [position(Int.min, 0): "minecraft:plains", position(0, Int.max): "minecraft:plains"]
        let areas = BiomeArea.connected(in: valid.merging(invalid) { $1 })
        #expect(areas.count == 2)
        #expect(Set(areas.map(\.representative)) == Set(valid.keys))
        #expect(areas.allSatisfy { $0.chunkCount == 1 && $0.boundary.count == 4 })
        #expect(BiomeArea.connected(in: invalid).isEmpty)
        #expect(BiomeArea.connected(in: [:]).isEmpty)
    }
}
