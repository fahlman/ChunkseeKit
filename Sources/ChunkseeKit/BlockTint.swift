/// A block-model tint, before optional neighboring-biome blending.
public enum BlockTint: Sendable, Equatable {
    case constant(UInt32)
    /// Sample the biome at this vertical offset from the block (upper tall grass uses -1).
    case biome(BiomeColor, yOffset: Int)
}

extension BlockState {
    /// The in-world tint of a model face's tint index, from generated game-code facts.
    /// For a block with known behavior, an index without a registered source returns white (no tint).
    /// Unknown code behavior, invalid indexes and color-driving properties return nil.
    /// Omitted properties use the same generated code defaults as block models.
    /// This describes block models, not item or particle tints. Water fluid rendering uses the
    /// biome's water color directly; its particle-only block tint is white here, as in the game.
    public func tintSource(at index: Int) -> BlockTint? {
        guard index >= 0 else { return nil }
        guard let sources = generatedFact(in: GeneratedBlockTints.sources) else { return nil }
        guard index < sources.count else { return GeneratedBlockTints.missingSource }
        switch sources[index] {
        case .fixed(let tint): return tint
        case .states(let names, let values):
            return BlockStateFact(properties: names, values: values).value(for: self)
        }
    }
}
