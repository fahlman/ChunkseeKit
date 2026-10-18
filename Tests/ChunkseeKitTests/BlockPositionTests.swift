import Testing
import ChunkseeKit

@Suite struct BlockPositionTests {
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
}
