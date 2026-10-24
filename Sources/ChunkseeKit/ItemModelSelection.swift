/// Saved facts that choose a static inventory model, including custom-model colors and shield
/// designs. Other stack tints are applied separately. Use this value as the model-cache key.
public struct ItemModelSelection: Sendable, Hashable {
    public let modelID: Identifier
    public let trimMaterialID: Identifier?
    public let customModelData: ItemCustomModelData
    public let bannerDesign: ItemBannerDesign
}

extension ItemStack {
    /// The item-model reference, trim-material key, custom data and saved banner design.
    /// Missing/removed trim and inline material holders have no key and choose the fallback.
    /// Malformed model, trim, custom data or banner design returns nil. Trim-pattern and tooltip
    /// fields do not select pictures; this reads the material identity, not the complete trim codec
    /// or a registry definition.
    /// Legacy tag.Trim is read only when no current trim component or removal is present.
    public var itemModelSelection: ItemModelSelection? {
        guard let modelID = itemModelID, let customModelData, let bannerDesign else { return nil }
        guard components?["!minecraft:trim"] == nil,
              let trim = components?["minecraft:trim"] ?? components?["Trim"] else {
            return .init(modelID: modelID, trimMaterialID: nil, customModelData: customModelData, bannerDesign: bannerDesign)
        }
        guard let material = trim.compound?["material"] else { return nil }
        if material.compound != nil {
            // TrimMaterialProperty uses Holder.unwrapKey: an inline holder never has a key.
            return .init(modelID: modelID, trimMaterialID: nil, customModelData: customModelData, bannerDesign: bannerDesign)
        }
        guard let value = material.string, let materialID = Identifier(value) else { return nil }
        return .init(modelID: modelID, trimMaterialID: materialID, customModelData: customModelData, bannerDesign: bannerDesign)
    }
}
