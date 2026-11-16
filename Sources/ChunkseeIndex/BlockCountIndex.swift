import ChunkseeKit
import Foundation

/// The captured horizontal point for a dimension's block search. The client owns the player
/// identity or fixed map-center lifetime; this immutable value owns distance/ring calculations.
public struct BlockSearchOrigin: Sendable, Hashable {
    public let x: Double
    public let z: Double

    public init?(x: Double, z: Double) {
        guard x.isFinite, z.isFinite else { return nil }
        self.x = x; self.z = z
    }

    fileprivate func distance(to chunk: ChunkPosition) -> Double {
        hypot(Double(chunk.x) * 16 + 8 - x, Double(chunk.z) * 16 + 8 - z)
    }

    fileprivate func ring(of region: RegionPosition) -> Double {
        max(abs(Double(region.x) - floor(x / Double(RegionPosition.sideInBlocks))),
            abs(Double(region.z) - floor(z / Double(RegionPosition.sideInBlocks))))
    }
}

/// Independently published raw terrain counts. Catalogs and origins are query inputs, never
/// retained scan identities. File stamps, scheduling, shared tasks and cancellation are client-owned.
public struct BlockCountIndex: Sendable {
    public enum Coverage: Sendable, Equatable { case unsearched, complete, failed }

    public struct Region: Sendable {
        /// Last good counts survive a failed/replaced read, without claiming current coverage.
        public let counts: RegionBlockCounts?
        public let lastAttempt: Coverage
    }

    public struct ChunkDeposit: Sendable, Equatable {
        public let chunk: ChunkPosition
        public let deposit: NotableBlock.Deposit

        public init(chunk: ChunkPosition, deposit: NotableBlock.Deposit) {
            self.chunk = chunk; self.deposit = deposit
        }
    }

    /// A match is one chunk/group row, including distinct groups in the same chunk.
    /// The full total and the limited nearest rows come from the same retained counts.
    public struct DepositMatches: Sendable, Equatable {
        public let totalCount: Int
        public let nearest: [ChunkDeposit]
    }

    public let dimension: String
    public private(set) var regions: [RegionPosition: Region] = [:]

    public init(dimension: String) { self.dimension = dimension }

    public func coverage(of region: RegionPosition, matching blockIDs: Set<String>) -> Coverage {
        guard !blockIDs.isEmpty else { return .complete }
        guard let entry = regions[region] else { return .unsearched }
        if entry.lastAttempt != .complete { return entry.lastAttempt }
        return entry.counts.map { blockIDs.isSubset(of: $0.blockIDs) } == true ? .complete : .unsearched
    }

    /// Clear coverage when the client's existing file-stamp owner detects changed terrain.
    /// Counts stay visible until replacement. Regrouping tags and entity/POI edits do not call this.
    public func invalidating(_ positions: Set<RegionPosition>) -> Self {
        var next = self
        for position in positions {
            next.regions[position] = Region(counts: regions[position]?.counts, lastAttempt: .unsearched)
        }
        return next
    }

    /// Publish completed reads and explicit failures, removing regions no longer available.
    /// A valid successful replacement wins over a simultaneous failure for the same coordinate.
    /// The caller rejects obsolete file stamps/task lifetimes before calling this method.
    public func updating(available: Set<RegionPosition>, replacements: [RegionBlockCounts],
                         failed: Set<RegionPosition> = []) -> Self {
        var next = self
        next.regions = regions.filter { available.contains($0.key) }
        var accepted = Set<RegionPosition>()
        for counts in replacements where counts.dimension == dimension && available.contains(counts.region) {
            next.regions[counts.region] = Region(counts: counts, lastAttempt: .complete)
            accepted.insert(counts.region)
        }
        for position in failed.intersection(available).subtracting(accepted) {
            next.regions[position] = Region(counts: next.regions[position]?.counts, lastAttempt: .failed)
        }
        return next
    }

    /// Only occupied regions need work. A failed attempt waits for a source change or explicit
    /// retry (invalidating), rather than becoming an endless "searching" state.
    public func regionsToRead(available: Set<RegionPosition>, matching blockIDs: Set<String>,
                              from origin: BlockSearchOrigin) -> [RegionPosition] {
        available.filter { coverage(of: $0, matching: blockIDs) == .unsearched }.sorted {
            let a = origin.ring(of: $0), b = origin.ring(of: $1)
            return a == b ? ($0.x, $0.z) < ($1.x, $1.z) : a < b
        }
    }

    /// Group all retained per-ID counts for this query, rank by distance from chunk centers,
    /// then apply the caller's limit. Equal distances use chunk X/Z and group identity; richness
    /// never displaces a nearer match. Different windows can query this same snapshot independently.
    public func nearestDeposits(matching groups: Set<NotableBlock>, using catalog: NotableBlock.Catalog,
                                from origin: BlockSearchOrigin, limit: Int) -> [ChunkDeposit] {
        guard limit > 0 else { return [] }
        return matchingDeposits(matching: groups, using: catalog, from: origin, limit: limit).nearest
    }

    /// Counts every matching row before limiting nearest membership. A nonpositive limit
    /// requests only the total; unsearched regions are not counted as zero-match results.
    public func matchingDeposits(matching groups: Set<NotableBlock>, using catalog: NotableBlock.Catalog,
                                 from origin: BlockSearchOrigin, limit: Int) -> DepositMatches {
        guard !groups.isEmpty else { return DepositMatches(totalCount: 0, nearest: []) }
        var found: [ChunkDeposit] = []
        for entry in regions.values {
            guard let counts = entry.counts else { continue }
            for (chunk, values) in counts.chunks {
                for deposit in NotableBlock.Deposit.grouped(values, using: catalog) where groups.contains(deposit.block) {
                    found.append(.init(chunk: chunk, deposit: deposit))
                }
            }
        }
        return DepositMatches(totalCount: found.count, nearest: Self.nearest(found, from: origin, limit: limit))
    }

    private static func nearest(_ values: [ChunkDeposit], from origin: BlockSearchOrigin, limit: Int) -> [ChunkDeposit] {
        guard limit > 0 else { return [] }
        let ranked = values.map { (value: $0, distance: origin.distance(to: $0.chunk)) }.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return ($0.value.chunk.x, $0.value.chunk.z, $0.value.deposit.block.id)
                < ($1.value.chunk.x, $1.value.chunk.z, $1.value.deposit.block.id)
        }
        return ranked.prefix(limit).map(\.value)
    }
}
