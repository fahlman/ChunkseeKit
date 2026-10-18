import Foundation
import Testing
import ChunkseeKit

@Suite struct CLIPortalTests {
    private struct Coordinate: Hashable { var x: Int, z: Int }

    private func frame(_ dimension: String, x: Int, z: Int = 0) -> NetherPortal {
        NetherPortal(dimension: dimension, blocks: [0, 1].flatMap { dx in
            (64..<67).map { NetherPortal.Block(x: x + dx, y: $0, z: z) }
        })
    }

    private func world(overworld: [NetherPortal], nether: [NetherPortal]) throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Portal round trips"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        for (folder, portals) in [(root, overworld), (root.appendingPathComponent("DIM-1"), nether)] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("region"), withIntermediateDirectories: true)
            let chunks = Dictionary(grouping: portals.flatMap(\.blocks)) { Coordinate(x: $0.x >> 4, z: $0.z >> 4) }
            let regions = Dictionary(grouping: Array(chunks.keys)) { Coordinate(x: $0.x >> 5, z: $0.z >> 5) }
            for (region, coordinates) in regions {
                let records = coordinates.map { coordinate in
                    let sections = Dictionary(grouping: chunks[coordinate]!) { $0.y >> 4 }.map { section, blocks in
                        (String(section), NBT.compound(["Valid": .byte(1), "Records": .list(blocks.map {
                            .compound(["type": .string("minecraft:nether_portal"),
                                       "pos": .intArray([Int32($0.x), Int32($0.y), Int32($0.z)]), "free_tickets": .int(0)])
                        })]))
                    }
                    return Fixtures.RegionChunk(localX: coordinate.x & 31, localZ: coordinate.z & 31,
                                                nbt: .compound(["DataVersion": .int(5023), "Sections": .compound(Dictionary(uniqueKeysWithValues: sections))]))
                }
                try Fixtures.write(Fixtures.region(records), to: folder.appendingPathComponent("poi/r.\(region.x).\(region.z).mca"))
            }
        }
        return root
    }

    @Test func anExistingDestinationWhoseDefaultReturnCreatesAPortalIsFlaggedOneWay() throws {
        let source = frame(NetherPortal.overworld, x: 7)
        let destination = frame(NetherPortal.nether, x: -16)
        #expect(source.link(into: [destination]) == .portal(destination, block: .init(x: -15, y: 64, z: 0)))
        #expect(destination.link(into: [source]) == .wouldCreateNewPortal(destination: .init(x: -128, y: 64, z: 0)))
        let root = try world(overworld: [source], nether: [destination])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output.contains("Overworld: 1 portals\n  (8, 64, 0) -> (-15, 64, 0)"))
        #expect(result.output.contains("(one-way: the return trip would create one near (-128, 64, 0))"))
        #expect(result.output.contains("Nether: 1 portals"))
    }
}
