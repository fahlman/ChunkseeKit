/// A registered block-model tint, before optional neighboring-biome blending.
public enum BlockTint: Sendable, Equatable {
    case constant(UInt32)
    /// Sample the biome at this vertical offset from the block (upper tall grass uses -1).
    case biome(BiomeColor, yOffset: Int)
}

extension BlockState {
    /// The in-world tint of a model face's tint index, verified against 26.3's BlockColors.
    /// Unknown versions, blocks, indexes and invalid color-driving properties return nil.
    /// Only the verified defaults for half, power and age are supplied when omitted in 26.3.
    /// This describes block models, not item or particle tints. Water fluid rendering uses the
    /// biome's water color directly; its particle-only block tint is white here, as in the game.
    public func tintSource(at index: Int, gameDataVersion: Int32) -> BlockTint? {
        guard Int(gameDataVersion) == SaveVersion.java26_3, index >= 0,
              let name = Identifier(id), name.namespace == "minecraft" else { return nil }
        if name.path == "pink_petals" || name.path == "wildflowers" {
            return switch index {
            case 0: .constant(0xffffff)
            case 1: .biome(.grass, yOffset: 0)
            default: nil
            }
        }
        guard index == 0 else { return nil }
        switch name.path {
        case "grass_block", "fern", "short_grass", "potted_fern", "bush", "sugar_cane":
            return .biome(.grass, yOffset: 0)
        case "large_fern", "tall_grass":
            return switch properties["half"] ?? "lower" {
            case "lower": .biome(.grass, yOffset: 0)
            case "upper": .biome(.grass, yOffset: -1)
            default: nil
            }
        case "oak_leaves", "jungle_leaves", "acacia_leaves", "dark_oak_leaves", "vine", "mangrove_leaves":
            return .biome(.foliage, yOffset: 0)
        case "leaf_litter": return .biome(.dryFoliage, yOffset: 0)
        case "water_cauldron": return .biome(.water, yOffset: 0)
        case "water", "bubble_column": return .constant(0xffffff)
        case "spruce_leaves": return .constant(0x619961)
        case "birch_leaves": return .constant(0x80a755)
        case "lily_pad": return .constant(0x208030)
        case "attached_melon_stem", "attached_pumpkin_stem": return .constant(0xe0c71c)
        case "melon_stem", "pumpkin_stem":
            guard let age = tintProperty("age", in: 0...7) else { return nil }
            return .constant(UInt32(age * 32) << 16 | UInt32(255 - age * 8) << 8 | UInt32(age * 4))
        case "redstone_wire":
            guard let power = tintProperty("power", in: 0...15) else { return nil }
            let level = Float(power) / 15
            return RGBColor.channels([
                level * 0.6 + (power > 0 ? 0.4 : 0.3),
                min(1, max(0, level * level * 0.7 - 0.5)),
                min(1, max(0, level * level * 0.6 - 0.7))
            ]).map(BlockTint.constant)
        default: return nil
        }
    }

    private func tintProperty(_ name: String, in range: ClosedRange<Int>) -> Int? {
        guard let raw = properties[name] else { return 0 }
        guard let value = Int(raw), String(value) == raw, range.contains(value) else { return nil }
        return value
    }
}
