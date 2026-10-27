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
        /// rounding. The parser already bounds number tokens before any codec reads them.
        private var decimal: (negative: Bool, digits: Substring, scale: Int)? {
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

    static func value(from data: Data) throws -> Any {
        try value(from: data, limitsNumbers: true)
    }

    /// Existing Foundation-backed fields keep their numeric conversion and validation. Only
    /// decoded member selection is shared with the game-number path before Foundation reads it.
    static func foundationValue(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: normalized(data), options: [.fragmentsAllowed])
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: normalized(data))
    }

    private static func value(from data: Data, limitsNumbers: Bool) throws -> Any {
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

    private static func parse(_ data: Data, limitsNumbers: Bool) throws -> Any {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self), limitsNumbers: limitsNumbers)
            return try parser.read()
        }
    }

    private enum JSONOutput { case value(Any), byte(UInt8) }

    /// Re-encode the selected tree without rounding numbers. An explicit stack keeps ignored
    /// deeply nested metadata safe on the same small worker stacks as the parser.
    private static func normalized(_ data: Data) throws -> Data {
        var pending: [JSONOutput] = [.value(try value(from: data, limitsNumbers: false))]
        var output = Data()
        while let next = pending.popLast() {
            switch next {
            case let .byte(byte): output.append(byte)
            case let .value(value):
                if let number = value as? Number { output.append(contentsOf: number.literal.utf8) }
                else if let object = value as? [String: Any] {
                    output.append(123); pending.append(.byte(125))
                    for (index, key) in object.keys.sorted().enumerated().reversed() {
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
            // A bounded explicit stack also supports Foundation's deepest accepted inputs
            // on Swift concurrency workers, whose call stacks are much smaller than main's.
            var containers: [Container] = []
            var result: Any?
            while true {
                if let ready = result {
                    guard !containers.isEmpty else {
                        whitespace()
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
                    whitespace()
                    if consume(closing) { result = containers.removeLast().value }
                    else {
                        guard consume(44) else { throw AssetReadError.invalidData }
                        whitespace()
                        // Foundation permits a trailing comma; preserve its current syntax.
                        if consume(closing) { result = containers.removeLast().value }
                        else {
                            if closing == 125 { containers[index].key = try key() }
                            result = nil
                        }
                    }
                } else {
                    whitespace()
                    guard cursor < bytes.count else { throw AssetReadError.invalidData }
                    if bytes[cursor] == 123 || bytes[cursor] == 91 {
                        guard containers.count < 512 else { throw AssetReadError.invalidData }
                        let closing: UInt8 = bytes[cursor] == 123 ? 125 : 93
                        cursor += 1
                        whitespace()
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

        private mutating func whitespace() {
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 9, 10, 13, 32: cursor += 1
                default: return
                }
            }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard cursor < bytes.count, bytes[cursor] == byte else { return false }
            cursor += 1
            return true
        }

        private mutating func key() throws -> String {
            guard cursor < bytes.count, bytes[cursor] == 34 else { throw AssetReadError.invalidData }
            let key = try string()
            whitespace()
            guard consume(58) else { throw AssetReadError.invalidData }
            return key
        }

        private mutating func scalar() throws -> Any {
            switch bytes[cursor] {
            case 34: return try string()
            case 116: try literal("true"); return true
            case 102: try literal("false"); return false
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
    }

    private static func digit(_ value: UInt8) -> Bool { (48...57).contains(value) }

    /// Game-number readers add StrictJsonParser's token limits. Existing Foundation adapters
    /// keep their own numeric bounds; both paths validate JSON spelling and delimiters here.
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
