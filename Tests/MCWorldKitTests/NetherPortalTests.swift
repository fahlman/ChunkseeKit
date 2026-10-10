import Foundation
import Testing
@testable import MCWorldKit

@Suite struct NetherPortalTests {
    typealias Block = NetherPortal.Block

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
        #expect(NetherPortal.destination(of: Block(x: -3178, y: 67, z: -544), from: NetherPortal.overworld) == Block(x: -398, y: 67, z: -68))
        #expect(NetherPortal.destination(of: Block(x: -398, y: 67, z: -68), from: NetherPortal.nether) == Block(x: -3184, y: 67, z: -544))
        #expect(NetherPortal.destination(of: Block(x: 0, y: 0, z: 0), from: "minecraft:the_end") == nil)
        #expect(NetherPortal.destination(of: Block(x: 4_000_000, y: 64, z: 0), from: NetherPortal.nether)?.x == 29_999_983)
    }

    @Test func linksToTheClosestPortalInRangeCountingY() {
        let home = frame(NetherPortal.overworld, x: 800, y: 64, z: 0)  // destination (100, 64, 0)
        let near = frame(NetherPortal.nether, x: 110, y: 64, z: 0)     // 10 away horizontally
        let below = frame(NetherPortal.nether, x: 100, y: 30, z: 0)    // straight down, but 34 away in Y
        let outOfRange = frame(NetherPortal.nether, x: 100, y: 64, z: 17)  // z 17 > radius 16
        guard case .portal(let target, let block)? = home.link(into: [below, near, outOfRange]) else {
            Issue.record("expected a link"); return
        }
        #expect(target == near && block == Block(x: 110, y: 64, z: 0))
        // Only the out-of-range one: the game would build a new portal.
        #expect(home.link(into: [outOfRange]) == .wouldCreateNewPortal(destination: Block(x: 100, y: 64, z: 0)))
        // Coming back, the Overworld search is wider (128).
        let far = frame(NetherPortal.overworld, x: 800 + 120, y: 64, z: 0)
        if case .portal(let back, _)? = near.link(into: [far]) { #expect(back == far) } else { Issue.record("expected a link back") }
        // The End has no Nether-portal travel.
        #expect(frame("minecraft:the_end", x: 0, y: 64, z: 0).link(into: [near]) == nil)
    }
}
