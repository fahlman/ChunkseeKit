import ChunkseeKit

extension PlayerInfo {
    /// Inventory and saved equipment searched together; the ender chest is a separate result.
    /// Do not add the selected hotbar item again as an inferred main hand.
    public var searchableInventory: [ItemStack] {
        let worn = equipment
        return inventory + worn.keys.sorted().compactMap { worn[$0] }
    }
}

extension BookContent {
    /// Saved searchable fields, preserving their order and line boundaries.
    public var searchText: String {
        ([title, author].compactMap(\.self) + pages).joined(separator: "\n")
    }
}

extension Sign {
    /// Both sides in saved order, without empty lines. Whitespace is significant to phrase queries;
    /// clients can trim it separately for display.
    public var searchLines: [String] { (front + back).filter { !$0.isEmpty } }
}

extension SearchQuery.Filter {
    /// Creature categories included by a filtered search. Trade matching further examines offers.
    public func includes(_ group: CreatureEntry.Group) -> Bool {
        switch self {
        case .creature: true
        case .pet: group == .pet
        case .villager, .trade: group == .villager
        case .structure, .place, .biome, .block: false
        }
    }
}

extension WorldIndex {
    /// Selects the strongest matching deposits across dimensions, retaining each dimension ID.
    /// Inputs must follow ChunkDeposit.orderedBefore, as DimensionIndex.blocks does: count
    /// descending, then chunk X, chunk Z and block-group ID ascending. Results use that same
    /// order with dimension ID before coordinates, so ties at the limit have stable membership.
    /// The client owns its display limit and conversion to map positions.
    public func richestDeposits(matching blocks: Set<NotableBlock>, limit: Int,
                                in part: KeyPath<Dimension, [DimensionIndex.ChunkDeposit]>) -> [Placed<DimensionIndex.ChunkDeposit>] {
        guard limit > 0, !blocks.isEmpty else { return [] }
        var best: [Placed<DimensionIndex.ChunkDeposit>] = []
        for (dimension, value) in dimensions {
            best += value[keyPath: part].lazy.filter { blocks.contains($0.deposit.block) }.prefix(limit)
                .map { Placed(dimension: dimension, value: $0) }
        }
        best.sort { DimensionIndex.ChunkDeposit.orderedBefore($0.value, in: $0.dimension,
                                                            $1.value, in: $1.dimension) }
        return Array(best.prefix(limit))
    }
}
