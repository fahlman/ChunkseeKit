/// Static special-item formats use geometry extracted from the game's baked models.
/// Entity skins have their own dimensions; AssetModel uses 16-unit UV coordinates.
enum SpecialItemModel: String {
    case chest = "minecraft:chest"
    case shulker = "minecraft:shulker_box"
    case shield = "minecraft:shield"
    case banner = "minecraft:banner"
    case conduit = "minecraft:conduit"
    case decoratedPot = "minecraft:decorated_pot"
    case copperStatue = "minecraft:copper_golem_statue"
    case head = "minecraft:head"
    case playerHead = "minecraft:player_head"

    private func material(_ definition: [String: Any], selection: ItemModelSelection?,
                          assets: GameAssets, budget: inout AssetReadBudget) throws -> AssetModel.Material {
        if self == .shield {
            return try AssetPatternMaterial.shield(selection?.bannerDesign, assets: assets, budget: &budget)
        }
        if self == .banner {
            guard let raw = definition["color"] as? String, let color = DyeColor(rawValue: raw) else { throw AssetReadError.invalidData }
            return try AssetPatternMaterial.banner(color: color, design: selection?.bannerDesign, assets: assets, budget: &budget)
        }
        if self == .playerHead { return try Head.playerMaterial(selection?.headSkin ?? .defaultSkin) }
        if self == .conduit || self == .decoratedPot {
            guard let texture = GeneratedSpecialItemModels.textures[modelKey] else { throw AssetReadError.unsupportedFeature }
            return .init(texture: try AssetJSON.identifier(texture), forceTranslucent: false)
        }
        if self == .copperStatue {
            // This renderer takes a full image resource, unlike Sheets' sprite identifiers.
            let image = try AssetJSON.identifier(definition["texture"])
            guard image.path.hasPrefix("textures/"), image.path.hasSuffix(".png") else { throw AssetReadError.invalidData }
            let path = image.path.dropFirst("textures/".count).dropLast(".png".count)
            return .init(texture: try AssetJSON.identifier("\(image.namespace):\(path)"), forceTranslucent: false)
        }
        // Sheets' SpriteMapper preserves the identifier's namespace and prefixes its path.
        let name = try AssetJSON.identifier(definition["texture"])
        let folder = self == .chest ? "chest" : "shulker"
        return .init(texture: try AssetJSON.identifier("\(name.namespace):entity/\(folder)/\(name.path)"),
                     forceTranslucent: false)
    }

    private var modelKey: String { String(rawValue.dropFirst("minecraft:".count)) }

    func elements(transform: AssetItemTransform, definition: [String: Any], selection: ItemModelSelection?,
                  assets: GameAssets, budget: inout AssetReadBudget) throws -> [AssetModel.Element] {
        let head = self == .head ? try Head(definition) : nil
        let primary = try head?.material ?? material(definition, selection: selection, assets: assets, budget: &budget)
        let key: String
        switch self {
        case .head:
            guard let head else { throw AssetReadError.invalidData }
            key = head.key
        case .copperStatue:
            guard let pose = definition["pose"] as? String else { throw AssetReadError.invalidData }
            key = modelKey + "/" + pose
        case .banner:
            let attachment: String
            if let raw = definition["attachment"] {
                guard let name = raw as? String else { throw AssetReadError.invalidData }
                attachment = name
            } else { attachment = "ground" }
            key = modelKey + "/" + attachment
        default: key = modelKey
        }
        guard let parts = GeneratedSpecialItemModels.models[key] else { throw AssetReadError.unsupportedFeature }
        let decorations = selection?.potDecorations ?? .empty
        return try parts.map { part in
            let surface: AssetModel.Material
            switch part.material {
            case .primary: surface = primary
            case .plain: surface = .init(texture: primary.texture, forceTranslucent: false)
            case .front: surface = try AssetPatternMaterial.pot(decorations.front, assets: assets, budget: &budget)
            case .back: surface = try AssetPatternMaterial.pot(decorations.back, assets: assets, budget: &budget)
            case .left: surface = try AssetPatternMaterial.pot(decorations.left, assets: assets, budget: &budget)
            case .right: surface = try AssetPatternMaterial.pot(decorations.right, assets: assets, budget: &budget)
            }
            return try part.element(transform: transform, material: surface)
        }
    }

}
