import Foundation

/// Engine-normalized appearance keys, independent of presentation or translation.
/// Saved variant strings remain intact; numeric variants/markings use generated symbolic keys.
public struct CreatureAppearance: Sendable, Equatable, Codable {
    /// Nil when only other appearance facts can be interpreted.
    public var variant: String?
    public var markings: String?
    /// Independent engine keys, currently body_shape, base_color, pattern_color, main_gene,
    /// and hidden_gene. Saved strings remain intact; names and ordering stay client-owned.
    public var traits: [String: String]?

    public init(variant: String? = nil, markings: String? = nil, traits: [String: String]? = nil) {
        self.variant = variant
        self.markings = markings
        self.traits = traits
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

    static func appearance(_ nbt: NBT, species: String, villager: Villager?) -> CreatureAppearance? {
        var result = CreatureAppearance(variant: string(nbt["variant"]) ?? string(nbt["Variant"]))
        if let schema = GeneratedMobAppearance.schemas[species] {
            result.variant = result.variant ?? string(nbt[schema.field])
            if let value = nbt[schema.field]?.int {
                if let shapes = schema.bodyShapes, Int32(exactly: value) != nil {
                    // TropicalFish packs size/pattern in the low 16 bits and two dye bytes above.
                    result.variant = result.variant ?? schema.variants[value & 65535]
                    var traits: [String: String] = [:]
                    traits["body_shape"] = shapes[value & 255]
                    traits["base_color"] = DyeColor(legacyID: (value >> 16) & 255)?.rawValue
                    traits["pattern_color"] = DyeColor(legacyID: (value >> 24) & 255)?.rawValue
                    result.traits = traits
                } else if value >= 0 {
                    let variantID = schema.markings == nil ? value : value & 255
                    result.variant = result.variant ?? schema.variants[variantID]
                    result.markings = schema.markings?[(value >> 8) & 255]
                }
            }
        }
        // These uniquely named saved structures carry their meaning without a species catalog.
        let main = string(nbt["MainGene"]), hidden = string(nbt["HiddenGene"])
        if main != nil || hidden != nil {
            var traits = result.traits ?? [:]
            traits["main_gene"] = main
            traits["hidden_gene"] = hidden
            result.traits = traits
            result.variant = result.variant ?? pandaVariant(main: main, hidden: hidden)
        }
        if let type = villager?.type, !type.isEmpty { result.variant = result.variant ?? type }
        if result.traits?.isEmpty == true { result.traits = nil }
        return result.variant != nil || result.markings != nil || result.traits != nil ? result : nil
    }

    private static func string(_ nbt: NBT?) -> String? {
        guard let value = nbt?.string, !value.isEmpty else { return nil }
        return value
    }

    private static func pandaVariant(main: String?, hidden: String?) -> String? {
        guard let main, let recessive = GeneratedMobAppearance.pandaRecessiveGenes[main] else { return nil }
        if !recessive { return "minecraft:" + main }
        guard let hidden, GeneratedMobAppearance.pandaRecessiveGenes[hidden] != nil else { return nil }
        // Panda.Gene.getVariantFromGenes shows a recessive look only for matching genes.
        return "minecraft:" + (main == hidden ? main : GeneratedMobAppearance.pandaNormalVariant)
    }

    static func equipment(_ nbt: NBT, saved: [String: ItemStack]?) -> [String: ItemStack]? {
        var items = saved
        // AbstractChestedHorse reads this flag with ValueInput.getBooleanOr(false).
        if nbt["ChestedHorse"]?.compoundBoolean == true {
            if items == nil { items = [:] }
            if items?["storage"] == nil { items?["storage"] = ItemStack(id: GeneratedEquipmentFacts.attachedChestItem) }
        }
        return items
    }
}
