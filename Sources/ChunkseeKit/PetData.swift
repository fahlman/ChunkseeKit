import Foundation

/// Namespaced appearance IDs, independent of presentation or translation.
public struct CreatureAppearance: Sendable, Equatable, Codable {
    public var variant: String
    public var markings: String?

    public init(variant: String, markings: String? = nil) {
        self.variant = variant
        self.markings = markings
    }
}

enum CreatureAttributes {
    static let healthNames: Set<String> = ["minecraft:max_health", "minecraft:generic.max_health", "generic.max_health", "generic.maxHealth"]

    static func maximumHealth(_ nbt: NBT, species: String, dataVersion: Int?) -> Double? {
        // Minecraft saves permanent attribute modifiers. Effects and custom equipment can add
        // transient ones on loading; omit the maximum rather than present a partial total.
        guard !hasTransientHealthModifier(nbt) else { return nil }
        let attributes = nbt["attributes"]?.list ?? nbt["Attributes"]?.list ?? []
        guard let attribute = attributes.first(where: { healthNames.contains($0["id"]?.string ?? $0["Name"]?.string ?? "") }) else {
            // Verified against the 26.3 client, not inferred from the creature's current health.
            // Older/newer chunk versions still use explicit saved attributes when present.
            guard dataVersion == 5023 else { return nil }
            switch species {
            case "minecraft:cat": return 10
            case "minecraft:parrot": return 6
            case "minecraft:wolf": return nbt["Owner"] != nil || nbt["OwnerUUID"] != nil ? 40 : 8
            case "minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:llama", "minecraft:trader_llama": return 53
            case "minecraft:skeleton_horse": return 15
            case "minecraft:zombie_horse": return 25
            case "minecraft:camel": return 32
            default: return nil
            }
        }
        guard let base = attribute["base"]?.double ?? attribute["Base"]?.double, base.isFinite else { return nil }
        var added = 0.0, multipliedBase = 0.0, multipliedTotal = 1.0
        for modifier in attribute["modifiers"]?.list ?? attribute["Modifiers"]?.list ?? [] {
            guard let amount = modifier["amount"]?.double ?? modifier["Amount"]?.double, amount.isFinite else { return nil }
            switch modifier["operation"]?.string ?? modifier["Operation"]?.int.map(String.init) {
            case "add_value", "0": added += amount
            case "add_multiplied_base", "1": multipliedBase += amount
            case "add_multiplied_total", "2": multipliedTotal *= 1 + amount
            default: return nil
            }
        }
        // AttributeInstance applies additive modifiers before both kinds of multiplication.
        // MAX_HEALTH is a ranged attribute, clamped to 1...1024 in Java Edition.
        let result = (base + added) * (1 + multipliedBase) * multipliedTotal
        guard result.isFinite else { return nil }
        return min(1024, max(1, result))
    }

    private static func hasTransientHealthModifier(_ nbt: NBT) -> Bool {
        let effects = nbt["active_effects"]?.list ?? nbt["ActiveEffects"]?.list ?? []
        if effects.contains(where: { $0["id"]?.string == "minecraft:health_boost" || $0["Id"]?.int == 21 }) { return true }
        let equipped = Array((nbt["equipment"]?.compound ?? [:]).values)
            + ["body_armor_item", "ArmorItem", "SaddleItem", "DecorItem"].compactMap { nbt[$0] }
        return equipped.compactMap(ItemStack.init).contains { item in
            let component = item.components?["minecraft:attribute_modifiers"]
            let modifiers = component?.list ?? component?["modifiers"]?.list ?? item.components?["AttributeModifiers"]?.list ?? []
            return modifiers.contains { healthNames.contains($0["type"]?.string ?? $0["AttributeName"]?.string ?? "") }
        }
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
        let saddled = ["minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:skeleton_horse", "minecraft:zombie_horse", "minecraft:camel"]
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
