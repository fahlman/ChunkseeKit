import Foundation
import CoreFoundation

/// Strict JSON primitives shared by the game-resource readers.
enum AssetJSON {
    private enum Invalid: Error { case asset }

    static func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw Invalid.asset }
        return value
    }

    static func array(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else { throw Invalid.asset }
        return value
    }

    static func identifier(_ value: Any?) throws -> Identifier {
        guard let value = value as? String, let id = GameAssets.resourceID(value) else { throw Invalid.asset }
        return id
    }

    static func jsonNumber(_ value: Any?) throws -> NSNumber {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { throw Invalid.asset }
        return value
    }

    static func number(_ value: Any?) throws -> Float {
        let number = try jsonNumber(value).floatValue
        guard number.isFinite else { throw Invalid.asset }
        return number
    }

    static func numbers(_ value: Any?, count: Int) throws -> [Float] {
        let values = try array(value)
        guard values.count == count else { throw Invalid.asset }
        return try values.map(number)
    }

    static func color(_ value: Any?) throws -> UInt32 {
        if let values = value as? [Any] {
            guard let color = RGBColor.channels(try values.map(number)) else { throw Invalid.asset }
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
              let color = UInt32(text.dropFirst(), radix: 16) else { throw Invalid.asset }
        return color
    }

    static func integer(_ value: Any?) throws -> Int {
        guard let value = Int32(exactly: try jsonNumber(value).doubleValue) else { throw Invalid.asset }
        return Int(value)
    }

    static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw Invalid.asset }
        return value.boolValue
    }
}
