import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct RegionTests {
    @Test func readsChunksWithEachCompression() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stone = [Fixtures.section(y: 0, palette: [.string("minecraft:stone")])]
        let chunks = [UInt8(1), 2, 3, 4].enumerated().map { i, c in
            Fixtures.RegionChunk(localX: i, localZ: 31, nbt: Fixtures.chunk(x: -32 + i, z: -1, sections: stone), compression: c)
        }
        let url = dir.appendingPathComponent("r.-1.-1.mca")
        try Fixtures.write(try Fixtures.region(chunks), to: url)

        let region = try RegionFile(contentsOf: url)
        #expect((region.x, region.z) == (-1, -1))
        #expect(region.chunkCoordinates.count == 4)
        #expect(try region.chunkNBT(localX: 10, localZ: 10) == nil)
        #expect(try region.timestamp(localX: 0, localZ: 31) == Date(timeIntervalSince1970: 1_700_000_000))
        for i in 0..<4 {
            let chunk = try Chunk(nbt: #require(try region.chunkNBT(localX: i, localZ: 31)))
            #expect(chunk.x == -32 + i)
            #expect(chunk.block(x: 0, y: 3, z: 0)?.id == "minecraft:stone")
        }
    }

    @Test func readsExternalChunk() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nbt = Fixtures.chunk(x: 33, z: 2, sections: [])
        try Fixtures.write(try Fixtures.region([.init(localX: 1, localZ: 2, nbt: nbt, compression: 0x82)]),
                           to: dir.appendingPathComponent("r.1.0.mca"))
        try Fixtures.write(try Compression.deflate(nbt.serialized()), to: dir.appendingPathComponent("c.33.2.mcc"))
        let region = try RegionFile(contentsOf: dir.appendingPathComponent("r.1.0.mca"))
        #expect(try region.chunkNBT(localX: 1, localZ: 2) == nbt)
    }

    @Test func reportsMissingExternalChunk() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([:]), compression: 0x82)]),
                           to: dir.appendingPathComponent("r.0.0.mca"))
        let region = try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca"))
        #expect(throws: RegionError.missingExternalChunk("c.0.0.mcc")) { try region.chunkNBT(localX: 0, localZ: 0) }
    }

    @Test func emptyRegionFile() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write([], to: dir.appendingPathComponent("r.0.0.mca"))
        #expect(try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca")).chunkCoordinates.isEmpty)
    }
}
