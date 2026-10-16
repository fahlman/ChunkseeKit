import Foundation

/// Engine-normalized appearance keys, independent of presentation or translation.
/// Wolf/cat variants are registry IDs; numeric variants/markings use documented symbolic keys.
public struct CreatureAppearance: Sendable, Equatable, Codable {
    public var variant: String
    public var markings: String?

    public init(variant: String, markings: String? = nil) {
        self.variant = variant
        self.markings = markings
    }
}

enum PetData {
    static let dyeNames = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                           "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]

    static func sittingOrder(_ nbt: NBT, species: String) -> Bool? {
        guard ["minecraft:wolf", "minecraft:cat", "minecraft:parrot"].contains(species) else { return nil }
        guard let tag = nbt["Sitting"] else { return false }
        guard let value = tag.int, value == 0 || value == 1 else { return nil }
        return value == 1
    }

    static func collarColor(_ nbt: NBT, species: String) -> String? {
        guard ["minecraft:wolf", "minecraft:cat"].contains(species) else { return nil }
        guard let tag = nbt["CollarColor"] else { return "red" }
        guard let value = tag.int, dyeNames.indices.contains(value) else { return nil }
        return dyeNames[value]
    }

    static func appearance(_ nbt: NBT, species: String) -> CreatureAppearance? {
        switch species {
        case "minecraft:wolf", "minecraft:cat":
            if let variant = nbt["variant"]?.string, !variant.isEmpty {
                return CreatureAppearance(variant: variant)
            }
            if species == "minecraft:cat" {
                return indexedAppearance(nbt["CatType"]?.int, variants: ["tabby", "black", "red", "siamese", "british_shorthair", "calico", "persian", "ragdoll", "white", "jellie", "all_black"])
            }
            return nil
        case "minecraft:parrot":
            return indexedAppearance(nbt["Variant"]?.int, variants: ["red_blue", "blue", "green", "yellow_blue", "gray"])
        case "minecraft:horse":
            guard let value = nbt["Variant"]?.int, value >= 0,
                  var appearance = indexedAppearance(value & 255, variants: ["white", "creamy", "chestnut", "brown", "black", "gray", "dark_brown"]) else { return nil }
            let markings = ["none", "white", "white_field", "white_dots", "black_dots"]
            let index = (value >> 8) & 255
            if markings.indices.contains(index), index != 0 { appearance.markings = "minecraft:" + markings[index] }
            return appearance
        case "minecraft:llama", "minecraft:trader_llama":
            return indexedAppearance(nbt["Variant"]?.int, variants: ["creamy", "white", "brown", "gray"])
        default: return nil
        }
    }

    private static func indexedAppearance(_ index: Int?, variants: [String]) -> CreatureAppearance? {
        guard let index, variants.indices.contains(index) else { return nil }
        return CreatureAppearance(variant: "minecraft:" + variants[index])
    }

    static func equipment(_ nbt: NBT, species: String) -> [String: ItemStack]? {
        let saddled = ["minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:skeleton_horse", "minecraft:zombie_horse", "minecraft:camel",
                       "minecraft:camel_husk", "minecraft:nautilus", "minecraft:zombie_nautilus"]
        let llama = ["minecraft:llama", "minecraft:trader_llama"].contains(species)
        let carriesChest = llama || ["minecraft:donkey", "minecraft:mule"].contains(species)
        let applicable = species == "minecraft:wolf" || llama || saddled.contains(species)
        var items: [String: ItemStack]
        if let current = nbt["equipment"]?.compound {
            items = current.compactMapValues(ItemStack.init)
        } else {
            items = [:]
            if let body = nbt["body_armor_item"].flatMap(ItemStack.init) { items["body"] = body }
            if species == "minecraft:horse", let armor = nbt["ArmorItem"].flatMap(ItemStack.init) { items["body"] = armor }
            if llama, let decor = nbt["DecorItem"].flatMap(ItemStack.init) { items["body"] = decor }
            if saddled.contains(species), let saddle = nbt["SaddleItem"].flatMap(ItemStack.init) { items["saddle"] = saddle }
        }
        if carriesChest, nbt["ChestedHorse"]?.int == 1 { items["storage"] = ItemStack(id: "minecraft:chest") }
        return applicable || !items.isEmpty ? items : nil
    }
}
