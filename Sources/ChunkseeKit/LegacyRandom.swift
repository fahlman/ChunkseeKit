/// The game's 48-bit legacy generator, shared by slime chunks, biome noise and block models.
struct LegacyRandom {
    private var state: UInt64
    private static let multiplier: UInt64 = 25_214_903_917
    private static let mask: UInt64 = (1 << 48) - 1

    init(seed: Int64) {
        state = (UInt64(bitPattern: seed) ^ Self.multiplier) & Self.mask
    }

    private mutating func next(_ bits: Int) -> UInt64 {
        state = (state &* Self.multiplier &+ 11) & Self.mask
        return state >> (48 - bits)
    }

    mutating func nextInt(bound: Int32) -> Int32 {
        precondition(bound > 0)
        if bound & (bound - 1) == 0 {
            return Int32((Int64(bound) * Int64(next(31))) >> 31)
        }
        while true {
            let bits = Int32(next(31)), value = bits % bound
            // Java rejects the incomplete tail using signed 32-bit overflow.
            if bits &- value &+ (bound - 1) >= 0 { return value }
        }
    }

    mutating func nextDouble() -> Double {
        Double((next(26) << 27) + next(27)) / 9_007_199_254_740_992
    }

    mutating func nextLong() -> Int64 {
        // Java sign-extends both int draws before shifting/adding; the low half is not unsigned.
        let high = Int64(Int32(bitPattern: UInt32(next(32))))
        let low = Int64(Int32(bitPattern: UInt32(next(32))))
        return (high << 32) &+ low
    }
}
