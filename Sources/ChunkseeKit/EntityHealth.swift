import Foundation

enum EntityHealth {
    static let healthNames: Set<String> = ["minecraft:max_health", "minecraft:generic.max_health", "generic.max_health", "generic.maxHealth"]

    static func maximumHealth(_ nbt: NBT, species: String, dataVersion: Int?, isTamed: Bool?, enchantments: [String: EnchantmentDefinition]) -> Double? {
        guard supportsEffects(nbt),
              let modifiers = EquipmentHealth.modifiers(in: EntityEquipment.creature(nbt, species: species) ?? [:], enchantments: enchantments) else { return nil }
        let base = defaultMaximum(species: species, dataVersion: dataVersion)
        // An unrecognized saved owner can still require the game's old-owner conversion.
        // Do not treat an owner we cannot identify as proof that a wolf is untamed.
        if species == "minecraft:wolf", base != nil, isTamed == nil { return nil }
        // Loading an unowned wolf calls setTame(false, true): reset the base, retaining modifiers.
        // Owned wolves load with setTame(true, false), preserving their saved base.
        let loadedBase = species == "minecraft:wolf" && isTamed == false ? base : nil
        return value(nbt, defaultBase: base, additionalModifiers: modifiers, baseOverride: loadedBase)
    }

    /// Keep the existing conservative mod-default boundary the same for players and creatures.
    static func supportsEffects(_ nbt: NBT) -> Bool {
        StatusEffect.active(in: nbt).allSatisfy { $0.id.hasPrefix("minecraft:") }
    }

    static func value(_ nbt: NBT, defaultBase: Double?, additionalModifiers: [NBT] = [], baseOverride: Double? = nil) -> Double? {
        let attributes = nbt["attributes"]?.list ?? nbt["Attributes"]?.list ?? []
        let attribute = attributes.first { healthNames.contains($0["id"]?.string ?? $0["Name"]?.string ?? "") }
        let base: Double
        if let baseOverride { base = baseOverride }
        else if let attribute {
            guard let saved = attribute["base"]?.double ?? attribute["Base"]?.double else { return nil }
            base = saved
        } else if let defaultBase { base = defaultBase }
        else { return nil }
        guard base.isFinite else { return nil }
        var modifiers = attribute?["modifiers"]?.list ?? attribute?["Modifiers"]?.list ?? []
        // Equipped-item modifiers replace a saved modifier with the same identity.
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
        return Double(Float(min(1024, max(1, result))))
    }

    private static func modifierID(_ nbt: NBT) -> String? {
        if let id = nbt["id"]?.string { return id }
        return nbt.uuid?.uuidString
    }

    private static func defaultMaximum(species: String, dataVersion: Int?) -> Double? {
        // Exact release data versions only; do not infer defaults for snapshots or newer saves.
        if let dataVersion, SaveVersion.verifiedRecentPetHealth.contains(dataVersion) {
            switch species {
            case "minecraft:cat": return 10
            case "minecraft:parrot": return 6
            case "minecraft:wolf": return 8
            default: break
            }
        }
        guard dataVersion == SaveVersion.java26_3 else { return nil }
        switch species {
        case "minecraft:horse", "minecraft:donkey", "minecraft:mule", "minecraft:llama", "minecraft:trader_llama": return 53
        case "minecraft:skeleton_horse": return 15
        case "minecraft:zombie_horse": return 25
        case "minecraft:camel", "minecraft:camel_husk": return 32
        case "minecraft:nautilus", "minecraft:zombie_nautilus": return 15
        default: return nil
        }
    }

}
