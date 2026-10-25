import Foundation

/// Engine-normalized appearance keys, independent of presentation or translation.
/// Saved variant strings remain intact; numeric variants/markings use generated symbolic keys.
public struct CreatureAppearance: Sendable, Equatable, Codable {
    public var variant: String
    public var markings: String?

    public init(variant: String, markings: String? = nil) {
        self.variant = variant
        self.markings = markings
    }
}

enum CreatureData {
    static func sittingOrder(_ nbt: NBT, species: String) -> Bool? {
        guard ["minecraft:wolf", "minecraft:cat", "minecraft:parrot"].contains(species) else { return nil }
        guard let tag = nbt["Sitting"] else { return false }
        guard let value = tag.int, value == 0 || value == 1 else { return nil }
        return value == 1
    }

    static func collarColor(_ nbt: NBT, species: String, isOwned: Bool) -> String? {
        if let tag = nbt["CollarColor"] { return tag.int.flatMap(DyeColor.init(legacyID:))?.rawValue }
        return isOwned && ["minecraft:wolf", "minecraft:cat"].contains(species) ? "red" : nil
    }

    static func appearance(_ nbt: NBT, species: String) -> CreatureAppearance? {
        for field in ["variant", "Variant"] {
            if let variant = nbt[field]?.string, !variant.isEmpty { return CreatureAppearance(variant: variant) }
        }
        guard let schema = GeneratedMobAppearance.schemas[species],
              let value = nbt[schema.field]?.int, value >= 0 else { return nil }
        // Horse's packed save format stores the coat in the low byte and markings above it.
        let variantID = schema.markings == nil ? value : value & 255
        guard let variant = schema.variants[variantID] else { return nil }
        return CreatureAppearance(variant: variant, markings: schema.markings?[(value >> 8) & 255])
    }

    static func equipment(_ nbt: NBT, species: String, isOwned: Bool) -> [String: ItemStack]? {
        var items = EntityEquipment.creature(nbt, species: species)
        if nbt["ChestedHorse"]?.bool == true {
            if items == nil { items = [:] }
            if items?["storage"] == nil { items?["storage"] = ItemStack(id: "minecraft:chest") }
        }
        return items ?? (isOwned && EntityEquipment.canWearPetEquipment(species) ? [:] : nil)
    }
}
