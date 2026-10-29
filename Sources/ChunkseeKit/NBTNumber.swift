extension NBT {
    /// Java Number.floatValue. Convert integers directly to avoid rounding through Double first.
    var javaFloat: Float? {
        switch self {
        case .byte(let value): Float(value)
        case .short(let value): Float(value)
        case .int(let value): Float(value)
        case .long(let value): Float(value)
        // FloatTag/DoubleTag cache zero on input. A nonzero Double may still round to -0f.
        case .float(let value): value == 0 ? 0 : value
        case .double(let value): value == 0 ? 0 : Float(value)
        default: nil
        }
    }

    /// Java Number.intValue, used by the game's numeric codecs. Keep narrowing distinct from
    /// `int`, which deliberately widens integral tags without coercing floating-point values.
    var javaInt: Int32? {
        switch self {
        case .byte(let value): Int32(value)
        case .short(let value): Int32(value)
        case .int(let value): value
        case .long(let value): Int32(truncatingIfNeeded: value)
        case .float(let value): Self.javaInt(Double(value))
        case .double(let value): Self.javaInt(value)
        default: nil
        }
    }

    /// CompoundTag.getInt/getIntOr use NumericTag.intValue, whose floating cases floor
    /// before the JVM's saturating conversion. Codec.INT instead uses Number.intValue.
    var compoundInt: Int32? {
        switch self {
        case .float(let value): Self.javaInt(Double(value).rounded(.down))
        case .double(let value): Self.javaInt(value.rounded(.down))
        default: javaInt
        }
    }

    /// NumericTag.byteValue narrows integral tags, or a floored/saturated floating int.
    var compoundByte: Int8? { compoundInt.map { Int8(truncatingIfNeeded: $0) } }

    /// NumericTag.longValue deliberately differs by tag: FloatTag truncates, DoubleTag
    /// floors. Keep integral values exact instead of passing them through Double.
    var compoundLong: Int64? {
        switch self {
        case .byte(let value): Int64(value)
        case .short(let value): Int64(value)
        case .int(let value): Int64(value)
        case .long(let value): value
        case .float(let value): Self.javaLong(Double(value))
        case .double(let value): Self.javaLong(value.rounded(.down))
        default: nil
        }
    }

    /// CompoundTag.getBoolean tests the converted byte, not the original number.
    var compoundBoolean: Bool? { compoundByte.map { $0 != 0 } }

    private static func javaInt(_ value: Double) -> Int32 {
        if value.isNaN { return 0 }
        if value >= Double(Int32.max) { return .max }
        if value <= Double(Int32.min) { return .min }
        return Int32(value)
    }

    private static func javaLong(_ value: Double) -> Int64 {
        if value.isNaN { return 0 }
        // Double(Int64.max) rounds up to 2^63; guard before Swift's checked conversion.
        if value >= Double(Int64.max) { return .max }
        if value <= Double(Int64.min) { return .min }
        return Int64(value)
    }
}
