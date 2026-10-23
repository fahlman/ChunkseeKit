import ChunkseeKit

/// Compact retained inputs for one region. Large heightmaps, inhabited-time grids, chunk NBT
/// and unnamed ordinary creatures are not retained. This is an in-memory index, not a cache format.
public struct RegionIndex: Sendable {
    public let dimension: String
    public let region: RegionPosition
    public let containers: [ItemContainer]
    public let signs: [Sign]
    public let spawners: [Spawner]
    public let structures: [StructureStart]
    public let creatures: [CreatureEntry]
    public let pointsOfInterest: [PointOfInterest]
    public let biomes: [ChunkPosition: String]
    public let caveBiomes: [ChunkPosition: [String]]
    public let blocks: [ChunkPosition: [NotableBlock.Deposit]]
    /// Saved palette names, including unused entries and IDs outside notable-block search groups.
    public let paletteBlockIDs: Set<String>
    public let formats: DimensionIndex.Formats
    let caveBiomeIDs: Set<String>

    /// Cave membership is an explicit client policy. The dimension index must use the same set.
    public init(_ facts: RegionFacts, caveBiomeIDs: Set<String>) {
        dimension = facts.dimension; region = facts.region
        containers = facts.containers; signs = facts.signs; spawners = facts.spawners
        structures = facts.structures; creatures = facts.creatures.compactMap(CreatureEntry.init)
        pointsOfInterest = facts.pointsOfInterest
        self.caveBiomeIDs = caveBiomeIDs
        paletteBlockIDs = facts.paletteBlockIDs
        biomes = Dictionary(uniqueKeysWithValues: facts.chunks.compactMap { chunk in
            chunk.sampledBiome.map { (chunk.position, $0) }
        })
        caveBiomes = Dictionary(uniqueKeysWithValues: facts.chunks.compactMap { chunk in
            let caves = chunk.biomes.filter { caveBiomeIDs.contains($0) }
            return caves.isEmpty ? nil : (chunk.position, caves)
        })
        blocks = Dictionary(uniqueKeysWithValues: facts.chunks.compactMap { chunk in
            let deposits = NotableBlock.Deposit.grouped(chunk.blockDeposits)
            return deposits.isEmpty ? nil : (chunk.position, deposits)
        })
        formats = DimensionIndex.Formats(readable: facts.formats.readable, legacy: facts.formats.legacy)
    }
}
