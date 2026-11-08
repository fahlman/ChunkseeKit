import Foundation

/// Each projection reads only its own attributes through the same codecs. A malformed
/// gameplay value must not hide otherwise readable visual lighting.
struct EnvironmentAttributeMap<Attribute: Hashable & RawRepresentable> where Attribute.RawValue == String {
    private let entries: [Attribute: Entry]

    func applying<Value: LightingValue>(_ attribute: Attribute, to base: Value,
                                        overrideRange: ClosedRange<Float>? = nil) throws -> Value {
        guard let entry = entries[attribute] else { return base }
        let argument = try Value.argument(entry.argument, modifier: entry.modifier, overrideRange: overrideRange)
        return try Value.apply(entry.modifier, to: base, argument: argument)
    }

    static func selected<Value>(_ raw: [String: Value]) throws -> [Attribute: Value] {
        guard raw.count <= 256 else { throw InvalidLighting.data }
        var result: [Attribute: Value] = [:]
        for (rawID, value) in raw {
            guard let id = Identifier(rawID), let attribute = Attribute(rawValue: id.description) else { continue }
            // Conflicting aliases must not make dictionary iteration order select a value.
            guard result.updateValue(value, forKey: attribute) == nil else { throw InvalidLighting.data }
        }
        return result
    }

    init(nbt: NBT) throws {
        guard let raw = nbt["attributes"] else { entries = [:]; return }
        guard let values = raw.compound else { throw InvalidLighting.data }
        entries = try Self.selected(values).mapValues { try Entry(nbt: $0) }
    }

    init(json: [String: Any]) throws {
        guard let raw = json["attributes"], !(raw is NSNull) else { entries = [:]; return }
        entries = try Self.selected(AssetJSON.object(raw)).mapValues { try Entry(json: $0) }
    }

    private struct Entry {
        let modifier: LightingModifier
        let argument: LightingInput

        init(nbt: NBT) throws {
            if nbt.compound != nil {
                guard let text = nbt["modifier"]?.string, let modifier = LightingModifier(rawValue: text),
                      let raw = nbt["argument"] else { throw InvalidLighting.data }
                self.modifier = modifier
                argument = .nbt(raw)
            } else {
                modifier = .override
                argument = .nbt(nbt)
            }
        }

        init(json: Any) throws {
            if let fields = json as? [String: Any] {
                guard let text = fields["modifier"] as? String, let modifier = LightingModifier(rawValue: text),
                      let raw = fields["argument"] else { throw InvalidLighting.data }
                self.modifier = modifier
                argument = .json(raw)
            } else {
                modifier = .override
                argument = .json(json)
            }
        }
    }
}
