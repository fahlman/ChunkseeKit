import Foundation

/// Choices that affect a region scan's result. Include these in a consumer's cache key.
public struct RegionScanOptions: Sendable, Hashable {
    /// nil counts every block ID; an empty set skips block counting. Properties are combined by ID.
    public var blockIDs: Set<String>?
    /// nil samples the middle column at its surface; a supplied Y samples that height instead.
    public var biomeSampleY: Int?
    /// The dimension's actual build height, when known. Never infer it from occupied sections.
    public var height: Int?

    public init(blockIDs: Set<String>? = nil, biomeSampleY: Int? = nil, height: Int? = nil) {
        self.blockIDs = blockIDs; self.biomeSampleY = biomeSampleY; self.height = height
    }
}

/// The count and enclosing section-height range of a block ID, without UI categories or labels.
public struct BlockDeposit: Sendable, Equatable {
    public let id: String
    public let count: Int
    public let minY: Int
    public let maxY: Int
}

/// Typed terrain facts for one readable modern chunk. Partial generation retains metadata only.
public struct TerrainChunkFacts: Sendable, Equatable {
    /// Position of the region-file entry, rather than an unchecked coordinate in its payload.
    public let position: ChunkPosition
    public let dataVersion: Int
    public let status: String?
    public let isFullyGenerated: Bool
    public let sampledBiome: String?
    /// Every actually referenced biome, including cave biomes; unused palette names are omitted.
    public let biomes: [String]
    public let blockDeposits: [BlockDeposit]
    /// First-free-block Y at each column (z * 16 + x). Ambiguous or invalid maps are absent.
    public let heightmaps: [String: [Int]]
}

public struct RegionFormatCounts: Sendable, Equatable {
    public internal(set) var readable = 0
    public internal(set) var legacy = 0
    public internal(set) var unreadableTerrain = 0
    public internal(set) var unreadableEntities = 0
    public internal(set) var unreadablePointsOfInterest = 0
}

/// One pass over a region's terrain, entities and POIs, ready for a consumer's transforms/cache.
///
/// Cache by all three file fingerprints, options, interpretationVersion and the consumer's own
/// transform version. This value owns the persistence contract; its newly introduced member
/// types deliberately have no standalone Codable contract. Older model conformances remain
/// source-compatible, but are not independently versioned caches.
public struct RegionFacts: Sendable, Codable {
    /// Bump whenever a reader changes a fact's meaning, even if the serialized shape is unchanged.
    public static let interpretationVersion = 14

    public let dimension: String
    public let region: RegionPosition
    public let options: RegionScanOptions
    public internal(set) var containers: [ItemContainer] = []
    public internal(set) var signs: [Sign] = []
    public internal(set) var spawners: [Spawner] = []
    public internal(set) var structures: [StructureStart] = []
    public internal(set) var creatures: [Creature] = []
    public internal(set) var pointsOfInterest: [PointOfInterest] = []
    public internal(set) var chunks: [TerrainChunkFacts] = []
    /// Declared block IDs in fully generated chunks' saved palettes, including unused entries.
    /// Independent of the block-count filter; this catalog does not prove a block occupies a position.
    public internal(set) var paletteBlockIDs: Set<String> = []
    /// 1,024 local entries, z * 32 + x. Includes legacy Level metadata; unavailable entries are 0.
    public internal(set) var inhabitedTimes = [Int](repeating: 0, count: 1024)
    public internal(set) var formats = RegionFormatCounts()

    init(dimension: String, region: RegionPosition, options: RegionScanOptions) {
        self.dimension = dimension; self.region = region; self.options = options
    }

    public init(from decoder: any Decoder) throws {
        let archive = try Archive(from: decoder)
        guard archive.version == Self.interpretationVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "RegionFacts interpretation version is stale or unsupported"))
        }
        guard archive.inhabitedTimes.count == 1024,
              archive.chunks.allSatisfy({ $0.heightmaps.values.allSatisfy { $0.count == 256 } }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "RegionFacts contains an invalid grid size"))
        }
        self.init(dimension: archive.dimension, region: archive.region,
                  options: .init(blockIDs: archive.blockIDs, biomeSampleY: archive.biomeSampleY, height: archive.height))
        containers = archive.containers; signs = archive.signs; spawners = archive.spawners
        structures = archive.structures.map(\.value); creatures = archive.creatures
        pointsOfInterest = archive.pointsOfInterest; chunks = archive.chunks.map(\.value)
        paletteBlockIDs = archive.paletteBlockIDs
        inhabitedTimes = archive.inhabitedTimes; formats = archive.formats.value
    }

    public func encode(to encoder: any Encoder) throws { try Archive(self).encode(to: encoder) }
}

private struct Archive: Codable {
    var version: Int
    var dimension: String
    var region: RegionPosition
    var blockIDs: Set<String>?
    var biomeSampleY: Int?
    var height: Int?
    var containers: [ItemContainer]
    var signs: [Sign]
    var spawners: [Spawner]
    var structures: [StructureRecord]
    var creatures: [Creature]
    var pointsOfInterest: [PointOfInterest]
    var chunks: [ChunkRecord]
    var paletteBlockIDs: Set<String>
    var inhabitedTimes: [Int]
    var formats: FormatRecord

    init(_ value: RegionFacts) {
        version = RegionFacts.interpretationVersion; dimension = value.dimension; region = value.region
        blockIDs = value.options.blockIDs; biomeSampleY = value.options.biomeSampleY; height = value.options.height
        containers = value.containers; signs = value.signs; spawners = value.spawners
        structures = value.structures.map(StructureRecord.init); creatures = value.creatures
        pointsOfInterest = value.pointsOfInterest; chunks = value.chunks.map(ChunkRecord.init)
        paletteBlockIDs = value.paletteBlockIDs
        inhabitedTimes = value.inhabitedTimes; formats = FormatRecord(value.formats)
    }
}

private struct FormatRecord: Codable {
    var readable: Int, legacy: Int, unreadableTerrain: Int, unreadableEntities: Int, unreadablePointsOfInterest: Int
    init(_ v: RegionFormatCounts) {
        readable = v.readable; legacy = v.legacy; unreadableTerrain = v.unreadableTerrain
        unreadableEntities = v.unreadableEntities; unreadablePointsOfInterest = v.unreadablePointsOfInterest
    }
    var value: RegionFormatCounts {
        RegionFormatCounts(readable: readable, legacy: legacy, unreadableTerrain: unreadableTerrain,
                           unreadableEntities: unreadableEntities, unreadablePointsOfInterest: unreadablePointsOfInterest)
    }
}

private struct DepositRecord: Codable {
    var id: String
    var count: Int, minY: Int, maxY: Int
    init(_ v: BlockDeposit) { id = v.id; count = v.count; minY = v.minY; maxY = v.maxY }
    var value: BlockDeposit { BlockDeposit(id: id, count: count, minY: minY, maxY: maxY) }
}

private struct ChunkRecord: Codable {
    var position: ChunkPosition
    var dataVersion: Int
    var status: String?
    var isFullyGenerated: Bool
    var sampledBiome: String?
    var biomes: [String]
    var blockDeposits: [DepositRecord]
    var heightmaps: [String: [Int]]
    init(_ v: TerrainChunkFacts) {
        position = v.position; dataVersion = v.dataVersion; status = v.status; isFullyGenerated = v.isFullyGenerated
        sampledBiome = v.sampledBiome; biomes = v.biomes; blockDeposits = v.blockDeposits.map(DepositRecord.init)
        heightmaps = v.heightmaps
    }
    var value: TerrainChunkFacts {
        TerrainChunkFacts(position: position, dataVersion: dataVersion, status: status, isFullyGenerated: isFullyGenerated,
                          sampledBiome: sampledBiome, biomes: biomes, blockDeposits: blockDeposits.map(\.value), heightmaps: heightmaps)
    }
}

private struct PieceRecord: Codable {
    var id: String
    var minX: Int, minY: Int, minZ: Int, maxX: Int, maxY: Int, maxZ: Int
    init(_ v: StructureStart.Piece) {
        id = v.id; minX = v.box.minX; minY = v.box.minY; minZ = v.box.minZ
        maxX = v.box.maxX; maxY = v.box.maxY; maxZ = v.box.maxZ
    }
    var value: StructureStart.Piece {
        .init(id: id, box: .init(minX: minX, minY: minY, minZ: minZ, maxX: maxX, maxY: maxY, maxZ: maxZ))
    }
}

private struct StructureRecord: Codable {
    var id: String
    var chunkX: Int, chunkZ: Int
    var pieces: [PieceRecord]
    init(_ v: StructureStart) { id = v.id; chunkX = v.chunkX; chunkZ = v.chunkZ; pieces = v.pieces.map(PieceRecord.init) }
    var value: StructureStart { StructureStart(id: id, chunkX: chunkX, chunkZ: chunkZ, pieces: pieces.map(\.value)) }
}
