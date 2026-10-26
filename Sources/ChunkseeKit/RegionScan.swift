import Foundation

public enum RegionScanError: Error, Equatable {
    case invalidRegion(RegionPosition)
    case invalidHeight(Int)
}

extension Dimension {
    /// Decodes each present terrain/entity/POI chunk once. Missing files are empty; unreadable
    /// individual chunks are counted and skipped. Opening errors and cancellation throw, so a
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
                   body: (Int, Int, NBT) throws -> Void) throws -> Int {
            try Task.checkCancellation()
            guard let file = try region(folder, x: position.x, z: position.z) else { return 0 }
            var unreadable = 0
            for (x, z) in file.chunkCoordinates {
                try Task.checkCancellation()
                guard let nbt = try? file.chunkNBT(localX: x, localZ: z, skipping: skipping) else {
                    unreadable += 1
                    continue
                }
                try body(x, z, nbt)
            }
            return unreadable
        }

        let unreadable = try visit(.terrain, skipping: omitted) { x, z, nbt in
            facts.containers += ItemContainer.containers(inChunk: nbt)
            facts.signs += Sign.signs(inChunk: nbt)
            facts.spawners += Spawner.spawners(inChunk: nbt)
            if let entities = SaveDataUpgrade.terrainEntityChunk(nbt) {
                facts.creatures += Creature.creatures(inEntityChunk: entities, enchantments: options.enchantments)
            }
            facts.inhabitedTimes[z * 32 + x] = Chunk.inhabitedTime(in: nbt) ?? 0
            let chunk: Chunk
            do { chunk = try Chunk(nbt: nbt) }
            catch ChunkError.unsupportedLegacyFormat { facts.formats.legacy += 1; return }
            catch { facts.formats.unreadableTerrain += 1; return }
            facts.formats.readable += 1
            if chunk.isFullyGenerated { facts.structures += chunk.structureStarts }
            let terrain = try TerrainChunkFacts(chunk, at: .init(x: origin.x + x, z: origin.z + z),
                                               options: options, paletteBlockIDs: &facts.paletteBlockIDs)
            facts.chunks.append(terrain)
        }
        facts.formats.unreadableTerrain += unreadable
        let unreadableEntities = try visit(.entities) { _, _, nbt in
            facts.containers += ItemContainer.containers(inEntityChunk: nbt)
            facts.creatures += Creature.creatures(inEntityChunk: nbt, enchantments: options.enchantments)
        }
        facts.formats.unreadableEntities = unreadableEntities
        let unreadablePOIs = try visit(.pointsOfInterest) { _, _, nbt in
            facts.pointsOfInterest += PointOfInterest.records(inChunk: nbt)
        }
        facts.formats.unreadablePointsOfInterest = unreadablePOIs
        try Task.checkCancellation()
        return facts
    }
}

extension TerrainChunkFacts {
    init(_ chunk: Chunk, at position: ChunkPosition, options: RegionScanOptions,
         paletteBlockIDs: inout Set<String>) throws {
        var heights: [String: [Int]] = [:]
        for name in chunk.heightmapNames {
            if let height = options.height { heights[name] = chunk.heightmap(name, height: height) }
            else { heights[name] = chunk.heightmap(name) }
        }
        var usedBiomes = Set<String>()
        var deposits: [String: BlockDeposit] = [:]
        if chunk.isFullyGenerated {
            for section in chunk.sections {
                try Task.checkCancellation()
                if let biomes = section.biomes {
                    for (index, count) in biomes.paletteCounts().enumerated() where count > 0 {
                        usedBiomes.insert(biomes.palette[index])
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
        }
        let sampledBiome = chunk.isFullyGenerated ? Self.sampleBiome(chunk, heights: heights, y: options.biomeSampleY) : nil
        self.init(position: position, dataVersion: chunk.dataVersion, status: chunk.status, isFullyGenerated: chunk.isFullyGenerated,
                  sampledBiome: sampledBiome, biomes: usedBiomes.sorted(), blockDeposits: deposits.values.sorted { $0.id < $1.id },
                  heightmaps: heights)
    }

    private static func sampleBiome(_ chunk: Chunk, heights: [String: [Int]], y requested: Int?) -> String? {
        guard let y = requested ?? chunk.surfaceY(x: 8, z: 8, heightmap: heights["WORLD_SURFACE"]) else { return nil }
        return chunk.biome(x: 8, y: y, z: 8)
    }
}
