extension GameAssets {
    /// The code-defined spawn egg for an entity type, when its item definition is readable
    /// in this asset jar. The release tool extracts Minecraft's own entity-data lookup;
    /// this never guesses an item name or treats an unfamiliar entity as having no egg.
    /// Nil means the relationship or resource is unavailable. The selected model may still
    /// be unsupported; read it through defaultItemModel and keep fallback presentation client-owned.
    /// No asset-version gate is applied. Custom/modded prototype relationships are not supplied
    /// by item-picture definitions, so they remain unknown without their code facts.
    public func spawnEggItemID(for entityType: String) -> Identifier? {
        guard let entity = Identifier(entityType),
              let name = GeneratedSpawnEggs.items[entity.description],
              let item = Identifier(name), resource(name, directory: "items", extension: "json") != nil else { return nil }
        return item
    }
}
