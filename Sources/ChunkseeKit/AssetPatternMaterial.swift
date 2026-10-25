import Foundation

/// Shield, banner and decorated-pot renderers' 26.3 material recipes. The special reader
/// checks the version and supplies the common item budget; no pixels or geometry are duplicated.
enum AssetPatternMaterial {
    static func shield(_ design: ItemBannerDesign?, assets: GameAssets,
                       budget: inout AssetReadBudget) throws -> AssetModel.Material {
        guard let design, design.baseColor != nil || !design.layers.isEmpty else {
            return .init(texture: try AssetJSON.identifier("minecraft:entity/shield/shield_base_nopattern"),
                         forceTranslucent: false)
        }
        return try patterned(base: "minecraft:entity/shield/shield_base", folder: "shield",
                             color: design.baseColor ?? .white, layers: design.layers, assets: assets, budget: &budget)
    }

    static func banner(color: DyeColor, design: ItemBannerDesign?, assets: GameAssets,
                       budget: inout AssetReadBudget) throws -> AssetModel.Material {
        // BannerSpecialRenderer takes its base dye from the definition, not the stack component.
        try patterned(base: "minecraft:entity/banner/banner_base", folder: "banner", color: color,
                      layers: design?.layers ?? [], assets: assets, budget: &budget)
    }

    static func pot(_ decoration: ItemPotDecorations.Decoration?, assets: GameAssets,
                    budget: inout AssetReadBudget) throws -> AssetModel.Material {
        let blank = AssetModel.Material(texture: try texture("minecraft:decorated_pot_side", folder: "decorated_pot"),
                                        forceTranslucent: false)
        guard let decoration else { return blank }
        let asset: Identifier
        switch decoration.pattern {
        case .removed: return blank
        case .inline(let assetID): asset = assetID
        case .reference(let reference):
            asset = try AssetJSON.identifier(definition(reference, registry: "decorated_pot_pattern",
                                                       assets: assets, budget: &budget)["asset_id"])
        case .itemDefault:
            let item = decoration.itemID
            guard let pattern = potDefaults[item.description] else {
                // Other vanilla items have no PROVIDES_POTTERY_PATTERN default. Unknown
                // mod items cannot borrow that rule without their registry/component data.
                guard item.namespace == "minecraft" else { throw Invalid.pattern }
                if item.path != "brick", item.path != "air" {
                    guard let data = assets.resource(item.description, directory: "items", extension: "json") else {
                        throw Invalid.pattern
                    }
                    try budget.consume(bytes: data.count)
                }
                return blank
            }
            asset = try AssetJSON.identifier(definition(try AssetJSON.identifier(pattern), registry: "decorated_pot_pattern",
                                                       assets: assets, budget: &budget)["asset_id"])
        }
        return .init(texture: try texture(asset.description, folder: "decorated_pot"), forceTranslucent: false)
    }

    private static func patterned(base: String, folder: String, color: DyeColor,
                                  layers: [ItemBannerDesign.Layer], assets: GameAssets,
                                  budget: inout AssetReadBudget) throws -> AssetModel.Material {
        var overlays: [AssetModel.Material.Overlay] = [
            .init(texture: try texture("minecraft:base", folder: folder), color: color.textureDiffuseRGB)
        ]
        // The save retains every layer, but BannerRenderer draws only the first sixteen.
        for layer in layers.prefix(16) {
            let asset: Identifier
            switch layer.pattern {
            case .reference(let reference):
                let root = try definition(reference, registry: "banner_pattern", assets: assets, budget: &budget)
                asset = try AssetJSON.identifier(root["asset_id"])
                // The direct holder codec requires this field even though it only labels tooltips.
                guard root["translation_key"] is String else { throw Invalid.pattern }
            case .inline(let assetID, _): asset = assetID
            }
            overlays.append(.init(texture: try texture(asset.description, folder: folder), color: layer.color.textureDiffuseRGB))
        }
        try budget.consume(elements: overlays.count)
        return .init(texture: try AssetJSON.identifier(base),
                     forceTranslucent: false, overlays: overlays)
    }

    private static func texture(_ asset: String, folder: String) throws -> Identifier {
        guard let id = GameAssets.resourceID(asset),
              let texture = GameAssets.resourceID("\(id.namespace):entity/\(folder)/\(id.path)") else { throw Invalid.pattern }
        return texture
    }

    private static func definition(_ reference: Identifier, registry: String, assets: GameAssets,
                                   budget: inout AssetReadBudget) throws -> [String: Any] {
        guard let id = GameAssets.resourceID(reference.description),
              let data = assets.resources.read("data/\(id.namespace)/\(registry)/\(id.path).json") else {
            throw Invalid.pattern
        }
        try budget.consume(bytes: data.count)
        return try AssetJSON.object(JSONSerialization.jsonObject(with: data))
    }

    // Items' 23 potPattern registrations in 26.3. These component defaults are game code,
    // not item-model JSON. Resolve each referenced pattern's asset through the supplied jar.
    private static let potDefaults: [String: String] = [
        "angler", "archer", "arms_up", "blade", "brewer", "burn", "danger", "explorer",
        "flow", "friend", "guster", "heart", "heartbreak", "howl", "miner", "mourner",
        "plenty", "prize", "scrape", "sheaf", "shelter", "skull", "snort"
    ].reduce(into: [:]) { $0["minecraft:\($1)_pottery_sherd"] = "minecraft:\($1)" }

    private enum Invalid: Error { case pattern }
}
