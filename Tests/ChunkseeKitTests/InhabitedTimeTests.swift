import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct InhabitedTimeTests {
    @Test func sharedMetadataReadPreservesRootPrecedenceAndMissingValues() throws {
        let old = NBT.compound(["Level": .compound(["InhabitedTime": .long(5)])])
        #expect(Chunk.inhabitedTime(in: old) == 5)
        #expect(Chunk.inhabitedTime(in: .compound([:])) == nil)
        for rootValue in [Int64(0), 72_000] {
            let nbt = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: [
                "InhabitedTime": .long(rootValue), "Level": .compound(["InhabitedTime": .long(5)]),
            ])
            #expect(Chunk.inhabitedTime(in: nbt) == Int(rootValue))
            #expect(try Chunk(nbt: nbt).inhabitedTime == Int(rootValue))
        }
        let upgraded = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: [
            "Level": .compound(["InhabitedTime": .long(5)]),
        ])
        #expect(try Chunk(nbt: upgraded).inhabitedTime == Chunk.inhabitedTime(in: upgraded))
        #expect(Chunk.inhabitedTime(in: upgraded) == 5)
    }

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
