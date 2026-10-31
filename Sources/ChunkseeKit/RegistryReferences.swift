/// A tag or an ordered list of registry identifiers. References need not resolve to files.
public enum RegistryReferences: Sendable, Equatable {
    case tag(String)
    case list([String])

    init?(json: Any) {
        self.init(json: json, tag: { Identifier($0)?.description }, members: { values in
            let ids = values.compactMap { ($0 as? String).flatMap(Identifier.init)?.description }
            return ids.count == values.count ? ids : nil
        })
    }

    /// Consumers that resolve resources retain their path policy and ordered, budgeted reads.
    init?(json: Any, tag: (String) -> String?, members: ([Any]) throws -> [String]?) rethrows {
        if let single = json as? String, single.hasPrefix("#"),
           let id = tag(String(single.dropFirst())) {
            self = .tag(id)
        } else {
            let direct = (json as? [Any]) ?? (json as? String).map { [$0] }
            guard let direct, let ids = try members(direct) else { return nil }
            self = .list(ids)
        }
    }

    init?(nbt: NBT) {
        if let single = nbt.string { self.init(json: single) }
        else if let values = nbt.list {
            let strings = values.compactMap(\.string)
            guard strings.count == values.count else { return nil }
            self.init(json: strings)
        } else { return nil }
    }
}

extension RegistryReferences: Decodable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) {
            guard let parsed = Self(json: text) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid registry reference")
            }
            self = parsed
        } else {
            guard let parsed = Self(json: try value.decode([String].self)) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid registry reference list")
            }
            self = parsed
        }
    }
}
