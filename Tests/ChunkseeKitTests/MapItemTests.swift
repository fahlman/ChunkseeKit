import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct MapItemTests {
    func colors(_ fill: Int8 = 0, at index: Int? = nil, _ value: Int8 = 0) -> NBT {
        var bytes = [Int8](repeating: fill, count: 128 * 128)
        if let index { bytes[index] = value }
        return .byteArray(bytes)
    }

    @Test func currentAndOlderFormats() throws {
        // 26.3 leaves out default fields: scale 0, unlocked.
        let current = try #require(MapItem(id: 43, nbt: .compound(["DataVersion": .int(5023), "data": .compound([
            "dimension": .string("minecraft:overworld"), "xCenter": .int(256), "zCenter": .int(-2432), "colors": colors(at: 5, 4 * 7 + 2),
        ])])))
        #expect(current.dimension == "minecraft:overworld" && current.scale == 0 && !current.isLocked && !current.isBlank)
        #expect(current.minX == 192 && current.minZ == -2496 && current.sideInBlocks == 128)

        let bukkit = try #require(MapItem(id: 10, nbt: .compound(["data": .compound([
            "dimension": .byte(15), "scale": .byte(3), "xCenter": .int(-576), "zCenter": .int(448), "colors": colors(),
        ])])))
        #expect(bukkit.dimension == nil && bukkit.unrecognizedDimension == "15" && bukkit.isBlank)
        #expect(bukkit.blocksPerPixel == 8 && bukkit.minX == -576 - 512)

        let nether = MapItem(id: 1, nbt: .compound(["data": .compound(["dimension": .byte(-1), "colors": colors(),
            "banners": .list([.compound(["pos": .compound(["X": .int(1), "Y": .int(2), "Z": .int(3)]), "color": .string("red"), "name": .string("Home")])])])]))
        #expect(nether?.dimension == "minecraft:the_nether" && nether?.banners.first == MapItem.Banner(x: 1, y: 2, z: 3, color: "red", name: "Home"))
        #expect(MapItem(id: 0, nbt: .compound(["data": .compound(["map": .int(44)])])) == nil)
    }

    @Test func palette() {
        #expect(MapItem.rgb(forColor: 0) == nil && MapItem.rgb(forColor: 3) == nil)
        let grass = MapItem.rgb(forColor: 4 * 1 + 2)   // grass at full brightness
        #expect(grass?.red == 0x7F && grass?.green == 0xB2 && grass?.blue == 0x38)
        let darkWater = MapItem.rgb(forColor: 4 * 12 + 3)   // water at the darkest shade
        #expect(darkWater?.blue == UInt8(0xFF * 135 / 255))
        #expect(MapItem.rgb(forColor: 255) == nil)
    }

    @Test func worldListsMapsAndSkipsOtherFiles() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("M")])]), to: dir.appendingPathComponent("level.dat"))
        try Fixtures.writeGzippedNBT(.compound(["data": .compound(["dimension": .byte(0), "colors": colors()])]), to: dir.appendingPathComponent("data/minecraft/maps/2.dat"))
        try Fixtures.writeGzippedNBT(.compound(["data": .compound(["dimension": .byte(0), "colors": colors()])]), to: dir.appendingPathComponent("data/map_7.dat"))
        try Fixtures.writeGzippedNBT(.compound(["data": .compound(["map": .int(7)])]), to: dir.appendingPathComponent("data/minecraft/maps/last_id.dat"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("region"), withIntermediateDirectories: true)
        #expect(try World(contentsOf: dir).mapItems().map(\.id) == [2, 7])
    }
}
