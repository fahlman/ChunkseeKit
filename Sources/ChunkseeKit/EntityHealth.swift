import Foundation

enum EntityHealth {
    static let healthNames: Set<String> = ["minecraft:max_health", "minecraft:generic.max_health", "generic.max_health", "generic.maxHealth"]

    static func maximumHealth(_ nbt: NBT, species: String, isTamed: Bool?, enchantments: [String: EnchantmentDefinition]) -> Double? {
        guard supportsEffects(nbt),
              let modifiers = EquipmentHealth.modifiers(in: EntityEquipment.creature(nbt) ?? [:], enchantments: enchantments) else { return nil }
        let base = defaultMaximum(nbt, species: species)
        let untamedBase = GeneratedHealthDefaults.untamedBaseOverrides[species]
        // An unrecognized saved owner can still require the game's old-owner conversion.
        // Do not treat an owner we cannot identify as proof that a wolf is untamed.
        if untamedBase != nil, isTamed == nil { return nil }
        // Loading an unowned wolf calls setTame(false, true): reset the base, retaining modifiers.
        // Owned wolves load with setTame(true, false), preserving their saved base.
        let loadedBase = isTamed == false ? untamedBase : nil
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
        // MAX_HEALTH uses the game's generated range, then LivingEntity converts to Float.
        let result = (base + added) * (1 + multipliedBase) * multipliedTotal
        guard result.isFinite else { return nil }
        return Double(Float(min(GeneratedHealthDefaults.maximum, max(GeneratedHealthDefaults.minimum, result))))
    }

    private static func modifierID(_ nbt: NBT) -> String? {
        if let id = nbt["id"]?.string { return id }
        return nbt.uuid?.uuidString
    }

    private static func defaultMaximum(_ nbt: NBT, species: String) -> Double? {
        if let kind = GeneratedHealthDefaults.cubeKinds[species] {
            // The save stores size minus one. ValueInput narrows to a Java int before
            // adding one (including overflow); setSize clamps before setting health.
            // Cube mobs do this before loading attributes, so an explicit saved base wins.
            let size = (nbt["Size"]?.javaInt ?? 0) &+ 1
            let clamped = min(GeneratedHealthDefaults.maximumCubeSize,
                              max(GeneratedHealthDefaults.minimumCubeSize, Int(size)))
            return GeneratedHealthDefaults.cubeBases[kind][clamped - GeneratedHealthDefaults.minimumCubeSize]
        }
        return GeneratedHealthDefaults.bases[species]
    }

}
