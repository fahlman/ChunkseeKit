import ChunkseeKit

/// A search group declared by the game's ore tag, or an explicitly chosen individual block.
/// Names and presentation belong to clients; there is no maintained list of ore types.
public enum NotableBlock: Sendable, Hashable {
    case tag(String)
    case block(String)

    public var resourceID: String {
        switch self { case .tag(let id), .block(let id): id }
    }

    /// Tags and blocks can have the same resource name without sharing a group identity.
    public var id: String {
        switch self { case .tag(let id): "#" + id; case .block(let id): id }
    }

    // Ryan's explicit product exceptions (app #576), independent of ore-tag membership.
    public static let netherGold = Self.block("minecraft:nether_gold_ore")
    public static let ancientDebris = Self.block("minecraft:ancient_debris")
    public static let spawner = Self.block("minecraft:spawner")
    public static let trialSpawner = Self.block("minecraft:trial_spawner")
    public static let buddingAmethyst = Self.block("minecraft:budding_amethyst")

    /// Resolve through World.tags(for:in:assets:) in the block registry.
    public static let tagIDs: Set<String> = ["minecraft:ores"]

    /// One world's immutable grouping snapshot. Raw counts are independent of this value,
    /// so regrouping already counted IDs requires no scan and never retires the core index.
    public struct Catalog: Sendable, Equatable {
        private let idsByGroup: [NotableBlock: Set<String>]
        private let groupsByID: [String: [NotableBlock]]
        public let hasOreDefinitions: Bool

        public init(tags: [String: GameTag]) {
            var ids: [NotableBlock: Set<String>] = [:]
            let ores = tags["minecraft:ores"]
            hasOreDefinitions = ores != nil
            for entry in ores?.entries ?? [] {
                let group: NotableBlock = entry.isTag ? .tag(entry.id) : .block(entry.id)
                ids[group, default: []].formUnion(entry.members.map(\.id))
            }
            // The product has a separate Nether Gold search group, even though the game
            // includes that block in gold_ores. No other tag membership is overridden.
            for group in Array(ids.keys) where group != .netherGold {
                ids[group]?.remove(NotableBlock.netherGold.resourceID)
            }
            for group in [NotableBlock.netherGold, .ancientDebris, .spawner, .trialSpawner, .buddingAmethyst] {
                ids[group] = [group.resourceID]
            }
            idsByGroup = ids
            var reverse: [String: [NotableBlock]] = [:]
            for group in ids.keys.sorted(by: { $0.id < $1.id }) {
                for id in ids[group] ?? [] { reverse[id, default: []].append(group) }
            }
            groupsByID = reverse
        }

        public var groups: [NotableBlock] { idsByGroup.keys.sorted { $0.id < $1.id } }

        /// Nil means an ore tag was unavailable; an empty set is known empty membership.
        public func ids(for group: NotableBlock) -> Set<String>? { idsByGroup[group] }

        /// The requested coverage for Dimension.countBlocks, independent of core scan options.
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

        /// Combines the terrain reader's per-ID counts, ordered by the group's identity.
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
            return found.values.sorted { $0.block.id < $1.block.id }
        }
    }
}
