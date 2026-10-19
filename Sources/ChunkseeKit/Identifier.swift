/// A Minecraft resource identifier. Syntax and default namespace follow the 26.3 Identifier codec.
/// A syntactically valid identifier is not necessarily registered, nor is its path a safe file path.
public struct Identifier: Sendable, Hashable, Codable, CustomStringConvertible {
    public let namespace: String
    public let path: String
    public var description: String { namespace + ":" + path }

    /// An omitted or empty namespace uses `minecraft`. Empty paths are valid codec values.
    public init?(_ value: String) {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let namespace = parts.count == 1 || parts[0].isEmpty ? "minecraft" : String(parts[0])
        self.init(namespace: namespace, path: String(parts.last ?? ""))
    }

    public init?(namespace: String, path: String) {
        let namespace = namespace.isEmpty ? "minecraft" : namespace
        guard namespace != "..", namespace.utf8.allSatisfy(Self.namespaceCharacter),
              path.utf8.allSatisfy({ Self.namespaceCharacter($0) || $0 == 47 }) else { return nil }
        self.namespace = namespace
        self.path = path
    }

    private static func namespaceCharacter(_ byte: UInt8) -> Bool {
        (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 || byte == 45 || byte == 46
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let parsed = Self(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Minecraft identifier")
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
