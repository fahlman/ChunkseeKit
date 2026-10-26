extension GameAssets {
    /// The code-defined inventory item for a saved block, when its item definition is readable
    /// in this jar. Wall/standing and other differently named blocks use the game's relationship,
    /// never a name conversion. Saved block properties do not change Block.asItem's identity.
    /// Nil means no item or unavailable code/resource facts, not an unknown block verdict.
    /// Model support and picture rendering remain separate; no asset-version gate is applied.
    public func blockItemID(for blockID: String) -> Identifier? {
        guard let block = Identifier(blockID),
              let name = GeneratedBlockItems.items[block.description],
              let item = Identifier(name), resource(name, directory: "items", extension: "json") != nil else { return nil }
        return item
    }
}
