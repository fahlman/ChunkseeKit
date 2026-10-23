/// Resolved blockstate model choices, before world-position random selection or rendering.
/// All parts are drawn together; each part chooses one of its weighted alternatives.
public struct AssetBlock: Sendable, Equatable {
    public let parts: [Part]

    public struct Part: Sendable, Equatable {
        /// Nonempty, in definition order. Weights are positive and total at most Int32.max.
        public let alternatives: [Alternative]
    }

    public struct Alternative: Sendable, Equatable {
        public let modelID: Identifier
        public let model: AssetModel
        public let weight: Int
        /// The definition's X/Y/Z rotations, normalized to 0, 90, 180 or 270 degrees.
        /// These are block model rotations, separate from the model's inventory transform.
        public let rotation: SIMD3<Int>
        public let uvLock: Bool
    }
}
