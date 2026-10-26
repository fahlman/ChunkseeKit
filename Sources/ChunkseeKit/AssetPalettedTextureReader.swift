import Foundation

/// Resolve one generated sprite while preserving source order, including later plain overrides.
struct AssetPalettedTextureReader {
    let assets: GameAssets

    func read(_ identifier: String, atlas: String) throws -> AssetPalettedTexture? {
        guard let requested = GameAssets.resourceID(identifier),
              let data = assets.resource(atlas, directory: "atlases", extension: "json") else { throw Invalid.asset }
        var budget = AssetReadBudget()
        try budget.consume(bytes: data.count)
        let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
        let sources = try AssetJSON.array(root["sources"])
        guard sources.count <= 256 else { throw Invalid.asset }
        var selected: AssetPalettedTexture?
        for raw in sources {
            let source = try AssetJSON.object(raw)
            switch try AssetJSON.identifier(source["type"]).description {
            case "minecraft:paletted_permutations":
                let textures = try AssetJSON.array(source["textures"])
                let permutations = try AssetJSON.object(source["permutations"])
                guard textures.count <= 4096, permutations.count <= 4096 else { throw Invalid.asset }
                try budget.consume(elements: textures.count * permutations.count)
                let key = try paletteTexture(AssetJSON.identifier(source["palette_key"]))
                let separator: String
                if let value = source["separator"] {
                    guard let value = value as? String else { throw Invalid.asset }
                    separator = value
                } else { separator = "_" }
                let palettes = try permutations.mapValues { try paletteTexture(AssetJSON.identifier($0)) }
                for rawTexture in textures {
                    let texture = try AssetJSON.identifier(rawTexture)
                    for (suffix, palette) in palettes {
                        guard let sprite = GameAssets.resourceID("\(texture.namespace):\(texture.path)\(separator)\(suffix)") else {
                            throw Invalid.asset
                        }
                        if sprite == requested, containsTexture(texture) {
                            selected = .init(texture: texture, paletteKey: key, palette: palette)
                        }
                    }
                }
            case "minecraft:directory":
                guard let directory = source["source"] as? String,
                      GameAssets.resourceID("minecraft:" + directory) != nil,
                      let prefix = source["prefix"] as? String,
                      GameAssets.resourceID("minecraft:" + prefix + "probe") != nil else { throw Invalid.asset }
                if requested.path.hasPrefix(prefix) {
                    let suffix = requested.path.dropFirst(prefix.count)
                    guard let texture = GameAssets.resourceID("\(requested.namespace):\(directory)/\(suffix)") else {
                        throw Invalid.asset
                    }
                    if containsTexture(texture) { selected = nil }
                }
            case "minecraft:single":
                let texture = try AssetJSON.identifier(source["resource"])
                let sprite = try source["sprite"].map(AssetJSON.identifier) ?? texture
                if sprite == requested, containsTexture(texture) { selected = nil }
            default:
                // An unsupported filter/source could remove or replace a prior match.
                throw Invalid.asset
            }
        }
        return selected
    }

    private func containsTexture(_ identifier: Identifier) -> Bool {
        assets.containsResource(identifier.description, directory: "textures", extension: "png")
    }

    private func paletteTexture(_ identifier: Identifier) throws -> Identifier {
        guard let texture = GameAssets.resourceID("\(identifier.namespace):palettes/\(identifier.path)") else {
            throw Invalid.asset
        }
        // Current atlases name palette resources; older atlases name texture paths directly.
        // An existing palette resource takes precedence, including an unreadable image.
        if !containsTexture(texture), containsTexture(identifier) { return identifier }
        return texture
    }
}

private enum Invalid: Error { case asset }
