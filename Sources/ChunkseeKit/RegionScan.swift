import Foundation

public enum RegionScanError: Error, Equatable {
    case invalidRegion(RegionPosition)
    case invalidHeight(Int)
}

extension Dimension {
    /// Decodes each present terrain/entity/POI chunk once. Missing files are empty; unreadable
    /// individual chunks are skipped. Opening errors and cancellation throw, so a
    /// failed/partial scan can never be mistaken for a completed cache entry.
    public func scan(region position: RegionPosition, options: RegionScanOptions = .init()) throws -> RegionFacts {
        try Task.checkCancellation()
        guard let origin = position.chunkOrigin else { throw RegionScanError.invalidRegion(position) }
        if let height = options.height, Chunk.heightmapBitWidth(for: height) == nil { throw RegionScanError.invalidHeight(height) }
        var facts = RegionFacts(dimension: id, region: position, options: options)
        let omitted = Chunk.keysNotNeededForTerrain.subtracting([
            "block_entities", "structures", "entities", "TileEntities", "Structures", "Entities",
        ])

        func visit(_ folder: Folder, skipping: Set<String> = [],
                   body: (Int, Int, NBT) throws -> Void) throws {
            try Task.checkCancellation()
            guard let file = try region(folder, x: position.x, z: position.z) else { return }
            for (x, z) in file.chunkCoordinates {
                try Task.checkCancellation()
                guard let nbt = try? file.chunkNBT(localX: x, localZ: z, skipping: skipping) else { continue }
                try body(x, z, nbt)
            }
        }

        try visit(.terrain, skipping: omitted) { x, z, nbt in
            let input = NormalizedChunk(nbt)
            facts.containers += ItemContainer.containers(in: input.records)
            facts.signs += Sign.signs(in: input.records)
            facts.spawners += Spawner.spawners(in: input.records)
            facts.creatures += Creature.creatures(in: input.records.entities)
            facts.inhabitedTimes[z * 32 + x] = input.records.inhabitedTime ?? 0
            let chunk: Chunk
            do { chunk = try Chunk(input: input.terrain) }
            catch ChunkError.unsupportedLegacyFormat { facts.formats.legacy += 1; return }
            catch { return }
            facts.formats.readable += 1
            guard chunk.isFullyGenerated else { return }
            facts.structures += chunk.structureStarts.map { StructureFacts($0, pieceIDs: options.structurePieceIDs) }
            let terrain = try TerrainChunkFacts(chunk, at: .init(x: origin.x + x, z: origin.z + z),
                                               options: options, paletteBlockIDs: &facts.paletteBlockIDs)
            facts.chunks.append(terrain)
        }
        try visit(.entities) { _, _, nbt in
            let entities = NormalizedEntities(nbt)
            facts.containers += ItemContainer.containers(in: entities)
            facts.creatures += Creature.creatures(in: entities)
        }
        try visit(.pointsOfInterest) { _, _, nbt in
            facts.pointsOfInterest += PointOfInterest.records(inChunk: nbt)
        }
        try Task.checkCancellation()
        return facts
    }
}

extension TerrainChunkFacts {
    init(_ chunk: Chunk, at position: ChunkPosition, options: RegionScanOptions,
         paletteBlockIDs: inout Set<String>) throws {
        var usedBiomes = Set<String>()
        var deposits: [String: BlockDeposit] = [:]
        for section in chunk.sections {
            try Task.checkCancellation()
            if options.biomeIDs?.isEmpty != true, let biomes = section.biomes {
                for (index, count) in biomes.paletteCounts().enumerated() where count > 0 {
                    let id = biomes.palette[index]
                    if options.biomeIDs?.contains(id) ?? true { usedBiomes.insert(id) }
                }
            }
            guard let blocks = section.blockStates else { continue }
            for state in blocks.palette { paletteBlockIDs.insert(state.id) }
            let wanted = blocks.palette.indices.filter { options.blockIDs?.contains(blocks.palette[$0].id) ?? true }
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
        // The surface query reads only WORLD_SURFACE, using the same actual-height and
        // malformed-map fallback as the raw chunk API. No heightmap is retained in the facts.
        let sampleY = options.biomeSampleY ?? chunk.surfaceY(x: 8, z: 8, height: options.height)
        self.init(position: position, sampledBiome: sampleY.flatMap { chunk.biome(x: 8, y: $0, z: 8) },
                  biomes: usedBiomes.sorted(), blockDeposits: deposits.values.sorted { $0.id < $1.id })
    }
}
