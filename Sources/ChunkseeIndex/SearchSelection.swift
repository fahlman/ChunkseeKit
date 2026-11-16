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
