/// Static special-item geometry verified against 26.3's container, shield and banner models
/// and ModelPart.Cube. Entity UVs use 64-pixel skins; AssetModel uses 16-unit UV coordinates.
enum SpecialItemModel: String {
    case chest = "minecraft:chest"
    case shulker = "minecraft:shulker_box"
    case shield = "minecraft:shield"
    case banner = "minecraft:banner"

    func material(_ definition: [String: Any], design: ItemBannerDesign?,
                  assets: GameAssets, budget: inout AssetReadBudget) throws -> AssetModel.Material {
        if self == .shield {
            return try AssetPatternMaterial.shield(design, assets: assets, budget: &budget)
        }
        if self == .banner {
            guard let raw = definition["color"] as? String, let color = DyeColor(rawValue: raw) else { throw Invalid.asset }
            return try AssetPatternMaterial.banner(color: color, design: design, assets: assets, budget: &budget)
        }
        // Sheets' SpriteMapper preserves the identifier's namespace and prefixes its path.
        let name = try AssetJSON.identifier(definition["texture"])
        let folder = self == .chest ? "chest" : "shulker"
        return .init(texture: try AssetJSON.identifier("\(name.namespace):entity/\(folder)/\(name.path)"),
                     forceTranslucent: false)
    }

    func elements(material: AssetModel.Material, transform: AssetItemTransform,
                  definition: [String: Any]) throws -> [AssetModel.Element] {
        let boxes: [Box]
        switch self {
        case .chest:
            boxes = [.init(SIMD3(1, 0, 1), SIMD3(15, 10, 15), SIMD2(0, 19)),
                     .init(SIMD3(1, 9, 1), SIMD3(15, 14, 15), .zero),
                     .init(SIMD3(7, 7, 15), SIMD3(9, 11, 16), .zero)]
        case .shulker:
            boxes = [.init(SIMD3(-8, 8, -8), SIMD3(8, 20, 8), .zero),
                     .init(SIMD3(-8, 16, -8), SIMD3(8, 24, 8), SIMD2(0, 28))]
        case .shield:
            boxes = [.init(SIMD3(-6, -11, -2), SIMD3(6, 11, -1), .zero),
                     .init(SIMD3(-1, -3, -1), SIMD3(1, 3, 5), SIMD2(26, 0))]
        case .banner:
            let attachment = try definition["attachment"].map { raw in
                guard let value = raw as? String, value == "ground" || value == "wall" else { throw Invalid.asset }
                return value
            } ?? "ground"
            let ground = attachment == "ground"
            let y: Float = ground ? -44 : -20.5, z: Float = ground ? 0 : 10.5
            let plain = AssetModel.Material(texture: material.texture, forceTranslucent: false)
            var body: [Box] = ground ? [.init(SIMD3(-1, -42, -1), SIMD3(1, 0, 1), SIMD2(44, 0), material: plain)] : []
            body.append(.init(SIMD3(-10, y, z - 1), SIMD3(10, y + 2, z + 1), SIMD2(0, 42), material: plain))
            // submitSpecial passes phase zero. BannerFlagModel's fixed inventory tilt is
            // (-0.0125 + 0.01 * cos(0)) * pi radians; the model stores degrees.
            let angle: Float = (-0.0125 + 0.01) * 180
            body.append(.init(SIMD3(-10, y, z - 2), SIMD3(10, y + 40, z - 1), .zero,
                              rotation: .init(origin: SIMD3(0, y, z), angles: .axis(.x, angle), rescale: false)))
            boxes = body
        }
        var result = [AssetModel.Element]()
        for box in boxes {
            let a = transform.applying(to: box.from)
            let b = transform.applying(to: box.to)
            let from = SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
            let to = SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
            guard (0..<3).allSatisfy({ (-16...32).contains(from[$0]) && (-16...32).contains(to[$0]) }) else { throw Invalid.asset }
            let size = (box.to - box.from) / 4, uv = box.uv / 4
            let u = uv.x, v = uv.y, x = size.x, y = size.y, z = size.z
            let regions: [(AssetModel.Direction, SIMD4<Float>)] = [
                (.down, SIMD4(u + z, v, u + z + x, v + z)),
                (.up, SIMD4(u + z + x, v + z, u + z + 2 * x, v)),
                (.west, SIMD4(u, v + z, u + z, v + z + y)),
                (.north, SIMD4(u + z, v + z, u + z + x, v + z + y)),
                (.east, SIMD4(u + z + x, v + z, u + 2 * z + x, v + z + y)),
                (.south, SIMD4(u + 2 * z + x, v + z, u + 2 * z + 2 * x, v + z + y))
            ]
            var faces = [AssetModel.Direction: AssetModel.Face]()
            for (direction, region) in regions {
                let vertical = direction == .down || direction == .up
                let face = AssetModel.Face(material: box.material ?? material, uv: region,
                                           rotation: vertical ? 0 : 180, tintIndex: nil, cullFace: nil)
                faces[transform.applying(to: direction)] = transform.applying(to: face, facing: direction)
            }
            let rotation = try box.rotation.map { try transform.applying(to: $0) }
            result.append(.init(from: from, to: to, faces: faces, rotation: rotation,
                                shadeDirectionOverride: nil, lightEmission: 0))
        }
        return result
    }

    private struct Box {
        let from: SIMD3<Float>, to: SIMD3<Float>, uv: SIMD2<Float>
        let material: AssetModel.Material?
        let rotation: AssetModel.Rotation?

        init(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ uv: SIMD2<Float>,
             material: AssetModel.Material? = nil, rotation: AssetModel.Rotation? = nil) {
            self.from = from; self.to = to; self.uv = uv
            self.material = material; self.rotation = rotation
        }
    }

    private enum Invalid: Error { case asset }
}
