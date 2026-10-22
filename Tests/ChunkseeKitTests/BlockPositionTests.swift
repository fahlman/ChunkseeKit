import Testing
import ChunkseeKit

@Suite struct BlockPositionTests {
    @Test func mapCoordinatesShareBoundsAndKeepUnknownHeightAbsent() throws {
        let position = try #require(BlockPosition.mapCoordinates(x: -8.7, y: 63.9, z: -513.1))
        #expect(position.x == -9 && position.y == 63 && position.z == -514)
        let flat = try #require(BlockPosition.mapCoordinates(x: -0.1, y: nil, z: 0.1))
        #expect(flat.x == -1 && flat.y == nil && flat.z == 0)
        let limits = try #require(BlockPosition.mapCoordinates(x: Double(Int32.min), y: Double(Int.min),
                                                               z: Double(Int32.max) + 0.5))
        #expect(limits.x == Int32.min && limits.y == Int.min && limits.z == Int32.max)
        #expect(BlockPosition.mapCoordinates(x: Double(Int32.min) - 0.5, y: nil, z: 0) == nil)
        #expect(BlockPosition.mapCoordinates(x: 0, y: nil, z: Double(Int32.max) + 1) == nil)
    }

    @Test func invalidMapAxesAreRejectedWithoutInventingAHeight() {
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max), Double(Int.min).nextDown] {
            #expect(BlockPosition.mapCoordinates(x: value, y: nil, z: 0) == nil)
            #expect(BlockPosition.mapCoordinates(x: 0, y: value, z: 0) == nil)
            #expect(BlockPosition.mapCoordinates(x: 0, y: nil, z: value) == nil)
        }
    }

    @Test(arguments: [
        (0.0, 0), (-0.0, 0), (1.0, 1), (-1.0, -1),
        (Double.leastNonzeroMagnitude, 0), (-Double.leastNonzeroMagnitude, -1),
        (1.0.nextDown, 0), ((-1.0).nextDown, -2), (-8.7, -9),
        (Double(Int.min), Int.min), (Double(Int.max).nextDown, Int.max - 1023),
    ])
    func coordinatesFloorAtBlockAndIntegerBoundaries(value: Double, expected: Int) throws {
        #expect(BlockPosition.coordinate(containing: value) == expected)
        let position = try #require(BlockPosition(x: value, y: value, z: value))
        #expect(position.x == expected && position.y == expected && position.z == expected)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity,
                      Double(Int.max), Double(Int.min).nextDown,
                      Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude])
    func anUnrepresentableAxisMakesThePositionUnavailable(_ value: Double) {
        #expect(BlockPosition.coordinate(containing: value) == nil)
        #expect(BlockPosition(x: value, y: 64, z: -2) == nil)
        #expect(BlockPosition(x: 1, y: value, z: -2) == nil)
        #expect(BlockPosition(x: 1, y: 64, z: value) == nil)
    }

    @Test func axesKeepMinecraftXYZOrder() throws {
        let position = try #require(BlockPosition(x: -8.7, y: 63.9, z: -513.1))
        #expect(position.x == -9 && position.y == 63 && position.z == -514)
    }

    @Test(arguments: [
        (0, 0, 0, 0, 0), (15, 15, 0, 0, 255), (16, 16, 1, 1, 0),
        (-1, 0, -1, 0, 15), (-16, 16, -1, 1, 0), (-17, -1, -2, -1, 255),
        (16, -17, 1, -2, 240), (Int.min, Int.max, Int.min / 16, Int.max / 16, 240),
    ])
    func columnsLocateChunksAndArrayEntriesWithoutAHeight(x: Int, z: Int, chunkX: Int, chunkZ: Int, index: Int) {
        let chunk = ChunkPosition(containingBlockX: x, blockZ: z)
        #expect(chunk == ChunkPosition(x: chunkX, z: chunkZ))
        #expect(ChunkPosition.localColumnIndex(blockX: x, blockZ: z) == index)
        for y in [Int.min, 64, Int.max] {
            #expect(BlockPosition(blockX: x, blockY: y, blockZ: z).chunk == chunk)
        }
    }

    @Test func publicRegionSizeMatchesItsCheckedOrigins() throws {
        #expect(RegionPosition.sideInBlocks == 512)
        let origin = try #require(RegionPosition(x: -1, z: 1).blockOrigin)
        #expect(origin.x == -RegionPosition.sideInBlocks && origin.z == RegionPosition.sideInBlocks)
        #expect(RegionPosition(x: .max, z: 0).blockOrigin == nil)
    }
}
