import ChunkseeKit

/// An immutable point snapshot with coarse region lookup, preserving the input order.
public struct PointIndex<Element: Sendable>: Sendable {
    public let elements: [Element]
    private let buckets: [RegionPosition: [Int]]
    private let unbucketed: [Int]

    /// Positions are exact world X/Z coordinates. Missing or unbucketable positions remain in
    /// every candidate result so a client's final bounds or hit-distance check decides their fate.
    /// Build a new snapshot when positions change; the position closure is used only here.
    public init(_ elements: [Element], position: (Element) -> (x: Double, z: Double)?) {
        self.elements = elements
        var buckets: [RegionPosition: [Int]] = [:], unbucketed: [Int] = []
        for (index, element) in elements.enumerated() {
            if let point = position(element), let x = Self.coordinate(point.x), let z = Self.coordinate(point.z) {
                buckets[RegionPosition(x: x, z: z), default: []].append(index)
            } else { unbucketed.append(index) }
        }
        self.buckets = buckets
        self.unbucketed = unbucketed
    }

    /// Broad candidates from all regions touched by these inclusive world bounds, plus entries
    /// without a bucket. This is not an exact rectangle filter. Unusable bucket bounds return all
    /// elements; clients retain their precise geometry, visibility and hit-priority rules.
    public func candidates(minX: Double, maxX: Double, minZ: Double, maxZ: Double) -> [Element] {
        guard !elements.isEmpty else { return [] }
        guard let minX = Self.coordinate(minX), let maxX = Self.coordinate(maxX),
              let minZ = Self.coordinate(minZ), let maxZ = Self.coordinate(maxZ),
              minX <= maxX, minZ <= maxZ else { return elements }
        var indices = unbucketed
        // Large sparse views must not enumerate enormous stretches of empty regions. Small
        // views use direct lookups without scanning every occupied bucket.
        let cells = (Double(maxX) - Double(minX) + 1) * (Double(maxZ) - Double(minZ) + 1)
        if cells <= Double(buckets.count) {
            for x in minX...maxX { for z in minZ...maxZ {
                indices += buckets[RegionPosition(x: x, z: z)] ?? []
            } }
        } else {
            for (region, members) in buckets where (minX...maxX).contains(region.x) && (minZ...maxZ).contains(region.z) {
                indices += members
            }
        }
        return indices.sorted().map { elements[$0] }
    }

    private static func coordinate(_ value: Double) -> Int? {
        BlockPosition.coordinate(containing: value / Double(RegionPosition.sideInBlocks))
    }
}
