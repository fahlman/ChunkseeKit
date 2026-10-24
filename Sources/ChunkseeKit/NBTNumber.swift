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

    private static func javaInt(_ value: Double) -> Int32 {
        if value.isNaN { return 0 }
        if value >= Double(Int32.max) { return .max }
        if value <= Double(Int32.min) { return .min }
        return Int32(value)
    }
}
