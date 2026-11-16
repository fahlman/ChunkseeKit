import CryptoKit
import Foundation

/// Stable persisted identities for complete cache inputs. Compute an immutable catalog's
/// identity once at publication; retain its typed value for in-memory equality.
public enum InterpretationKey {
    /// SHA-256 of a canonical binary property list. Keyed entries are explicitly sorted;
    /// arrays retain their order, and set-valued owners must encode their own sorted elements.
    /// Scalars are enclosed and tagged, so nil, numbers and literal strings remain distinct.
    /// Encoding failures throw instead of making unrelated inputs share a fallback key.
    public static func identity(of value: some Encodable) throws -> String {
        SHA256.hash(data: try canonicalData(for: value)).map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalData(for value: some Encodable) throws -> Data {
        let input = IdentityEncoder(node: IdentityNode(path: []))
        try input.encode(value)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(input.node)
    }
}

// A property-list writer does not promise dictionary order, and its ordinary Codable nil
// representation can coincide with a literal string. Encode a typed tree of ordered arrays,
// then let Foundation own the binary format. This also encloses top-level scalar inputs.
private final class IdentityNode: Encodable {
    enum Scalar {
        case null, bool(Bool), string(String), integer(String), real(Double), data(Data)
    }
    final class Object { var values: [String: IdentityNode] = [:] }
    final class Array { var values: [IdentityNode] = [] }
    enum Storage { case scalar(Scalar), object(Object), array(Array) }
    let path: [any CodingKey]
    var storage: Storage?

    init(path: [any CodingKey]) { self.path = path }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.unkeyedContainer()
        switch storage {
        case .scalar(let scalar):
            switch scalar {
            case .null: try values.encode("null")
            case .bool(let value): try values.encode("bool"); try values.encode(value)
            case .string(let value): try values.encode("string"); try values.encode(value)
            case .integer(let value): try values.encode("integer"); try values.encode(value)
            case .real(let value):
                try values.encode("real")
                // NaN payloads and the sign of zero carry no additional cache-input meaning.
                try values.encode(value.isNaN ? Double.nan : (value == 0 ? 0 : value))
            case .data(let value): try values.encode("data"); try values.encode(value)
            }
        case .object(let object):
            try values.encode("object")
            for key in object.values.keys.sorted() {
                var entry = values.nestedUnkeyedContainer()
                try entry.encode(key)
                try entry.encode(object.values[key]!)
            }
        case .array(let array):
            try values.encode("array")
            for value in array.values { try values.encode(value) }
        case nil:
            throw EncodingError.invalidValue("unencoded value", .init(codingPath: path,
                debugDescription: "The Encodable input did not encode a value"))
        }
    }
}

private struct IdentityCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init(intValue: Int) { self.intValue = intValue; stringValue = "Index \(intValue)" }
}

private final class IdentityEncoder: Encoder {
    let node: IdentityNode
    var codingPath: [any CodingKey] { node.path }
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    init(node: IdentityNode) { self.node = node }

    func encode(_ value: some Encodable) throws {
        if let data = value as? Data { node.storage = .scalar(.data(data)) }
        else { try value.encode(to: self) }
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        if node.storage == nil { node.storage = .object(.init()) }
        guard case .object(let object) = node.storage else {
            preconditionFailure("An Encodable value requested incompatible containers")
        }
        return KeyedEncodingContainer(IdentityKeyed<Key>(owner: self, object: object))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        if node.storage == nil { node.storage = .array(.init()) }
        guard case .array(let array) = node.storage else {
            preconditionFailure("An Encodable value requested incompatible containers")
        }
        return IdentityUnkeyed(owner: self, array: array)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer { IdentitySingle(owner: self) }
}

private struct IdentityKeyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let owner: IdentityEncoder
    let object: IdentityNode.Object
    var codingPath: [any CodingKey] { owner.codingPath }

    private func child(_ key: any CodingKey) -> IdentityEncoder {
        let node = IdentityNode(path: codingPath + [key])
        object.values[key.stringValue] = node
        return IdentityEncoder(node: node)
    }

    mutating func encodeNil(forKey key: Key) throws { child(key).node.storage = .scalar(.null) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: String, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try child(key).encode(value) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try child(key).encode(value) }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type,
                                                       forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        child(key).container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        child(key).unkeyedContainer()
    }
    mutating func superEncoder() -> any Encoder { child(IdentityCodingKey(stringValue: "super")) }
    mutating func superEncoder(forKey key: Key) -> any Encoder { child(key) }
}

private struct IdentityUnkeyed: UnkeyedEncodingContainer {
    let owner: IdentityEncoder
    let array: IdentityNode.Array
    var codingPath: [any CodingKey] { owner.codingPath }
    var count: Int { array.values.count }

    private func child() -> IdentityEncoder {
        let node = IdentityNode(path: codingPath + [IdentityCodingKey(intValue: count)])
        array.values.append(node)
        return IdentityEncoder(node: node)
    }

    mutating func encodeNil() throws { child().node.storage = .scalar(.null) }
    mutating func encode<T: Encodable>(_ value: T) throws { try child().encode(value) }
    mutating func encode(_ value: Bool) throws { try child().encode(value) }
    mutating func encode(_ value: String) throws { try child().encode(value) }
    mutating func encode(_ value: Double) throws { try child().encode(value) }
    mutating func encode(_ value: Float) throws { try child().encode(value) }
    mutating func encode(_ value: Int) throws { try child().encode(value) }
    mutating func encode(_ value: Int8) throws { try child().encode(value) }
    mutating func encode(_ value: Int16) throws { try child().encode(value) }
    mutating func encode(_ value: Int32) throws { try child().encode(value) }
    mutating func encode(_ value: Int64) throws { try child().encode(value) }
    mutating func encode(_ value: UInt) throws { try child().encode(value) }
    mutating func encode(_ value: UInt8) throws { try child().encode(value) }
    mutating func encode(_ value: UInt16) throws { try child().encode(value) }
    mutating func encode(_ value: UInt32) throws { try child().encode(value) }
    mutating func encode(_ value: UInt64) throws { try child().encode(value) }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        child().container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { child().unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { child() }
}

private struct IdentitySingle: SingleValueEncodingContainer {
    let owner: IdentityEncoder
    var codingPath: [any CodingKey] { owner.codingPath }
    mutating func encodeNil() throws { owner.node.storage = .scalar(.null) }
    mutating func encode<T: Encodable>(_ value: T) throws { try owner.encode(value) }
    mutating func encode(_ value: Bool) throws { owner.node.storage = .scalar(.bool(value)) }
    mutating func encode(_ value: String) throws { owner.node.storage = .scalar(.string(value)) }
    mutating func encode(_ value: Double) throws { owner.node.storage = .scalar(.real(value)) }
    mutating func encode(_ value: Float) throws { owner.node.storage = .scalar(.real(Double(value))) }
    mutating func encode(_ value: Int) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: Int8) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: Int16) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: Int32) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: Int64) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: UInt) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: UInt8) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: UInt16) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: UInt32) throws { owner.node.storage = .scalar(.integer(String(value))) }
    mutating func encode(_ value: UInt64) throws { owner.node.storage = .scalar(.integer(String(value))) }
}
