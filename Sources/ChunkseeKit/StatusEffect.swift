import Foundation

/// One currently active saved effect. Duration is in game ticks, or -1 for an infinite effect.
public struct StatusEffect: Sendable, Equatable {
    public var id: String
    /// Zero-based strength, as stored by Minecraft.
    public var amplifier: Int
    public var durationTicks: Int
    public var level: Int { amplifier + 1 }

    public init(id: String, amplifier: Int, durationTicks: Int) {
        self.id = id
        self.amplifier = amplifier
        self.durationTicks = durationTicks
    }

    init?(_ nbt: NBT) {
        let id: String
        if let saved = nbt["id"]?.string, !saved.isEmpty {
            id = saved.contains(":") ? saved : "minecraft:" + saved
        } else if let number = nbt["Id"]?.int, Self.legacyIDs.indices.contains(number), number > 0 {
            id = "minecraft:" + Self.legacyIDs[number]
        } else { return nil }
        let amplifier: Int
        switch nbt["amplifier"] ?? nbt["Amplifier"] {
        case .byte(let value)?: amplifier = Int(UInt8(bitPattern: value))
        case nil: amplifier = 0
        case let tag?:
            guard let value = tag.int else { return nil }
            amplifier = value
        }
        guard (0...255).contains(amplifier),
              let duration = nbt["duration"]?.int ?? nbt["Duration"]?.int,
              duration == -1 || duration > 0 else { return nil }
        self.init(id: id, amplifier: amplifier, durationTicks: duration)
    }

    // Before 1.20.2 effects used numeric IDs; player files can remain in the older format.
    private static let legacyIDs = ["", "speed", "slowness", "haste", "mining_fatigue", "strength",
        "instant_health", "instant_damage", "jump_boost", "nausea", "regeneration", "resistance",
        "fire_resistance", "water_breathing", "invisibility", "blindness", "night_vision", "hunger",
        "weakness", "poison", "wither", "health_boost", "absorption", "saturation", "glowing",
        "levitation", "luck", "unluck", "slow_falling", "conduit_power", "dolphins_grace", "bad_omen",
        "hero_of_the_village", "darkness"]
}

extension PlayerInfo {
    /// Active effects at the last save, not the weaker effects queued in `hidden_effect`.
    public var activeEffects: [StatusEffect] {
        StatusEffect.active(in: nbt)
    }

    /// The selected hotbar item, or an explicit saved main-hand equipment item when present.
    public var mainHandItem: ItemStack? {
        if let mainHand = equipment["mainhand"] { return mainHand }
        guard let selectedSlot, (0..<9).contains(selectedSlot) else { return nil }
        return inventory.first { $0.slot == selectedSlot }
    }

    /// Saved maximum health in half-hearts, including permanent effects and applicable equipment.
    /// Unknown defaults or unsupported modifiers leave it unavailable.
    public var maxHealth: Double? { PlayerHealth.maximum(self) }
}

private enum PlayerHealth {
    static func maximum(_ player: PlayerInfo) -> Double? {
        guard EntityHealth.supportsEffects(player.nbt) else { return nil }
        // Health Boost is already a permanent saved attribute modifier, including legacy UUIDs.
        var equipment = player.equipment
        equipment["mainhand"] = player.mainHandItem
        guard let modifiers = EquipmentHealth.modifiers(in: equipment) else { return nil }
        return EntityHealth.value(player.nbt, defaultBase: player.dataVersion == 5023 ? 20 : nil,
                                  additionalModifiers: modifiers)
    }

}

extension StatusEffect {
    static func active(in nbt: NBT) -> [StatusEffect] {
        (nbt["active_effects"]?.list ?? nbt["ActiveEffects"]?.list ?? []).compactMap(StatusEffect.init)
    }
}
