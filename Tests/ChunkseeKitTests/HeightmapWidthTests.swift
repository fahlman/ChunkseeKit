import Foundation
import Testing
@testable import ChunkseeKit

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
    @Test(arguments: [2032, 2048, 4000, 4064])
    func explicitBuildHeightRecoversAllColumnsAndPreservesFirstFreeY(_ height: Int) throws {
        let bits = Int.bitWidth - height.leadingZeroBitCount
        let values = (0..<256).map { ($0 * 17) % (height + 1) }
        let packed = Fixtures.pack(values, bits: bits)
        // Independent 26.3 SimpleBitStorage oracle; both widths still have 52 words.
        if height == 2032 { #expect(Array(packed.prefix(3)) == [1_196_706_880_325_632, 2_692_773_195_231_317, 4_188_839_510_137_002]) }
        if height == 4000 { #expect(Array(packed.prefix(3)) == [19_143_803_680_133_120, 43_075_019_282_473_045, 67_006_234_884_812_970]) }
        let chunk = try map(packed, minSectionY: -127)
        #expect(chunk.heightmap("WORLD_SURFACE", height: height) == values.map { $0 - 2032 })
        #expect(chunk.heightmap("WORLD_SURFACE", height: height)?.first == -2032)
    }

    @Test func vanillaHeightsKeepTheirAutomaticWidthAndAbsoluteCoordinates() throws {
        for (height, minimum) in [(128, 0), (256, 0), (384, -4)] {
            let bits = Int.bitWidth - height.leadingZeroBitCount
            var values = (0..<256).map { $0 % (height + 1) }
            values[255] = height
            let chunk = try map(Fixtures.pack(values, bits: bits), minSectionY: Int64(minimum))
            let expected = values.map { $0 + minimum * 16 }
            #expect(chunk.heightmap("WORLD_SURFACE") == expected)
            #expect(chunk.heightmap("WORLD_SURFACE", height: height) == expected)
            #expect(chunk.heightmap("WORLD_SURFACE")?.last == minimum * 16 + height)
        }
    }

    @Test func inconsistentDataAndOverflowingCoordinatesAreUnavailable() throws {
        var values = [Int](repeating: 0, count: 256)
        values[255] = 384
        let packed = Fixtures.pack(values, bits: 9), chunk = try map(packed, minSectionY: -4)
        for height in [0, -1, Int.max, 256] { #expect(chunk.heightmap("WORLD_SURFACE", height: height) == nil) }
        #expect(chunk.heightmap("MISSING", height: 384) == nil)
        let short = try map([0], minSectionY: -4)
        #expect(short.heightmap("WORLD_SURFACE") == nil && short.heightmap("WORLD_SURFACE", height: 384) == nil)
        for section in [Int64.max, Int64.min, Int64.max / 16] {
            let malformed = try map(packed, minSectionY: section)
            #expect(malformed.heightmap("WORLD_SURFACE") == nil)
            #expect(malformed.heightmap("WORLD_SURFACE", height: 384) == nil)
        }
    }

    @Test(arguments: 1...32)
    func sharedPalettePackingRetainsIndicesCountsAndPadding(_ bits: Int) throws {
        let limit = Int((UInt64(1) << UInt64(bits)) - 1)
        let values = (0..<257).map { $0 % 7 == 0 ? limit : $0 % 2 }
        let palette = ["air", "stone"]
        let container = try PalettedContainer(palette: palette, data: Fixtures.pack(values, bits: bits), entryCount: 257, minimumBits: bits)
        #expect(container.allPaletteIndices() == values)
        #expect(container.paletteCounts() == [values.filter { $0 == 0 }.count, values.filter { $0 == 1 }.count])
        for index in [0, 1, 5, 64, 256] {
            #expect(container.paletteIndex(at: index) == values[index])
            #expect(container[index] == (values[index] < palette.count ? palette[values[index]] : nil))
        }
    }

    private func map(_ packed: [Int64], minSectionY: Int64) throws -> Chunk {
        let nbt = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: [
            "yPos": .long(minSectionY), "Heightmaps": .compound(["WORLD_SURFACE": .longArray(packed)]),
        ])
        return try Chunk(nbt: NBT.read(nbt.serialized()).value)
    }

}
