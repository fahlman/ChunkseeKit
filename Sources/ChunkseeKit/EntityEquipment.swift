import Foundation

/// Slot reading shared by health calculation and the public player/pet equipment records.
enum EntityEquipment {
    // EquipmentSlot's order also decides replacement of modifiers sharing an identity.
    static let slots = ["mainhand", "offhand", "feet", "legs", "chest", "head", "body", "saddle"]
    static let playerInventorySlots = [100: "feet", 101: "legs", 102: "chest", 103: "head", -106: "offhand"]
    static let saddledSpecies: Set<String> = ["minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:skeleton_horse",
        "minecraft:zombie_horse", "minecraft:camel", "minecraft:camel_husk", "minecraft:nautilus", "minecraft:zombie_nautilus"]
    static let llamaSpecies: Set<String> = ["minecraft:llama", "minecraft:trader_llama"]

    static func current(_ nbt: NBT) -> [String: ItemStack]? {
        nbt["equipment"]?.compound.map { values in
            values.filter { slots.contains($0.key) }.compactMapValues(ItemStack.init)
        }
    }

    static func player(_ nbt: NBT) -> [String: ItemStack] {
        var items = current(nbt) ?? [:]
        for item in ItemStack.list(nbt["Inventory"]) {
            if let slot = item.slot, let name = playerInventorySlots[slot], items[name] == nil { items[name] = item }
        }
        return items
    }

    static func creature(_ nbt: NBT, species: String) -> [String: ItemStack] {
        // A current compound, including an explicit empty one, supersedes old creature fields.
        if let items = current(nbt) { return items }
        var items: [String: ItemStack] = [:]
        for (key, names) in [("ArmorItems", ["feet", "legs", "chest", "head"]), ("HandItems", ["mainhand", "offhand"])] {
            for (name, item) in zip(names, nbt[key]?.list ?? []) { items[name] = ItemStack(item) }
        }
        items["body"] = nbt["body_armor_item"].flatMap(ItemStack.init)
        if species == "minecraft:horse", let armor = nbt["ArmorItem"].flatMap(ItemStack.init) { items["body"] = armor }
        if llamaSpecies.contains(species), let decor = nbt["DecorItem"].flatMap(ItemStack.init) { items["body"] = decor }
        if saddledSpecies.contains(species) {
            items["saddle"] = (nbt["saddle"] ?? nbt["SaddleItem"]).flatMap(ItemStack.init)
        }
        return items
    }

    static func canWearPetEquipment(_ species: String) -> Bool {
        species == "minecraft:wolf" || llamaSpecies.contains(species) || saddledSpecies.contains(species)
    }

    static func carriesChest(_ species: String) -> Bool {
        llamaSpecies.contains(species) || ["minecraft:donkey", "minecraft:mule"].contains(species)
    }
}

/// Applicable unsaved modifiers from equipped items; arithmetic stays in EntityHealth.
enum EquipmentHealth {
    static func modifiers(in equipment: [String: ItemStack]) -> [NBT]? {
        var found: [NBT] = []
        for slot in EntityEquipment.slots {
            guard let item = equipment[slot], item.count > 0 else { continue }
            if let durability = item.durability, durability.remaining == 0 { continue }
            guard let modifiers = modifiers(item, slot: slot) else { return nil }
            found += modifiers
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
            return group == "any" || group == slot || (group == "hand" && ["mainhand", "offhand"].contains(slot))
                || (group == "armor" && ["head", "chest", "legs", "feet", "body"].contains(slot))
        }
    }
}
