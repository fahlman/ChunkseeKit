import ChunkseeKit

/// Existing block-search groups. Names and presentation belong to clients.
/// Group selection is product policy; ore membership comes from the world's block tags.
/// The app's original measurements on Ryan's Realm found coal, iron, copper and redstone in about
/// a third of sections, making their counting several times costlier (fahlman/Chunksee#81).
public enum NotableBlock: String, CaseIterable, Sendable {
    case diamond, emerald, gold, netherGold, lapis, ancientDebris, spawner, trialSpawner, buddingAmethyst

    private var tagID: String? {
        switch self {
        case .diamond: "minecraft:diamond_ores"
        case .emerald: "minecraft:emerald_ores"
        case .gold: "minecraft:gold_ores"
        case .lapis: "minecraft:lapis_ores"
        default: nil
        }
    }

    private var selectedBlockID: String? {
        switch self {
        case .netherGold: "minecraft:nether_gold_ore"
        case .ancientDebris: "minecraft:ancient_debris"
        case .spawner: "minecraft:spawner"
        case .trialSpawner: "minecraft:trial_spawner"
        case .buddingAmethyst: "minecraft:budding_amethyst"
        default: nil
        }
    }

    /// Resolve these through World.tags(for:in:assets:) in the block registry.
    public static var tagIDs: Set<String> { Set(allCases.compactMap(\.tagID)) }

    /// One world's immutable grouping snapshot. The same catalog supplies the scan IDs and
    /// the index's grouping policy. Missing tags stay unknown, distinct from valid empty tags.
    public struct Catalog: Sendable, Equatable {
        private let idsByGroup: [NotableBlock: Set<String>]
        private let groupsByID: [String: [NotableBlock]]

        public init(tags: [String: GameTag]) {
            var ids: [NotableBlock: Set<String>] = [:]
            for group in NotableBlock.allCases {
                if let tagID = group.tagID, let tag = tags[tagID] {
                    ids[group] = Set(tag.members.map(\.id))
                } else if let id = group.selectedBlockID {
                    ids[group] = [id]
                }
            }
            // The product has a separate Nether Gold search group, even though the game
            // includes that block in gold_ores. No other tag membership is overridden.
            if let netherGold = NotableBlock.netherGold.selectedBlockID {
                ids[.gold]?.remove(netherGold)
            }
            idsByGroup = ids
            var reverse: [String: [NotableBlock]] = [:]
            for group in NotableBlock.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                for id in ids[group] ?? [] { reverse[id, default: []].append(group) }
            }
            groupsByID = reverse
        }

        /// Nil means an ore tag was unavailable; an empty set is known empty membership.
        public func ids(for group: NotableBlock) -> Set<String>? { idsByGroup[group] }

        /// The union of readable groups, for RegionScanOptions.blockIDs.
        public var blockIDs: Set<String> { Set(groupsByID.keys) }

        /// A saved ID may belong to multiple tags; each corresponding search group retains it.
        /// Optional tag declarations are usable when that ID actually occurs in the save.
        public func groups(for id: String) -> [NotableBlock] {
            guard let canonical = Identifier(id)?.description else { return [] }
            return groupsByID[canonical] ?? []
        }
    }

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
        /// Blocks outside the supplied catalog are omitted.
        public static func grouped(_ deposits: [ChunkseeKit.BlockDeposit], using catalog: Catalog) -> [Self] {
            var found: [NotableBlock: Self] = [:]
            for value in deposits {
                for block in catalog.groups(for: value.id) {
                    if var deposit = found[block] {
                        deposit.count += value.count
                        deposit.minY = min(deposit.minY, value.minY)
                        deposit.maxY = max(deposit.maxY, value.maxY)
                        found[block] = deposit
                    } else {
                        found[block] = Self(block: block, count: value.count, minY: value.minY, maxY: value.maxY)
                    }
                }
            }
            return found.values.sorted { $0.block.rawValue < $1.block.rawValue }
        }
    }
}
