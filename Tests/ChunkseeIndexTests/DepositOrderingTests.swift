import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct DepositOrderingTests {
    @Test func unchangedDepositsKeepTheirOrderAndLimitedMembershipAfterRefresh() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Deposit order")
        ])]), to: root.appendingPathComponent("level.dat"))
        let catalog = try NotableBlockFixtures.catalog()
        let dimensions = ["minecraft:overworld", "minecraft:the_nether"]
        let positions: [ChunkPosition] = [
            .init(x: 1, z: 1), .init(x: -1, z: 0), .init(x: -2, z: 1), .init(x: 0, z: 0),
            .init(x: -2, z: 0), .init(x: 1, z: 0), .init(x: 0, z: 1), .init(x: -1, z: 1),
        ]
        for dimension in dimensions {
            let directory = dimension.replacingOccurrences(of: ":", with: "/")
            for (region, chunks) in Dictionary(grouping: positions, by: \.region) {
                let entries = chunks.map { position in
                    let count = position == .init(x: 1, z: 1) ? 7 : 4
                    let indices = [Int](repeating: 1, count: count) + [Int](repeating: 2, count: 4)
                        + [Int](repeating: 0, count: 4096 - count - 4)
                    let section = Fixtures.section(y: -2, palette: ["air", "diamond_ore", "emerald_ore"].map {
                        .compound(["Name": .string("minecraft:" + $0)])
                    }, indices: indices)
                    return Fixtures.RegionChunk(localX: position.localX, localZ: position.localZ,
                        nbt: Fixtures.chunk(x: position.x, z: position.z, sections: [section]))
                }
                try Fixtures.write(try Fixtures.region(entries), to: root.appendingPathComponent(
                    "dimensions/\(directory)/region/r.\(region.x).\(region.z).mca"))
            }
        }

        var original: [String: DimensionIndex] = [:]
        var rebuilt: [String: DimensionIndex] = [:]
        var refreshed: [String: DimensionIndex] = [:]
        let world = try World(contentsOf: root)
        for id in dimensions {
            let dimension = try #require(world.dimension(id))
            let facts = try dimension.regionFiles().map {
                try dimension.scan(region: .init(x: $0.x, z: $0.z), options: .init(blockIDs: catalog.blockIDs))
            }
            let available = Set(facts.map(\.region))
            let parts = facts.map { RegionIndex($0, caveBiomeIDs: [], notableBlocks: catalog) }
            let empty = DimensionIndex(dimension: id, caveBiomeIDs: [], notableBlocks: catalog)
            let first = empty.updating(available: available, selected: nil, replacements: parts)
            original[id] = first

            // Reversing the saved archive's chunks rebuilds each region dictionary with the
            // same facts in a different insertion order, without changing any ore counts.
            let reordered = try facts.reversed().map { facts in
                var archive = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as? [String: Any])
                let chunks = try #require(archive["chunks"] as? [[String: Any]])
                archive["chunks"] = Array(chunks.reversed())
                let decoded = try JSONDecoder().decode(RegionFacts.self,
                    from: JSONSerialization.data(withJSONObject: archive))
                return RegionIndex(decoded, caveBiomeIDs: [], notableBlocks: catalog)
            }
            rebuilt[id] = empty.updating(available: available, selected: nil, replacements: reordered)
            refreshed[id] = first.updating(available: available, selected: [.init(x: -1, z: 0)],
                                           replacements: reordered)
        }

        let rich = deposit(.diamond, 7, x: 1, z: 1)
        var expected = [rich]
        for x in [-2, -1, 0, 1] {
            for z in [0, 1] {
                if x != 1 || z != 1 { expected.append(deposit(.diamond, 4, x: x, z: z)) }
                expected.append(deposit(.emerald, 4, x: x, z: z))
            }
        }
        for snapshots in [original, rebuilt, refreshed] {
            for value in snapshots.values { #expect(value.blocks == expected) }
            for order in [dimensions, Array(dimensions.reversed())] {
                var catalog: [String: DimensionIndex] = [:]
                for id in order { catalog[id] = snapshots[id] }
                let best = WorldIndex(dimensions: catalog)
                    .richestDeposits(matching: [.diamond, .emerald], limit: 5, in: \.blocks)
                #expect(best.map(\.dimension) == [dimensions[0], dimensions[1], dimensions[0], dimensions[0], dimensions[0]])
                #expect(best.map(\.value) == [rich, rich, deposit(.diamond, 4, x: -2, z: 0),
                    deposit(.emerald, 4, x: -2, z: 0), deposit(.diamond, 4, x: -2, z: 1)])
            }
        }
    }

    @Test func unsortedDimensionArraysAreRankedBeforeTheirLimit() {
        struct Content: Sendable { var blocks: [DimensionIndex.ChunkDeposit] }
        let input = [deposit(.emerald, 4, x: 2, z: 0), deposit(.diamond, 4, x: -1, z: 2),
                     deposit(.emerald, 4, x: -1, z: 0), deposit(.diamond, 4, x: -1, z: 0),
                     deposit(.coal, 90, x: 3, z: 0), deposit(.diamond, 9, x: 8, z: 8)]
        let id = "example:caves"
        for values in [input, Array(input.reversed())] {
            let world = WorldIndex(dimensions: [id: Content(blocks: values)])
            let best = world.richestDeposits(matching: [.diamond, .emerald], limit: 3, in: \.blocks)
            #expect(best.map(\.value) == [deposit(.diamond, 9, x: 8, z: 8),
                deposit(.diamond, 4, x: -1, z: 0), deposit(.emerald, 4, x: -1, z: 0)])
        }
    }

    private func deposit(_ block: NotableBlock, _ count: Int, x: Int, z: Int) -> DimensionIndex.ChunkDeposit {
        .init(chunk: .init(x: x, z: z), deposit: .init(block: block, count: count, minY: -32, maxY: -17))
    }
}
