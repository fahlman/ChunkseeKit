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

    /// The region file at region coordinates in a folder, if it exists.
    public func region(_ folder: Folder = .terrain, x: Int, z: Int) throws -> RegionFile? {
        let url = directory(folder).appendingPathComponent("r.\(x).\(z).mca")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RegionFile(contentsOf: url)
    }

    /// Every readable chunk of one region file in a folder, with the entries in `skipping` left
    /// out. Chunks that can't be read are skipped, so one damaged chunk doesn't hide the rest.
    func chunks(_ folder: Folder, regionX: Int, regionZ: Int, skipping: Set<String> = []) throws -> [(localX: Int, localZ: Int, nbt: NBT)] {
        guard let region = try region(folder, x: regionX, z: regionZ) else { return [] }
        return region.chunkCoordinates.compactMap { x, z in
            (try? region.chunkNBT(localX: x, localZ: z, skipping: skipping)).flatMap { $0 }.map { (x, z, $0) }
        }
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
