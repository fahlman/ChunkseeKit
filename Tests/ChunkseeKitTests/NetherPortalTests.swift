import Foundation
import Testing
import ChunkseeKitTestSupport
@testable import ChunkseeKit

@Suite struct NetherPortalTests {
    typealias Block = NetherPortal.Block

    @Test func unavailablePoiFolderThrowsAnErrorNamingTheFolder() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: NetherPortal.overworld, url: root)
        try Data().write(to: dimension.poiDirectory)
        do {
            _ = try dimension.netherPortals()
            Issue.record("An unavailable POI folder must not report no portals")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadUnknown)
            #expect(error.filePath == dimension.poiDirectory.path)
        }
    }

    @Test(arguments: [false, true])
    func missingAndEmptyPoiFoldersHaveNoPortals(_ empty: Bool) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: NetherPortal.overworld, url: root)
        if empty { try FileManager.default.createDirectory(at: dimension.poiDirectory, withIntermediateDirectories: true) }
        #expect(try dimension.netherPortals().isEmpty)
    }

    /// A 2-wide, 3-tall portal along X with its bottom-left block at (x, y, z).
    func frame(_ dimension: String, x: Int, y: Int, z: Int) -> NetherPortal {
        NetherPortal(dimension: dimension, blocks: [0, 1].flatMap { dx in (0..<3).map { Block(x: x + dx, y: y + $0, z: z) } })
    }

    @Test func groupsTouchingBlocksIntoPortals() {
        let points = frame(NetherPortal.overworld, x: 100, y: 64, z: 40).blocks.map {
            PointOfInterest(type: "minecraft:nether_portal", x: $0.x, y: $0.y, z: $0.z, freeTickets: 0)
        } + [PointOfInterest(type: "minecraft:nether_portal", x: 500, y: 70, z: 500, freeTickets: 0),
             PointOfInterest(type: "minecraft:home", x: 101, y: 64, z: 41, freeTickets: 0)]
        let portals = NetherPortal.portals(from: points, in: NetherPortal.overworld)
        #expect(portals.map(\.blocks.count) == [6, 1])
        #expect(portals[0].entry == Block(x: 100, y: 64, z: 40))
        #expect(portals[0].centerX == 101)
    }

    @Test func destinationsScaleAndRoundDown() {
        #expect(NetherPortal.destination(of: Block(x: -3178, y: 67, z: -544), from: NetherPortal.overworld, dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border) == Block(x: -398, y: 67, z: -68))
        #expect(NetherPortal.destination(of: Block(x: -398, y: 67, z: -68), from: NetherPortal.nether, dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border) == Block(x: -3184, y: 67, z: -544))
        #expect(NetherPortal.destination(of: Block(x: 0, y: 0, z: 0), from: "minecraft:the_end", dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border) == nil)
        #expect(NetherPortal.destination(of: Block(x: 4_000_000, y: 64, z: 0), from: NetherPortal.nether, dimensionTypes: PortalFixtures.types, destinationBorder: PortalFixtures.border)?.x == 29_999_983)
    }

    @Test func linksToTheClosestPortalInRangeCountingY() {
        let home = frame(NetherPortal.overworld, x: 800, y: 64, z: 0)  // destination (100, 64, 0)
        let near = frame(NetherPortal.nether, x: 110, y: 64, z: 0)     // 10 away horizontally
        let below = frame(NetherPortal.nether, x: 100, y: 30, z: 0)    // straight down, but 34 away in Y
        let outOfRange = frame(NetherPortal.nether, x: 100, y: 64, z: 17)  // z 17 > radius 16
        guard case .portal(let target, let block)? = home.link(into: [below, near, outOfRange], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) else {
            Issue.record("expected a link"); return
        }
        #expect(target == near && block == Block(x: 110, y: 64, z: 0))
        // Only the out-of-range one: the game would build a new portal.
        #expect(home.link(into: [outOfRange], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: Block(x: 100, y: 64, z: 0)))
        // Coming back, the Overworld search is wider (128).
        let far = frame(NetherPortal.overworld, x: 800 + 120, y: 64, z: 0)
        if case .portal(let back, _)? = near.link(into: [far], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) { #expect(back == far) } else { Issue.record("expected a link back") }
        // No dimension type is supplied for this End portal.
        #expect(frame("minecraft:the_end", x: 0, y: 64, z: 0).link(into: [near], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == nil)
    }

    @Test func roundTripsDistinguishReciprocalRedirectedAndNewReturnPortals() {
        let home = frame(NetherPortal.overworld, x: 800, y: 64, z: 0)
        let paired = frame(NetherPortal.nether, x: 100, y: 64, z: 0)
        #expect(home.roundTrip(into: [paired], returningThrough: [home], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .twoWay(target: paired, block: Block(x: 100, y: 64, z: 0)))

        let offset = frame(NetherPortal.nether, x: 110, y: 64, z: 0)
        let other = frame(NetherPortal.overworld, x: 880, y: 64, z: 0)
        #expect(home.roundTrip(into: [offset], returningThrough: [home, other], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) ==
                .oneWay(target: offset, block: Block(x: 110, y: 64, z: 0), returning: .portal(other, block: Block(x: 880, y: 64, z: 0))))

        let edge = frame(NetherPortal.overworld, x: 7, y: 64, z: 0)
        let negative = frame(NetherPortal.nether, x: -16, y: 64, z: 0)
        #expect(edge.roundTrip(into: [negative], returningThrough: [edge], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) ==
                .oneWay(target: negative, block: Block(x: -15, y: 64, z: 0), returning: .wouldCreateNewPortal(destination: Block(x: -128, y: 64, z: 0))))
    }

    @Test func roundTripsPreserveCreationUnknownDimensionsAndExplicitEntryRules() {
        let home = frame(NetherPortal.overworld, x: 7, y: 64, z: 0)
        let end = frame("minecraft:the_end", x: 0, y: 64, z: 0)
        #expect(home.roundTrip(into: [], returningThrough: [home], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: Block(x: 0, y: 64, z: 0)))
        #expect(home.roundTrip(into: [end], returningThrough: [home], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: Block(x: 0, y: 64, z: 0)))
        #expect(end.roundTrip(into: [home], returningThrough: [], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == nil)

        let far = frame(NetherPortal.nether, x: 17, y: 64, z: 0)
        #expect(home.roundTrip(into: [far], returningThrough: [home], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders) == .wouldCreateNewPortal(destination: Block(x: 0, y: 64, z: 0)))
        #expect(home.roundTrip(into: [far], returningThrough: [home], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders, entering: Block(x: 8, y: 64, z: 0)) ==
                .twoWay(target: far, block: Block(x: 17, y: 64, z: 0)))
        #expect(home.roundTrip(into: [far], returningThrough: [], dimensionTypes: PortalFixtures.types, borders: PortalFixtures.borders, entering: Block(x: 8, y: 64, z: 0)) ==
                .oneWay(target: far, block: Block(x: 17, y: 64, z: 0), returning: .wouldCreateNewPortal(destination: Block(x: 136, y: 64, z: 0))))
    }
}
