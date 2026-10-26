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
        #expect(try RegionFile.chunkNBT(contentsOf: url, localX: 10, localZ: 10) == nil)
        #expect(try region.timestamp(localX: 0, localZ: 31) == Date(timeIntervalSince1970: 1_700_000_000))
        for i in 0..<4 {
            let chunk = try Chunk(nbt: #require(try region.chunkNBT(localX: i, localZ: 31)))
            #expect(chunk.x == -32 + i)
            #expect(chunk.block(x: 0, y: 3, z: 0)?.id == "minecraft:stone")
            let direct = try RegionFile.chunkNBT(contentsOf: url, localX: i, localZ: 31)
            #expect(direct == Fixtures.chunk(x: -32 + i, z: -1, sections: stone))
            #expect(try RegionFile.chunkNBT(contentsOf: url, localX: i, localZ: 31, skipping: ["sections"])
                == region.chunkNBT(localX: i, localZ: 31, skipping: ["sections"]))
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
        #expect(try RegionFile.chunkNBT(contentsOf: region.url, localX: 1, localZ: 2) == nbt)
    }

    @Test func reportsMissingExternalChunk() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([:]), compression: 0x82)]),
                           to: dir.appendingPathComponent("r.0.0.mca"))
        let region = try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca"))
        #expect(throws: RegionError.missingExternalChunk("c.0.0.mcc")) { try region.chunkNBT(localX: 0, localZ: 0) }
        #expect(throws: RegionError.missingExternalChunk("c.0.0.mcc")) {
            try RegionFile.chunkNBT(contentsOf: region.url, localX: 0, localZ: 0)
        }
    }

    @Test func emptyRegionFile() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write([], to: dir.appendingPathComponent("r.0.0.mca"))
        #expect(try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca")).chunkCoordinates.isEmpty)
        #expect(try RegionFile.chunkNBT(contentsOf: dir.appendingPathComponent("r.0.0.mca"), localX: 0, localZ: 0) == nil)
    }

    @Test func bothReadPathsRejectInvalidChunkLocationsLengthsAndCompression() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("r.0.0.mca")
        let valid = try Fixtures.region([.init(localX: 0, localZ: 0,
            nbt: .compound(["text": .string(String(repeating: "x", count: 5000))]), compression: 3)])
        var samples: [([UInt8], RegionError)] = [([1], .truncatedHeader)]
        var missingSector = valid; missingSector[0] = 127
        samples.append((missingSector, .invalidChunkLength))
        for prefix in [[UInt8](repeating: 0, count: 4), [255, 255, 255, 255], [127, 255, 255, 255]] {
            var invalid = valid; invalid.replaceSubrange(8192..<8196, with: prefix)
            samples.append((invalid, .invalidChunkLength))
        }
        var shortSector = valid; shortSector[3] = 1
        samples.append((shortSector, .invalidChunkLength))
        samples.append((Array(valid.prefix(8200)), .invalidChunkLength))
        var compression = valid; compression[8196] = 99
        samples.append((compression, .unknownCompression(99)))
        for (bytes, error) in samples {
            try Fixtures.write(bytes, to: url)
            #expect(throws: error) { try RegionFile(contentsOf: url).chunkNBT(localX: 0, localZ: 0) }
            #expect(throws: error) { try RegionFile.chunkNBT(contentsOf: url, localX: 0, localZ: 0) }
        }
        try Fixtures.write(valid, to: url)
        #expect(throws: RegionError.chunkOutOfBounds(localX: -1, localZ: 0)) {
            try RegionFile.chunkNBT(contentsOf: url, localX: -1, localZ: 0)
        }
    }
}
