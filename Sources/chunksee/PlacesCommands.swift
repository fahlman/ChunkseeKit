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
                switch portal.link(into: candidates) {
                case .portal(let target, _)?:
                    // Does the target lead back here?
                    var note = ""
                    if case .portal(let returns, _)? = target.link(into: back), returns != portal { note = "  (one-way: it leads back to \(describe(returns)))" }
                    print("  \(describe(portal)) -> \(describe(target))\(note)")
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
        for (rx, rz, _) in dim.regionFiles() {
            for creature in (try? dim.creatures(regionX: rx, regionZ: rz)) ?? [] {
                kinds[creature.id, default: 0] += 1
                guard creature.customName != nil || creature.owner != nil else { continue }
                let owner = creature.owner.map { " owned by \($0.uuidString.lowercased())" } ?? ""
                let position = blockPosition(x: creature.x, y: creature.y, z: creature.z)
                    .map { "(\($0.x), \($0.y), \($0.z))" } ?? "unknown position"
                print("\(creature.id)\(creature.customName.map { " \"\($0)\"" } ?? "") at \(position)\(owner)")
            }
        }
        for (kind, count) in kinds.sorted(by: byCount) { print("\(count) \(kind)") }
}
