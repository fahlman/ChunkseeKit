import Foundation

/// The tag type IDs used by the NBT binary format.
public enum NBTTagType: UInt8, Sendable {
    case end = 0, byte, short, int, long, float, double, byteArray, string, list, compound, intArray, longArray
}

/// A decoded NBT value.
public enum NBT: Equatable, Sendable {
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray([Int8])
    case string(String)
    /// A list keeps its element type so empty lists round-trip faithfully.
    case list(NBTTagType, [NBT])
    case compound([String: NBT])
    case intArray([Int32])
    case longArray([Int64])

    public var tagType: NBTTagType {
        switch self {
        case .byte: .byte
        case .short: .short
        case .int: .int
        case .long: .long
        case .float: .float
        case .double: .double
        case .byteArray: .byteArray
        case .string: .string
        case .list: .list
        case .compound: .compound
        case .intArray: .intArray
        case .longArray: .longArray
        }
    }

    /// Builds a list, inferring the element type from the first element.
    public static func list(_ elements: [NBT]) -> NBT {
        .list(elements.first?.tagType ?? .end, elements)
    }
}

// MARK: - Convenience accessors

extension NBT {
    public subscript(key: String) -> NBT? {
        if case .compound(let c) = self { return c[key] }
        return nil
    }

    public subscript(index: Int) -> NBT? {
        if case .list(_, let l) = self, l.indices.contains(index) { return l[index] }
        return nil
    }

    /// Any integral tag widened to `Int`.
    public var int: Int? {
        switch self {
        case .byte(let v): Int(v)
        case .short(let v): Int(v)
        case .int(let v): Int(v)
        case .long(let v): Int(v)
        default: nil
        }
    }

    public var double: Double? {
        switch self {
        case .float(let v): Double(v)
        case .double(let v): v
        default: int.map(Double.init)
        }
    }

    /// NBT has no boolean type; booleans are stored as bytes.
    public var bool: Bool? { int.map { $0 != 0 } }

    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var compound: [String: NBT]? {
        if case .compound(let v) = self { return v }
        return nil
    }

    public var list: [NBT]? {
        if case .list(_, let v) = self { return v }
        return nil
    }

    public var byteArray: [Int8]? {
        if case .byteArray(let v) = self { return v }
        return nil
    }

    public var intArray: [Int32]? {
        if case .intArray(let v) = self { return v }
        return nil
    }

    public var longArray: [Int64]? {
        if case .longArray(let v) = self { return v }
        return nil
    }

    /// A UUID stored as four big-endian ints (most significant first), the format used since 1.16.
    public var uuid: UUID? {
        guard let a = intArray, a.count == 4 else { return nil }
        var bytes = [UInt8]()
        for v in a { withUnsafeBytes(of: UInt32(bitPattern: v).bigEndian) { bytes.append(contentsOf: $0) } }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - Errors

public enum NBTError: Error, Equatable {
    case unexpectedEndOfData
    case invalidTagType(UInt8)
    case invalidRootTag(UInt8)
    case negativeLength(Int32)
    case nestingTooDeep
    case invalidModifiedUTF8
}

// MARK: - Reading

extension NBT {
    /// Decodes an uncompressed, named-root NBT payload (the on-disk format).
    public static func read(_ bytes: [UInt8]) throws -> (name: String, value: NBT) {
        var reader = NBTReader(bytes: bytes)
        return try reader.readRoot()
    }

    /// Decodes an NBT file, transparently handling gzip/zlib compression (e.g. `level.dat`).
    public static func read(contentsOf url: URL) throws -> NBT {
        let raw = [UInt8](try Data(contentsOf: url))
        let bytes = Compression.looksCompressed(raw) ? try Compression.inflate(raw) : raw
        return try read(bytes).value
    }
}

struct NBTReader {
    private let bytes: [UInt8]
    private var pos = 0
    private static let maxDepth = 512

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func readRoot() throws -> (name: String, value: NBT) {
        let type = try u8()
        guard type == NBTTagType.compound.rawValue || type == NBTTagType.list.rawValue else {
            throw NBTError.invalidRootTag(type)
        }
        let name = try readString()
        return (name, try payload(NBTTagType(rawValue: type)!, depth: 0))
    }

    private mutating func payload(_ type: NBTTagType, depth: Int) throws -> NBT {
        guard depth < Self.maxDepth else { throw NBTError.nestingTooDeep }
        switch type {
        case .end: throw NBTError.invalidTagType(0)
        case .byte: return .byte(Int8(bitPattern: try u8()))
        case .short: return .short(Int16(bitPattern: try be(UInt16.self)))
        case .int: return .int(Int32(bitPattern: try be(UInt32.self)))
        case .long: return .long(Int64(bitPattern: try be(UInt64.self)))
        case .float: return .float(Float(bitPattern: try be(UInt32.self)))
        case .double: return .double(Double(bitPattern: try be(UInt64.self)))
        case .byteArray:
            let n = try length()
            try need(n)
            defer { pos += n }
            return .byteArray(bytes[pos..<pos + n].map { Int8(bitPattern: $0) })
        case .string: return .string(try readString())
        case .list:
            let rawType = try u8()
            let n = try length()
            guard let elementType = NBTTagType(rawValue: rawType) else { throw NBTError.invalidTagType(rawType) }
            if n == 0 { return .list(elementType, []) }
            guard elementType != .end else { throw NBTError.invalidTagType(0) }
            var items = [NBT]()
            items.reserveCapacity(min(n, bytes.count - pos))
            for _ in 0..<n { items.append(try payload(elementType, depth: depth + 1)) }
            return .list(elementType, items)
        case .compound:
            var dict = [String: NBT]()
            while true {
                let rawType = try u8()
                if rawType == 0 { break }
                guard let t = NBTTagType(rawValue: rawType) else { throw NBTError.invalidTagType(rawType) }
                let name = try readString()
                dict[name] = try payload(t, depth: depth + 1)
            }
            return .compound(dict)
        case .intArray:
            let n = try length()
            try need(n * 4)
            var out = [Int32](); out.reserveCapacity(n)
            for _ in 0..<n { out.append(Int32(bitPattern: try be(UInt32.self))) }
            return .intArray(out)
        case .longArray:
            let n = try length()
            try need(n * 8)
            var out = [Int64](); out.reserveCapacity(n)
            for _ in 0..<n { out.append(Int64(bitPattern: try be(UInt64.self))) }
            return .longArray(out)
        }
    }

    private func need(_ n: Int) throws {
        if n > bytes.count - pos { throw NBTError.unexpectedEndOfData }
    }

    private mutating func u8() throws -> UInt8 {
        try need(1)
        defer { pos += 1 }
        return bytes[pos]
    }

    private mutating func be<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        try need(size)
        var v: T = 0
        for i in 0..<size { v = v << 8 | T(bytes[pos + i]) }
        pos += size
        return v
    }

    private mutating func length() throws -> Int {
        let n = Int32(bitPattern: try be(UInt32.self))
        guard n >= 0 else { throw NBTError.negativeLength(n) }
        return Int(n)
    }

    private mutating func readString() throws -> String {
        let n = Int(try be(UInt16.self))
        try need(n)
        defer { pos += n }
        return try ModifiedUTF8.decode(bytes[pos..<pos + n])
    }
}

// MARK: - Writing

extension NBT {
    /// Encodes this value as an uncompressed, named-root NBT payload.
    public func serialized(rootName: String = "") -> [UInt8] {
        var out = [UInt8]()
        out.append(tagType.rawValue)
        NBT.writeString(rootName, into: &out)
        writePayload(into: &out)
        return out
    }

    private func writePayload(into out: inout [UInt8]) {
        switch self {
        case .byte(let v): out.append(UInt8(bitPattern: v))
        case .short(let v): NBT.be(UInt16(bitPattern: v), &out)
        case .int(let v): NBT.be(UInt32(bitPattern: v), &out)
        case .long(let v): NBT.be(UInt64(bitPattern: v), &out)
        case .float(let v): NBT.be(v.bitPattern, &out)
        case .double(let v): NBT.be(v.bitPattern, &out)
        case .byteArray(let v):
            NBT.be(UInt32(v.count), &out)
            out.append(contentsOf: v.map { UInt8(bitPattern: $0) })
        case .string(let v): NBT.writeString(v, into: &out)
        case .list(let type, let items):
            precondition(items.allSatisfy { $0.tagType == items[0].tagType }, "NBT lists must have a single element type")
            out.append(items.isEmpty ? type.rawValue : items[0].tagType.rawValue)
            NBT.be(UInt32(items.count), &out)
            for item in items { item.writePayload(into: &out) }
        case .compound(let dict):
            // Sorted for deterministic output.
            for key in dict.keys.sorted() {
                let value = dict[key]!
                out.append(value.tagType.rawValue)
                NBT.writeString(key, into: &out)
                value.writePayload(into: &out)
            }
            out.append(0)
        case .intArray(let v):
            NBT.be(UInt32(v.count), &out)
            for x in v { NBT.be(UInt32(bitPattern: x), &out) }
        case .longArray(let v):
            NBT.be(UInt32(v.count), &out)
            for x in v { NBT.be(UInt64(bitPattern: x), &out) }
        }
    }

    private static func be<T: FixedWidthInteger>(_ v: T, _ out: inout [UInt8]) {
        withUnsafeBytes(of: v.bigEndian) { out.append(contentsOf: $0) }
    }

    private static func writeString(_ s: String, into out: inout [UInt8]) {
        let encoded = ModifiedUTF8.encode(s)
        be(UInt16(encoded.count), &out)
        out.append(contentsOf: encoded)
    }
}

// MARK: - Modified UTF-8

/// Java's "modified UTF-8": NUL is encoded as `C0 80`, and characters outside the BMP are
/// encoded as a surrogate pair of two 3-byte sequences (CESU-8) rather than one 4-byte sequence.
enum ModifiedUTF8 {
    static func decode(_ bytes: ArraySlice<UInt8>) throws -> String {
        if bytes.allSatisfy({ $0 < 0x80 }) { return String(decoding: bytes, as: UTF8.self) }
        var units = [UInt16]()
        units.reserveCapacity(bytes.count)
        var i = bytes.startIndex
        func cont(_ at: Int) throws -> UInt16 {
            guard at < bytes.endIndex, bytes[at] & 0xC0 == 0x80 else { throw NBTError.invalidModifiedUTF8 }
            return UInt16(bytes[at] & 0x3F)
        }
        while i < bytes.endIndex {
            let b = bytes[i]
            if b < 0x80 {
                units.append(UInt16(b)); i += 1
            } else if b & 0xE0 == 0xC0 {
                units.append(UInt16(b & 0x1F) << 6 | (try cont(i + 1))); i += 2
            } else if b & 0xF0 == 0xE0 {
                units.append(UInt16(b & 0x0F) << 12 | (try cont(i + 1)) << 6 | (try cont(i + 2))); i += 3
            } else {
                throw NBTError.invalidModifiedUTF8
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func encode(_ s: String) -> [UInt8] {
        var out = [UInt8]()
        for u in s.utf16 {
            switch u {
            case 0x0001...0x007F:
                out.append(UInt8(u))
            case 0, 0x0080...0x07FF:
                out.append(0xC0 | UInt8(u >> 6)); out.append(0x80 | UInt8(u & 0x3F))
            default:
                out.append(0xE0 | UInt8(u >> 12)); out.append(0x80 | UInt8((u >> 6) & 0x3F)); out.append(0x80 | UInt8(u & 0x3F))
            }
        }
        return out
    }
}
