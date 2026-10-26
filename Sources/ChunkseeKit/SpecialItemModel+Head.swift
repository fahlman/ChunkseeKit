extension SpecialItemModel {
    struct Head {
        let key: String
        let material: AssetModel.Material

        static func playerMaterial(_ skin: ItemHeadSkin) throws -> AssetModel.Material {
            let texture: Identifier
            switch skin {
            case .defaultSkin:
                guard let name = GeneratedSpecialItemModels.textures["player_head"] else { throw Invalid.asset }
                texture = try AssetJSON.identifier(name)
            case .resource(let resource): texture = try AssetJSON.identifier(resource.description)
            case .unresolved: throw Invalid.asset
            }
            // PlayerSkinRenderCache uses SkullBlockRenderer's translucent skin material.
            return .init(texture: texture, forceTranslucent: true)
        }

        init(_ definition: [String: Any]) throws {
            guard let kind = definition["kind"] as? String,
                  (try definition["animation"].map(AssetJSON.number) ?? 0) == 0 else { throw Invalid.asset }
            key = "head/" + kind
            guard GeneratedSpecialItemModels.models[key] != nil else { throw Invalid.asset }
            let texture: String
            if let raw = definition["texture"] {
                let id = try AssetJSON.identifier(raw)
                texture = "\(id.namespace):entity/\(id.path)"
            } else {
                guard let name = GeneratedSpecialItemModels.textures[key] else { throw Invalid.asset }
                texture = name
            }
            material = .init(texture: try AssetJSON.identifier(texture), forceTranslucent: false)
        }

        private enum Invalid: Error { case asset }
    }
}
