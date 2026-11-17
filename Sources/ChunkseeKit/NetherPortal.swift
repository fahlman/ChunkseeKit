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
                    let x = block.x.addingReportingOverflow(dx), y = block.y.addingReportingOverflow(dy)
                    let z = block.z.addingReportingOverflow(dz)
                    guard !x.overflow, !y.overflow, !z.overflow else { continue }
                    let next = Block(x: x.partialValue, y: y.partialValue, z: z.partialValue)
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

    /// The outbound link and whether the destination's default entry leads back to this portal.
    public enum RoundTrip: Sendable, Equatable {
        case twoWay(target: NetherPortal, block: Block)
        /// The return goes to another existing portal or would create a new one.
        case oneWay(target: NetherPortal, block: Block, returning: Link)
        /// The outward link is known, but return dimension or border facts are unavailable.
        case returnUnknown(target: NetherPortal, block: Block)
        /// There is no outbound portal in range, so there is no return link to inspect yet.
        case wouldCreateNewPortal(destination: Block)
    }

    public static let overworld = GeneratedPortalFacts.otherDimension
    public static let nether = GeneratedPortalFacts.specialDimension

    /// Minecraft routes Nether portals to the Overworld, and portals in every other valid
    /// dimension to the Nether. This does not establish that a destination exists in the world.
    public static func targetDimension(from dimension: String) -> String? {
        guard let id = Identifier(dimension) else { return nil }
        return id.description == nether ? overworld : nether
    }

    /// Scales X/Z by source coordinate_scale / target coordinate_scale, clamps against the
    /// destination's saved border, then floors to blocks; Y is unchanged. Missing/invalid facts
    /// stay unavailable. This uses the saved border size, not its future interpolation target.
    public static func destination(of block: Block, from dimension: String,
                                   dimensionTypes: [String: DimensionType], destinationBorder: WorldBorder?) -> Block? {
        guard let source = Identifier(dimension)?.description, let target = targetDimension(from: source),
              let fromScale = dimensionTypes[source]?.coordinateScale,
              let toScale = dimensionTypes[target]?.coordinateScale,
              let bounds = BorderBounds(destinationBorder) else { return nil }
        let scale = fromScale / toScale
        guard let x = bounds.clamped(Double(block.x) * scale, within: bounds.x),
              let z = bounds.clamped(Double(block.z) * scale, within: bounds.z) else { return nil }
        return Block(x: x, y: block.y, z: z)
    }

    /// How far, in blocks along X and Z, the game looks for an existing portal around the
    /// destination. The radii and dimension branch are extracted from PortalForcer's code.
    public static func searchRadius(arrivingIn dimension: String) -> Int {
        Identifier(dimension)?.description == nether
            ? GeneratedPortalFacts.specialSearchRadius : GeneratedPortalFacts.otherSearchRadius
    }

    /// Predicts where this portal leads, entering at `entry` (by default the bottom-center block),
    /// given the portals of the target dimension. The game picks the portal block closest to the
    /// destination by straight-line distance, Y included, within the search square; ties go to
    /// the lower block. This is a prediction: players can enter at any block, and the game only
    /// finds portals whose chunks it can load.
    public func link(into candidates: [NetherPortal], dimensionTypes: [String: DimensionType],
                     borders: [String: WorldBorder], entering entry: Block? = nil) -> Link? {
        guard entry != nil || !blocks.isEmpty, let target = Self.targetDimension(from: dimension),
              let destination = Self.destination(of: entry ?? self.entry, from: dimension,
                  dimensionTypes: dimensionTypes, destinationBorder: borders[target]),
              let bounds = BorderBounds(borders[target]) else { return nil }
        let radius = Self.searchRadius(arrivingIn: target)
        var best: (portal: NetherPortal, block: Block, distance: Double)?
        for portal in candidates where Identifier(portal.dimension)?.description == target {
            for block in portal.blocks {
                guard bounds.contains(block) else { continue }
                // Minecraft's Vec3i.distSqr converts before subtracting and squaring. Saved
                // Int32 heights can overflow an Int square even with X/Z inside the radius.
                let dx = Double(block.x) - Double(destination.x), dy = Double(block.y) - Double(destination.y)
                let dz = Double(block.z) - Double(destination.z)
                guard abs(dx) <= Double(radius), abs(dz) <= Double(radius) else { continue }
                let distance = dx * dx + dy * dy + dz * dz
                if best == nil || distance < best!.distance || (distance == best!.distance && block.y < best!.block.y) {
                    best = (portal, block, distance)
                }
            }
        }
        if let best { return .portal(best.portal, block: best.block) }
        return .wouldCreateNewPortal(destination: destination)
    }

    /// Classifies both legs using `link` and complete portal lists from each
    /// dimension. The outward leg uses `entry` or this portal's default bottom-center entry;
    /// the return uses the target's default entry, not the outward arrival block. As with `link`,
    /// this is a prediction: entering another block or unavailable chunks can change the trip.
    /// Returns nil when the outward facts are unavailable; a known outward link is retained
    /// as returnUnknown when only the return facts are missing. Supply all possible return
    /// destinations: a custom dimension's Nether portal returns through the Overworld.
    public func roundTrip(into candidates: [NetherPortal], returningThrough origins: [NetherPortal],
                          dimensionTypes: [String: DimensionType], borders: [String: WorldBorder],
                          entering entry: Block? = nil) -> RoundTrip? {
        guard let outward = link(into: candidates, dimensionTypes: dimensionTypes, borders: borders, entering: entry) else { return nil }
        switch outward {
        case .wouldCreateNewPortal(let destination):
            return .wouldCreateNewPortal(destination: destination)
        case .portal(let target, let block):
            guard let returning = target.link(into: origins, dimensionTypes: dimensionTypes, borders: borders) else {
                return .returnUnknown(target: target, block: block)
            }
            if case .portal(let back, _) = returning, back == self {
                return .twoWay(target: target, block: block)
            }
            return .oneWay(target: target, block: block, returning: returning)
        }
    }
}

/// WorldBorder's absolute limit, inclusive minimum and exclusive maximum are shared by
/// destination clamping and candidate filtering. Border motion cannot be predicted offline.
private struct BorderBounds {
    let x: (min: Double, max: Double), z: (min: Double, max: Double)

    init?(_ border: WorldBorder?) {
        guard let border, border.centerX.isFinite, border.centerZ.isFinite,
              border.size.isFinite else { return nil }
        let limit = Double(GeneratedPortalFacts.absoluteBorderLimit)
        func bounds(_ center: Double) -> (min: Double, max: Double) {
            (min(max(center - border.size / 2, -limit), limit),
             min(max(center + border.size / 2, -limit), limit))
        }
        x = bounds(border.centerX); z = bounds(border.centerZ)
    }

    func clamped(_ value: Double, within bounds: (min: Double, max: Double)) -> Int? {
        guard value.isFinite else { return nil }
        // Mth.clamp tests the lower edge first. Min(max(...)) differs for saved borders
        // narrower than the inset, including zero/negative sizes accepted by the game codec.
        let clamped = value < bounds.min ? bounds.min : min(value, bounds.max - GeneratedPortalFacts.borderInset)
        return Int(exactly: clamped.rounded(.down))
    }

    func contains(_ block: NetherPortal.Block) -> Bool {
        Double(block.x) >= x.min && Double(block.x) < x.max
            && Double(block.z) >= z.min && Double(block.z) < z.max
    }
}

extension Dimension {
    /// Every Nether portal in this dimension, from its `poi` files.
    /// Missing or empty folders contain no portals. An unavailable listing throws
    /// `CocoaError.Code.fileReadUnknown` with `filePath` naming the folder; region errors propagate.
    public func netherPortals() throws -> [NetherPortal] {
        let listing = readRegionFiles(.pointsOfInterest)
        guard listing.isComplete else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: poiDirectory.path])
        }
        let points = try listing.files.flatMap { try pointsOfInterest(regionX: $0.x, regionZ: $0.z) }
        return NetherPortal.portals(from: points, in: id)
    }
}
