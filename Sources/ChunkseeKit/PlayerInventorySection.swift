/// A saved player inventory's sections. Slot numbers remain on the original ItemStack values.
public enum PlayerInventorySection: CaseIterable, Sendable {
    case hotbar
    case storage
    case enderChest

    var slotRange: Range<Int> {
        switch self {
        case .hotbar: 0..<9
        case .storage: 9..<36
        case .enderChest: 0..<27
        }
    }

    static var carriedSlots: Range<Int> { hotbar.slotRange.lowerBound..<storage.slotRange.upperBound }
}

extension PlayerInfo {
    /// Ordered contents, including nil for empty slots. Missing/out-of-section slot numbers are
    /// omitted; if readable items repeat a slot, the last one occupies it. Raw inventories stay intact.
    public func inventorySlots(in section: PlayerInventorySection) -> [ItemStack?] {
        let items = section == .enderChest ? enderChest : inventory
        let range = section.slotRange
        var slots = [ItemStack?](repeating: nil, count: range.count)
        for item in items {
            guard let slot = item.slot, range.contains(slot) else { continue }
            slots[slot - range.lowerBound] = item
        }
        return slots
    }
}
