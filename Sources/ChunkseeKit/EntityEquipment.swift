import Foundation

/// Slot reading shared by health calculation and the public player/mob equipment records.
enum EntityEquipment {
    // EquipmentSlot's order also decides replacement of modifiers sharing an identity.
    static let slots = ["mainhand", "offhand", "feet", "legs", "chest", "head", "body", "saddle"]
    static let playerInventorySlots = [100: "feet", 101: "legs", 102: "chest", 103: "head", -106: "offhand"]
    static let saddledSpecies: Set<String> = ["minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:skeleton_horse",
        "minecraft:zombie_horse", "minecraft:camel", "minecraft:camel_husk", "minecraft:nautilus", "minecraft:zombie_nautilus"]
    static let llamaSpecies: Set<String> = ["minecraft:llama", "minecraft:trader_llama"]

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

    static func creature(_ nbt: NBT, species: String) -> [String: ItemStack]? {
        // A current compound, including an explicit empty one, supersedes old creature fields.
        if let items = current(nbt) { return items }
        var items: [String: ItemStack] = [:]
        var hasSavedEquipment = false
        for (key, names) in [("ArmorItems", ["feet", "legs", "chest", "head"]), ("HandItems", ["mainhand", "offhand"])] {
            guard let contents = nbt[key]?.list else { continue }
            hasSavedEquipment = true
            for (name, item) in zip(names, contents) { items[name] = ItemStack(item) }
        }
        if let armor = nbt["body_armor_item"], armor.compound != nil {
            hasSavedEquipment = true
            items["body"] = ItemStack(armor)
        }
        if species == "minecraft:horse", let armor = nbt["ArmorItem"] {
            // HorseBodyArmorItemFix clears the old chest entry, even for an empty ArmorItem.
            hasSavedEquipment = hasSavedEquipment || armor.compound != nil
            items["chest"] = nil
            items["body"] = ItemStack(armor)
        }
        if llamaSpecies.contains(species), let decor = nbt["DecorItem"] {
            hasSavedEquipment = hasSavedEquipment || decor.compound != nil
            items["body"] = ItemStack(decor)
        }
        if saddledSpecies.contains(species), let saddle = nbt["saddle"] ?? nbt["SaddleItem"] {
            hasSavedEquipment = hasSavedEquipment || saddle.compound != nil
            items["saddle"] = ItemStack(saddle)
        }
        return hasSavedEquipment ? items : nil
    }

    static func canWearPetEquipment(_ species: String) -> Bool {
        species == "minecraft:wolf" || llamaSpecies.contains(species) || saddledSpecies.contains(species)
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

/// Applicable unsaved modifiers from equipped items; arithmetic stays in EntityHealth.
enum EquipmentHealth {
    static func modifiers(in equipment: [String: ItemStack], enchantments: [String: EnchantmentDefinition]) -> [NBT]? {
        var found: [NBT] = []
        for slot in EntityEquipment.slots {
            guard let item = equipment[slot], item.count > 0 else { continue }
            if let durability = item.durability, durability.remaining == 0 { continue }
            guard let modifiers = modifiers(item, slot: slot, enchantments: enchantments) else { return nil }
            found += modifiers
        }
        return found
    }

    private static func modifiers(_ item: ItemStack, slot: String, enchantments: [String: EnchantmentDefinition]) -> [NBT]? {
        guard item.activeEnchantments.keys.allSatisfy({ id in
            Identifier(id).flatMap { enchantments[$0.description] }?.preservesSavedMaximum(in: slot) == true
        }) else { return nil }
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
