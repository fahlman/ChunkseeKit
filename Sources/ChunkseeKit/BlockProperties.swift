/// Saved values override mechanically generated code defaults without changing the saved state.
/// Resolve the block once per model read; all its predicates and seed rules share this lookup.
struct BlockProperties {
    let id: Identifier?
    private let saved: [String: String]
    private let defaults: [String: String]

    init(_ state: BlockState) {
        id = Identifier(state.id)
        saved = state.properties
        defaults = id.flatMap { GeneratedBlockDefaults.values[$0.description] } ?? [:]
    }

    subscript(_ name: String) -> String? { saved[name] ?? defaults[name] }
}
