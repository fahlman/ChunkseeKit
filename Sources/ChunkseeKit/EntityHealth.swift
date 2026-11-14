import Foundation

enum EntityHealth {
    static let healthNames: Set<String> = ["minecraft:max_health", "minecraft:generic.max_health", "generic.max_health", "generic.maxHealth"]

    static func creatureInputs(_ nbt: NBT, species: String, isTamed: Bool?, equipment: [String: ItemStack]?) -> MaximumHealthInputs? {
        // An unreadable equipment field is not the same saved fact as known empty equipment.
        guard let equipment else { return nil }
        let base = defaultMaximum(nbt, species: species)
        let untamedBase = GeneratedHealthDefaults.untamedBaseOverrides[species]
        // An unrecognized saved owner can still require the game's old-owner conversion.
        // Do not treat an owner we cannot identify as proof that a wolf is untamed.
        if untamedBase != nil, isTamed == nil { return nil }
        // Loading an unowned wolf calls setTame(false, true): reset the base, retaining modifiers.
        // Owned wolves load with setTame(true, false), preserving their saved base.
        let loadedBase = isTamed == false ? untamedBase : nil
        return inputs(nbt, defaultBase: base, baseOverride: loadedBase,
                      equipment: equipment)
    }

    /// Keep the existing conservative mod-default boundary the same for players and creatures.
    static func supportsEffects(_ nbt: NBT) -> Bool {
        StatusEffect.active(in: nbt).allSatisfy { $0.id.hasPrefix("minecraft:") }
    }

    static func inputs(_ nbt: NBT, defaultBase: Double?, baseOverride: Double?,
                       equipment: [String: ItemStack]) -> MaximumHealthInputs? {
        guard supportsEffects(nbt), let equipped = EquipmentHealth.inputs(in: equipment) else { return nil }
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
        let modifiers = attribute?["modifiers"]?.list ?? attribute?["Modifiers"]?.list ?? []
        return MaximumHealthInputs(base: base, savedModifiers: modifiers.map(HealthModifier.init),
                                   equippedModifiers: equipped.modifiers, enchantments: equipped.enchantments)
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
