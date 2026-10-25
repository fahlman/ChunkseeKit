/// Saved facts that choose a static inventory model, including custom-model colors, shield
/// designs, decorated-pot sides, head skins and saved item-property branches. Other stack tint
/// values are separate; component presence can itself select a model. Use this as the model-cache key.
public struct ItemModelSelection: Sendable, Hashable {
    public let modelID: Identifier
    public let trimMaterialID: Identifier?
    public let customModelData: ItemCustomModelData
    public let bannerDesign: ItemBannerDesign
    public let potDecorations: ItemPotDecorations
    public let headSkin: ItemHeadSkin
    let savedProperties: SavedItemModelProperties

    /// Additional retained cache-key storage for saved block properties/component identities.
    /// Clients include this in their model/image cache budgets alongside existing selection fields.
    public var savedPropertyStorageCost: Int { savedProperties.storageCost }
}

extension ItemStack {
    /// The item-model reference, trim-material key, custom data, banner design, pot sides and head skin.
    /// Missing/removed trim and inline material holders have no key and choose the fallback.
    /// Malformed model, trim, custom data, banner design, pot sides or head skin returns nil. Trim-pattern
    /// and tooltip fields do not select pictures; this reads the material identity, not the
    /// complete trim codec or a registry definition.
    /// Legacy tag.Trim is read only when no current trim component or removal is present.
    public var itemModelSelection: ItemModelSelection? {
        guard let modelID = itemModelID, let customModelData, let bannerDesign, let potDecorations,
              let headSkin else { return nil }
        let savedProperties = SavedItemModelProperties(self)
        guard components?["!minecraft:trim"] == nil,
              let trim = components?["minecraft:trim"] ?? components?["Trim"] else {
            return .init(modelID: modelID, trimMaterialID: nil, customModelData: customModelData,
                         bannerDesign: bannerDesign, potDecorations: potDecorations, headSkin: headSkin,
                         savedProperties: savedProperties)
        }
        guard let material = trim.compound?["material"] else { return nil }
        if material.compound != nil {
            // TrimMaterialProperty uses Holder.unwrapKey: an inline holder never has a key.
            return .init(modelID: modelID, trimMaterialID: nil, customModelData: customModelData,
                         bannerDesign: bannerDesign, potDecorations: potDecorations, headSkin: headSkin,
                         savedProperties: savedProperties)
        }
        guard let value = material.string, let materialID = Identifier(value) else { return nil }
        return .init(modelID: modelID, trimMaterialID: materialID, customModelData: customModelData,
                     bannerDesign: bannerDesign, potDecorations: potDecorations, headSkin: headSkin,
                     savedProperties: savedProperties)
    }
}
