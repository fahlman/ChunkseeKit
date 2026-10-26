extension SpecialItemModel {
    struct Head {
        let key: String
        let material: AssetModel.Material

        static func playerMaterial(_ skin: ItemHeadSkin) throws -> AssetModel.Material {
            let texture: Identifier
            switch skin {
            case .defaultSkin:
                guard let name = GeneratedSpecialItemModels.textures["player_head"] else { throw AssetReadError.unsupportedFeature }
                texture = try AssetJSON.identifier(name)
            case .resource(let resource): texture = try AssetJSON.identifier(resource.description)
            case .unresolved: throw AssetReadError.incompleteState
            }
            // PlayerSkinRenderCache uses SkullBlockRenderer's translucent skin material.
            return .init(texture: texture, forceTranslucent: true)
        }

        init(_ definition: [String: Any]) throws {
            guard let kind = definition["kind"] as? String else { throw AssetReadError.invalidData }
            guard (try definition["animation"].map(AssetJSON.number) ?? 0) == 0 else { throw AssetReadError.unsupportedFeature }
            key = "head/" + kind
            guard GeneratedSpecialItemModels.models[key] != nil else { throw AssetReadError.unsupportedFeature }
            let texture: String
            if let raw = definition["texture"] {
                let id = try AssetJSON.identifier(raw)
                texture = "\(id.namespace):entity/\(id.path)"
            } else {
                guard let name = GeneratedSpecialItemModels.textures[key] else { throw AssetReadError.unsupportedFeature }
                texture = name
            }
            material = .init(texture: try AssetJSON.identifier(texture), forceTranslucent: false)
        }

    }
}
