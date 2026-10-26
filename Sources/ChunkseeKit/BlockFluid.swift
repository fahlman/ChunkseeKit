extension BlockState {
    /// Whether this state contains a fluid declared by a composed tag, such as minecraft:water.
    /// Resolve the tag once from the world's resources; this query performs no file reads.
    /// Known empty states return false even without a tag. Missing block-code facts, relevant
    /// invalid properties, or a missing tag for a nonempty state return nil. Saved properties
    /// override generated defaults, independently of game or save version labels.
    public func containsFluid(in tag: GameTag?) -> Bool? {
        guard let fluid = fact(GeneratedBlockFluids.fluids) else { return nil }
        if fluid.isEmpty { return false }
        return tag.map { $0.members.contains { $0.id == fluid } }
    }

    /// Minecraft's full-support test for the upper face, as used by its map's fluid rule.
    /// This is a code-derived support fact, not texture coverage or opacity. Missing code,
    /// a relevant invalid property, or a rule requiring neighboring world data returns nil.
    /// The fluid answer is independent, so an unknown face does not hide known water.
    public var hasSolidUpperFace: Bool? { fact(GeneratedBlockFluids.upperFaces) }

    private func fact<Value>(_ facts: [String: BlockStateFact<Value>]) -> Value? {
        let rule = facts[id] ?? Identifier(id).flatMap { facts[$0.description] }
        return rule?.value(for: self)
    }
}

/// One generated property-dependent fact, with omitted values supplied by the shared owner.
struct BlockStateFact<Value: Sendable>: Sendable {
    let properties: [String]
    let values: [[String]: Value]

    func value(for state: BlockState) -> Value? {
        if properties.isEmpty { return values[[]] }
        let supplied = BlockProperties(state)
        var key = [String]()
        key.reserveCapacity(properties.count)
        for property in properties {
            guard let value = supplied[property] else { return nil }
            key.append(value)
        }
        return values[key]
    }
}
