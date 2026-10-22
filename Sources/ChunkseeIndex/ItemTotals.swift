import ChunkseeKit

/// Quantities of matching stacks, including nested boxes and bundles. Clients choose searchable
/// text and grouping keys; display names, result order and formatting stay outside this value.
public struct ItemTotals<Key: Hashable & Sendable>: Sendable {
    public let quantities: [Key: Int]

    /// A matching zero-quantity stack is still a match, as in the existing search behavior.
    public var isEmpty: Bool { quantities.isEmpty }
    public var count: Int { quantities.values.reduce(0, +) }

    public init(in items: [ItemStack], matching include: (ItemStack) -> Bool = { _ in true },
                groupingBy key: (ItemStack) -> Key) {
        var quantities: [Key: Int] = [:]
        for outer in items {
            for item in outer.allItems where include(item) {
                quantities[key(item), default: 0] += item.count
            }
        }
        self.quantities = quantities
    }
}
