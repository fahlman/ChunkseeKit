extension World {
    /// Java Edition's slime-chunk classification, using chunk coordinates and the world seed.
    /// These are signed 32-bit coordinates, as in the game. For low-altitude Overworld spawning,
    /// height and the remaining mob-spawn conditions still apply. Swamp spawning has its own rule.
    /// Verified against Minecraft 26.3's WorldgenRandom and Slime spawn call.
    public static func isSlimeChunk(x: Int32, z: Int32, seed: Int64) -> Bool {
        // The game's int products overflow BEFORE widening, except the final z-square multiplier.
        var mixed = seed
        mixed &+= Int64(x &* x &* 4_987_142)
        mixed &+= Int64(x &* 5_947_611)
        mixed &+= Int64(z &* z) &* 4_392_871
        mixed &+= Int64(z &* 389_711)

        let multiplier: UInt64 = 25_214_903_917, mask: UInt64 = (1 << 48) - 1
        var state = (UInt64(bitPattern: mixed ^ 987_234_911) ^ multiplier) & mask
        while true {
            state = (state &* multiplier &+ 11) & mask
            let bits = Int32(state >> 17), value = bits % 10
            // BitRandomSource rejects the incomplete tail; a simple modulo gives wrong chunks
            // for those seeds. Preserve Java's signed-overflow check.
            if bits &- value &+ 9 >= 0 { return value == 0 }
        }
    }
}
