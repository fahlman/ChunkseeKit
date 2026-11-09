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

    /// ListTag's 26.3 on-disk mixed-list wrapper is exactly one empty-name entry.
    /// Use only for list elements, and unwrap once. Raw NBT stays intact for round-tripping.
    var unwrappedListElement: NBT {
        guard let fields = compound, fields.count == 1, let value = fields[""] else { return self }
        return value
    }

    /// Represent a logical ListTag using the same homogeneous on-disk wrapper convention
    /// as mixed saved lists. A compound that itself looks like a wrapper needs another layer
    /// so a single unwrapping operation preserves that compound's identity.
    static func listPreservingTypes(_ values: [NBT]) -> NBT {
        let type = values.first?.tagType ?? .end
        let mixed = values.contains { $0.tagType != type }
        let wrappedCompound = values.contains { $0.compound?.count == 1 && $0[""] != nil }
        guard mixed || wrappedCompound else { return .list(type, values) }
        return .list(.compound, values.map { value in
            if let fields = value.compound, !(fields.count == 1 && fields[""] != nil) { return value }
            return .compound(["": value])
        })
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

    /// A UUID string, four big-endian ints, or an entity/modifier compound containing `UUID`
    /// or the legacy `UUIDMost`/`UUIDLeast` pair. All forms produce the same UUID identity.
    public var uuid: UUID? {
        if case .string(let value) = self { return UUID(uuidString: value) }
        if case .compound(let fields) = self {
            if let direct = fields["UUID"]?.uuid { return direct }
            guard case .long(let most)? = fields["UUIDMost"], case .long(let least)? = fields["UUIDLeast"] else { return nil }
            return NBT.intArray([Int32(truncatingIfNeeded: most >> 32), Int32(truncatingIfNeeded: most),
                                 Int32(truncatingIfNeeded: least >> 32), Int32(truncatingIfNeeded: least)]).uuid
        }
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
        try read(bytes, skipping: [])
    }

    /// Decodes NBT, leaving out compound entries whose name is in `skipping`, at any depth. Skipped
    /// entries are stepped over without building values, which is much faster when a caller needs
    /// only part of a large payload (for example, terrain without block ticks or light).
    public static func read(_ bytes: [UInt8], skipping: Set<String>) throws -> (name: String, value: NBT) {
        try bytes.withUnsafeBytes { buffer in
            var reader = NBTReader(bytes: buffer, skipping: skipping)
            return try reader.readRoot()
        }
    }

    /// Decodes an NBT file, transparently handling gzip/zlib compression (e.g. `level.dat`).
    public static func read(contentsOf url: URL) throws -> NBT {
        let raw = [UInt8](try Data(contentsOf: url))
        let bytes = Compression.looksCompressed(raw) ? try Compression.inflate(raw) : raw
        return try read(bytes).value
    }
}

/// Reads NBT from a raw buffer. Numbers are loaded big-endian straight from memory and arrays are
/// decoded in bulk: chunk payloads are mostly long and byte arrays, so per-byte reads dominated
/// parsing. Every read is bounds-checked against the buffer before it happens.
struct NBTReader {
    private let bytes: UnsafeRawBufferPointer
    private let skipping: Set<String>
    private let recursionLimit: Int
    private var pos = 0
    private static let maxDepth = 512

    init(bytes: UnsafeRawBufferPointer, skipping: Set<String> = [], recursionLimit: Int = 64) {
        precondition((0...Self.maxDepth).contains(recursionLimit))
        self.bytes = bytes
        self.skipping = skipping
        self.recursionLimit = recursionLimit
    }

    mutating func readRoot() throws -> (name: String, value: NBT) {
        let type = try u8()
        guard type == NBTTagType.compound.rawValue || type == NBTTagType.list.rawValue else {
            throw NBTError.invalidRootTag(type)
        }
        let name = try readString()
        return (name, try payload(NBTTagType(rawValue: type)!, depth: 0))
    }

    private struct Container {
        enum Kind { case root, list(NBTTagType), compound }
        let kind: Kind
        var items: [NBT] = []
        var remaining = 0
        var fields: [String: NBT] = [:]
        var name = ""
    }

    private mutating func payload(_ type: NBTTagType, depth: Int) throws -> NBT {
        try checkDepth(depth)
        // Ordinary chunks keep the shallow traversal's cost. The fixed handoff bounds
        // native stack use even when a valid save contains hundreds of nested passengers.
        if depth >= recursionLimit { return try iterativePayload(type, depth: depth) }
        switch type {
        case .list:
            let (elementType, count) = try listHeader()
            var items: [NBT] = []
            items.reserveCapacity(min(count, bytes.count - pos))
            for _ in 0..<count { items.append(try payload(elementType, depth: depth + 1)) }
            return .list(elementType, items)
        case .compound:
            var fields: [String: NBT] = [:]
            while let entry = try compoundEntry(depth: depth + 1) {
                fields[entry.name] = try payload(entry.type, depth: depth + 1)
            }
            return .compound(fields)
        default: return try scalar(type)
        }
    }

    private mutating func iterativePayload(_ rootType: NBTTagType, depth: Int) throws -> NBT {
        // Only suspended parents live in the stack. The active collection stays local so
        // appending a child does not repeatedly access and retain the stack's last element.
        var parents: [Container] = [], current = Container(kind: .root), type = rootType
        nextPayload: while true {
            try checkDepth(depth + parents.count)
            var value: NBT
            switch type {
            case .list:
                let (elementType, n) = try listHeader()
                if n == 0 { value = .list(elementType, []); break }
                parents.append(current)
                current = Container(kind: .list(elementType), remaining: n)
                current.items.reserveCapacity(min(n, bytes.count - pos))
                type = elementType
                continue
            case .compound:
                if let entry = try compoundEntry(depth: depth + parents.count + 1) {
                    parents.append(current)
                    current = Container(kind: .compound, name: entry.name)
                    type = entry.type
                    continue
                }
                value = .compound([:])
            default: value = try scalar(type)
            }
            while true {
                switch current.kind {
                case .root: return value
                case .list(let elementType):
                    current.items.append(value)
                    current.remaining -= 1
                    if current.remaining > 0 {
                        type = elementType
                        continue nextPayload
                    }
                    value = .list(elementType, current.items)
                case .compound:
                    current.fields[current.name] = value
                    if let entry = try compoundEntry(depth: depth + parents.count) {
                        current.name = entry.name
                        type = entry.type
                        continue nextPayload
                    }
                    value = .compound(current.fields)
                }
                current = parents.removeLast()
            }
        }
    }

    private func checkDepth(_ depth: Int) throws {
        guard depth < Self.maxDepth else { throw NBTError.nestingTooDeep }
    }

    // Both traversals share decoding without adding a call for every shallow scalar.
    @inline(__always) private mutating func scalar(_ type: NBTTagType) throws -> NBT {
        switch type {
        case .end: throw NBTError.invalidTagType(0)
        case .byte: return .byte(Int8(bitPattern: try u8()))
        case .short: return .short(Int16(bitPattern: try be(UInt16.self)))
        case .int: return .int(Int32(bitPattern: try be(UInt32.self)))
        case .long: return .long(Int64(bitPattern: try be(UInt64.self)))
        case .float: return .float(Float(bitPattern: try be(UInt32.self)))
        case .double: return .double(Double(bitPattern: try be(UInt64.self)))
        case .string: return .string(try readString())
        case .byteArray:
            let n = try length(), start = pos
            try advance(n)
            return .byteArray([Int8](unsafeUninitializedCapacity: n) { buffer, count in
                if n > 0 { UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[start..<start + n])) }
                count = n
            })
        case .intArray:
            let n = try length(), start = pos
            try advance(n * 4)
            return .intArray([Int32](unsafeUninitializedCapacity: n) { buffer, count in
                for i in 0..<n {
                    buffer[i] = Int32(bitPattern: UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: start + i * 4, as: UInt32.self)))
                }
                count = n
            })
        case .longArray:
            let n = try length(), start = pos
            try advance(n * 8)
            return .longArray([Int64](unsafeUninitializedCapacity: n) { buffer, count in
                for i in 0..<n {
                    buffer[i] = Int64(bitPattern: UInt64(bigEndian: bytes.loadUnaligned(fromByteOffset: start + i * 8, as: UInt64.self)))
                }
                count = n
            })
        case .list, .compound: preconditionFailure("Containers are handled by the traversal")
        }
    }

    private mutating func listHeader(skipped: Bool = false) throws -> (NBTTagType, Int) {
        let rawType = try u8(), count = try length()
        // An unused type byte on an empty skipped list has always been tolerated.
        if skipped, count == 0 { return (.end, 0) }
        guard let type = NBTTagType(rawValue: rawType), count == 0 || type != .end else {
            throw NBTError.invalidTagType(rawType)
        }
        return (type, count)
    }

    private mutating func compoundEntry(depth: Int) throws -> (type: NBTTagType, name: String)? {
        while true {
            let rawType = try u8()
            guard rawType != 0 else { return nil }
            guard let type = NBTTagType(rawValue: rawType) else { throw NBTError.invalidTagType(rawType) }
            let name = try readString()
            if !skipping.isEmpty, skipping.contains(name) { try skip(type, depth: depth) }
            else { return (type, name) }
        }
    }

    /// Skipped values need only structure and byte bounds, not decoded collections or names.
    private mutating func skip(_ rootType: NBTTagType, depth: Int) throws {
        try checkDepth(depth)
        if depth >= recursionLimit { return try iterativeSkip(rootType, depth: depth) }
        switch rootType {
        case .list:
            let (elementType, count) = try listHeader(skipped: true)
            for _ in 0..<count { try skip(elementType, depth: depth + 1) }
        case .compound:
            while let type = try skippedCompoundEntry() { try skip(type, depth: depth + 1) }
        default: try skipScalar(rootType)
        }
    }

    private mutating func iterativeSkip(_ rootType: NBTTagType, depth: Int) throws {
        struct Frame {
            let kind: Container.Kind
            var remaining = 0
        }
        var parents: [Frame] = [], current = Frame(kind: .root), type = rootType
        nextPayload: while true {
            try checkDepth(depth + parents.count)
            switch type {
            case .list:
                let (elementType, n) = try listHeader(skipped: true)
                if n == 0 { break }
                parents.append(current)
                current = Frame(kind: .list(elementType), remaining: n)
                type = elementType
                continue
            case .compound:
                if let entry = try skippedCompoundEntry() {
                    parents.append(current)
                    current = Frame(kind: .compound)
                    type = entry
                    continue
                }
            default: try skipScalar(type)
            }
            while true {
                switch current.kind {
                case .root: return
                case .list(let elementType):
                    current.remaining -= 1
                    if current.remaining > 0 {
                        type = elementType
                        continue nextPayload
                    }
                case .compound:
                    if let entry = try skippedCompoundEntry() {
                        type = entry
                        continue nextPayload
                    }
                }
                current = parents.removeLast()
            }
        }
    }

    @inline(__always) private mutating func skipScalar(_ type: NBTTagType) throws {
        switch type {
        case .end: throw NBTError.invalidTagType(0)
        case .byte: try advance(1)
        case .short: try advance(2)
        case .int, .float: try advance(4)
        case .long, .double: try advance(8)
        case .byteArray: try advance(try length())
        case .intArray: try advance(try length() * 4)
        case .longArray: try advance(try length() * 8)
        case .string: try advance(Int(try be(UInt16.self)))
        case .list, .compound: preconditionFailure("Containers are handled by the traversal")
        }
    }

    private mutating func skippedCompoundEntry() throws -> NBTTagType? {
        let rawType = try u8()
        guard rawType != 0 else { return nil }
        guard let type = NBTTagType(rawValue: rawType) else { throw NBTError.invalidTagType(rawType) }
        try advance(Int(try be(UInt16.self)))
        return type
    }

    private mutating func advance(_ n: Int) throws {
        try need(n)
        pos += n
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
        defer { pos += size }
        return T(bigEndian: bytes.loadUnaligned(fromByteOffset: pos, as: T.self))
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
        let raw = UnsafeRawBufferPointer(rebasing: bytes[pos..<pos + n])
        // Keys and IDs are almost always ASCII, which is the same in modified UTF-8 and UTF-8.
        if !raw.contains(where: { $0 >= 0x80 }) { return String(decoding: raw, as: UTF8.self) }
        return try ModifiedUTF8.decode(Array(raw)[...])
    }
}

// MARK: - Codable

/// Encoded as binary NBT, so values survive exactly, including tag and list types. NBT's root must
/// be a compound, so the value is stored as its only entry.
extension NBT: Codable {
    public init(from decoder: any Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        guard let value = try NBT.read([UInt8](data), skipping: []).value["v"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No NBT value"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Data(NBT.compound(["v": self]).serialized()))
    }
}

// MARK: - Writing

extension NBT {
    /// Encodes this value as an uncompressed, named-root NBT payload.
    /// Traversal uses an explicit stack rather than recursive calls and imposes no fixed depth
    /// limit. The reader independently rejects tag depth 512 or greater (the root is depth zero).
    public func serialized(rootName: String = "") -> [UInt8] {
        var out = [UInt8]()
        out.append(tagType.rawValue)
        NBT.writeString(rootName, into: &out)
        writePayload(into: &out)
        return out
    }

    private enum WriteFrame {
        case value(NBT)
        case list(Array<NBT>.Iterator)
        case compound([String: NBT], Array<String>.Iterator)
    }

    private func writePayload(into out: inout [UInt8]) {
        // Retain one continuation per enclosing container, not one frame per remaining child.
        var pending = [WriteFrame.value(self)]
        while let frame = pending.popLast() {
            switch frame {
            case .list(var items):
                guard let item = items.next() else { continue }
                pending.append(.list(items))
                pending.append(.value(item))
            case .compound(let values, var keys):
                guard let key = keys.next() else { out.append(0); continue }
                let value = values[key]!
                out.append(value.tagType.rawValue)
                NBT.writeString(key, into: &out)
                pending.append(.compound(values, keys))
                pending.append(.value(value))
            case .value(let value):
                switch value {
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
                    pending.append(.list(items.makeIterator()))
                case .compound(let values):
                    // Sorting preserves the writer's deterministic compound order.
                    pending.append(.compound(values, values.keys.sorted().makeIterator()))
                case .intArray(let v):
                    NBT.be(UInt32(v.count), &out)
                    for x in v { NBT.be(UInt32(bitPattern: x), &out) }
                case .longArray(let v):
                    NBT.be(UInt32(v.count), &out)
                    for x in v { NBT.be(UInt64(bitPattern: x), &out) }
                }
            }
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
