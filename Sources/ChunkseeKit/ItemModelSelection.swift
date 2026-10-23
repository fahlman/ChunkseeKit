/// Saved facts that choose a static inventory model. Tints are applied to the resolved model
/// separately. Clients can key their model caches by this value instead of the whole stack.
public struct ItemModelSelection: Sendable, Hashable {
    public let modelID: Identifier
    public let trimMaterialID: Identifier?
}

extension ItemStack {
    /// The item-model reference and saved trim-material key used by the 26.3 inventory selector.
    /// Missing/removed trim and inline material holders have no key and choose the fallback.
    /// Malformed model/trim values return nil. Pattern and tooltip fields do not select pictures;
    /// this reads the material identity, not the complete trim codec or a registry definition.
    /// Legacy tag.Trim is read only when no current trim component or removal is present.
    public var itemModelSelection: ItemModelSelection? {
        guard let modelID = itemModelID else { return nil }
        guard components?["!minecraft:trim"] == nil,
              let trim = components?["minecraft:trim"] ?? components?["Trim"] else {
            return .init(modelID: modelID, trimMaterialID: nil)
        }
        guard let material = trim.compound?["material"] else { return nil }
        if material.compound != nil {
            // TrimMaterialProperty uses Holder.unwrapKey: an inline holder never has a key.
            return .init(modelID: modelID, trimMaterialID: nil)
        }
        guard let value = material.string, let materialID = Identifier(value) else { return nil }
        return .init(modelID: modelID, trimMaterialID: materialID)
    }
}
