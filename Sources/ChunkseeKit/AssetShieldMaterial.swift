import Foundation

/// ShieldSpecialRenderer/BannerRenderer's 26.3 material recipe. The existing special reader
/// checks the version and supplies the common item budget; no pixels or geometry are duplicated.
enum AssetShieldMaterial {
    static func read(_ design: ItemBannerDesign?, assets: GameAssets,
                     budget: inout AssetReadBudget) throws -> AssetModel.Material {
        guard let design, design.baseColor != nil || !design.layers.isEmpty else {
            return .init(texture: try AssetJSON.identifier("minecraft:entity/shield/shield_base_nopattern"),
                         forceTranslucent: false)
        }
        var overlays: [AssetModel.Material.Overlay] = [
            .init(texture: try texture("minecraft:base"), color: (design.baseColor ?? .white).textureDiffuseRGB26_3)
        ]
        // The save retains every layer, but BannerRenderer draws only the first sixteen.
        for layer in design.layers.prefix(16) {
            let asset: Identifier
            switch layer.pattern {
            case .reference(let reference):
                guard let id = GameAssets.resourceID(reference.description),
                      let data = assets.resources.read("data/\(id.namespace)/banner_pattern/\(id.path).json") else {
                    throw Invalid.pattern
                }
                try budget.consume(bytes: data.count)
                let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
                asset = try AssetJSON.identifier(root["asset_id"])
                // The direct holder codec requires this field even though it only labels tooltips.
                guard root["translation_key"] is String else { throw Invalid.pattern }
            case .inline(let assetID, _): asset = assetID
            }
            overlays.append(.init(texture: try texture(asset.description), color: layer.color.textureDiffuseRGB26_3))
        }
        try budget.consume(elements: overlays.count)
        return .init(texture: try AssetJSON.identifier("minecraft:entity/shield/shield_base"),
                     forceTranslucent: false, overlays: overlays)
    }

    private static func texture(_ asset: String) throws -> Identifier {
        guard let id = GameAssets.resourceID(asset),
              let texture = GameAssets.resourceID("\(id.namespace):entity/shield/\(id.path)") else { throw Invalid.pattern }
        return texture
    }

    private enum Invalid: Error { case pattern }
}
