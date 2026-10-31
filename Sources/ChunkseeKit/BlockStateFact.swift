extension BlockState {
    /// Saved IDs are normally canonical. Parse aliases only after a direct lookup misses.
    func generatedFact<Value>(in facts: [String: Value]) -> Value? {
        facts[id] ?? Identifier(id).flatMap { facts[$0.description] }
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
