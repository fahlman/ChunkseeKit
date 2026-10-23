/// A static inventory illustration selected from an installed game's item definition.
/// Live properties and animation remain outside this representation.
public struct AssetItem: Sendable, Equatable {
    /// Composite order is significant. An empty definition has no parts.
    public let parts: [Part]

    public struct Part: Sendable, Equatable {
        public let model: AssetModel
        /// Indexes correspond to the model's layer/face tintIndex; missing indexes are untinted.
        public let tints: [Tint]
    }

    public enum Tint: Sendable, Equatable {
        /// Packed 0xRRGGBB. Color values here never supply alpha.
        case constant(UInt32)
        case dye(defaultColor: UInt32)
        case potion(defaultColor: UInt32)
        case firework(defaultColor: UInt32)
        /// A pixel in the game's 256 by 256 colormap, with a top-left origin.
        /// The client decodes the named texture; no image framework belongs in the reader.
        case colorMap(texture: Identifier, pixel: SIMD2<Int>)
    }
}
