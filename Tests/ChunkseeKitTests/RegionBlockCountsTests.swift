import ChunkseeKitTestSupport
import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct RegionBlockCountsTests {
    @Test func terrainOnlyCountsPersistCoverageAndIgnoreUnrelatedFiles() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:world", url: root), fixture = RegionFactsTests()
        try fixture.write(fixture.terrain(), in: .terrain, dimension: dimension)
        // These unreadable files must never be opened by the terrain-only path.
        for folder in [Dimension.Folder.entities, .pointsOfInterest] {
            try Fixtures.write([0, 1], to: dimension.regionURL(folder, at: fixture.region))
        }
        let path = dimension.regionURL(at: fixture.region), before = try Data(contentsOf: path)
        let ids: Set<String> = ["minecraft:diamond_ore", "minecraft:gold_ore", "example:absent"]
        let counts = try dimension.countBlocks(region: fixture.region, matching: ids)
        #expect(counts.blockIDs == ids && counts.dimension == dimension.id && counts.region == fixture.region)
        #expect(counts.chunks == [.init(x: -1, z: 0): [.init(id: "minecraft:diamond_ore", count: 128, minY: 48, maxY: 63)]])
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(counts)
        #expect(data.starts(with: Data("bplist".utf8)))
        #expect(try PropertyListDecoder().decode(RegionBlockCounts.self, from: data) == counts)
        #expect(try dimension.countBlocks(region: fixture.region, matching: ["example:absent"]).chunks.isEmpty)
        #expect(try dimension.countBlocks(region: fixture.region, matching: []).chunks.isEmpty)
        #expect(try Data(contentsOf: path) == before)
    }

    @Test func propertiesCombineAcrossSectionsAndPartialChunksDoNotCount() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:world", url: root), region = RegionPosition(x: -1, z: -1)
        let palettes: [NBT] = ["true", "false"].map {
            .compound(["Name": .string("example:ore"), "Properties": .compound(["lit": .string($0)])])
        }
        let lower = Fixtures.section(y: -2, palette: palettes,
            indices: (0..<4096).map { $0 % 2 })
        let upper = Fixtures.section(y: 1, palette: [.string("example:ore")])
        let full = Fixtures.chunk(x: 777, z: 888, sections: [lower, upper])
        let partial = Fixtures.chunk(x: -2, z: -1, sections: [upper], extra: ["status": .string("minecraft:noise")])
        try Fixtures.write(Fixtures.region([
            .init(localX: 31, localZ: 31, nbt: full), .init(localX: 30, localZ: 31, nbt: partial)
        ]), to: dimension.regionURL(at: region))
        let counts = try dimension.countBlocks(region: region, matching: ["example:ore"])
        #expect(counts.chunks == [.init(x: -1, z: -1): [.init(id: "example:ore", count: 8192, minY: -32, maxY: 31)]])
    }

    @Test func unrelatedMalformedBiomesAreNotNeededToCountBlocks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:world", url: root), region = RegionPosition(x: 0, z: 0)
        var section = try #require(Fixtures.section(y: 0, palette: [.string("example:ore")]).compound)
        section["biomes"] = .compound(["palette": .list([.int(12)])])
        let chunk = Fixtures.chunk(x: 0, z: 0, sections: [.compound(section)])
        #expect(throws: (any Error).self) { try Chunk(nbt: chunk) }
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]), to: dimension.regionURL(at: region))
        #expect(try dimension.countBlocks(region: region, matching: ["example:ore"]).chunks[.init(x: 0, z: 0)]?.first?.count == 4096)
    }

    @Test func corruptTerrainIsAFailureRatherThanACompletedEmptyCount() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:world", url: root), fixture = RegionFactsTests()
        let ids: Set<String> = ["minecraft:diamond_ore"]
        let absent = try dimension.countBlocks(region: fixture.region, matching: ids)
        #expect(absent.chunks.isEmpty && absent.blockIDs == ids)
        var bytes = try Fixtures.region([.init(localX: 31, localZ: 0, nbt: fixture.terrain())])
        bytes[8192 + 4] = 99
        try Fixtures.write(bytes, to: dimension.regionURL(at: fixture.region))
        #expect(throws: (any Error).self) { try dimension.countBlocks(region: fixture.region, matching: ids) }
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try dimension.countBlocks(region: fixture.region, matching: ids)
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        #expect(throws: RegionScanError.invalidRegion(.init(x: Int.max, z: 0))) {
            try dimension.countBlocks(region: .init(x: Int.max, z: 0), matching: ids)
        }
    }

    @Test func countArchiveHasItsOwnVersionAndCanonicalCoverage() throws {
        let first = RegionBlockCounts(dimension: "example:world", region: .init(x: 0, z: 0),
            blockIDs: Set(["example:a", "example:b"]), chunks: [:])
        let reversed = RegionBlockCounts(dimension: first.dimension, region: first.region,
            blockIDs: Set(["example:b", "example:a"]), chunks: [:])
        #expect(try InterpretationKey.identity(of: first) == InterpretationKey.identity(of: reversed))
        #expect(RegionBlockCounts.interpretationVersion.dependencies == [Chunk.interpretationVersion])
        var archive = try #require(PropertyListSerialization.propertyList(
            from: PropertyListEncoder().encode(first), format: nil) as? [String: Any])
        var version = try #require(archive["version"] as? [String: Any])
        version["revision"] = RegionBlockCounts.interpretationVersion.revision + 1
        archive["version"] = version
        let stale = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        #expect(throws: (any Error).self) { try PropertyListDecoder().decode(RegionBlockCounts.self, from: stale) }
    }
}
