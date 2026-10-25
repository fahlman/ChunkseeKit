/// Verified save versions and format boundaries used by the readers. Unknown versions do not
/// acquire release-specific defaults merely because their number is newer.
public enum SaveVersion {
    public static let java26_1 = 4786
    public static let java26_1_1 = 4788
    public static let java26_1_2 = 4790
    public static let java26_2 = 4903
    public static let java26_3 = 5023
    /// Exact snapshot identity; each reader independently documents which facts are verified.
    public static let java26_4Snapshot5 = 5125

    /// 1.18 (21w43a): root-level chunk sections and their paletted containers.
    public static let flatChunkRoot = 2844
    /// 26.3 Snapshot 7: lowercase block palette keys and compact entries.
    public static let lowercaseBlockPalette = 5009
    /// 26.4 Snapshot 1: per-block biomes and lowercase chunk status; synthetic coverage only.
    public static let perBlockBiomes = 5119

    static let verifiedRecentPetHealth: Set<Int> = [java26_1, java26_1_1, java26_1_2, java26_2, java26_3]
}

/// Source-compatible name for the original chunk-format constants.
public typealias DataVersion = SaveVersion
