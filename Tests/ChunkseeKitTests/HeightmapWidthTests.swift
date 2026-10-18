import Foundation
import Testing
import ChunkseeKit

@Suite struct HeightmapWidthTests {
    @Test(arguments: [2032, 4000])
    func ambiguousLongCountsDoNotGuessTheDimensionHeight(_ height: Int) throws {
        let bits = height == 2032 ? 11 : 12
        let values = (0..<256).map { ($0 * 17) % (height + 1) }
        let packed = Fixtures.pack(values, bits: bits)
        #expect(packed.count == 52)
        let nbt = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: [
            "yPos": .int(-127), "Heightmaps": .compound(["WORLD_SURFACE": .longArray(packed)]),
        ])
        let chunk = try Chunk(nbt: NBT.read(nbt.serialized()).value)
        #expect(chunk.heightmap("WORLD_SURFACE") == nil, "An array of 52 longs cannot distinguish 11 from 12 bits")
    }
}
