/// The three original PNG resources needed for a generated 26.3 atlas sprite.
/// Read each through GameAssets.texture; image decoding and caching belong to the client.
public struct AssetPalettedTexture: Sendable, Equatable {
    public let texture: Identifier
    public let paletteKey: Identifier
    public let palette: Identifier
}

/// Minecraft 26.3's palette replacement over decoded, unpremultiplied 0xAARRGGBB pixels.
/// This interprets the palette format without depending on an image framework.
public struct AssetPaletteMapping: Sendable {
    private let replacements: [UInt32: UInt32]

    /// Palettes use row-major pixels and must have equal lengths, at most 4,096 entries.
    /// Transparent key entries do not replace colors; the last repeated RGB key wins.
    public init?(key: [UInt32], palette: [UInt32]) {
        guard key.count == palette.count, key.count <= 4096 else { return nil }
        var replacements: [UInt32: UInt32] = [:]
        for (source, target) in zip(key, palette) where source >> 24 != 0 {
            replacements[source | 0xFF000000] = target
        }
        self.replacements = replacements
    }

    /// Match RGB independently of alpha, then multiply source and replacement alpha.
    /// Unmatched and fully transparent pixels retain their original values.
    public func color(_ argb: UInt32) -> UInt32 {
        let alpha = argb >> 24
        guard alpha != 0, let replacement = replacements[argb | 0xFF000000] else { return argb }
        return (alpha * (replacement >> 24) / 255) << 24 | (replacement & 0xFFFFFF)
    }
}
