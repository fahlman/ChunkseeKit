import Foundation
import CoreFoundation

/// Strict JSON primitives shared by the item and blockstate asset readers.
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

    static func integer(_ value: Any?) throws -> Int {
        guard let value = Int32(exactly: try jsonNumber(value).doubleValue) else { throw Invalid.asset }
        return Int(value)
    }

    static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw Invalid.asset }
        return value.boolValue
    }
}
