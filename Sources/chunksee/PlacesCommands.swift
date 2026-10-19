import Foundation
import ChunkseeKit

/// Commands about points of interest, portals and creatures.

func poiCommand(_ world: World, _ arguments: Arguments) {
        let dims = arguments.dimensions(1, in: world)
        for dim in dims {
            var byType: [String: [PointOfInterest]] = [:]
            for (x, z, _) in dim.regionFiles(.pointsOfInterest) {
                for poi in (try? dim.pointsOfInterest(regionX: x, regionZ: z)) ?? [] { byType[poi.type, default: []].append(poi) }
            }
            print("\(dim.id): \(byType.values.reduce(0) { $0 + $1.count }) points of interest")
            for (type, list) in byType.sorted(by: { byCount(($0.key, $0.value.count), ($1.key, $1.value.count)) }) {
                let places = list.prefix(3).map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: " ")
                print("  \(list.count)\t\(type)  \(places)\(list.count > 3 ? " …" : "")")
            }
        }
}

func portalsCommand(_ world: World, _ arguments: Arguments) throws {
        guard let overworld = world.dimension("overworld"), let nether = world.dimension("the_nether") else {
            fail("this world needs both an Overworld and a Nether")
        }
        let overworldPortals = try overworld.netherPortals(), netherPortals = try nether.netherPortals()
        func describe(_ p: NetherPortal) -> String { "(\(Int(p.centerX.rounded(.down))), \(p.minY), \(Int(p.centerZ.rounded(.down))))" }
        func show(_ portals: [NetherPortal], _ candidates: [NetherPortal], back: [NetherPortal], label: String) {
            print("\(label): \(portals.count) portals")
            for portal in portals {
                switch portal.roundTrip(into: candidates, returningThrough: back) {
                case .twoWay(let target, _)?:
                    print("  \(describe(portal)) -> \(describe(target))")
                case .oneWay(let target, _, let returning)?:
                    let note: String
                    switch returning {
                    case .portal(let returns, _):
                        note = "it leads back to \(describe(returns))"
                    case .wouldCreateNewPortal(let destination):
                        note = "the return trip would create one near (\(destination.x), \(destination.y), \(destination.z))"
                    }
                    print("  \(describe(portal)) -> \(describe(target))  (one-way: \(note))")
                case .wouldCreateNewPortal(let destination)?:
                    print("  \(describe(portal)) -> no portal in range; would create one near (\(destination.x), \(destination.y), \(destination.z))")
                case nil:
                    print("  \(describe(portal)) -> ?")
                }
            }
        }
        show(overworldPortals, netherPortals, back: overworldPortals, label: "Overworld")
        show(netherPortals, overworldPortals, back: netherPortals, label: "Nether")
}

func creaturesCommand(_ world: World, _ arguments: Arguments) {
        let dim = arguments.dimension(1, in: world)
        var kinds: [String: Int] = [:]
        func show(_ creature: Creature, at block: BlockPosition?, carrier: UUID?) {
            kinds[creature.id, default: 0] += 1
            guard carrier != nil || creature.customName != nil || creature.owner != nil else { return }
            let owner = creature.owner.map { " owned by \($0.uuidString.lowercased())" } ?? ""
            let position = block.map { "(\($0.x), \($0.y), \($0.z))" } ?? "unknown position"
            let shoulder = carrier.map { " on shoulder of \($0.uuidString.lowercased())" } ?? ""
            print("\(creature.id)\(creature.customName.map { " \"\($0)\"" } ?? "") at \(position)\(owner)\(shoulder)")
        }
        for (rx, rz, _) in dim.regionFiles(.entities) {
            for creature in (try? dim.creatures(regionX: rx, regionZ: rz)) ?? [] {
                show(creature, at: BlockPosition(x: creature.x, y: creature.y, z: creature.z), carrier: nil)
            }
        }
        for player in world.players() where !player.isFromBukkitServer {
            guard let location = player.position, location.dimension == dim.id else { continue }
            for creature in player.shoulderPets {
                // A shoulder entity's own saved coordinates predate mounting.
                show(creature, at: location.blockPosition, carrier: player.uuid)
            }
        }
        for (kind, count) in kinds.sorted(by: byCount) { print("\(count) \(kind)") }
}
