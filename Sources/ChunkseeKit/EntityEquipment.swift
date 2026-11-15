import Foundation

/// Slot reading shared by health calculation and the public player/mob equipment records.
enum EntityEquipment {
    // EquipmentSlot's order also decides replacement of modifiers sharing an identity.
    static let slots = ["mainhand", "offhand", "feet", "legs", "chest", "head", "body", "saddle"]
    static let playerInventorySlots = [100: "feet", 101: "legs", 102: "chest", 103: "head", -106: "offhand"]

    static func current(_ nbt: NBT) -> [String: ItemStack]? {
        nbt["equipment"]?.compound.map { values in
            values.compactMapValues(ItemStack.init)
        }
    }

    static func player(_ nbt: NBT) -> [String: ItemStack] {
        var items = current(nbt) ?? [:]
        for item in ItemStack.list(nbt["Inventory"]) {
            if let slot = item.slot, let name = playerInventorySlots[slot], items[name] == nil { items[name] = item }
        }
        return items
    }

    static func creature(_ nbt: NBT) -> [String: ItemStack]? {
        // A current compound, including an explicit empty one, supersedes old creature fields.
        if let items = current(nbt) { return items }
        var items: [String: ItemStack] = [:]
        var hasSavedEquipment = false
        var hasEquipmentField = nbt["equipment"] != nil
        for (key, names) in [("ArmorItems", ["feet", "legs", "chest", "head"]), ("HandItems", ["mainhand", "offhand"])] {
            guard let saved = nbt[key] else { continue }
            hasEquipmentField = true
            guard let contents = saved.list else { continue }
            hasSavedEquipment = true
            for (name, item) in zip(names, contents) { items[name] = ItemStack(item) }
        }
        for key in ["body_armor_item", "ArmorItem", "DecorItem"] {
            guard let armor = nbt[key] else { continue }
            hasEquipmentField = true
            guard armor.compound != nil else { continue }
            hasSavedEquipment = true
            // HorseBodyArmorItemFix clears the old chest entry for ArmorItem, even when
            // empty; DecorItem conversion keeps it. The saved field identifies the format.
            if key == "ArmorItem" { items["chest"] = nil }
            items["body"] = ItemStack(armor)
        }
        if let saddle = nbt["saddle"] ?? nbt["SaddleItem"] {
            hasEquipmentField = true
            if saddle.compound != nil {
                hasSavedEquipment = true
                items["saddle"] = ItemStack(saddle)
            }
        } else if let saddle = nbt["Saddle"] {
            hasEquipmentField = true
            if let attached = saddle.bool {
                hasSavedEquipment = true
                if attached {
                    items["saddle"] = ItemStack(id: GeneratedEquipmentFacts.legacySaddleItem,
                                              count: GeneratedEquipmentFacts.legacySaddleCount)
                }
            }
        }
        if hasSavedEquipment { return items }
        // LivingEntity omits empty equipment and loads an empty EntityEquipment when absent.
        // An unreadable saved field is not evidence of that omission.
        return hasEquipmentField ? nil : [:]
    }

    static func matches(group: String, slot: String) -> Bool? {
        switch group {
        case "any": true
        case "hand": ["mainhand", "offhand"].contains(slot)
        case "armor": ["head", "chest", "legs", "feet", "body"].contains(slot)
        default: slots.contains(group) ? group == slot : nil
        }
    }
}

/// Applicable saved equipment inputs; resource definitions are consulted only when resolving.
enum EquipmentHealth {
    struct Inputs {
        var modifiers: [HealthModifier] = []
        var enchantments: [HealthEnchantment] = []
    }

    static func inputs(in equipment: [String: ItemStack]) -> Inputs? {
        var found = Inputs()
        for slot in EntityEquipment.slots {
            guard let item = equipment[slot], item.count > 0 else { continue }
            if let durability = item.durability, durability.remaining == 0 { continue }
            guard let modifiers = modifiers(item, slot: slot) else { return nil }
            found.modifiers += modifiers.map(HealthModifier.init)
            found.enchantments += item.activeEnchantments.keys.sorted().map { HealthEnchantment(id: $0, slot: slot) }
        }
        return found
    }

    private static func modifiers(_ item: ItemStack, slot: String) -> [NBT]? {
        if item.components?["!minecraft:attribute_modifiers"] != nil { return [] }
        let component = item.components?["minecraft:attribute_modifiers"]
        let legacy = item.components?["AttributeModifiers"]
        guard component != nil || legacy != nil else { return item.id.hasPrefix("minecraft:") ? [] : nil }
        guard let entries = component?.list ?? component?["modifiers"]?.list ?? legacy?.list else { return nil }
        return entries.filter { entry in
            let name = entry["type"]?.string ?? entry["AttributeName"]?.string ?? ""
            guard EntityHealth.healthNames.contains(name) else { return false }
            let group = entry["slot"]?.string ?? entry["Slot"]?.string ?? "any"
            return EntityEquipment.matches(group: group, slot: slot) == true
        }
    }
}
