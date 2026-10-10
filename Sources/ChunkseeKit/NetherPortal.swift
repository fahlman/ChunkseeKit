import Foundation

/// A Nether portal: the touching portal blocks recorded as `minecraft:nether_portal` points of
/// interest, grouped into one frame.
public struct NetherPortal: Sendable, Equatable {
    public struct Block: Hashable, Sendable, Comparable {
        public var x: Int, y: Int, z: Int

        public init(x: Int, y: Int, z: Int) {
            self.x = x; self.y = y; self.z = z
        }

        public static func < (a: Block, b: Block) -> Bool { (a.y, a.x, a.z) < (b.y, b.x, b.z) }
    }

    /// The portal's dimension, e.g. `minecraft:the_nether`.
    public var dimension: String
    /// Portal blocks, sorted bottom row first.
    public var blocks: [Block]

    public init(dimension: String, blocks: [Block]) {
        self.dimension = dimension
        self.blocks = blocks.sorted()
    }

    public var centerX: Double { blocks.map { Double($0.x) + 0.5 }.reduce(0, +) / Double(blocks.count) }
    public var centerZ: Double { blocks.map { Double($0.z) + 0.5 }.reduce(0, +) / Double(blocks.count) }
    public var minY: Int { blocks.first?.y ?? 0 }

    /// Where a player usually enters: the bottom-row block nearest the portal's center.
    public var entry: Block {
        let bottom = blocks.filter { $0.y == minY }
        return bottom.min {
            hypot(Double($0.x) + 0.5 - centerX, Double($0.z) + 0.5 - centerZ)
                < hypot(Double($1.x) + 0.5 - centerX, Double($1.z) + 0.5 - centerZ)
        } ?? blocks[0]
    }

    public func contains(_ block: Block) -> Bool { blocks.contains(block) }

    /// Groups a dimension's `minecraft:nether_portal` points of interest into portals: blocks that
    /// share a face belong to the same portal. Other point-of-interest types are ignored.
    public static func portals(from points: [PointOfInterest], in dimension: String) -> [NetherPortal] {
        var unvisited = Set(points.filter { $0.type == "minecraft:nether_portal" }.map { Block(x: $0.x, y: $0.y, z: $0.z) })
        var portals: [NetherPortal] = []
        while let seed = unvisited.min() {
            unvisited.remove(seed)
            var stack = [seed], members: [Block] = []
            while let block = stack.popLast() {
                members.append(block)
                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let next = Block(x: block.x + dx, y: block.y + dy, z: block.z + dz)
                    if unvisited.remove(next) != nil { stack.append(next) }
                }
            }
            portals.append(NetherPortal(dimension: dimension, blocks: members))
        }
        return portals.sorted { $0.blocks[0] < $1.blocks[0] }
    }

    // MARK: Linking

    /// Where a portal in one dimension leads.
    public enum Link: Sendable, Equatable {
        /// To an existing portal, arriving at `block`.
        case portal(NetherPortal, block: Block)
        /// No portal is in range, so the game would build a new one near `destination`.
        case wouldCreateNewPortal(destination: Block)
    }

    public static let overworld = "minecraft:overworld"
    public static let nether = "minecraft:the_nether"

    /// The other dimension a portal leads to, or `nil` for dimensions without Nether portal travel.
    public static func targetDimension(from dimension: String) -> String? {
        switch dimension {
        case overworld: nether
        case nether: overworld
        default: nil
        }
    }

    /// The matching coordinates in the target dimension: X and Z ÷ 8 (rounded down) into the
    /// Nether, × 8 into the Overworld, kept inside the world border; Y unchanged.
    public static func destination(of block: Block, from dimension: String) -> Block? {
        func clamp(_ v: Int) -> Int { min(max(v, -29_999_984), 29_999_983) }
        switch dimension {
        case overworld:
            return Block(x: clamp(Int((Double(block.x) / 8).rounded(.down))), y: block.y,
                         z: clamp(Int((Double(block.z) / 8).rounded(.down))))
        case nether:
            return Block(x: clamp(block.x * 8), y: block.y, z: clamp(block.z * 8))
        default:
            return nil
        }
    }

    /// How far, in blocks along X and Z, the game looks for an existing portal around the
    /// destination: 128 arriving in the Overworld, 16 arriving in the Nether (since 1.16.2).
    public static func searchRadius(arrivingIn dimension: String) -> Int {
        dimension == nether ? 16 : 128
    }

    /// Predicts where this portal leads, entering at `entry` (by default the bottom-center block),
    /// given the portals of the target dimension. The game picks the portal block closest to the
    /// destination by straight-line distance, Y included, within the search square; ties go to
    /// the lower block. This is a prediction: players can enter at any block, and the game only
    /// finds portals whose chunks it can load.
    public func link(into candidates: [NetherPortal], entering entry: Block? = nil) -> Link? {
        guard let target = Self.targetDimension(from: dimension),
              let destination = Self.destination(of: entry ?? self.entry, from: dimension) else { return nil }
        let radius = Self.searchRadius(arrivingIn: target)
        var best: (portal: NetherPortal, block: Block, distance: Int)?
        for portal in candidates where portal.dimension == target {
            for block in portal.blocks
            where abs(block.x - destination.x) <= radius && abs(block.z - destination.z) <= radius {
                let dx = block.x - destination.x, dy = block.y - destination.y, dz = block.z - destination.z
                let distance = dx * dx + dy * dy + dz * dz
                if best == nil || distance < best!.distance || (distance == best!.distance && block.y < best!.block.y) {
                    best = (portal, block, distance)
                }
            }
        }
        if let best { return .portal(best.portal, block: best.block) }
        return .wouldCreateNewPortal(destination: destination)
    }
}

extension Dimension {
    /// Every Nether portal in this dimension, from its `poi` files.
    public func netherPortals() throws -> [NetherPortal] {
        let points = try regionFiles(.pointsOfInterest).flatMap { try pointsOfInterest(regionX: $0.x, regionZ: $0.z) }
        return NetherPortal.portals(from: points, in: id)
    }
}
