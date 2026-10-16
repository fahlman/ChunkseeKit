import Foundation

enum EntityHealth {
    static let healthNames: Set<String> = ["minecraft:max_health", "minecraft:generic.max_health", "generic.max_health", "generic.maxHealth"]

    static func maximumHealth(_ nbt: NBT, species: String, dataVersion: Int?) -> Double? {
        // Minecraft saves permanent attribute modifiers. Effects and custom equipment can add
        // transient ones on loading; omit the maximum rather than present a partial total.
        guard !hasTransientHealthModifier(nbt) else { return nil }
        return value(nbt, defaultBase: defaultMaximum(nbt, species: species, dataVersion: dataVersion))
    }

    static func value(_ nbt: NBT, defaultBase: Double?, additionalModifiers: [NBT] = []) -> Double? {
        let attributes = nbt["attributes"]?.list ?? nbt["Attributes"]?.list ?? []
        let attribute = attributes.first { healthNames.contains($0["id"]?.string ?? $0["Name"]?.string ?? "") }
        let base: Double
        if let attribute {
            guard let saved = attribute["base"]?.double ?? attribute["Base"]?.double else { return nil }
            base = saved
        } else if let defaultBase { base = defaultBase }
        else { return nil }
        guard base.isFinite else { return nil }
        var modifiers = attribute?["modifiers"]?.list ?? attribute?["Modifiers"]?.list ?? []
        // Transient modifiers replace permanent ones with the same identity on loading.
        for modifier in additionalModifiers {
            if let id = modifierID(modifier), let index = modifiers.firstIndex(where: { modifierID($0) == id }) {
                modifiers[index] = modifier
            } else { modifiers.append(modifier) }
        }
        var added = 0.0, multipliedBase = 0.0, multipliedTotal = 1.0
        for modifier in modifiers {
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

    private static func modifierID(_ nbt: NBT) -> String? {
        if let id = nbt["id"]?.string { return id }
        if let uuid = nbt["UUID"]?.uuid { return uuid.uuidString }
        if case .long(let most)? = nbt["UUIDMost"], case .long(let least)? = nbt["UUIDLeast"] { return "\(most):\(least)" }
        return nil
    }

    private static func defaultMaximum(_ nbt: NBT, species: String, dataVersion: Int?) -> Double? {
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
