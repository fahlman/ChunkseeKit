import Foundation

/// Readable facts from one data-defined enchantment. No enchantment-ID catalog is used.
public struct EnchantmentDefinition: Sendable, Hashable, Codable {
    /// The definition's display component, before language lookup or layout. Missing,
    /// malformed, dynamic or over-budget text is unavailable without discarding other facts.
    public let description: TextComponent.Content?
    /// The definition's maximum level, after the game's integer conversion and 1...255 range check.
    /// This is definition metadata, not a restriction on the level stored on an item.
    public let maximumLevel: Int?
    /// Whether its effects declare unsaved maximum-health attribute modifiers. Nil means a
    /// relevant effect format cannot be interpreted, including functions with unknown behavior.
    public let hasMaximumHealthModifier: Bool?
    /// The definition's equipment-slot groups, when readable. Conditions are not evaluated.
    public let slots: [String]?

    public init?(data: Data) {
        var textBudget = ResourceReadBudget()
        self.init(data: data, textBudget: &textBudget)
    }

    private init?(data: Data, textBudget: inout ResourceReadBudget) {
        guard data.count <= ZipResources.maximumResourceSize,
              let json = try? AssetJSON.object(from: data) else { return nil }
        // Enchantment.DIRECT_CODEC reads description through ComponentSerialization.CODEC.
        description = json["description"].flatMap { try? TextComponent.content($0, budget: &textBudget) }
        // Enchantment.EnchantmentDefinition.CODEC uses intRange(1, 255) for max_level.
        let level = try? AssetJSON.integer(json["max_level"])
        maximumLevel = level.flatMap { (1...255).contains($0) ? $0 : nil }
        slots = json["slots"] as? [String]
        if let effects = json["effects"] {
            var reader = EnchantmentEffectHealth()
            hasMaximumHealthModifier = reader.read(effects)
        } else {
            // Enchantment's codec defaults an absent effects component map to empty.
            hasMaximumHealthModifier = false
        }
    }

    func preservesSavedMaximum(in slot: String) -> Bool {
        if hasMaximumHealthModifier == false { return true }
        guard let slots else { return false }
        // A known-inapplicable enchantment cannot contribute its effects to this slot.
        return slots.allSatisfy { EntityEquipment.matches(group: $0, slot: slot) == false }
    }

    fileprivate static func read(in packs: [WorldResourcePack]) throws -> [String: Self] {
        let registry = try WorldResourcePack.Registry(directory: "enchantment", in: packs)
        var remaining = 64 * 1024 * 1024
        // Exhausted description work must not discard otherwise readable definition facts.
        var textBudget = ResourceReadBudget()
        return try registry.readAll(maximumCount: 4096) { data in
            guard data.count <= remaining else { remaining = 0; return nil }
            remaining -= data.count
            return Self(data: data, textBudget: &textBudget)
        }
    }
}

extension GameAssets {
    /// A bounded snapshot of enchantment facts from this jar. Missing or malformed
    /// definitions are omitted; unknown effect formats remain explicit nil facts.
    public func enchantmentDefinitions() throws -> [String: EnchantmentDefinition] {
        try EnchantmentDefinition.read(in: [.zip(resources)])
    }
}

extension World {
    /// Reads the enabled data packs over the supplied current-game jar, using the shared
    /// resource-priority and invalid-override policy. Limits: 64 packs, 4,096 definitions,
    /// 16 MiB per file and 64 MiB total. Descriptions share 65,536 component/argument visits,
    /// with at most 64 component levels. No game-version-specific definition list is applied.
    /// Retain this immutable snapshot and pass it explicitly when resolving maximum health.
    public func enchantmentDefinitions(assets: GameAssets?) throws -> [String: EnchantmentDefinition] {
        guard let packs = try resourcePacks(assets: assets) else { return [:] }
        return try EnchantmentDefinition.read(in: packs)
    }
}

private struct EnchantmentEffectHealth {
    private var remaining = 65_536

    mutating func read(_ value: Any) -> Bool? {
        guard let components = value as? [String: Any] else { return nil }
        var found = false, unknown = false
        for (name, value) in components {
            guard remaining > 0 else { return found ? true : nil }
            let health = component(name, value: value)
            found = found || health == true
            unknown = unknown || health == nil
        }
        return found ? true : (unknown ? nil : false)
    }

    private mutating func component(_ name: String, value: Any) -> Bool? {
        guard consume(), let id = GameAssets.resourceID(name),
              let format = GeneratedEnchantmentEffects.components[id.description] else { return nil }
        switch format {
        case .attributes, .conditionalEffects:
            guard let entries = value as? [[String: Any]] else { return nil }
            var found = false, unknown = false
            for entry in entries {
                guard remaining > 0 else { return found ? true : nil }
                let health: Bool?
                if case .attributes = format { health = consume() ? attribute(entry) : nil }
                else { health = entry["effect"].flatMap { effectHealth($0, depth: 0) } }
                found = found || health == true
                unknown = unknown || health == nil
            }
            return found ? true : (unknown ? nil : false)
        case .conditionalValues, .sounds:
            // These codecs return numeric operations, immunity or sounds, not attributes.
            return value is [[String: Any]] ? false : nil
        case .value, .unit:
            return value is [String: Any] ? false : nil
        case .sound:
            return value is String || value is [String: Any] ? false : nil
        case .soundList:
            guard let sounds = value as? [Any] else { return nil }
            return sounds.allSatisfy { $0 is String || $0 is [String: Any] } ? false : nil
        }
    }

    private mutating func effectHealth(_ value: Any, depth: Int) -> Bool? {
        guard depth < 64, consume(), let effect = value as? [String: Any],
              let name = effect["type"] as? String, let id = GameAssets.resourceID(name),
              let format = GeneratedEnchantmentEffects.effects[id.description] else { return nil }
        switch format {
        case .attribute: return attribute(effect)
        case .allOf:
            guard let effects = effect["effects"] as? [Any] else { return nil }
            var found = false, unknown = false
            for nested in effects {
                guard remaining > 0 else { return found ? true : nil }
                let health = effectHealth(nested, depth: depth + 1)
                found = found || health == true
                unknown = unknown || health == nil
            }
            return found ? true : (unknown ? nil : false)
        case .noAttribute: return false
        case .unavailable: return nil
        }
    }

    private func attribute(_ value: [String: Any]) -> Bool? {
        guard let name = value["attribute"] as? String, let id = GameAssets.resourceID(name) else { return nil }
        return EntityHealth.healthNames.contains(id.description)
    }

    private mutating func consume() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}
