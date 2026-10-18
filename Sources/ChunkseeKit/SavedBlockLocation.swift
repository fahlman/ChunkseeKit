/// The paired dimension and integer block position used by modern spawn/death records.
struct SavedBlockLocation {
    let dimension: String
    let position: (x: Int, y: Int, z: Int)

    init?(_ nbt: NBT?) {
        guard let nbt, nbt["dimension"]?.string != nil,
              let dimension = nbt["dimension"]?.dimensionID,
              let pos = nbt["pos"]?.intArray, pos.count == 3 else { return nil }
        self.dimension = dimension
        position = (Int(pos[0]), Int(pos[1]), Int(pos[2]))
    }
}

extension NBT {
    /// Stored dimension IDs: strings get the default namespace; legacy numeric values only
    /// identify the three vanilla dimensions. This does not validate identifier syntax or world membership.
    var dimensionID: String? {
        if let id = string { return id.contains(":") ? id : "minecraft:" + id }
        switch int {
        case 0: return "minecraft:overworld"
        case -1: return "minecraft:the_nether"
        case 1: return "minecraft:the_end"
        default: return nil
        }
    }
}
