import ChunkseeKit

struct SearchRegion: Hashable {
    let x: Int, z: Int
}

/// Contents can live in either folder; overlap must be read only once.
func searchRegions(in dimension: Dimension, discovery: inout RegionDiscovery) -> [SearchRegion] {
    let terrain = discovery.files(in: dimension) ?? []
    let entities = discovery.files(in: dimension, folder: .entities) ?? []
    return Set((terrain + entities).map { SearchRegion(x: $0.x, z: $0.z) })
        .sorted { ($0.x, $0.z) < ($1.x, $1.z) }
}
