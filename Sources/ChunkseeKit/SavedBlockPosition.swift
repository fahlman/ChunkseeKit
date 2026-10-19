extension NBT {
    /// BlockPos.CODEC: exactly three integers. A coordinate compound is a different legacy format.
    var blockPosition: BlockPosition? {
        guard let values = intArray, values.count == 3 else { return nil }
        return BlockPosition(blockX: Int(values[0]), blockY: Int(values[1]), blockZ: Int(values[2]))
    }

    /// Block-entity coordinates are lower-case fields, not the BlockPos int-array codec.
    var blockEntityPosition: BlockPosition? {
        guard let x = self["x"]?.int, let y = self["y"]?.int, let z = self["z"]?.int else { return nil }
        return BlockPosition(blockX: x, blockY: y, blockZ: z)
    }
}
