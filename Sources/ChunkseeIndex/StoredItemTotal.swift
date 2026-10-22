import ChunkseeKit

/// One saved item ID's total quantity and number of outer containers holding it.
/// Boxes and bundles count alongside their contents; names and display order belong to clients.
public struct StoredItemTotal: Sendable, Equatable {
    public let id: String
    public let count: Int
    public let containers: Int

    /// Totals by saved ID, ordered by ID. Each input container counts once for each ID it holds.
    /// Sealed containers contribute only items already saved; their loot is never predicted.
    public static func totals(in containers: [ItemContainer]) -> [StoredItemTotal] {
        var totals: [String: (count: Int, containers: Int)] = [:]
        for container in containers {
            let here = ItemTotals(in: container.items, groupingBy: \.id)
            for (id, count) in here.quantities {
                totals[id, default: (0, 0)].count += count
                totals[id, default: (0, 0)].containers += 1
            }
        }
        return totals.map { StoredItemTotal(id: $0.key, count: $0.value.count, containers: $0.value.containers) }
            .sorted { $0.id < $1.id }
    }
}
