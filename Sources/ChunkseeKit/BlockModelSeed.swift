/// Vanilla model seeding is behavior on the registered block, not part of its asset JSON.
/// The reader already resolved this ID's definition from the supplied 26.3 jar. Only the
/// overriding classes need a catalog; ordinary blocks use the shared position directly.
enum BlockModelSeed {
    static func offset(for properties: BlockProperties, gameDataVersion: Int32) -> SIMD3<Int32>? {
        guard gameDataVersion == SaveVersion.java26_3,
              let id = properties.id, id.namespace == "minecraft" else { return nil }
        if doubleBlocks.contains(id.path) {
            switch properties["half"] {
            case "lower": return .zero
            case "upper": return SIMD3(0, -1, 0)
            default: return nil
            }
        }
        guard beds.contains(id.path) else {
            // These two asset blockstates describe entities, which have no block seed behavior.
            guard id.path != "item_frame", id.path != "glow_item_frame" else { return nil }
            return .zero
        }
        switch properties["part"] {
        case "head": return .zero
        case "foot":
            switch properties["facing"] {
            case "north": return SIMD3(0, 0, -1)
            case "south": return SIMD3(0, 0, 1)
            case "east": return SIMD3(1, 0, 0)
            case "west": return SIMD3(-1, 0, 0)
            default: return nil
            }
        default: return nil
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

    private static let beds: Set<String> = Set("""
    black_bed blue_bed brown_bed cyan_bed gray_bed green_bed light_blue_bed light_gray_bed lime_bed
    magenta_bed orange_bed pink_bed purple_bed red_bed straw_bed white_bed yellow_bed
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let doubleBlocks: Set<String> = Set("""
    acacia_door bamboo_door birch_door cherry_door copper_door crimson_door dark_oak_door
    exposed_copper_door iron_door jungle_door large_fern lilac mangrove_door oak_door
    oxidized_copper_door pale_oak_door peony pitcher_crop pitcher_plant poplar_door rose_bush
    small_dripleaf spruce_door sunflower tall_grass tall_seagrass warped_door waxed_copper_door
    waxed_exposed_copper_door waxed_oxidized_copper_door waxed_weathered_copper_door
    weathered_copper_door
    """.split(whereSeparator: \.isWhitespace).map(String.init))

}
