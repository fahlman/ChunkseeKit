import Foundation

extension Chunk {
    /// Saved ticks near a chunk, including pre-1.18 metadata under `Level`. This does not decode
    /// legacy terrain. Root metadata wins when an upgraded chunk retains a vestigial `Level`.
    public static func inhabitedTime(in nbt: NBT) -> Int? {
        nbt["InhabitedTime"]?.int ?? nbt["Level"]?["InhabitedTime"]?.int
    }

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
            times[chunk.localZ * 32 + chunk.localX] = Chunk.inhabitedTime(in: chunk.nbt) ?? 0
        }
        return times
    }
}
