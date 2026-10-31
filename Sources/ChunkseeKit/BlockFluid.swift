extension BlockState {
    /// Whether this state contains a fluid declared by a composed tag, such as minecraft:water.
    /// Resolve the tag once from the world's resources; this query performs no file reads.
    /// Known empty states return false even without a tag. Missing block-code facts, relevant
    /// invalid properties, or a missing tag for a nonempty state return nil. Saved properties
    /// override generated defaults, independently of game or save version labels.
    public func containsFluid(in tag: GameTag?) -> Bool? {
        guard let fluid = generatedFact(in: GeneratedBlockFluids.fluids)?.value(for: self) else { return nil }
        if fluid.isEmpty { return false }
        return tag.map { $0.members.contains { $0.id == fluid } }
    }

    /// Minecraft's full-support test for the upper face, as used by its map's fluid rule.
    /// This is a code-derived support fact, not texture coverage or opacity. Missing code,
    /// a relevant invalid property, or a rule requiring neighboring world data returns nil.
    /// The fluid answer is independent, so an unknown face does not hide known water.
    public var hasSolidUpperFace: Bool? {
        generatedFact(in: GeneratedBlockFluids.upperFaces)?.value(for: self)
    }
}
