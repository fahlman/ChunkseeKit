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
        regionURL(folder, at: RegionPosition(x: x, z: z))
    }

    public func regionURL(_ folder: Folder = .terrain, at position: RegionPosition) -> URL {
        directory(folder).appendingPathComponent("r.\(position.x).\(position.z).mca")
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
    public func chunk(x: Int, z: Int) throws -> Chunk? { try chunk(at: ChunkPosition(x: x, z: z)) }

    public func chunk(at position: ChunkPosition) throws -> Chunk? {
        guard let region = try region(x: position.region.x, z: position.region.z),
              let nbt = try region.chunkNBT(localX: position.localX, localZ: position.localZ) else { return nil }
        return try Chunk(nbt: nbt)
    }

    /// The block at absolute world coordinates. Loads the chunk each call; cache `Chunk`s for bulk reads.
    public func block(x: Int, y: Int, z: Int) throws -> BlockState? {
        try block(at: BlockPosition(blockX: x, blockY: y, blockZ: z))
    }

    public func block(at position: BlockPosition) throws -> BlockState? {
        try chunk(at: position.chunk)?.block(x: position.x & 15, y: position.y, z: position.z & 15)
    }

    /// Entities saved in the given chunk, including older terrain-embedded records.
    /// Includes nested passengers, parent before children in saved order. Each raw compound
    /// retains its Passengers field; do not traverse it again when consuming this flat list.
    public func entities(chunkX: Int, chunkZ: Int) throws -> [NBT] {
        try entityChunks(x: chunkX, z: chunkZ).flatMap { EntityTraversal.flatten($0["Entities"]?.list ?? []) }
    }

    /// The same query using terrain from this dimension with entity fields retained, avoiding a second
    /// region read. The separate entity file is read normally; raw entity fields stay intact.
    public func entities(in chunk: Chunk) throws -> [NBT] {
        var result = EntityTraversal.flatten(SaveDataUpgrade.terrainEntityChunk(chunk.nbt)?["Entities"]?.list ?? [])
        if let separate = try entityChunk(x: chunk.x, z: chunk.z) {
            result += EntityTraversal.flatten(separate["Entities"]?.list ?? [])
        }
        return result
    }

    /// Each source keeps its own DataVersion. Reading both also retains mixed-format regions.
    func entityChunks(x: Int, z: Int) throws -> [NBT] {
        let position = ChunkPosition(x: x, z: z)
        var result: [NBT] = []
        if let terrain = try rawChunk(.terrain, at: position, skipping: Chunk.keysNotNeededForEmbeddedEntities),
           let entities = SaveDataUpgrade.terrainEntityChunk(terrain) { result.append(entities) }
        if let separate = try entityChunk(x: x, z: z) { result.append(separate) }
        return result
    }

    /// Shared raw read so creature decoding retains the entity chunk's DataVersion.
    func entityChunk(x: Int, z: Int) throws -> NBT? {
        try rawChunk(.entities, at: ChunkPosition(x: x, z: z))
    }

    private func rawChunk(_ folder: Folder, at position: ChunkPosition,
                          skipping: Set<String> = []) throws -> NBT? {
        let url = regionURL(folder, at: position.region)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RegionFile.chunkNBT(contentsOf: url, localX: position.localX,
                                       localZ: position.localZ, skipping: skipping)
    }
}

extension Chunk {
    static let keysNotNeededForEmbeddedEntities: Set<String> = keysNotNeededForTerrain
        .subtracting(["entities", "Entities"])
        .union(["sections", "Sections", "Heightmaps", "Structures", "TileEntities", "Biomes"])
}
