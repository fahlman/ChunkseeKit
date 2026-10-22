import ChunkseeKit

struct SearchRegion: Hashable {
    let x: Int, z: Int
}

/// Contents can live in either folder; overlap must be read only once.
func searchRegions(in dimension: Dimension) -> [SearchRegion] {
    Set((dimension.regionFiles() + dimension.regionFiles(.entities)).map { SearchRegion(x: $0.x, z: $0.z) })
        .sorted { ($0.x, $0.z) < ($1.x, $1.z) }
}
