import Foundation

/// Vanilla item defaults omitted from item stacks, checked against the 26.3 client.
enum VanillaItemDurability {
    static let values: [String: Int] = {
        var values = ["bow": 384, "crossbow": 465, "trident": 250, "shield": 336, "elytra": 432,
                      "fishing_rod": 64, "flint_and_steel": 64, "shears": 238, "brush": 64,
                      "carrot_on_a_stick": 25, "warped_fungus_on_a_stick": 100, "mace": 500, "wolf_armor": 64]
        let tools = ["wooden": 59, "stone": 131, "copper": 190, "iron": 250, "golden": 32, "diamond": 1561, "netherite": 2031]
        for (material, maximum) in tools {
            for tool in ["sword", "shovel", "pickaxe", "axe", "hoe", "spear"] { values[material + "_" + tool] = maximum }
        }
        let armor = ["leather": 5, "copper": 11, "chainmail": 15, "iron": 15, "golden": 7, "diamond": 33, "netherite": 37]
        for (material, factor) in armor {
            for (piece, multiplier) in ["helmet": 11, "chestplate": 16, "leggings": 15, "boots": 13] {
                values[material + "_" + piece] = factor * multiplier
            }
        }
        values["turtle_helmet"] = 25 * 11
        return Dictionary(uniqueKeysWithValues: values.map { ("minecraft:" + $0.key, $0.value) })
    }()
}
