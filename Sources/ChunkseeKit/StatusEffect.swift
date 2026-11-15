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
        guard let id = Self.savedID(nbt),
              let amplifier = Self.savedAmplifier(nbt["amplifier"] ?? nbt["Amplifier"]),
              let duration = nbt["duration"]?.int ?? nbt["Duration"]?.int,
              duration == -1 || duration > 0 else { return nil }
        self.init(id: id, amplifier: amplifier, durationTicks: duration)
    }

    /// Shared by active effects and potion contents; only active effects require a live duration.
    static func savedID(_ nbt: NBT) -> String? {
        if let saved = nbt["id"]?.string, !saved.isEmpty {
            return Identifier(saved)?.description
        } else if let number = nbt["Id"]?.javaInt.map(Int.init),
                  GeneratedLegacyContentIDs.effects.indices.contains(number) {
            return GeneratedLegacyContentIDs.effects[number]
        }
        return nil
    }

    /// 26.3's UNSIGNED_BYTE codec narrows Number.byteValue before unsigned interpretation.
    /// Edited numeric tags therefore wrap, while a missing amplifier still defaults to zero.
    static func savedAmplifier(_ tag: NBT?) -> Int? {
        guard let tag else { return 0 }
        return tag.javaInt.map { Int(UInt8(truncatingIfNeeded: $0)) }
    }
}

extension PlayerInfo {
    /// Active effects at the last save, not the weaker effects queued in `hidden_effect`.
    public var activeEffects: [StatusEffect] {
        StatusEffect.active(in: nbt)
    }

    /// The selected hotbar item, or an explicit saved main-hand equipment item when present.
    public var mainHandItem: ItemStack? {
        if let mainHand = equipment["mainhand"] { return mainHand }
        guard let selectedSlot else { return nil }
        return inventorySlots(in: .hotbar)[selectedSlot]
    }

    /// Saved inputs, independent of the selected resource definitions.
    public var healthInputs: MaximumHealthInputs? {
        // Health Boost is already a permanent saved attribute modifier, including legacy UUIDs.
        EntityHealth.inputs(nbt, defaultBase: GeneratedHealthDefaults.bases[GeneratedHealthDefaults.player],
                            baseOverride: nil, equipment: equippedItems)
    }

    /// Maximum health in half-hearts, or nil when saved inputs or current definitions are unavailable.
    public func maximumHealth(enchantments: [String: EnchantmentDefinition]) -> Double? {
        healthInputs?.maximum(enchantments: enchantments)
    }
}

extension StatusEffect {
    static func active(in nbt: NBT) -> [StatusEffect] {
        (nbt["active_effects"]?.list ?? nbt["ActiveEffects"]?.list ?? []).compactMap(StatusEffect.init)
    }
}
