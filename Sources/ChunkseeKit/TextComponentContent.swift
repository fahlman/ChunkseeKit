import Foundation

extension TextComponent {
    /// Interpretable resource text before the client selects a language or lays it out.
    /// Styles and click/hover actions are omitted. Dynamic game-context content is unavailable.
    /// Codable archives this typed value; `content(json:)` interprets Minecraft's JSON format.
    public indirect enum Content: Sendable, Hashable, Codable {
        case literal(String)
        case translated(key: String, fallback: String?, arguments: [Argument])
        case sequence([Content])
    }

    /// Translation arguments retain their primitive type or nested component when archived too.
    public enum Argument: Sendable, Hashable, Codable {
        case string(String)
        case integer(Int64)
        case float(Float)
        /// A Double argument; do not infer an integer or Float from its rounded value.
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
              let json = try? jsonValue(from: data) else { return nil }
        return try? content(json, budget: &budget)
    }

    /// Interprets native or already upgraded NBT components. Strings are always literal;
    /// save readers convert historical JSON text once using the containing file's version.
    /// NBT limits: 16 MiB per interpreted string, 64 MiB total, 64 component levels and
    /// 65,536 component/argument visits. Unused style/action fields are not traversed.
    public static func content(_ nbt: NBT) -> Content? {
        var budget = ResourceReadBudget()
        return try? read(.nbt(nbt), depth: 0, budget: &budget)
    }

    static func content(_ json: Any, budget: inout ResourceReadBudget) throws -> Content {
        try read(.json(json), depth: 0, budget: &budget)
    }

    static func jsonValue(from data: Data) throws -> Any {
        try AssetJSON.value(from: data)
    }

    private static func read(_ input: TextInput, depth: Int, budget: inout ResourceReadBudget) throws -> Content {
        guard depth < 64, budget.consume(1) else { throw AssetReadError.invalidData }
        if let literal = try input.readString(budget: &budget) {
            return .literal(literal)
        }
        if let values = try input.list() {
            guard !values.isEmpty else { throw AssetReadError.invalidData }
            return .sequence(try values.map { try read($0, depth: depth + 1, budget: &budget) })
        }
        let kind: String
        if let explicit = input["type"] {
            guard let value = try explicit.readString(budget: &budget) else { throw AssetReadError.invalidData }
            kind = value
        } else {
            // ComponentSerialization's legacy matcher tries the literal codec first.
            kind = input["text"]?.string != nil ? "text" : "translatable"
        }
        let base: Content
        switch kind {
        case "text":
            guard let text = try input["text"]?.readString(budget: &budget) else { throw AssetReadError.invalidData }
            base = .literal(text)
        case "translatable":
            guard let key = try input["translate"]?.readString(budget: &budget) else { throw AssetReadError.invalidData }
            let arguments: [Argument]
            if let value = input["with"] {
                guard let list = try value.list() else { throw AssetReadError.invalidData }
                arguments = try list.map { try argument($0, depth: depth + 1, budget: &budget) }
            } else { arguments = [] }
            // TranslatableContents uses a lenient optional string codec for fallback.
            base = .translated(key: key, fallback: try input["fallback"]?.readString(budget: &budget), arguments: arguments)
        default:
            // Keybinds, scores, selectors, NBT lookups and object pictures need game context.
            throw AssetReadError.invalidData
        }
        guard let extra = input["extra"] else { return base }
        guard let siblings = try extra.list(), !siblings.isEmpty else { throw AssetReadError.invalidData }
        return .sequence([base] + (try siblings.map { try read($0, depth: depth + 1, budget: &budget) }))
    }

    private static func argument(_ input: TextInput, depth: Int, budget: inout ResourceReadBudget) throws -> Argument {
        guard budget.consume(1) else { throw AssetReadError.invalidData }
        if let value = try input.readString(budget: &budget) { return .string(value) }
        if let value = input.boolean { return .boolean(value) }
        if let value = input.numberArgument { return value }
        return .component(try read(input, depth: depth, budget: &budget))
    }
}

/// Format adapters only; component dispatch, fields and recursion have one owner above.
private enum TextInput {
    case json(Any)
    case nbt(NBT)

    var string: String? {
        switch self {
        case .json(let value): value as? String
        case .nbt(let value): value.string
        }
    }

    func readString(budget: inout ResourceReadBudget) throws -> String? {
        let value = string
        if case .nbt = self, let value, !budget.charge(bytes: value.utf8.count) { throw AssetReadError.invalidData }
        return value
    }

    var boolean: Bool? {
        guard case .json(let value) = self else { return nil }
        return try? AssetJSON.boolean(value)
    }

    var numberArgument: TextComponent.Argument? {
        switch self {
        case .json(let value): (value as? AssetJSON.Number)?.argument
        // JavaOps keeps NBT's supplied numeric kind, including byte arguments and nonfinite
        // floats. Unlike JSON, a Double equal to an integer or Float is not narrowed.
        case .nbt(let value):
            switch value {
            case .byte(let value): .integer(Int64(value))
            case .short(let value): .integer(Int64(value))
            case .int(let value): .integer(Int64(value))
            case .long(let value): .integer(value)
            // FloatTag/DoubleTag.load use valueOf, which canonicalizes either signed zero.
            case .float(let value): .float(value == 0 ? 0 : value)
            case .double(let value): .number(value == 0 ? 0 : value)
            default: nil
            }
        }
    }

    subscript(key: String) -> Self? {
        switch self {
        case .json(let value): ((value as? [String: Any])?[key]).map(Self.json)
        case .nbt(let value): value[key].map(Self.nbt)
        }
    }

    func list() throws -> [Self]? {
        switch self {
        case .json(let value):
            guard let values = value as? [Any] else { return nil }
            guard values.count <= 65_536 else { throw AssetReadError.invalidData }
            return values.map(Self.json)
        case .nbt(let value):
            guard let values = value.list else { return nil }
            guard values.count <= 65_536 else { throw AssetReadError.invalidData }
            return values.map { .nbt($0.unwrappedListElement) }
        }
    }
}
