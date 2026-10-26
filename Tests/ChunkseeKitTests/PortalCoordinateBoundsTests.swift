import Testing
@testable import ChunkseeKit

@Suite struct PortalCoordinateBoundsTests {
    typealias Block = NetherPortal.Block

    @Test func scalingClampsBeforeConvertingToAnInteger() {
        for dimension in [NetherPortal.overworld, NetherPortal.nether] {
            #expect(NetherPortal.destination(of: Block(x: .max, y: .min, z: .min), from: dimension, dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border)
                    == Block(x: 29_999_983, y: .min, z: -29_999_984))
            #expect(NetherPortal.destination(of: Block(x: .min, y: .max, z: .max), from: dimension, dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border)
                    == Block(x: -29_999_984, y: .max, z: 29_999_983))
        }
    }

    @Test func groupingDoesNotWrapNeighborsAtIntegerLimits() {
        let groups: [Set<Block>] = [
            [Block(x: .max, y: 0, z: 0), Block(x: .max - 1, y: 0, z: 0)],
            [Block(x: .min, y: 0, z: 0), Block(x: .min + 1, y: 0, z: 0)],
            [Block(x: 0, y: .max, z: .min)],
            [Block(x: 0, y: .min, z: .max)],
        ]
        let points = groups.flatMap { $0 }.map {
            PointOfInterest(type: "minecraft:nether_portal", x: $0.x, y: $0.y, z: $0.z, freeTickets: 0)
        }
        let portals = NetherPortal.portals(from: points, in: NetherPortal.nether)
        #expect(Set(portals.map { Set($0.blocks) }) == Set(groups))
    }

    @Test func savedPOIHeightsCannotOverflowTheLinkDistance() throws {
        func portals(_ positions: [[Int32]], dimension: String) -> [NetherPortal] {
            let records = positions.map { NBT.compound(["type": .string("minecraft:nether_portal"), "pos": .intArray($0)]) }
            let nbt = NBT.compound(["Sections": .compound(["0": .compound(["Records": .list(records)])])])
            return NetherPortal.portals(from: PointOfInterest.records(inChunk: nbt), in: dimension)
        }
        let source = try #require(portals([[0, .min, 0]], dimension: NetherPortal.overworld).first)
        let target = try #require(portals([[0, .max, 0], [0, .max - 1, 0]], dimension: NetherPortal.nether).first)
        #expect(source.link(into: [target], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .portal(target, block: Block(x: 0, y: Int(Int32.max) - 1, z: 0)))
    }

    @Test func extremeOutOfRangeCandidatesDoNotTrapAndTiesStillPreferLowerY() {
        let source = NetherPortal(dimension: NetherPortal.overworld, blocks: [Block(x: .max, y: 0, z: 0)])
        let distant = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: .min, y: 0, z: 0)])
        #expect(source.link(into: [distant], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: Block(x: 29_999_983, y: 0, z: 0)))

        let home = NetherPortal(dimension: NetherPortal.overworld, blocks: [Block(x: 0, y: 64, z: 0)])
        let above = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: 0, y: 65, z: 0)])
        let below = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: 0, y: 63, z: 0)])
        #expect(home.link(into: [above, below], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .portal(below, block: below.entry))
    }
}
