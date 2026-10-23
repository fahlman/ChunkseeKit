import ChunkseeKit

/// Existing block-search groups. Names and presentation belong to clients.
/// Common ores stay excluded from this catalog; a caller can still scan any ID through the core reader.
/// The app's original measurements on Ryan's Realm found coal, iron, copper and redstone in about
/// a third of sections, making their counting several times costlier (fahlman/Chunksee#81).
public enum NotableBlock: String, CaseIterable, Sendable {
    case diamond, emerald, gold, netherGold, lapis, ancientDebris, spawner, trialSpawner, buddingAmethyst

    /// Exact saved IDs counted together, including deepslate variants.
    public var ids: [String] {
        switch self {
        case .diamond: ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore"]
        case .emerald: ["minecraft:emerald_ore", "minecraft:deepslate_emerald_ore"]
        case .gold: ["minecraft:gold_ore", "minecraft:deepslate_gold_ore"]
        case .netherGold: ["minecraft:nether_gold_ore"]
        case .lapis: ["minecraft:lapis_ore", "minecraft:deepslate_lapis_ore"]
        case .ancientDebris: ["minecraft:ancient_debris"]
        case .spawner: ["minecraft:spawner"]
        case .trialSpawner: ["minecraft:trial_spawner"]
        case .buddingAmethyst: ["minecraft:budding_amethyst"]
        }
    }

    public static let byID: [String: NotableBlock] = Dictionary(uniqueKeysWithValues:
        allCases.flatMap { block in block.ids.map { ($0, block) } })

    /// One group's count and enclosing section-height range in a chunk.
    /// These are section bounds from the scan, not exact block heights.
    public struct Deposit: Sendable, Equatable {
        public let block: NotableBlock
        public private(set) var count: Int
        public private(set) var minY: Int
        public private(set) var maxY: Int

        public init(block: NotableBlock, count: Int, minY: Int, maxY: Int) {
            self.block = block; self.count = count; self.minY = minY; self.maxY = maxY
        }

        /// Combines the core reader's per-ID counts, ordered by the group's raw value.
        /// Unknown IDs and blocks outside the catalog are omitted.
        public static func grouped(_ deposits: [ChunkseeKit.BlockDeposit]) -> [Self] {
            var found: [NotableBlock: Self] = [:]
            for value in deposits {
                guard let block = NotableBlock.byID[value.id] else { continue }
                if var deposit = found[block] {
                    deposit.count += value.count
                    deposit.minY = min(deposit.minY, value.minY)
                    deposit.maxY = max(deposit.maxY, value.maxY)
                    found[block] = deposit
                } else {
                    found[block] = Self(block: block, count: value.count, minY: value.minY, maxY: value.maxY)
                }
            }
            return found.values.sorted { $0.block.rawValue < $1.block.rawValue }
        }
    }
}
