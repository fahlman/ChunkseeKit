import Foundation

/// A dimension type's time/sky facts, not a running clock or evaluated lighting.
public struct DimensionTime: Sendable, Equatable {
    public let hasFixedTime: Bool
    public let hasSkylight: Bool
    /// A normalized reference, or nil when the definition has no default clock.
    public let defaultClock: String?
    public let timelines: Timelines

    /// Unresolved registry references. A tag is distinct from an ordered list of timeline IDs.
    public enum Timelines: Sendable, Equatable {
        case tag(String)
        case list([String])

        private init?(single: String) {
            if single.hasPrefix("#") {
                guard let id = Identifier(String(single.dropFirst())) else { return nil }
                self = .tag(id.description)
            } else {
                guard let id = Identifier(single) else { return nil }
                self = .list([id.description])
            }
        }

        fileprivate init?(nbt: NBT) {
            if let single = nbt.string { self.init(single: single) }
            else if let values = nbt.list {
                let ids = values.compactMap { $0.string.flatMap(Identifier.init)?.description }
                guard ids.count == values.count else { return nil }
                self = .list(ids)
            } else { return nil }
        }
    }

    init?(nbt: NBT) {
        guard let sky = nbt["has_skylight"]?.bool else { return nil }
        hasSkylight = sky
        if let fixed = nbt["has_fixed_time"] {
            guard let value = fixed.bool else { return nil }
            hasFixedTime = value
        } else { hasFixedTime = false }
        if let clock = nbt["default_clock"] {
            guard let value = clock.string.flatMap(Identifier.init) else { return nil }
            defaultClock = value.description
        } else { defaultClock = nil }
        if let raw = nbt["timelines"] {
            guard let value = Timelines(nbt: raw) else { return nil }
            timelines = value
        } else { timelines = .list([]) }
    }
}

extension DimensionTime: Decodable {
    private enum Keys: String, CodingKey {
        case hasFixedTime = "has_fixed_time", hasSkylight = "has_skylight"
        case defaultClock = "default_clock", timelines
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        hasSkylight = try fields.decode(Bool.self, forKey: .hasSkylight)
        hasFixedTime = try fields.decodeIfPresent(Bool.self, forKey: .hasFixedTime) ?? false
        defaultClock = try fields.decodeIfPresent(Identifier.self, forKey: .defaultClock)?.description
        timelines = try fields.decodeIfPresent(Timelines.self, forKey: .timelines) ?? .list([])
    }
}

extension DimensionTime.Timelines: Decodable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) {
            guard let parsed = Self(single: text) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid timeline reference")
            }
            self = parsed
        } else {
            self = .list(try value.decode([Identifier].self).map(\.description))
        }
    }
}
