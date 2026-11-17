import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct DepositOrderingTests {
    @Test func nearestBeforeLimitIncludesPoorNearbyChunksAndSupportsTwoOrigins() throws {
        let fixture = try CountsFixture()
        defer { fixture.remove() }
        let catalog = try NotableBlockFixtures.catalog()
        let positions = (0..<220).map { ChunkPosition(x: $0, z: 0) }
        let facts = try fixture.write(positions, includeEmerald: false, ids: catalog.blockIDs)
        let available = Set(facts.map(\.region))
        let index = BlockCountIndex(dimension: fixture.dimension.id).updating(available: available, replacements: facts)
        let west = try #require(BlockSearchOrigin(x: 8, z: 8)), east = try #require(BlockSearchOrigin(x: 219 * 16 + 8, z: 8))
        let westMatches = index.matchingDeposits(matching: [.diamond], using: catalog, from: west, limit: 200)
        let eastMatches = index.matchingDeposits(matching: [.diamond], using: catalog, from: east, limit: 200)
        let fromWest = westMatches.nearest, fromEast = eastMatches.nearest
        #expect(westMatches.totalCount == 220 && eastMatches.totalCount == 220)
        #expect(fromWest.map(\.chunk.x) == Array(0..<200))
        #expect(fromWest.first?.deposit.count == 1 && fromWest.last?.deposit.count == 1000)
        #expect(fromEast.map(\.chunk.x) == Array((20..<220).reversed()))
        #expect(index.nearestDeposits(matching: [.diamond], using: catalog, from: west, limit: 200) == fromWest)
        #expect(index.regionsToRead(available: available, matching: catalog.blockIDs, from: east).isEmpty)
        for limit in [0, -1] {
            #expect(index.nearestDeposits(matching: [.diamond], using: catalog, from: west, limit: limit).isEmpty)
            let totalOnly = index.matchingDeposits(matching: [.diamond], using: catalog, from: west, limit: limit)
            #expect(totalOnly.nearest.isEmpty && totalOnly.totalCount == 220)
        }
        for groups in [Set<NotableBlock>(), [.ancientDebris]] {
            let none = index.matchingDeposits(matching: groups, using: catalog, from: west, limit: 200)
            #expect(none.nearest.isEmpty && none.totalCount == 0)
        }
        #expect(BlockSearchOrigin(x: .nan, z: 0) == nil && BlockSearchOrigin(x: 0, z: .infinity) == nil)
    }

    @Test func tiesAndLimitedMembershipSurviveArchiveOrderAndPartialReplacement() throws {
        let fixture = try CountsFixture()
        defer { fixture.remove() }
        let catalog = try NotableBlockFixtures.catalog()
        let positions: [ChunkPosition] = [.init(x: 1, z: 0), .init(x: -1, z: 0), .init(x: 0, z: 0)]
        let facts = try fixture.write(positions, includeEmerald: true, ids: catalog.blockIDs)
        let available = Set(facts.map(\.region)), origin = try #require(BlockSearchOrigin(x: 8, z: 8))
        let initial = BlockCountIndex(dimension: fixture.dimension.id).updating(available: available, replacements: facts)
        let reordered = try facts.reversed().map { counts in
            var archive = try #require(PropertyListSerialization.propertyList(
                from: PropertyListEncoder().encode(counts), format: nil) as? [String: Any])
            archive["chunks"] = Array(try #require(archive["chunks"] as? [[String: Any]]).reversed())
            return try PropertyListDecoder().decode(RegionBlockCounts.self, from:
                PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0))
        }
        let rebuilt = BlockCountIndex(dimension: fixture.dimension.id).updating(available: available, replacements: reordered)
        let refreshed = initial.updating(available: available, replacements: Array(reordered.prefix(1)))
        for index in [initial, rebuilt, refreshed] {
            let matches = index.matchingDeposits(matching: [.diamond, .emerald], using: catalog, from: origin, limit: 5)
            let results = matches.nearest
            #expect(matches.totalCount == 6)
            #expect(results.map(\.chunk.x) == [0, 0, -1, -1, 1])
            #expect(results.map(\.deposit.block) == [.diamond, .emerald, .diamond, .emerald, .diamond])
            #expect(results.allSatisfy { $0.deposit.minY == -32 && $0.deposit.maxY == -17 })
        }
    }

    @Test func unsearchedFailureEmptyAndDeletedCoverageAreSeparate() throws {
        let fixture = try CountsFixture()
        defer { fixture.remove() }
        let catalog = try NotableBlockFixtures.catalog(), position = RegionPosition(x: 0, z: 0)
        let origin = try #require(BlockSearchOrigin(x: 8, z: 8))
        let facts = try fixture.write([.init(x: 0, z: 0)], includeEmerald: false, ids: catalog.blockIDs)
        let fresh = BlockCountIndex(dimension: fixture.dimension.id)
        #expect(fresh.coverage(of: position, matching: catalog.blockIDs) == .unsearched)
        let first = fresh.updating(available: [position], replacements: facts)
        #expect(first.coverage(of: position, matching: catalog.blockIDs) == .complete)
        let changed = first.invalidating([position])
        #expect(changed.coverage(of: position, matching: catalog.blockIDs) == .unsearched)
        #expect(changed.regions[position]?.counts == first.regions[position]?.counts)
        let failed = changed.updating(available: [position], replacements: [], failed: [position])
        #expect(failed.coverage(of: position, matching: catalog.blockIDs) == .failed)
        #expect(failed.regions[position]?.counts == first.regions[position]?.counts)
        #expect(failed.matchingDeposits(matching: [.diamond], using: catalog, from: origin, limit: 200).totalCount == 1)
        #expect(failed.regionsToRead(available: [position], matching: catalog.blockIDs, from: origin).isEmpty)
        #expect(failed.invalidating([position]).regionsToRead(available: [position], matching: catalog.blockIDs, from: origin) == [position])
        try Fixtures.write(Fixtures.region([]), to: fixture.dimension.regionURL(at: position))
        let empty = try fixture.dimension.countBlocks(region: position, matching: catalog.blockIDs)
        let cleared = failed.updating(available: [position], replacements: [empty])
        #expect(cleared.coverage(of: position, matching: catalog.blockIDs) == .complete)
        #expect(cleared.nearestDeposits(matching: [.diamond], using: catalog, from: origin, limit: 200).isEmpty)
        #expect(cleared.matchingDeposits(matching: [.diamond], using: catalog, from: origin, limit: 200).totalCount == 0)
        #expect(first.nearestDeposits(matching: [.diamond], using: catalog, from: origin, limit: 200).count == 1)
        #expect(first.updating(available: [], replacements: facts).regions.isEmpty)
        let foreign = BlockCountIndex(dimension: "example:another").updating(available: [position], replacements: facts)
        #expect(foreign.regions.isEmpty)
    }

    @Test func sparseOccupiedRegionsAreOrderedByOutwardRings() throws {
        let index = BlockCountIndex(dimension: "example:world")
        let origin = try #require(BlockSearchOrigin(x: -1, z: -1))
        let positions: Set<RegionPosition> = [.init(x: 0, z: 0), .init(x: -1, z: -1),
            .init(x: 100_000, z: -100_000), .init(x: -2, z: -1)]
        #expect(index.regionsToRead(available: positions, matching: ["example:ore"], from: origin) == [
            .init(x: -1, z: -1), .init(x: -2, z: -1), .init(x: 0, z: 0), .init(x: 100_000, z: -100_000)])
        #expect(index.regionsToRead(available: positions, matching: [], from: origin).isEmpty)
    }

    @Test func checkedQueriesKeepCompleteTotalsAndNearestMembership() throws {
        let fixture = try CountsFixture()
        defer { fixture.remove() }
        let catalog = try NotableBlockFixtures.catalog()
        let facts = try fixture.write((0..<12).map { .init(x: $0, z: 0) },
                                      includeEmerald: true, ids: catalog.blockIDs)
        let index = BlockCountIndex(dimension: fixture.dimension.id)
            .updating(available: Set(facts.map(\.region)), replacements: facts)
        for x in [8, 184] {
            let origin = try #require(BlockSearchOrigin(x: Double(x), z: 8))
            for groups in [Set<NotableBlock>(), [.diamond], [.diamond, .emerald], [.ancientDebris]] {
                for limit in [-1, 0, 1, 5, 200] {
                    let expected = index.matchingDeposits(matching: groups, using: catalog, from: origin, limit: limit)
                    let checked = try index.matchingDeposits(matching: groups, using: catalog, from: origin, limit: limit,
                                                             checkingCancellation: { try Task.checkCancellation() })
                    #expect(checked == expected)
                    let nearest = try index.nearestDeposits(matching: groups, using: catalog, from: origin, limit: limit,
                                                            checkingCancellation: { try Task.checkCancellation() })
                    #expect(nearest == expected.nearest)
                }
            }
        }
    }

    @Test func cancellationRethrowsBeforeAndDuringGroupingAndRanking() throws {
        struct Stopped: Error, Equatable { let checkpoint: Int }
        let fixture = try CountsFixture()
        defer { fixture.remove() }
        let catalog = try NotableBlockFixtures.catalog()
        let facts = try fixture.write((0..<64).map { .init(x: $0, z: 0) },
                                      includeEmerald: true, ids: catalog.blockIDs)
        let index = BlockCountIndex(dimension: fixture.dimension.id)
            .updating(available: Set(facts.map(\.region)), replacements: facts)
        let origin = try #require(BlockSearchOrigin(x: 8, z: 8)), groups: Set<NotableBlock> = [.diamond, .emerald]
        var totalOnlyChecks = 0, allChecks = 0
        let total = index.matchingDeposits(matching: groups, using: catalog, from: origin, limit: 0,
                                          checkingCancellation: { totalOnlyChecks += 1 })
        let complete = index.matchingDeposits(matching: groups, using: catalog, from: origin, limit: 8,
                                             checkingCancellation: { allChecks += 1 })
        #expect(total.totalCount == 128 && complete.totalCount == total.totalCount && complete.nearest.count == 8)
        #expect(totalOnlyChecks > 1 && allChecks > totalOnlyChecks)
        // Choose early, middle and late checkpoints from completed calls, without tying the
        // contract to a fixed polling frequency, dictionary traversal or sorting algorithm.
        for stop in Set([0, totalOnlyChecks / 2, totalOnlyChecks, allChecks / 2, allChecks - 1]) {
            var checks = 0
            let failure = Stopped(checkpoint: stop)
            #expect(throws: failure) {
                try index.matchingDeposits(matching: groups, using: catalog, from: origin, limit: 8) {
                    let checkpoint = checks
                    checks += 1
                    if checkpoint == stop { throw failure }
                }
            }
            #expect(checks == stop + 1)
        }
        for limit in [-1, 0, 8] {
            #expect(throws: Stopped(checkpoint: 0)) {
                try index.nearestDeposits(matching: groups, using: catalog, from: origin, limit: limit) {
                    throw Stopped(checkpoint: 0)
                }
            }
        }
    }

    @Test func cancelledTaskDoesNotPublishACompletedEmptyResult() async throws {
        let index = BlockCountIndex(dimension: "minecraft:overworld")
        let catalog = NotableBlock.Catalog(tags: [:]), origin = try #require(BlockSearchOrigin(x: 8, z: 8))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try index.matchingDeposits(matching: [], using: catalog, from: origin, limit: 200,
                                          checkingCancellation: { try Task.checkCancellation() })
            }
        }
        await task.value
    }

    private struct CountsFixture {
        let root: URL
        let dimension: ChunkseeKit.Dimension

        init() throws {
            root = try Fixtures.tempDirectory()
            try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Counts")])]),
                to: root.appendingPathComponent("level.dat"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/overworld/region"),
                withIntermediateDirectories: true)
            dimension = try #require(World(contentsOf: root).dimension("overworld"))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func write(_ positions: [ChunkPosition], includeEmerald: Bool, ids: Set<String>) throws -> [RegionBlockCounts] {
            for (region, chunks) in Dictionary(grouping: positions, by: \.region) {
                let entries = chunks.map { position in
                    let count = position.x == 0 ? 1 : 1000
                    let emerald = includeEmerald ? 4 : 0
                    let indices = [Int](repeating: 1, count: count) + [Int](repeating: 2, count: emerald)
                        + [Int](repeating: 0, count: 4096 - count - emerald)
                    let section = Fixtures.section(y: -2, palette: ["air", "diamond_ore", "emerald_ore"].map {
                        .compound(["Name": .string("minecraft:" + $0)])
                    }, indices: indices)
                    return Fixtures.RegionChunk(localX: position.localX, localZ: position.localZ,
                        nbt: Fixtures.chunk(x: position.x, z: position.z, sections: [section]))
                }
                try Fixtures.write(Fixtures.region(entries), to: dimension.regionURL(at: region))
            }
            return try Set(positions.map(\.region)).map { try dimension.countBlocks(region: $0, matching: ids) }
        }
    }
}
