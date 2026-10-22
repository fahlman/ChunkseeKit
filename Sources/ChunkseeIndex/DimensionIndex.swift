import ChunkseeKit

/// A dimension's retained region contributions and complete aggregates. Reading, scheduling,
/// cancellation, native presentation and publication belong to clients.
public struct DimensionIndex: Sendable {
    public struct Formats: Sendable, Equatable {
        public let readable: Int
        public let legacy: Int
        public var isOnlyLegacy: Bool { legacy > 0 && readable == 0 }

        public init(readable: Int = 0, legacy: Int = 0) {
            self.readable = readable; self.legacy = legacy
        }
    }

    public struct ChunkDeposit: Sendable, Equatable {
        public let chunk: ChunkPosition
        public let deposit: NotableBlock.Deposit

        public init(chunk: ChunkPosition, deposit: NotableBlock.Deposit) {
            self.chunk = chunk; self.deposit = deposit
        }
    }

    public let dimension: String
    public let caveBiomeIDs: Set<String>
    public private(set) var regions: [RegionPosition: RegionIndex] = [:]
    public private(set) var containers: [ItemContainer] = []
    public private(set) var storage: [StoredItemTotal] = []
    public private(set) var signs: [Sign] = []
    public private(set) var spawners: [Spawner] = []
    public private(set) var structures: [StructureStart] = []
    public private(set) var creatures: [CreatureEntry] = []
    public private(set) var pointsOfInterest: [PointOfInterest] = []
    public private(set) var portals: [NetherPortal] = []
    public private(set) var biomes: [ChunkPosition: String] = [:]
    public private(set) var caveBiomes: [ChunkPosition: [String]] = [:]
    public private(set) var biomeAreas: [BiomeArea] = []
    /// Richest chunks first. Equal counts have no specified order.
    public private(set) var blocks: [ChunkDeposit] = []
    public private(set) var formats = Formats()

    public init(dimension: String, caveBiomeIDs: Set<String>) {
        self.dimension = dimension; self.caveBiomeIDs = caveBiomeIDs
    }

    /// Reconciles a completed read without changing this snapshot. A nil selection is a full
    /// pass; a subset leaves unselected contributions untouched, even if absent from `available`.
    /// A missing replacement for an available region means its read failed, so its old value stays.
    /// A selected region absent from `available` is deleted. Successful empty replacements clear it.
    /// Only available, selected replacements with this dimension and cave policy are accepted;
    /// repeated replacements for one coordinate use the last value. Cancellation must be handled
    /// by the caller before it publishes the returned snapshot.
    public func updating(available: Set<RegionPosition>, selected: Set<RegionPosition>?,
                         replacements: [RegionIndex]) -> Self {
        var next = Self(dimension: dimension, caveBiomeIDs: caveBiomeIDs)
        next.regions = regions.filter { coordinate, _ in
            if let selected, !selected.contains(coordinate) { return true }
            return available.contains(coordinate)
        }
        let changed = selected.map { $0.intersection(available) } ?? available
        for region in replacements where changed.contains(region.region) && region.dimension == dimension
            && region.caveBiomeIDs == caveBiomeIDs {
            next.regions[region.region] = region
        }
        for coordinate in next.regions.keys.sorted(by: { ($0.x, $0.z) < ($1.x, $1.z) }) {
            let region = next.regions[coordinate]!
            next.containers += region.containers
            next.signs += region.signs
            next.spawners += region.spawners
            next.structures += region.structures
            next.creatures += region.creatures
            next.pointsOfInterest += region.pointsOfInterest
            next.biomes.merge(region.biomes) { $1 }
            next.caveBiomes.merge(region.caveBiomes) { $1 }
            next.blocks += region.blocks.flatMap { chunk, deposits in deposits.map { ChunkDeposit(chunk: chunk, deposit: $0) } }
            next.formats = Formats(readable: next.formats.readable + region.formats.readable,
                                   legacy: next.formats.legacy + region.formats.legacy)
        }
        next.storage = StoredItemTotal.totals(in: next.containers)
        next.portals = NetherPortal.portals(from: next.pointsOfInterest, in: dimension)
        next.biomeAreas = BiomeArea.connected(in: next.biomes.filter { !caveBiomeIDs.contains($0.value) })
            + caveBiomeIDs.sorted().flatMap { biome in
                BiomeArea.connected(in: next.caveBiomes.filter { $0.value.contains(biome) }.mapValues { _ in biome })
            }
        next.blocks.sort { $0.deposit.count > $1.deposit.count }
        return next
    }
}
