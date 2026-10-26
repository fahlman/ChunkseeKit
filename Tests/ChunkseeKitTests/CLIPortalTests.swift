import Foundation
import ChunkseeKitTestSupport
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
            "BorderSize": .double(59_999_968),
            "WorldGenSettings": .compound(["dimensions": .compound([
                NetherPortal.overworld: .compound(["type": PortalFixtures.definition(scale: 1)]),
                NetherPortal.nether: .compound(["type": PortalFixtures.definition(scale: 8)]),
            ])]),
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
        #expect(source.link(into: [destination], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .portal(destination, block: .init(x: -15, y: 64, z: 0)))
        #expect(destination.link(into: [source], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: .init(x: -128, y: 64, z: 0)))
        let root = try world(overworld: [source], nether: [destination])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output.contains("Overworld: 1 portals\n  (8, 64, 0) -> (-15, 64, 0)"))
        #expect(result.output.contains("(one-way: the return trip would create one near (-128, 64, 0))"))
        #expect(result.output.contains("Nether: 1 portals"))
    }

    @Test func reciprocalLinksKeepTheirOutputWithoutAOneWayWarning() throws {
        let root = try world(overworld: [frame(NetherPortal.overworld, x: 0)], nether: [frame(NetherPortal.nether, x: 0)])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output == "Overworld: 1 portals\n  (1, 64, 0) -> (1, 64, 0)\nNether: 1 portals\n  (1, 64, 0) -> (1, 64, 0)\n")
    }

    @Test func aReturnToAnotherExistingPortalKeepsTheOriginalOneWayNote() throws {
        let root = try world(overworld: [frame(NetherPortal.overworld, x: 0), frame(NetherPortal.overworld, x: 80)],
                             nether: [frame(NetherPortal.nether, x: 10)])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output.contains("(1, 64, 0) -> (11, 64, 0)  (one-way: it leads back to (81, 64, 0))"))
        #expect(!result.output.contains("the return trip would create"))
    }

    @Test func outboundCreationKeepsTheOriginalMessage() throws {
        let root = try world(overworld: [frame(NetherPortal.overworld, x: 7)], nether: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output == "Overworld: 1 portals\n  (8, 64, 0) -> no portal in range; would create one near (0, 64, 0)\nNether: 0 portals\n")
    }

    @Test func missingContextPreservesThePortalWithoutGuessingADestination() throws {
        let root = try world(overworld: [frame(NetherPortal.overworld, x: 800)], nether: [])
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(5023)])]),
            to: root.appendingPathComponent("level.dat"))
        let result = try Fixtures.runCLI(root, command: "portals")
        #expect(result.status == 0)
        #expect(result.output == "Overworld: 1 portals\n  (801, 64, 0) -> ?\nNether: 0 portals\n")
    }
}
