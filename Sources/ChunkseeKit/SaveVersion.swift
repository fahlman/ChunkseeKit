/// Known save-version numbers and historical format boundaries used by the readers.
public enum SaveVersion {
    public static let java26_1 = 4786
    public static let java26_1_1 = 4788
    public static let java26_1_2 = 4790
    public static let java26_2 = 4903
    public static let java26_3 = 5023

    /// 1.18 (21w43a): root-level chunk sections and their paletted containers.
    public static let flatChunkRoot = 2844
    /// 26.3 Snapshot 7: lowercase block palette keys and compact entries.
    public static let lowercaseBlockPalette = 5009
    /// 26.4 Snapshot 1: per-block biomes and lowercase chunk status; synthetic coverage only.
    public static let perBlockBiomes = 5119
}

/// Source-compatible name for the original chunk-format constants.
public typealias DataVersion = SaveVersion
