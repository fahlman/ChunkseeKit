import Foundation

/// A dimension type's time/sky facts, not a running clock or evaluated lighting.
public struct DimensionTime: Sendable, Equatable {
    public let hasFixedTime: Bool
    public let hasSkylight: Bool
    /// A normalized reference, or nil when the definition has no default clock.
    public let defaultClock: String?
    public let timelines: Timelines

    /// Unresolved registry references. A tag is distinct from an ordered list of timeline IDs.
    public typealias Timelines = RegistryReferences

    private init(hasSkylight: Bool, hasFixedTime: Bool?, defaultClock: Identifier?, timelines: Timelines?) {
        self.hasSkylight = hasSkylight
        self.hasFixedTime = hasFixedTime ?? false
        self.defaultClock = defaultClock?.description
        self.timelines = timelines ?? .list([])
    }

    /// An absent optional field gets the shared default; a malformed present field invalidates time.
    private static func optional<Field, Value>(_ field: Field?, read: (Field) -> Value?) throws -> Value? {
        guard let field else { return nil }
        guard let value = read(field) else { throw AssetReadError.invalidData }
        return value
    }

    init?(nbt: NBT) {
        guard let sky = nbt["has_skylight"]?.bool else { return nil }
        do {
            try self.init(hasSkylight: sky,
                          hasFixedTime: Self.optional(nbt["has_fixed_time"], read: { $0.bool }),
                          defaultClock: Self.optional(nbt["default_clock"], read: { $0.string.flatMap(Identifier.init) }),
                          timelines: Self.optional(nbt["timelines"], read: Timelines.init(nbt:)))
        } catch { return nil }
    }

    init?(json: [String: Any]) {
        let fields = json.filter { !($0.value is NSNull) }
        guard let sky = try? AssetJSON.boolean(fields["has_skylight"]) else { return nil }
        do {
            try self.init(hasSkylight: sky,
                          hasFixedTime: Self.optional(fields["has_fixed_time"], read: { try? AssetJSON.boolean($0) }),
                          defaultClock: Self.optional(fields["default_clock"], read: { ($0 as? String).flatMap(Identifier.init) }),
                          timelines: Self.optional(fields["timelines"], read: Timelines.init(json:)))
        } catch { return nil }
    }
}

extension DimensionTime: Decodable {
    private enum Keys: String, CodingKey {
        case hasFixedTime = "has_fixed_time", hasSkylight = "has_skylight"
        case defaultClock = "default_clock", timelines
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        try self.init(hasSkylight: fields.decode(Bool.self, forKey: .hasSkylight),
                      hasFixedTime: fields.decodeIfPresent(Bool.self, forKey: .hasFixedTime),
                      defaultClock: fields.decodeIfPresent(Identifier.self, forKey: .defaultClock),
                      timelines: fields.decodeIfPresent(Timelines.self, forKey: .timelines))
    }
}
