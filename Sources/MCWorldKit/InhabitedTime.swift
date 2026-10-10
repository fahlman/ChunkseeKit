import Foundation

extension Chunk {
    /// Entries a time-spent scan doesn't need: everything big, leaving `InhabitedTime`.
    public static let keysNotNeededForInhabitedTime: Set<String> =
        keysNotNeededForTerrain.union(["sections", "Heightmaps", "structures", "block_entities"])
}

extension Dimension {
    /// Ticks players have spent near each chunk of a region (`InhabitedTime`, which also drives
    /// regional difficulty): 1,024 values, index `localZ * 32 + localX`, 0 where a chunk is
    /// missing or unreadable.
    public func inhabitedTimes(regionX: Int, regionZ: Int) throws -> [Int] {
        var times = [Int](repeating: 0, count: 1024)
        for chunk in try chunks(.terrain, regionX: regionX, regionZ: regionZ, skipping: Chunk.keysNotNeededForInhabitedTime) {
            // Chunks from before 1.18 keep it under `Level`.
            times[chunk.localZ * 32 + chunk.localX] = chunk.nbt["InhabitedTime"]?.int ?? chunk.nbt["Level"]?["InhabitedTime"]?.int ?? 0
        }
        return times
    }
}
