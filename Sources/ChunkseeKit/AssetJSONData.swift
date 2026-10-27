import Foundation

/// Foundation validates JSON structure and strings. Temporary unique names preserve member
/// order until we can apply Gson's last-member rule; protected numbers retain their spelling
/// until the resource codec chooses its Java primitive.
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
        try value(from: data, preservingNumbers: true)
    }

    /// Existing Foundation-backed readers keep their scalar conversions while sharing member
    /// selection. Their independent numeric contracts are not changed by this adapter.
    static func foundationValue(from data: Data) throws -> Any {
        try value(from: data, preservingNumbers: false)
    }

    /// Metadata with an existing Decodable contract retains its field validation and exact
    /// numeric spelling. Only duplicate-member selection happens before JSONDecoder.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        var normalized = Data()
        try appendJSON(value(from: data), to: &normalized)
        return try JSONDecoder().decode(type, from: normalized)
    }

    private static func value(from data: Data, preservingNumbers: Bool) throws -> Any {
        let bytes = Array(data)
        var protected = Data(), cursor = 0, copied = 0
        while cursor < bytes.count {
            if bytes[cursor] == 34 {
                protected.append(contentsOf: bytes[copied...cursor])
                // Even escaped-equivalent names remain distinct until Foundation has decoded
                // their spelling. A source offset also makes selection independent of hash order.
                protected.append(contentsOf: "S\(cursor):".utf8)
                copied = cursor + 1
                cursor = try endOfString(bytes, from: cursor)
            } else if preservingNumbers && (bytes[cursor] == 45 || digit(bytes[cursor])) {
                let end = try endOfNumber(bytes, from: cursor)
                protected.append(contentsOf: bytes[copied..<cursor])
                protected.append(contentsOf: [34, 78]) // Numeric spelling becomes an N string.
                protected.append(contentsOf: bytes[cursor..<end])
                protected.append(34)
                cursor = end; copied = end
            } else { cursor += 1 }
        }
        protected.append(contentsOf: bytes[copied...])
        return try restore(JSONSerialization.jsonObject(with: protected, options: [.fragmentsAllowed]))
    }

    private static func endOfString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var cursor = start + 1
        while cursor < bytes.count, bytes[cursor] != 34 {
            if bytes[cursor] == 92 { cursor += 1 }
            cursor += 1
        }
        guard cursor < bytes.count else { throw AssetReadError.invalidData }
        return cursor + 1
    }

    private static func digit(_ value: UInt8) -> Bool { (48...57).contains(value) }

    /// Validate number spelling and its following delimiter before replacing it with a string.
    /// In particular, an invalid numeric object key must not become a valid string key.
    private static func endOfNumber(_ bytes: [UInt8], from start: Int) throws -> Int {
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
                guard cursor == firstDigit || integer != 0 else { throw AssetReadError.invalidData }
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
        guard cursor - start < 1024 else { throw AssetReadError.invalidData }
        var next = cursor
        while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        guard next == bytes.count || [44, 93, 125].contains(bytes[next]) else { throw AssetReadError.invalidData }
        return cursor
    }

    private static func restore(_ value: Any) throws -> Any {
        if let text = value as? String {
            switch text.first {
            case "S": return try originalString(text).value
            case "N": return Number(literal: String(text.dropFirst()))
            default: throw AssetReadError.invalidData
            }
        }
        if let list = value as? [Any] { return try list.map(restore) }
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            var positions: [String: Int] = [:]
            for (key, value) in object {
                let member = try originalString(key)
                guard member.position > (positions[member.value] ?? -1) else { continue }
                positions[member.value] = member.position
                result[member.value] = try restore(value)
            }
            return result
        }
        return value
    }

    private static func originalString(_ text: String) throws -> (position: Int, value: String) {
        guard text.first == "S", let colon = text.firstIndex(of: ":"),
              let position = Int(text[text.index(after: text.startIndex)..<colon]) else { throw AssetReadError.invalidData }
        return (position, String(text[text.index(after: colon)...]))
    }

    private static func appendJSON(_ value: Any, to data: inout Data) throws {
        if let number = value as? Number { data.append(contentsOf: number.literal.utf8) }
        else if let object = value as? [String: Any] {
            data.append(123)
            for (index, key) in object.keys.sorted().enumerated() {
                if index > 0 { data.append(44) }
                data.append(try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed]))
                data.append(58)
                try appendJSON(object[key]!, to: &data)
            }
            data.append(125)
        } else if let values = value as? [Any] {
            data.append(91)
            for (index, value) in values.enumerated() {
                if index > 0 { data.append(44) }
                try appendJSON(value, to: &data)
            }
            data.append(93)
        } else { data.append(try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) }
    }
}
