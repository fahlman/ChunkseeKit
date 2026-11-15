import Foundation

/// Typed saved modifiers and the base established by saved attributes or generated defaults.
/// These inputs are independent of the selected game files.
/// Resolve again with current definitions after decoding a cached region.
public struct MaximumHealthInputs: Sendable, Equatable, Codable {
    let base: Double
    let savedModifiers: [HealthModifier]
    let equippedModifiers: [HealthModifier]
    let enchantments: [HealthEnchantment]

    /// Half-hearts, or nil when a saved modifier or required definition is unavailable.
    public func maximum(enchantments definitions: [String: EnchantmentDefinition]) -> Double? {
        guard base.isFinite, enchantments.allSatisfy({ entry in
            Identifier(entry.id).flatMap { definitions[$0.description] }?
                .preservesSavedMaximum(in: entry.slot) == true
        }) else { return nil }

        var modifiers = savedModifiers
        // Equipment replaces the first saved modifier with the same identity before
        // validation. A malformed saved modifier can therefore be replaced by a valid one.
        for modifier in equippedModifiers {
            if let id = modifier.id, let index = modifiers.firstIndex(where: { $0.id == id }) {
                modifiers[index] = modifier
            } else { modifiers.append(modifier) }
        }
        var added = 0.0, multipliedBase = 0.0, multipliedTotal = 1.0
        for modifier in modifiers {
            guard let amount = modifier.amount, amount.isFinite else { return nil }
            switch modifier.operation {
            case .add: added += amount
            case .multiplyBase: multipliedBase += amount
            case .multiplyTotal: multipliedTotal *= 1 + amount
            case nil: return nil
            }
        }
        // AttributeInstance adds before multiplying; LivingEntity rounds the bounded
        // MAX_HEALTH attribute to Float. Both range limits come from the game generator.
        let result = (base + added) * (1 + multipliedBase) * multipliedTotal
        guard result.isFinite else { return nil }
        return Double(Float(min(GeneratedHealthDefaults.maximum, max(GeneratedHealthDefaults.minimum, result))))
    }
}

struct HealthModifier: Sendable, Equatable, Codable {
    enum Operation: String, Sendable, Codable { case add, multiplyBase, multiplyTotal }

    let id: String?
    let amount: Double?
    let operation: Operation?

    init(_ nbt: NBT) {
        id = nbt["id"]?.string ?? nbt.uuid?.uuidString
        amount = (nbt["amount"]?.double ?? nbt["Amount"]?.double).flatMap { $0.isFinite ? $0 : nil }
        switch nbt["operation"]?.string ?? nbt["Operation"]?.int.map(String.init) {
        case "add_value", "0": operation = .add
        case "add_multiplied_base", "1": operation = .multiplyBase
        case "add_multiplied_total", "2": operation = .multiplyTotal
        default: operation = nil
        }
    }
}

struct HealthEnchantment: Sendable, Equatable, Codable {
    let id: String
    let slot: String
}
