import Foundation
import Testing
import ChunkseeKit

@Suite struct PlayerInventorySectionTests {
    private func item(_ id: String, slot: NBT? = nil, legacy: Bool = false) -> NBT {
        var fields: [String: NBT] = ["id": .string("minecraft:" + id)]
        fields[legacy ? "Count" : "count"] = legacy ? .byte(1) : .int(1)
        fields["Slot"] = slot
        return .compound(fields)
    }

    @Test(arguments: [false, true])
    func currentAndLegacyItemsRetainSectionOrderEmptySlotsAndEquipment(_ legacy: Bool) {
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "SelectedItemSlot": .int(8),
            "Inventory": .list([
                item("diamond", slot: .byte(35), legacy: legacy),
                item("stone", slot: .byte(0), legacy: legacy),
                item("iron_pickaxe", slot: .byte(8), legacy: legacy),
                item("apple", slot: .byte(9), legacy: legacy),
                item("iron_helmet", slot: .byte(103), legacy: legacy),
                item("shield", slot: .byte(-106), legacy: legacy),
            ]),
            "EnderItems": .list([
                item("emerald", slot: .byte(26), legacy: legacy),
                item("gold_ingot", slot: .byte(0), legacy: legacy),
                item("dirt", slot: .byte(27), legacy: legacy),
            ]),
        ]))
        let hotbar = player.inventorySlots(in: .hotbar)
        let storage = player.inventorySlots(in: .storage)
        let enderChest = player.inventorySlots(in: .enderChest)
        #expect(hotbar.count == 9 && storage.count == 27 && enderChest.count == 27)
        #expect(hotbar[0]?.id == "minecraft:stone" && hotbar[8]?.id == "minecraft:iron_pickaxe")
        #expect(hotbar[1..<8].allSatisfy { $0 == nil })
        #expect(storage[0]?.id == "minecraft:apple" && storage[26]?.id == "minecraft:diamond")
        #expect(storage[1..<26].allSatisfy { $0 == nil })
        #expect(storage[0]?.slot == 9 && storage[26]?.slot == 35)
        #expect(enderChest[0]?.id == "minecraft:gold_ingot" && enderChest[26]?.id == "minecraft:emerald")
        #expect(enderChest[1..<26].allSatisfy { $0 == nil })
        #expect(player.mainHandItem == hotbar[8])
        #expect(player.inventory.count == 4 && player.enderChest.count == 3)
        #expect(player.equipment["head"]?.id == "minecraft:iron_helmet")
        #expect(player.equipment["offhand"]?.id == "minecraft:shield")
    }

    @Test func missingExtremeAndDuplicateSlotsDoNotInventPositionsOrChangeRawItems() {
        let entries = [item("diamond", slot: .byte(4)), item("emerald", slot: .byte(4)),
                       item("gold_ingot"), item("stone", slot: .long(Int64.max)),
                       item("dirt", slot: .long(Int64.min)), item("sand", slot: .int(36))]
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Inventory": .list(entries), "EnderItems": .list(entries), "SelectedItemSlot": .int(4),
        ]))
        for section in [PlayerInventorySection.hotbar, .enderChest] {
            let slots = player.inventorySlots(in: section)
            #expect(slots[4]?.id == "minecraft:emerald")
            #expect(slots.compactMap { $0 }.count == 1)
        }
        #expect(player.inventorySlots(in: .storage).allSatisfy { $0 == nil })
        #expect(player.mainHandItem == player.inventorySlots(in: .hotbar)[4])
        #expect(player.inventory.map(\.id) == ["minecraft:diamond", "minecraft:emerald", "minecraft:gold_ingot"])
        #expect(player.enderChest.count == entries.count)
    }

    @Test func absentInventoriesHaveEmptySlotsAndStorageCannotBecomeTheSelectedHand() {
        let empty = PlayerInfo(uuid: UUID(), nbt: .compound([:]))
        for section in PlayerInventorySection.allCases {
            #expect(!empty.inventorySlots(in: section).isEmpty)
            #expect(empty.inventorySlots(in: section).allSatisfy { $0 == nil })
        }
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Inventory": .list([item("iron_sword", slot: .byte(9))]), "SelectedItemSlot": .int(9),
        ]))
        #expect(player.inventorySlots(in: .storage)[0]?.id == "minecraft:iron_sword")
        #expect(player.mainHandItem == nil)
    }
}
