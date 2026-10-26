/// The release tool extracts registered blocks' seed methods and offsets. Picture selectors
/// cannot establish this behavior: a resource override does not change the block's game code.
enum BlockModelSeed {
    static func offset(for properties: BlockProperties) -> SIMD3<Int32>? {
        guard let id = properties.id, let format = GeneratedBlockModelSeeds.formats[id.description] else { return nil }
        switch format {
        case .ordinary: return GeneratedBlockModelSeeds.ordinaryOffset
        case .doubleBlock:
            return properties["half"].flatMap { GeneratedBlockModelSeeds.doubleBlockOffsets[$0] }
        case .bed:
            guard let part = properties["part"], let offsets = GeneratedBlockModelSeeds.bedOffsets[part],
                  let first = offsets.values.first else { return nil }
            // A missing facing does not hide a known, facing-independent head offset.
            if offsets.values.allSatisfy({ $0 == first }) { return first }
            return properties["facing"].flatMap { offsets[$0] }
        }
    }

    static func seed(at position: BlockPosition, offset: SIMD3<Int32>) -> Int64? {
        guard let x = Int32(exactly: position.x), let y = Int32(exactly: position.y),
              let z = Int32(exactly: position.z) else { return nil }
        // BlockPos offsets wrap as Java ints. Mth.getSeed multiplies X as an int, then mixes
        // signed longs; checked input conversion must precede these intentional overflows.
        var value = Int64((x &+ offset.x) &* 3_129_871)
            ^ (Int64(z &+ offset.z) &* 116_129_781) ^ Int64(y &+ offset.y)
        value = value &* value &* 42_317_861 &+ value &* 11
        return value >> 16
    }

}
