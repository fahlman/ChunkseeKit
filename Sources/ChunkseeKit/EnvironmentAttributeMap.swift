import Foundation

/// Each projection reads only its own attributes through the same codecs. A malformed
/// gameplay value must not hide otherwise readable visual lighting.
struct EnvironmentAttributeMap<Attribute: Hashable & RawRepresentable>: Decodable where Attribute.RawValue == String {
    private let entries: [Attribute: Entry]

    func applying<Value: LightingValue>(_ attribute: Attribute, to base: Value,
                                        overrideRange: ClosedRange<Float>? = nil) throws -> Value {
        guard let entry = entries[attribute] else { return base }
        let argument = try Value.argument(entry.argument.raw, modifier: entry.modifier, overrideRange: overrideRange)
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

    private enum RootKey: String, CodingKey { case attributes }
    private struct AttributeKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: RootKey.self)
        guard root.contains(.attributes), try !root.decodeNil(forKey: .attributes) else {
            entries = [:]; return
        }
        let fields = try root.nestedContainer(keyedBy: AttributeKey.self, forKey: .attributes)
        let keys = try Self.selected(Dictionary(uniqueKeysWithValues: fields.allKeys.map { ($0.stringValue, $0) }))
        entries = try keys.mapValues { try fields.decode(Entry.self, forKey: $0) }
    }

    private struct Entry: Decodable {
        let modifier: LightingModifier
        let argument: Argument
        private enum Key: String, CodingKey { case modifier, argument }

        init(nbt: NBT) throws {
            if nbt.compound != nil {
                guard let text = nbt["modifier"]?.string, let modifier = LightingModifier(rawValue: text),
                      let raw = nbt["argument"] else { throw InvalidLighting.data }
                self.modifier = modifier
                argument = try Argument(nbt: raw)
            } else {
                modifier = .override
                argument = try Argument(nbt: nbt)
            }
        }

        init(from decoder: any Decoder) throws {
            if let value = try? Argument(from: decoder) {
                modifier = .override
                argument = value
            } else {
                let fields = try decoder.container(keyedBy: Key.self)
                guard let modifier = LightingModifier(rawValue: try fields.decode(String.self, forKey: .modifier)) else {
                    throw InvalidLighting.data
                }
                self.modifier = modifier
                argument = try fields.decode(Argument.self, forKey: .argument)
            }
        }
    }

    /// Both encodings feed the same strict scalar, RGB and phase codecs used by timelines.
    /// Only supported primitive forms are adapted; this is not a recursive JSON/NBT bridge.
    private struct Argument: Decodable {
        let raw: Any

        init(nbt: NBT) throws {
            if let text = nbt.string { raw = text }
            else if let number = nbt.double { raw = number }
            else {
                switch nbt {
                case .list(_, let values):
                    guard values.count == 3 else { throw InvalidLighting.data }
                    let numbers = values.compactMap { $0.unwrappedListElement.double }
                    guard numbers.count == 3 else { throw InvalidLighting.data }
                    raw = numbers
                case .byteArray(let values):
                    guard values.count == 3 else { throw InvalidLighting.data }
                    raw = values.map(Double.init)
                case .intArray(let values):
                    guard values.count == 3 else { throw InvalidLighting.data }
                    raw = values.map(Double.init)
                case .longArray(let values):
                    guard values.count == 3 else { throw InvalidLighting.data }
                    raw = values.map(Double.init)
                default: throw InvalidLighting.data
                }
            }
        }

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { raw = text }
            else if let number = try? value.decode(Double.self) { raw = number }
            else {
                var values = try decoder.unkeyedContainer()
                guard values.count == 3 else { throw InvalidLighting.data }
                raw = try [values.decode(Double.self), values.decode(Double.self), values.decode(Double.self)]
            }
        }
    }
}
