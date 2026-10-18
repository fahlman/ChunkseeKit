/// Non-straddling packed longs shared by palette and heightmap readers. Callers validate the
/// stored width and word count before decoding; uniform palettes take their own constant path.
enum PackedLongs {
    static func wordCount(entries: Int, bits: Int) -> Int {
        let perLong = 64 / bits
        return (entries + perLong - 1) / perLong
    }

    static func value(at index: Int, in data: [Int64], bits: Int) -> Int {
        let perLong = 64 / bits
        let mask = (UInt64(1) << UInt64(bits)) - 1
        let word = UInt64(bitPattern: data[index / perLong])
        return Int((word >> UInt64((index % perLong) * bits)) & mask)
    }

    static func forEachValue(in data: [Int64], entries: Int, bits: Int, _ body: (Int) -> Void) {
        let perLong = 64 / bits
        let mask = (UInt64(1) << UInt64(bits)) - 1
        var remaining = entries
        for raw in data where remaining > 0 {
            var word = UInt64(bitPattern: raw)
            let here = min(perLong, remaining)
            for _ in 0..<here {
                body(Int(word & mask))
                word >>= UInt64(bits)
            }
            remaining -= here
        }
    }
}
