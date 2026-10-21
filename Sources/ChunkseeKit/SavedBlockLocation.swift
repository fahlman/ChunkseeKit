/// The paired dimension and integer block position used by modern spawn/death records.
struct SavedBlockLocation {
    let dimension: String
    let position: BlockPosition

    init?(_ nbt: NBT?) {
        guard let nbt, nbt["dimension"]?.string != nil,
              let dimension = nbt["dimension"]?.dimensionID,
              let pos = nbt["pos"]?.blockPosition else { return nil }
        self.dimension = dimension
        position = pos
    }
}

extension NBT {
    /// Raw dimension text for a value the reader cannot recognize. Unsupported tag shapes do
    /// not expose debug NBT syntax; player and map diagnostics use the same placeholder.
    var dimensionDescription: String { string ?? int.map(String.init) ?? "?" }

    /// Stored dimension IDs: strings get the default namespace; legacy numeric values only
    /// identify the three vanilla dimensions. Syntax is validated; world membership is separate.
    var dimensionID: String? {
        if let id = string { return Identifier(id)?.description }
        switch int {
        case 0: return "minecraft:overworld"
        case -1: return "minecraft:the_nether"
        case 1: return "minecraft:the_end"
        default: return nil
        }
    }
}
