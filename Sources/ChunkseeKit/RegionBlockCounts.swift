import Foundation

/// The count and enclosing section-height range of a block ID, without UI categories or labels.
public struct BlockDeposit: Sendable, Equatable {
    public let id: String
    public let count: Int
    public let minY: Int
    public let maxY: Int
}

/// A completed terrain-only count of readable, supported chunks. Empty and unreadable chunks
/// are omitted; blockIDs records the requested IDs, including those absent from readable chunks.
/// Grouping is a later index operation.
/// Cache with the terrain file's fingerprint, this interpretation and the requested ID coverage.
/// Entity/POI files, ore tags and search origins do not contribute to these raw counts.
public struct RegionBlockCounts: Sendable, Codable, Equatable {
    public static let interpretationVersion = InterpretationVersion(
        domain: "blockCounts", revision: 1, generatedFacts: "", dependencies: [Chunk.interpretationVersion])

    public let dimension: String
    public let region: RegionPosition
    public let blockIDs: Set<String>
    public let chunks: [ChunkPosition: [BlockDeposit]]

    init(dimension: String, region: RegionPosition, blockIDs: Set<String>, chunks: [ChunkPosition: [BlockDeposit]]) {
        self.dimension = dimension; self.region = region; self.blockIDs = blockIDs; self.chunks = chunks
    }

    public init(from decoder: any Decoder) throws {
        let archive = try Archive(from: decoder)
        guard archive.version == Self.interpretationVersion, archive.region.chunkOrigin != nil,
              archive.chunks.count <= 1024 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "RegionBlockCounts interpretation or region is invalid"))
        }
        let ids = Set(archive.blockIDs)
        var chunks: [ChunkPosition: [BlockDeposit]] = [:]
        for row in archive.chunks {
            guard row.position.region == archive.region, chunks[row.position] == nil,
                  !row.deposits.isEmpty, Set(row.deposits.map(\.id)).count == row.deposits.count,
                  row.deposits.allSatisfy({ ids.contains($0.id) && $0.count > 0 && $0.minY <= $0.maxY }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "RegionBlockCounts contains invalid chunk counts"))
            }
            chunks[row.position] = row.deposits.map(\.value)
        }
        self.init(dimension: archive.dimension, region: archive.region, blockIDs: ids, chunks: chunks)
    }

    public func encode(to encoder: any Encoder) throws { try Archive(self).encode(to: encoder) }
}

extension Dimension {
    /// Reads only terrain block palettes. Missing terrain is successfully empty; damaged or
    /// unsupported individual chunks are skipped, as in scan(region:options:). Opening errors
    /// and cancellation throw, so interrupted reads cannot enter a warm cache.
    /// Fully generated chunks use the same normalized palettes and section counter as before.
    public func countBlocks(region position: RegionPosition, matching blockIDs: Set<String>) throws -> RegionBlockCounts {
        try Task.checkCancellation()
        guard let origin = position.chunkOrigin else { throw RegionScanError.invalidRegion(position) }
        var chunks: [ChunkPosition: [BlockDeposit]] = [:]
        if !blockIDs.isEmpty {
            let omitted = Chunk.keysNotNeededForTerrain.union(["Structures", "Heightmaps", "biomes", "Biomes"])
            try visitRegionChunks(.terrain, at: position, skipping: omitted) { x, z, nbt in
                guard case .readable(let chunk) = try RegionTerrainChunk(TerrainChunkInput(nbt)),
                      chunk.isFullyGenerated else { return }
                let deposits = try chunk.blockDeposits(matching: blockIDs)
                if !deposits.isEmpty { chunks[.init(x: origin.x + x, z: origin.z + z)] = deposits }
            }
        }
        try Task.checkCancellation()
        return .init(dimension: id, region: position, blockIDs: blockIDs, chunks: chunks)
    }
}

extension Chunk {
    /// The section/palette counter formerly used by RegionScan. Properties combine by block ID;
    /// the bounds describe containing sections, not the exact occupied blocks' heights.
    func blockDeposits(matching ids: Set<String>) throws -> [BlockDeposit] {
        var deposits: [String: BlockDeposit] = [:]
        for section in sections {
            try Task.checkCancellation()
            guard let blocks = section.blockStates else { continue }
            let wanted = blocks.palette.indices.filter { ids.contains(blocks.palette[$0].id) }
            guard !wanted.isEmpty else { continue }
            let bottom = section.y.multipliedReportingOverflow(by: 16)
            let top = bottom.partialValue.addingReportingOverflow(15)
            guard !bottom.overflow, !top.overflow else { continue }
            let counts = blocks.paletteCounts()
            for index in wanted where counts[index] > 0 {
                let id = blocks.palette[index].id, previous = deposits[id]
                deposits[id] = BlockDeposit(id: id, count: (previous?.count ?? 0) + counts[index],
                    minY: min(previous?.minY ?? bottom.partialValue, bottom.partialValue),
                    maxY: max(previous?.maxY ?? top.partialValue, top.partialValue))
            }
        }
        return deposits.values.sorted { $0.id < $1.id }
    }
}

private struct Archive: Codable {
    let version: InterpretationVersion
    let dimension: String
    let region: RegionPosition
    let blockIDs: [String]
    let chunks: [ChunkRecord]

    init(_ counts: RegionBlockCounts) {
        version = RegionBlockCounts.interpretationVersion
        dimension = counts.dimension; region = counts.region; blockIDs = counts.blockIDs.sorted()
        chunks = counts.chunks.keys.sorted { ($0.x, $0.z) < ($1.x, $1.z) }.map {
            ChunkRecord(position: $0, deposits: counts.chunks[$0]!.sorted { $0.id < $1.id }.map(DepositRecord.init))
        }
    }
}

private struct ChunkRecord: Codable {
    let position: ChunkPosition
    let deposits: [DepositRecord]
}

private struct DepositRecord: Codable {
    let id: String
    let count: Int, minY: Int, maxY: Int
    init(_ v: BlockDeposit) { id = v.id; count = v.count; minY = v.minY; maxY = v.maxY }
    var value: BlockDeposit { .init(id: id, count: count, minY: minY, maxY: maxY) }
}
