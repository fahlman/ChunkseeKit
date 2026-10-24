/// Resolved blockstate model choices, before world-position random selection or rendering.
/// All parts are drawn together; each part chooses one of its weighted alternatives.
public struct AssetBlock: Sendable, Equatable {
    public let parts: [Part]
    let seedOffset: SIMD3<Int32>?
    let isMultipart: Bool

    /// One model per part, in drawing order, using the position's verified vanilla 26.3 seed.
    /// Unverified versions/blocks, missing seed-driving properties and coordinates outside
    /// signed 32-bit bounds return nil. No resources are reread; `parts` remains unchanged.
    public func selectedAlternatives(at position: BlockPosition) -> [Alternative]? {
        guard let seedOffset, let seed = BlockModelSeed.seed(at: position, offset: seedOffset) else { return nil }
        var random = LegacyRandom(seed: seed)
        let partSeed = isMultipart ? random.nextLong() : seed
        return parts.map { part in
            // Multipart resets the generator for every part, including after unweighted parts.
            var random = LegacyRandom(seed: partSeed)
            if part.alternatives.count == 1 { return part.alternatives[0] }
            var remaining = Int(random.nextInt(bound: part.totalWeight))
            for choice in part.alternatives {
                remaining -= choice.weight
                if remaining < 0 { return choice }
            }
            preconditionFailure("Resolved model weights must cover the random draw")
        }
    }

    public struct Part: Sendable, Equatable {
        /// Nonempty, in definition order. Weights are positive and total at most Int32.max.
        public let alternatives: [Alternative]
        let totalWeight: Int32
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
