import Foundation

extension Dimension {
    /// Region passes share their failure boundary: missing files are empty, file-opening
    /// errors fail the pass, and a damaged individual chunk cannot hide readable neighbors.
    func visitRegionChunks(_ folder: Folder, at position: RegionPosition, skipping: Set<String> = [],
                           body: (Int, Int, NBT) throws -> Void) throws {
        try Task.checkCancellation()
        guard let file = try region(folder, x: position.x, z: position.z) else { return }
        for (x, z) in file.chunkCoordinates {
            try Task.checkCancellation()
            let nbt: NBT
            do {
                guard let value = try file.chunkNBT(localX: x, localZ: z, skipping: skipping) else { continue }
                nbt = value
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
            try body(x, z, nbt)
        }
        try Task.checkCancellation()
    }
}

/// Both terrain passes keep good neighbors when a chunk uses an unsupported numeric layout
/// or malformed palettes. Core facts also report the legacy count and retain independent records.
enum RegionTerrainChunk {
    case readable(Chunk)
    case legacy
    case unreadable

    init(_ input: TerrainChunkInput) throws {
        try Task.checkCancellation()
        do { self = .readable(try Chunk(input: input)) }
        catch ChunkError.unsupportedLegacyFormat { self = .legacy }
        catch is CancellationError { throw CancellationError() }
        catch { self = .unreadable }
    }
}
