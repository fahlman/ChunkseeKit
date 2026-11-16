import Foundation

/// Choices that affect a region scan's result. Include these in a consumer's cache key.
public struct RegionScanOptions: Sendable, Hashable, Encodable {
    /// nil retains every used biome; an empty set retains none. Surface sampling is independent.
    public var biomeIDs: Set<String>?
    /// nil retains every structure piece; an empty set retains only the complete start's bounds.
    public var structurePieceIDs: Set<String>?
    /// nil samples the middle column at its surface; a supplied Y samples that height instead.
    public var biomeSampleY: Int?
    /// The dimension's actual build height, when known. Never infer it from occupied sections.
    public var height: Int?

    public init(biomeIDs: Set<String>? = nil,
                structurePieceIDs: Set<String>? = nil, biomeSampleY: Int? = nil, height: Int? = nil) {
        self.biomeIDs = biomeIDs; self.structurePieceIDs = structurePieceIDs
        self.biomeSampleY = biomeSampleY; self.height = height
    }

    private enum CodingKeys: String, CodingKey { case biomeIDs, structurePieceIDs, biomeSampleY, height }

    /// Sets have no semantic order. Keep their persisted identity stable without requiring
    /// clients to copy option fields. InterpretationKey owns the persisted dictionary ordering.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(biomeIDs?.sorted(), forKey: .biomeIDs)
        try values.encodeIfPresent(structurePieceIDs?.sorted(), forKey: .structurePieceIDs)
        try values.encodeIfPresent(biomeSampleY, forKey: .biomeSampleY)
        try values.encodeIfPresent(height, forKey: .height)
    }
}

/// Compact terrain facts for one fully generated, readable chunk.
public struct TerrainChunkFacts: Sendable, Equatable {
    /// Position of the region-file entry, rather than an unchecked coordinate in its payload.
    public let position: ChunkPosition
    public let sampledBiome: String?
    /// Actually referenced members of the requested biome set; unused palette names are omitted.
    public let biomes: [String]
}

/// A structure's complete bounds and the explicitly requested subset of its pieces.
/// Use StructureStart or Chunk.structureStarts when every raw piece is needed.
public struct StructureFacts: Sendable, Equatable {
    public let id: String
    public let chunkX: Int
    public let chunkZ: Int
    public let bounds: BlockBox?
    public let pieces: [StructureStart.Piece]

    init(_ start: StructureStart, pieceIDs: Set<String>?) {
        id = start.id; chunkX = start.chunkX; chunkZ = start.chunkZ
        // Filtering the raw start first would shrink its bounds to the selected pieces.
        bounds = start.bounds
        pieces = pieceIDs.map { ids in start.pieces.filter { ids.contains($0.id) } } ?? start.pieces
    }

    init(id: String, chunkX: Int, chunkZ: Int, bounds: BlockBox?, pieces: [StructureStart.Piece]) {
        self.id = id; self.chunkX = chunkX; self.chunkZ = chunkZ
        self.bounds = bounds; self.pieces = pieces
    }
}

public struct RegionFormatCounts: Sendable, Equatable {
    public internal(set) var readable = 0
    public internal(set) var legacy = 0
}

/// One pass over a region's terrain, entities and POIs, ready for a consumer's transforms/cache.
///
/// Cache by all three file fingerprints, options, interpretationVersion and the consumer's own
/// transform version. This value owns the persistence contract; its newly introduced member
/// types deliberately have no standalone Codable contract. Older model conformances remain
/// source-compatible, but are not independently versioned caches.
public struct RegionFacts: Sendable, Codable {
    /// Bump the revision whenever a fact reader changes meaning, even with the same serialized
    /// shape. Generated facts and the terrain reader contribute their own identities.
    public static let interpretationVersion = InterpretationVersion(
        domain: "regionFacts", revision: 36, generatedFacts: GeneratedInterpretationDigests.regionFacts,
        dependencies: [Chunk.interpretationVersion])

    public let dimension: String
    public let region: RegionPosition
    public let options: RegionScanOptions
    public internal(set) var containers: [ItemContainer] = []
    public internal(set) var signs: [Sign] = []
    public internal(set) var spawners: [Spawner] = []
    public internal(set) var structures: [StructureFacts] = []
    public internal(set) var creatures: [Creature] = []
    public internal(set) var pointsOfInterest: [PointOfInterest] = []
    public internal(set) var chunks: [TerrainChunkFacts] = []
    /// Declared block IDs in fully generated chunks' saved palettes, including unused entries.
    /// This catalog does not prove a block occupies a position. Counts have their own reader.
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
        guard archive.inhabitedTimes.count == 1024 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "RegionFacts contains an invalid grid size"))
        }
        self.init(dimension: archive.dimension, region: archive.region,
                  options: .init(biomeIDs: archive.biomeIDs.map { Set($0) },
                                 structurePieceIDs: archive.structurePieceIDs.map { Set($0) },
                                 biomeSampleY: archive.biomeSampleY, height: archive.height))
        containers = archive.containers; signs = archive.signs; spawners = archive.spawners
        structures = archive.structures.map(\.value); creatures = archive.creatures
        pointsOfInterest = archive.pointsOfInterest; chunks = archive.chunks.map(\.value)
        paletteBlockIDs = Set(archive.paletteBlockIDs)
        inhabitedTimes = archive.inhabitedTimes; formats = archive.formats.value
    }

    public func encode(to encoder: any Encoder) throws { try Archive(self).encode(to: encoder) }
}

private struct Archive: Codable {
    var version: InterpretationVersion
    var dimension: String
    var region: RegionPosition
    var biomeIDs: [String]?
    var structurePieceIDs: [String]?
    var biomeSampleY: Int?
    var height: Int?
    var containers: [ItemContainer]
    var signs: [Sign]
    var spawners: [Spawner]
    var structures: [StructureRecord]
    var creatures: [Creature]
    var pointsOfInterest: [PointOfInterest]
    var chunks: [ChunkRecord]
    var paletteBlockIDs: [String]
    var inhabitedTimes: [Int]
    var formats: FormatRecord

    init(_ value: RegionFacts) {
        version = RegionFacts.interpretationVersion; dimension = value.dimension; region = value.region
        biomeSampleY = value.options.biomeSampleY; height = value.options.height
        biomeIDs = value.options.biomeIDs?.sorted(); structurePieceIDs = value.options.structurePieceIDs?.sorted()
        containers = value.containers; signs = value.signs; spawners = value.spawners
        structures = value.structures.map(StructureRecord.init); creatures = value.creatures
        pointsOfInterest = value.pointsOfInterest; chunks = value.chunks.map(ChunkRecord.init)
        paletteBlockIDs = value.paletteBlockIDs.sorted()
        inhabitedTimes = value.inhabitedTimes; formats = FormatRecord(value.formats)
    }
}

private struct FormatRecord: Codable {
    var readable: Int, legacy: Int
    init(_ v: RegionFormatCounts) {
        readable = v.readable; legacy = v.legacy
    }
    var value: RegionFormatCounts {
        RegionFormatCounts(readable: readable, legacy: legacy)
    }
}

private struct ChunkRecord: Codable {
    var position: ChunkPosition
    var sampledBiome: String?
    var biomes: [String]
    init(_ v: TerrainChunkFacts) {
        position = v.position
        sampledBiome = v.sampledBiome; biomes = v.biomes
    }
    var value: TerrainChunkFacts {
        TerrainChunkFacts(position: position, sampledBiome: sampledBiome, biomes: biomes)
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
    var bounds: BoxRecord?
    var pieces: [PieceRecord]
    init(_ v: StructureFacts) {
        id = v.id; chunkX = v.chunkX; chunkZ = v.chunkZ
        bounds = v.bounds.map(BoxRecord.init); pieces = v.pieces.map(PieceRecord.init)
    }
    var value: StructureFacts {
        StructureFacts(id: id, chunkX: chunkX, chunkZ: chunkZ, bounds: bounds?.value, pieces: pieces.map(\.value))
    }
}

private struct BoxRecord: Codable {
    var minX: Int, minY: Int, minZ: Int, maxX: Int, maxY: Int, maxZ: Int
    init(_ v: BlockBox) {
        minX = v.minX; minY = v.minY; minZ = v.minZ
        maxX = v.maxX; maxY = v.maxY; maxZ = v.maxZ
    }
    var value: BlockBox {
        BlockBox(minX: minX, minY: minY, minZ: minZ, maxX: maxX, maxY: maxY, maxZ: maxZ)
    }
}
