import Foundation
import CoreFoundation

/// JSON primitives and game numeric conversions shared by the resource readers.
enum AssetJSON {
    static func object(from data: Data) throws -> [String: Any] {
        do { return try object(value(from: data)) }
        catch { throw AssetReadError.invalidData }
    }

    static func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw AssetReadError.invalidData }
        return value
    }

    static func array(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else { throw AssetReadError.invalidData }
        return value
    }

    static func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw AssetReadError.invalidData }
        return value
    }

    /// GsonHelper's string fields accept every primitive, preserving numeric spelling.
    /// Codec.STRING fields continue to use the strict string reader above.
    static func primitiveString(_ value: Any?) throws -> String {
        if let text = value as? String { return text }
        if let number = value as? Number { return number.literal }
        return try boolean(value) ? "true" : "false"
    }

    /// GsonHelper's boolean fields use Boolean.parseBoolean on non-boolean primitives.
    static func primitiveBoolean(_ value: Any?) throws -> Bool {
        try primitiveString(value).lowercased() == "true"
    }

    static func identifier(_ value: Any?) throws -> Identifier {
        guard let value = value as? String, let id = GameAssets.resourceID(value) else { throw AssetReadError.invalidData }
        return id
    }

    static func number(_ value: Any?) throws -> Float {
        let number = try float(value)
        guard number.isFinite else { throw AssetReadError.invalidData }
        return number
    }

    static func float(_ value: Any?) throws -> Float {
        // Gson's typed FLOAT field parses the original decimal directly, without a Double
        // intermediate. Native saved attributes have their own tagged format adapter.
        guard let value = value as? Number, let number = Float(value.literal) else {
            throw AssetReadError.invalidData
        }
        return number
    }

    static func double(_ value: Any?) throws -> Double {
        guard let value = value as? Number, let number = Double(value.literal), number.isFinite else {
            throw AssetReadError.invalidData
        }
        return number
    }

    static func numbers(_ value: Any?, count: Int, read: (Any?) throws -> Float = AssetJSON.number) throws -> [Float] {
        let values = try array(value)
        guard values.count == count else { throw AssetReadError.invalidData }
        return try values.map(read)
    }

    static func color(_ value: Any?) throws -> UInt32 {
        if let values = value as? [Any] {
            guard let color = RGBColor.channels(try values.map(number)) else { throw AssetReadError.invalidData }
            return color
        }
        return RGBColor.integer(Int32(try integer(value)))
    }

    /// ExtraCodecs.STRING_RGB_COLOR adds exactly six hex digits to RGB_COLOR_CODEC.
    static func stringColor(_ value: Any?) throws -> UInt32 {
        guard let text = value as? String else { return try color(value) }
        let bytes = Array(text.utf8)
        guard bytes.count == 7, bytes.first == 35,
              bytes.dropFirst().allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let color = UInt32(text.dropFirst(), radix: 16) else { throw AssetReadError.invalidData }
        return color
    }

    /// STRING_RGB_VEC3_COLOR keeps list channels as floats, unlike the packed RGB codec.
    static func colorVector(_ value: Any?) throws -> SIMD3<Float> {
        if value is [Any] {
            let channels = try numbers(value, count: 3, read: AssetJSON.float)
            return SIMD3(channels[0], channels[1], channels[2])
        }
        let color = try stringColor(value)
        return RGBColor.vector(color)
    }

    static func integer(_ value: Any?) throws -> Int {
        guard let value = value as? Number, let integer = value.int32 else { throw AssetReadError.invalidData }
        return Int(integer)
    }

    static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw AssetReadError.invalidData }
        return value.boolValue
    }
}
