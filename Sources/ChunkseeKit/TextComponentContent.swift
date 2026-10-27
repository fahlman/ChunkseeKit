import Foundation

extension TextComponent {
    /// Interpretable resource text before the client selects a language or lays it out.
    /// Styles and click/hover actions are omitted. Dynamic game-context content is unavailable.
    public indirect enum Content: Sendable, Hashable {
        case literal(String)
        case translated(key: String, fallback: String?, arguments: [Argument])
        case sequence([Content])
    }

    /// Translation arguments retain their primitive type or nested component.
    public enum Argument: Sendable, Hashable {
        case string(String)
        case number(Double)
        case boolean(Bool)
        case component(Content)
    }

    /// Reads literal/translated JSON components, arrays and `extra` siblings. Translation
    /// lookup and argument substitution belong to the client. A dynamic or malformed component
    /// returns nil; it is not replaced with an invented name or a partial title.
    /// Limits: 16 MiB input, 64 component levels and 65,536 component/argument visits.
    public static func content(json data: Data) -> Content? {
        var budget = ResourceReadBudget()
        guard budget.charge(data),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return try? content(json, depth: 0, budget: &budget)
    }

    static func content(_ json: Any, depth: Int = 0, budget: inout ResourceReadBudget) throws -> Content {
        guard depth < 64, budget.consume(1) else { throw AssetReadError.invalidData }
        if let literal = json as? String { return .literal(literal) }
        if let values = json as? [Any] {
            guard !values.isEmpty else { throw AssetReadError.invalidData }
            return .sequence(try values.map { try content($0, depth: depth + 1, budget: &budget) })
        }
        let fields = try AssetJSON.object(json)
        let kind: String
        if let explicit = fields["type"] {
            guard let value = explicit as? String else { throw AssetReadError.invalidData }
            kind = value
        } else {
            // ComponentSerialization's legacy matcher tries the literal codec first.
            kind = fields["text"] is String ? "text" : "translatable"
        }
        let base: Content
        switch kind {
        case "text":
            guard let text = fields["text"] as? String else { throw AssetReadError.invalidData }
            base = .literal(text)
        case "translatable":
            guard let key = fields["translate"] as? String else { throw AssetReadError.invalidData }
            let arguments: [Argument]
            if let value = fields["with"] {
                arguments = try AssetJSON.array(value).map { try argument($0, depth: depth + 1, budget: &budget) }
            } else { arguments = [] }
            // TranslatableContents uses a lenient optional string codec for fallback.
            base = .translated(key: key, fallback: fields["fallback"] as? String, arguments: arguments)
        default:
            // Keybinds, scores, selectors, NBT lookups and object pictures need game context.
            throw AssetReadError.invalidData
        }
        guard let extra = fields["extra"] else { return base }
        let siblings = try AssetJSON.array(extra)
        guard !siblings.isEmpty else { throw AssetReadError.invalidData }
        return .sequence([base] + (try siblings.map { try content($0, depth: depth + 1, budget: &budget) }))
    }

    private static func argument(_ json: Any, depth: Int, budget: inout ResourceReadBudget) throws -> Argument {
        guard budget.consume(1) else { throw AssetReadError.invalidData }
        if let value = json as? String { return .string(value) }
        if let value = try? AssetJSON.boolean(json) { return .boolean(value) }
        if let value = try? AssetJSON.jsonNumber(json).doubleValue {
            guard value.isFinite else { throw AssetReadError.invalidData }
            return .number(value)
        }
        return .component(try content(json, depth: depth, budget: &budget))
    }
}
