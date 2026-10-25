extension World {
    /// Biome IDs declared by the game's standard association tag for this dimension.
    /// Reads the matching jar and enabled data packs at runtime; no biome inventory is built in.
    /// These tags describe associations, not proof of saved usage or custom-generator output.
    ///
    /// Missing/unreadable tags, unavailable game files and dimensions without a standard tag
    /// return nil. A valid empty tag returns an empty array. Saved biome usage stays independent.
    public func possibleBiomes(in dimensionID: String, assets: GameAssets?) throws -> [String]? {
        let tag: String
        switch Identifier(dimensionID)?.description {
        case "minecraft:overworld": tag = "minecraft:is_overworld"
        case "minecraft:the_nether": tag = "minecraft:is_nether"
        case "minecraft:the_end": tag = "minecraft:is_end"
        default: return nil
        }
        return try tags(for: [tag], in: "worldgen/biome", assets: assets)[tag]?.members.map(\.id)
    }
}
