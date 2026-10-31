import CryptoKit
import Foundation

/// Stable persisted identities for complete cache inputs. Compute an immutable catalog's
/// identity once at publication; retain its typed value for in-memory equality.
public enum InterpretationKey {
    /// SHA-256 of compact JSON with recursively sorted object keys and unescaped slashes.
    /// Arrays retain their meaning and order. Kit's set-valued inputs encode sorted arrays;
    /// custom Encodable inputs must likewise define the order of any unordered collections.
    /// Non-finite numbers use "Infinity", "-Infinity" and "NaN", as in typed JSON archives.
    /// Inputs that mix numbers and literal strings at one position must retain their type tags.
    /// Encoding failures throw instead of making unrelated inputs share a fallback key.
    public static func identity(of value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Game text can retain non-finite arguments. They must not disable a whole cache;
        // this strategy leaves every previously encodable finite input unchanged.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let bytes = try encoder.encode(value)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
