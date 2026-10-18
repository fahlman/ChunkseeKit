import Foundation

/// One dimension's folder: terrain, entities and points of interest, each a set of region files.
public struct Dimension: Sendable {
    /// Namespaced ID, e.g. `minecraft:the_nether`.
    public let id: String
    public let url: URL

    /// The three sets of region files a dimension keeps.
    public enum Folder: Sendable, CaseIterable {
        /// Blocks, biomes and block entities: `region/`.
        case terrain
        /// Mobs, item frames, minecarts and the like (since 1.17): `entities/`.
        case entities
        /// Beds, workstations, portals and other points of interest: `poi/`.
        case pointsOfInterest
    }

    public var regionDirectory: URL { url.appendingPathComponent("region") }
    public var entitiesDirectory: URL { url.appendingPathComponent("entities") }
    public var poiDirectory: URL { url.appendingPathComponent("poi") }
    /// Per-dimension saved data (raids, world border, chunk tickets), 26.1+.
    public var dataDirectory: URL { url.appendingPathComponent("data") }

    public func directory(_ folder: Folder) -> URL {
        switch folder {
        case .terrain: regionDirectory
        case .entities: entitiesDirectory
        case .pointsOfInterest: poiDirectory
        }
    }

    /// Coordinates and URLs of every region file in a folder, sorted by coordinates.
    public func regionFiles(_ folder: Folder = .terrain) -> [(x: Int, z: Int, url: URL)] {
        let directory = directory(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            RegionFile.parseCoordinates(name).map { ($0.x, $0.z, directory.appendingPathComponent(name)) }
        }.sorted { ($0.x, $0.z) < ($1.x, $1.z) }
    }

    /// URL of a region file at region coordinates (not chunk or block coordinates).
    /// This only constructs a path; the file and its parent folder need not exist.
    public func regionURL(_ folder: Folder = .terrain, x: Int, z: Int) -> URL {
        directory(folder).appendingPathComponent("r.\(x).\(z).mca")
    }

    /// The region file at region coordinates in a folder, if it exists.
    public func region(_ folder: Folder = .terrain, x: Int, z: Int) throws -> RegionFile? {
        let url = regionURL(folder, x: x, z: z)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RegionFile(contentsOf: url)
    }

    /// Visits one decoded chunk at a time, with region-local X/Z and raw NBT. Entries named in
    /// `skipping` are omitted. Missing regions are empty; unreadable individual chunks are skipped.
    /// Opening errors and errors thrown by `body` (including cancellation) propagate immediately.
    public func forEachChunk(_ folder: Folder = .terrain, regionX: Int, regionZ: Int,
                             skipping: Set<String> = [], _ body: (Int, Int, NBT) throws -> Void) throws {
        guard let region = try region(folder, x: regionX, z: regionZ) else { return }
        for (x, z) in region.chunkCoordinates {
            guard let nbt = try? region.chunkNBT(localX: x, localZ: z, skipping: skipping) else { continue }
            try body(x, z, nbt)
        }
    }

    /// Every readable chunk of one region file in a folder, with the entries in `skipping` left
    /// out. Chunks that can't be read are skipped, so one damaged chunk doesn't hide the rest.
    func chunks(_ folder: Folder, regionX: Int, regionZ: Int, skipping: Set<String> = []) throws -> [(localX: Int, localZ: Int, nbt: NBT)] {
        var chunks: [(localX: Int, localZ: Int, nbt: NBT)] = []
        try forEachChunk(folder, regionX: regionX, regionZ: regionZ, skipping: skipping) { x, z, nbt in
            chunks.append((x, z, nbt))
        }
        return chunks
    }

    /// The chunk at absolute chunk coordinates, or `nil` if it hasn't been generated.
    public func chunk(x: Int, z: Int) throws -> Chunk? {
        guard let region = try region(x: x >> 5, z: z >> 5),
              let nbt = try region.chunkNBT(localX: x & 31, localZ: z & 31) else { return nil }
        return try Chunk(nbt: nbt)
    }

    /// The block at absolute world coordinates. Loads the chunk each call; cache `Chunk`s for bulk reads.
    public func block(x: Int, y: Int, z: Int) throws -> BlockState? {
        try chunk(x: x >> 4, z: z >> 4)?.block(x: x & 15, y: y, z: z & 15)
    }

    /// Entities saved in the given chunk (stored separately from terrain since 1.17).
    public func entities(chunkX: Int, chunkZ: Int) throws -> [NBT] {
        guard let region = try region(.entities, x: chunkX >> 5, z: chunkZ >> 5),
              let nbt = try region.chunkNBT(localX: chunkX & 31, localZ: chunkZ & 31) else { return [] }
        return nbt["Entities"]?.list ?? []
    }
}

extension Dimension {
    /// Every biome that vanilla Minecraft generates in this dimension, by namespaced ID, or none for
    /// a custom dimension. From Minecraft 26.3's biome tags `is_overworld`, `is_nether` and
    /// `is_end`; a world saved by an older version may lack biomes added since.
    public var vanillaBiomes: [String] {
        switch id {
        case "minecraft:overworld": Self.overworldBiomes
        case "minecraft:the_nether": Self.netherBiomes
        case "minecraft:the_end": Self.endBiomes
        default: []
        }
    }

    static let overworldBiomes = [
        "minecraft:mushroom_fields",
        "minecraft:deep_frozen_ocean",
        "minecraft:frozen_ocean",
        "minecraft:deep_cold_ocean",
        "minecraft:cold_ocean",
        "minecraft:deep_ocean",
        "minecraft:ocean",
        "minecraft:deep_lukewarm_ocean",
        "minecraft:lukewarm_ocean",
        "minecraft:warm_ocean",
        "minecraft:stony_shore",
        "minecraft:swamp",
        "minecraft:mangrove_swamp",
        "minecraft:snowy_slopes",
        "minecraft:snowy_plains",
        "minecraft:snowy_beach",
        "minecraft:windswept_gravelly_hills",
        "minecraft:grove",
        "minecraft:windswept_hills",
        "minecraft:snowy_taiga",
        "minecraft:windswept_forest",
        "minecraft:taiga",
        "minecraft:plains",
        "minecraft:meadow",
        "minecraft:beach",
        "minecraft:forest",
        "minecraft:old_growth_spruce_taiga",
        "minecraft:flower_forest",
        "minecraft:birch_forest",
        "minecraft:dark_forest",
        "minecraft:pale_garden",
        "minecraft:savanna_plateau",
        "minecraft:savanna",
        "minecraft:jungle",
        "minecraft:badlands",
        "minecraft:desert",
        "minecraft:wooded_badlands",
        "minecraft:jagged_peaks",
        "minecraft:stony_peaks",
        "minecraft:frozen_river",
        "minecraft:river",
        "minecraft:ice_spikes",
        "minecraft:dappled_forest",
        "minecraft:old_growth_pine_taiga",
        "minecraft:sunflower_plains",
        "minecraft:old_growth_birch_forest",
        "minecraft:sparse_jungle",
        "minecraft:bamboo_jungle",
        "minecraft:eroded_badlands",
        "minecraft:windswept_savanna",
        "minecraft:cherry_grove",
        "minecraft:frozen_peaks",
        "minecraft:dripstone_caves",
        "minecraft:lush_caves",
        "minecraft:sulfur_caves",
        "minecraft:deep_dark"
    ]

    static let netherBiomes = [
        "minecraft:nether_wastes",
        "minecraft:soul_sand_valley",
        "minecraft:crimson_forest",
        "minecraft:warped_forest",
        "minecraft:basalt_deltas"
    ]

    static let endBiomes = [
        "minecraft:the_end",
        "minecraft:end_highlands",
        "minecraft:end_midlands",
        "minecraft:small_end_islands",
        "minecraft:end_barrens"
    ]
}
