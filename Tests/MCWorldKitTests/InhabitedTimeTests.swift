import Foundation
import Testing
@testable import MCWorldKit

@Suite struct InhabitedTimeTests {
    @Test func timesByChunkInARegion() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var lived = Fixtures.chunk(x: -1, z: -2, sections: [])
        lived = .compound(lived.compound!.merging(["InhabitedTime": .long(72_000)]) { $1 })
        let old = NBT.compound(["DataVersion": .int(1343), "Level": .compound(["InhabitedTime": .long(5)])])
        try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 30, nbt: lived), .init(localX: 0, localZ: 0, nbt: old)]),
                           to: dir.appendingPathComponent("dimensions/minecraft/overworld/region/r.-1.-1.mca"))
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("T")])]), to: dir.appendingPathComponent("level.dat"))
        let overworld = try #require(try World(contentsOf: dir).dimension("overworld"))
        let times = try overworld.inhabitedTimes(regionX: -1, regionZ: -1)
        #expect(times.count == 1024 && times[30 * 32 + 31] == 72_000 && times[0] == 5)
        #expect(times.reduce(0, +) == 72_005)
        #expect(try overworld.inhabitedTimes(regionX: 9, regionZ: 9).allSatisfy { $0 == 0 })
    }
}
