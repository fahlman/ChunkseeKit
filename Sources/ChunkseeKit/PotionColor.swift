extension ItemStack {
    /// An explicit saved potion override as 0xRRGGBB, independent of effect/definition defaults.
    public var customPotionColor: UInt32? {
        ItemColor.integer(SavedPotion(components).customColor)
    }

    /// The game's potion tint, using an explicit override or visible effects weighted by level.
    /// Supply the item definition's default RGB. Generated code-only potion/effect defaults
    /// apply independently of gameDataVersion, retained for existing callers. Unknown needed facts,
    /// malformed color-driving fields or more than 4096 effects return nil, not a guessed color.
    /// Missing/removed contents and no visible effects use the supplied default.
    public func potionColor(gameDataVersion _: Int32, defaultColor: UInt32) -> UInt32? {
        let saved = SavedPotion(components)
        if let override = saved.customColor { return ItemColor.integer(override) }
        guard saved.isReadable else { return nil }
        var effects = [PotionColorEffect]()
        if let base = saved.base {
            guard let rawID = base.string, let id = Identifier(rawID),
                  let recipe = GeneratedPotionColors.recipes[id.description] else { return nil }
            effects = recipe
        }
        if let custom = saved.effects {
            guard let list = custom.list, list.count <= 4096 - effects.count else { return nil }
            for entry in list {
                guard let id = StatusEffect.savedID(entry),
                      let amplifier = StatusEffect.savedAmplifier(entry["amplifier"] ?? entry["Amplifier"]) else { return nil }
                let visibility = entry["show_particles"] ?? entry["ShowParticles"]
                // NbtOps.getBooleanValue compares Number.doubleValue with zero, including NaN.
                guard visibility == nil || visibility?.double != nil else { return nil }
                let visible = visibility?.double.map { $0 != 0 } ?? true
                if visible { effects.append(.init(id: id, amplifier: amplifier)) }
            }
        }
        var red = 0, green = 0, blue = 0, weight = 0
        for effect in effects {
            guard let color = GeneratedPotionColors.effects[effect.id] else { return nil }
            let level = effect.amplifier + 1
            red += Int((color >> 16) & 255) * level
            green += Int((color >> 8) & 255) * level
            blue += Int(color & 255) * level
            weight += level
        }
        guard weight > 0 else { return defaultColor & 0x00ff_ffff }
        return UInt32(red / weight) << 16 | UInt32(green / weight) << 8 | UInt32(blue / weight)
    }
}

/// Current components take precedence even when malformed; removal suppresses older tags.
private struct SavedPotion {
    let value: NBT?
    let modern: Bool

    init(_ components: NBT?) {
        if components?["!minecraft:potion_contents"] != nil {
            value = nil; modern = true
        } else if let current = components?["minecraft:potion_contents"] {
            value = current; modern = true
        } else {
            value = components; modern = false
        }
    }

    var isReadable: Bool { value == nil || value?.compound != nil || (modern && value?.string != nil) }
    var customColor: NBT? { value?[modern ? "custom_color" : "CustomPotionColor"] }
    var base: NBT? {
        // PotionContents.CODEC also accepts the potion holder ID as a shorthand string.
        if modern, value?.string != nil { return value }
        return value?[modern ? "potion" : "Potion"]
    }
    var effects: NBT? { value?[modern ? "custom_effects" : "CustomPotionEffects"] }
}

struct PotionColorEffect: Sendable {
    let id: String
    let amplifier: Int
}
