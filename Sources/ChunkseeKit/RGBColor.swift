/// Shared ExtraCodecs.RGB_COLOR_CODEC conversion for saved NBT and asset JSON.
enum RGBColor {
    static func integer(_ value: Int32) -> UInt32 {
        UInt32(bitPattern: value) & 0x00ff_ffff
    }

    static func channels(_ values: [Float]) -> UInt32? {
        guard values.count == 3, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        // ARGB.as8BitChannel uses floor(channel * 255) at Float precision.
        let rgb = values.map { UInt32(($0 * 255).rounded(.down)) }
        return rgb[0] << 16 | rgb[1] << 8 | rgb[2]
    }
}
