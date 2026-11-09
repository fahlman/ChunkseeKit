import Foundation

/// Preserve numeric spelling until the resource codec chooses its Java primitive. The UTF-8
/// game path builds that tree directly; Foundation still decodes escaped Unicode strings.
extension AssetJSON {
    struct Number {
        let literal: String

        /// Gson LazilyParsedNumber.intValue truncates decimal fractions and keeps the low
        /// 32 bits. A floating-point conversion would lose integer digits before narrowing.
        var int32: Int32? {
            guard let value = decimal else { return nil }
            let digits = value.digits.dropLast(max(0, min(value.scale, value.digits.count)))
            var magnitude: UInt32 = 0
            for digit in digits.utf8 { magnitude = magnitude &* 10 &+ UInt32(digit - 48) }
            if value.scale < 0 {
                // Each decimal zero supplies a factor of two; no low bits survive 32 zeros.
                guard -value.scale < UInt32.bitWidth else { return 0 }
                for _ in 0..<(-value.scale) { magnitude = magnitude &* 10 }
            }
            return Int32(bitPattern: value.negative ? 0 &- magnitude : magnitude)
        }

        /// JsonOps.convertTo first tries BigDecimal.longValueExact, then an exact Float,
        /// then Double. This is distinct from a typed INT or FLOAT resource field.
        var argument: TextComponent.Argument? {
            guard let value = decimal else { return nil }
            if value.digits.isEmpty { return .integer(0) }
            if value.scale <= 0, value.digits.count - value.scale <= 19,
               let integer = Int64((value.negative ? "-" : "") + value.digits + String(repeating: "0", count: -value.scale)) {
                return .integer(integer)
            }
            guard let number = Double(literal) else { return nil }
            let float = Float(number)
            return Double(float) == number ? .float(float) : .number(number)
        }

        /// Exact decimal coefficient/scale under Gson NumberLimits, normalized without
        /// rounding. Conversion limits do not apply to a language value kept as text.
        private var decimal: (negative: Bool, digits: Substring, scale: Int)? {
            guard literal.utf8.count <= 10_000 else { return nil }
            let negative = literal.first == "-"
            let unsigned = negative ? literal.dropFirst() : literal[...]
            let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
            guard let exponent = parts.count == 2 ? Int(parts[1]) : 0,
                  (-10_000...20_000).contains(exponent) else { return nil }
            let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            var scale = (mantissa.count == 2 ? mantissa[1].count : 0) - exponent
            guard abs(scale) < 10_000 else { return nil }
            let digits = mantissa.joined()
            var significant = digits[...]
            while significant.first == "0" { significant.removeFirst() }
            while significant.last == "0" { significant.removeLast(); scale -= 1 }
            return (negative, significant, scale)
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: normalized(data))
    }

    /// Every reader receives the same exact number tokens. Existing document readers keep
    /// their syntax bounds; resource codecs additionally enforce JsonReader's token limits.
    static func value(from data: Data, limitsNumbers: Bool = true) throws -> Any {
        if data.prefix(4).contains(0) || data.first == 0xFF || data.first == 0xFE {
            // Keep the Unicode encodings Foundation previously accepted, while selecting
            // duplicate decoded names through the same parser as UTF-8 game files.
            for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
                if let text = String(data: data, encoding: encoding),
                   let result = try? parse(Data(text.utf8), limitsNumbers: limitsNumbers) { return result }
            }
            throw AssetReadError.invalidData
        }
        return try parse(data, limitsNumbers: limitsNumbers)
    }

    /// UnflattenTextComponentFix uses LenientJsonParser, not the resource JSON reader.
    /// Its syntax is confined to the historical saved-text boundary; installed resources
    /// and public JSON components retain their existing syntax and number limits.
    static func legacyTextValue(from data: Data) throws -> Any {
        try parse(data, limitsNumbers: true, lenient: true)
    }

    private static func parse(_ data: Data, limitsNumbers: Bool, lenient: Bool = false) throws -> Any {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self), limitsNumbers: limitsNumbers, lenient: lenient)
            return try parser.read()
        }
    }

    private enum JSONOutput { case value(Any), byte(UInt8) }

    /// Re-encode the selected tree without rounding numbers. An explicit stack keeps ignored
    /// deeply nested metadata safe on the same small worker stacks as the parser.
    private static func normalized(_ data: Data) throws -> Data {
        try encoded(try value(from: data, limitsNumbers: false))
    }

    /// LegacyComponentDataFixUtils rewrites lenient sign/book JSON to GsonHelper's stable
    /// spelling before unflattening. That spelling is observable when NBT conversion fails.
    static func legacyTextData(_ value: Any) throws -> Data {
        try encoded(value, legacy: true)
    }

    private static func encoded(_ value: Any, legacy: Bool = false) throws -> Data {
        var pending: [JSONOutput] = [.value(value)]
        var output = Data()
        while let next = pending.popLast() {
            switch next {
            case let .byte(byte): output.append(byte)
            case let .value(value):
                if let number = value as? Number { output.append(contentsOf: number.literal.utf8) }
                else if let object = value as? [String: Any] {
                    output.append(123); pending.append(.byte(125))
                    let keys = legacy ? object.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) } : object.keys.sorted()
                    for (index, key) in keys.enumerated().reversed() {
                        pending.append(.value(object[key]!))
                        pending.append(.byte(58)); pending.append(.value(key))
                        if index > 0 { pending.append(.byte(44)) }
                    }
                } else if let values = value as? [Any] {
                    output.append(91); pending.append(.byte(93))
                    for (index, value) in values.enumerated().reversed() {
                        pending.append(.value(value))
                        if index > 0 { pending.append(.byte(44)) }
                    }
                } else if legacy, let text = value as? String {
                    output.append(34)
                    for scalar in text.unicodeScalars {
                        let escape: String?
                        switch scalar.value {
                        case 34: escape = "\\\""
                        case 92: escape = "\\\\"
                        case 8: escape = "\\b"
                        case 9: escape = "\\t"
                        case 10: escape = "\\n"
                        case 12: escape = "\\f"
                        case 13: escape = "\\r"
                        case 0..<32, 0x2028, 0x2029: escape = String(format: "\\u%04x", scalar.value)
                        default: escape = nil
                        }
                        output.append(contentsOf: (escape ?? String(scalar)).utf8)
                    }
                    output.append(34)
                } else {
                    output.append(try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
                }
            }
        }
        return output
    }

    /// The borrowed buffer never escapes `withUnsafeBytes`; strings and number tokens copy
    /// their own bytes before the parsed value leaves it.
    private struct Parser {
        let bytes: UnsafeBufferPointer<UInt8>
        let limitsNumbers: Bool
        let lenient: Bool
        var cursor = 0

        private struct Container {
            let closing: UInt8
            var fields: [String: Any] = [:]
            var elements: [Any] = []
            var key: String?
            var value: Any { closing == 125 ? fields : elements }
        }

        mutating func read() throws -> Any {
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { cursor = 3 }
            if lenient {
                try whitespace()
                // Gson consumes this non-executable prefix only at the start of a document.
                let prefix: [UInt8] = [41, 93, 125, 39, 10]
                if bytes.count - cursor >= prefix.count,
                   bytes[cursor..<(cursor + prefix.count)].elementsEqual(prefix) { cursor += prefix.count }
            }
            // A bounded explicit stack also supports Foundation's deepest accepted inputs
            // on Swift concurrency workers, whose call stacks are much smaller than main's.
            var containers: [Container] = []
            var result: Any?
            while true {
                if let ready = result {
                    guard !containers.isEmpty else {
                        try whitespace()
                        guard cursor == bytes.count else { throw AssetReadError.invalidData }
                        return ready
                    }
                    let index = containers.count - 1, closing = containers[index].closing
                    if closing == 125 {
                        let key = containers[index].key!
                        // Gson's object builder replaces an earlier member with the same
                        // decoded name. Every losing value was still fully parsed above.
                        containers[index].fields[key] = ready
                    } else { containers[index].elements.append(ready) }
                    try whitespace()
                    if consume(closing) { result = containers.removeLast().value }
                    else {
                        guard consume(44) || (lenient && consume(59)) else { throw AssetReadError.invalidData }
                        try whitespace()
                        // Foundation permits a trailing comma; preserve its current syntax.
                        if !lenient && consume(closing) { result = containers.removeLast().value }
                        else {
                            if closing == 125 { containers[index].key = try key() }
                            result = nil
                        }
                    }
                } else {
                    try whitespace()
                    guard cursor < bytes.count else { throw AssetReadError.invalidData }
                    // Gson supplies null for an omitted array member, including a trailing
                    // comma. The later JsonOps-to-NBT conversion decides whether it is valid.
                    if lenient, containers.last?.closing == 93, [44, 59, 93].contains(bytes[cursor]) {
                        result = NSNull()
                        continue
                    }
                    if bytes[cursor] == 123 || bytes[cursor] == 91 {
                        guard containers.count < 512 else { throw AssetReadError.invalidData }
                        let closing: UInt8 = bytes[cursor] == 123 ? 125 : 93
                        cursor += 1
                        try whitespace()
                        var container = Container(closing: closing)
                        if consume(closing) { result = container.value }
                        else {
                            if closing == 125 { container.key = try key() }
                            containers.append(container)
                        }
                    } else { result = try scalar() }
                }
            }
        }

        private mutating func whitespace() throws {
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 9, 10, 13, 32: cursor += 1
                case 35 where lenient:
                    skipLine()
                case 47 where lenient && cursor + 1 < bytes.count:
                    if bytes[cursor + 1] == 47 { skipLine() }
                    else if bytes[cursor + 1] == 42 {
                        cursor += 2
                        while cursor + 1 < bytes.count && !(bytes[cursor] == 42 && bytes[cursor + 1] == 47) { cursor += 1 }
                        guard cursor + 1 < bytes.count else { throw AssetReadError.invalidData }
                        cursor += 2
                    } else { return }
                default: return
                }
            }
        }

        private mutating func skipLine() {
            while cursor < bytes.count && bytes[cursor] != 10 && bytes[cursor] != 13 { cursor += 1 }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard cursor < bytes.count, bytes[cursor] == byte else { return false }
            cursor += 1
            return true
        }

        private mutating func key() throws -> String {
            guard cursor < bytes.count else { throw AssetReadError.invalidData }
            let key: String
            if bytes[cursor] == 34 || (lenient && bytes[cursor] == 39) { key = try string() }
            else if lenient { key = try unquoted() }
            else { throw AssetReadError.invalidData }
            try whitespace()
            if !consume(58) {
                guard lenient && consume(61) else { throw AssetReadError.invalidData }
                _ = consume(62)
            }
            return key
        }

        private mutating func scalar() throws -> Any {
            if lenient {
                if bytes[cursor] == 34 || bytes[cursor] == 39 { return try string() }
                let word = try unquoted()
                switch word.lowercased() {
                case "true": return true
                case "false": return false
                case "null": return NSNull()
                default:
                    // JsonReader returns an unquoted string when peekNumber rejects the
                    // spelling or its buffer limit. Reuse the exact resource token owner.
                    let token = Array(word.utf8)
                    if let end = try? AssetJSON.endOfNumber(token, from: 0, limitsNumbers: true), end == token.count {
                        return Number(literal: word)
                    }
                    return word
                }
            }
            switch bytes[cursor] {
            case 34: return try string()
            case 116:
                try literal("true")
                return true
            case 102:
                try literal("false")
                return false
            case 110: try literal("null"); return NSNull()
            case 45, 48...57:
                let start = cursor
                cursor = try AssetJSON.endOfNumber(bytes, from: start, limitsNumbers: limitsNumbers)
                return Number(literal: String(decoding: bytes[start..<cursor], as: UTF8.self))
            default: throw AssetReadError.invalidData
            }
        }

        private mutating func literal(_ text: StaticString) throws {
            let matches = text.withUTF8Buffer { literal in
                bytes.count - cursor >= literal.count &&
                    bytes[cursor..<(cursor + literal.count)].elementsEqual(literal)
            }
            guard matches else { throw AssetReadError.invalidData }
            cursor += text.utf8CodeUnitCount
        }

        private mutating func string() throws -> String {
            if lenient { return try lenientString() }
            let start = cursor
            cursor += 1
            var escaped = false
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 34:
                    let end = cursor
                    cursor += 1
                    if escaped {
                        let data = Data(bytes[start..<cursor])
                        guard let text = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
                            throw AssetReadError.invalidData
                        }
                        return text
                    }
                    guard let text = String(bytes: bytes[(start + 1)..<end], encoding: .utf8) else {
                        throw AssetReadError.invalidData
                    }
                    return text
                case 92: escaped = true; cursor += 2
                case 0..<32: throw AssetReadError.invalidData
                default: cursor += 1
                }
            }
            throw AssetReadError.invalidData
        }

        private mutating func unquoted() throws -> String {
            let start = cursor
            // JsonReader.isLiteral: form feed delimits a token but is not whitespace.
            while cursor < bytes.count && ![9, 10, 12, 13, 32, 35, 44, 47, 58, 59, 61, 91, 92, 93, 123, 125].contains(bytes[cursor]) {
                cursor += 1
            }
            guard cursor > start, let value = String(bytes: bytes[start..<cursor], encoding: .utf8) else {
                throw AssetReadError.invalidData
            }
            return value
        }

        private mutating func lenientString() throws -> String {
            let quote = bytes[cursor]
            cursor += 1
            var start = cursor
            var units: [UInt16] = []
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if byte == quote || byte == 92 {
                    guard let segment = String(bytes: bytes[start..<cursor], encoding: .utf8) else {
                        throw AssetReadError.invalidData
                    }
                    units.append(contentsOf: segment.utf16)
                    cursor += 1
                    if byte == quote { return String(decoding: units, as: UTF16.self) }
                    guard cursor < bytes.count else { throw AssetReadError.invalidData }
                    let escape = bytes[cursor]
                    cursor += 1
                    switch escape {
                    case 10, 34, 39, 47, 92: units.append(UInt16(escape))
                    case 98: units.append(8)
                    case 102: units.append(12)
                    case 110: units.append(10)
                    case 114: units.append(13)
                    case 116: units.append(9)
                    case 117:
                        guard bytes.count - cursor >= 4,
                              bytes[cursor..<(cursor + 4)].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                              let unit = UInt16(String(decoding: bytes[cursor..<(cursor + 4)], as: UTF8.self), radix: 16) else {
                            throw AssetReadError.invalidData
                        }
                        units.append(unit)
                        cursor += 4
                    default: throw AssetReadError.invalidData
                    }
                    start = cursor
                } else { cursor += 1 }
            }
            throw AssetReadError.invalidData
        }
    }

    private static func digit(_ value: UInt8) -> Bool { (48...57).contains(value) }

    /// Resource readers add StrictJsonParser's token limits; existing document syntax remains
    /// unchanged. Both paths validate spelling and retain the same Number representation.
    private static func endOfNumber<Bytes: RandomAccessCollection>(_ bytes: Bytes, from start: Int, limitsNumbers: Bool) throws -> Int
        where Bytes.Element == UInt8, Bytes.Index == Int {
        var cursor = start
        if bytes[cursor] == 45 { cursor += 1 }
        guard cursor < bytes.count, digit(bytes[cursor]) else { throw AssetReadError.invalidData }
        if bytes[cursor] == 48 { cursor += 1 }
        else {
            // Gson JsonReader.peekNumber keeps a wrapped long accumulator even after
            // overflow. Its zero check rejects a following integer digit in that case too.
            var integer: UInt64 = 0
            let firstDigit = cursor
            while cursor < bytes.count, digit(bytes[cursor]) {
                guard !limitsNumbers || cursor == firstDigit || integer != 0 else { throw AssetReadError.invalidData }
                integer = integer &* 10 &+ UInt64(bytes[cursor] - 48)
                cursor += 1
            }
        }
        if cursor < bytes.count, bytes[cursor] == 46 {
            cursor += 1
            let fraction = cursor
            while cursor < bytes.count, digit(bytes[cursor]) { cursor += 1 }
            guard cursor > fraction else { throw AssetReadError.invalidData }
        }
        if cursor < bytes.count, bytes[cursor] == 69 || bytes[cursor] == 101 {
            cursor += 1
            if cursor < bytes.count, bytes[cursor] == 43 || bytes[cursor] == 45 { cursor += 1 }
            let exponent = cursor
            while cursor < bytes.count, digit(bytes[cursor]) { cursor += 1 }
            guard cursor > exponent else { throw AssetReadError.invalidData }
        }
        // StrictJsonParser cannot read a number that fills JsonReader's 1,024-character buffer.
        guard !limitsNumbers || cursor - start < 1024 else { throw AssetReadError.invalidData }
        var next = cursor
        while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        guard next == bytes.count || [44, 93, 125].contains(bytes[next]) else { throw AssetReadError.invalidData }
        return cursor
    }

}
