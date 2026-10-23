/// Static special-item geometry verified against 26.3 ChestModel, ShulkerModel, ShieldModel and
/// ModelPart.Cube. Entity UVs use 64-pixel skins; AssetModel uses 16-unit UV coordinates.
enum SpecialItemModel: String {
    case chest = "minecraft:chest"
    case shulker = "minecraft:shulker_box"
    case shield = "minecraft:shield"

    func texture(_ definition: [String: Any]) throws -> Identifier {
        if self == .shield {
            // ShieldSpecialRenderer uses this skin when no saved banner pattern or base color
            // is supplied. This API resolves the definition's static default, not saved variants.
            return try AssetJSON.identifier("minecraft:entity/shield/shield_base_nopattern")
        }
        // Sheets' SpriteMapper preserves the identifier's namespace and prefixes its path.
        let name = try AssetJSON.identifier(definition["texture"])
        let folder = self == .chest ? "chest" : "shulker"
        return try AssetJSON.identifier("\(name.namespace):entity/\(folder)/\(name.path)")
    }

    func elements(texture: Identifier, transform: AssetItemTransform) -> [AssetModel.Element]? {
        let boxes: [(from: SIMD3<Float>, to: SIMD3<Float>, uv: SIMD2<Float>)]
        switch self {
        case .chest:
            boxes = [(SIMD3(1, 0, 1), SIMD3(15, 10, 15), SIMD2(0, 19)),
                     (SIMD3(1, 9, 1), SIMD3(15, 14, 15), .zero),
                     (SIMD3(7, 7, 15), SIMD3(9, 11, 16), .zero)]
        case .shulker:
            boxes = [(SIMD3(-8, 8, -8), SIMD3(8, 20, 8), .zero),
                     (SIMD3(-8, 16, -8), SIMD3(8, 24, 8), SIMD2(0, 28))]
        case .shield:
            boxes = [(SIMD3(-6, -11, -2), SIMD3(6, 11, -1), .zero),
                     (SIMD3(-1, -3, -1), SIMD3(1, 3, 5), SIMD2(26, 0))]
        }
        var result = [AssetModel.Element]()
        for box in boxes {
            let a = transform.applying(to: box.from)
            let b = transform.applying(to: box.to)
            let from = SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
            let to = SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
            guard (0..<3).allSatisfy({ (-16...32).contains(from[$0]) && (-16...32).contains(to[$0]) }) else { return nil }
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
                let face = AssetModel.Face(material: .init(texture: texture, forceTranslucent: false), uv: region,
                                           rotation: vertical ? 0 : 180, tintIndex: nil, cullFace: nil)
                faces[transform.applying(to: direction)] = transform.applying(to: face, facing: direction)
            }
            result.append(.init(from: from, to: to, faces: faces, rotation: nil,
                                shadeDirectionOverride: nil, lightEmission: 0))
        }
        return result
    }
}
