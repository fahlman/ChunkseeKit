/// Closed single-container geometry verified against 26.3 ChestModel, ShulkerModel and
/// ModelPart.Cube. Entity UVs use 64-pixel skins; AssetModel uses 16-unit UV coordinates.
enum ContainerItemModel: String {
    case chest = "minecraft:chest"
    case shulker = "minecraft:shulker_box"

    func texture(_ name: Identifier) -> Identifier? {
        // Sheets' SpriteMapper preserves the identifier's namespace and prefixes its path.
        let folder = self == .chest ? "chest" : "shulker"
        return GameAssets.resourceID("\(name.namespace):entity/\(folder)/\(name.path)")
    }

    func elements(texture: Identifier, scale: SIMD3<Float>, translation: SIMD3<Float>, turnX: Bool) -> [AssetModel.Element]? {
        let boxes: [(from: SIMD3<Float>, to: SIMD3<Float>, uv: SIMD2<Float>)]
        switch self {
        case .chest:
            boxes = [(SIMD3(1, 0, 1), SIMD3(15, 10, 15), SIMD2(0, 19)),
                     (SIMD3(1, 9, 1), SIMD3(15, 14, 15), .zero),
                     (SIMD3(7, 7, 15), SIMD3(9, 11, 16), .zero)]
        case .shulker:
            boxes = [(SIMD3(-8, 8, -8), SIMD3(8, 20, 8), .zero),
                     (SIMD3(-8, 16, -8), SIMD3(8, 24, 8), SIMD2(0, 28))]
        }
        var result = [AssetModel.Element]()
        for box in boxes {
            let signedScale = scale * (turnX ? SIMD3(1, -1, -1) : .one)
            let a = box.from * signedScale + translation * 16, b = box.to * signedScale + translation * 16
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
                // Baking the shulker's half-turn swaps its top/bottom and front/back. Its
                // vertical face corners also turn halfway relative to cuboid face coordinates.
                let target: AssetModel.Direction
                switch (turnX, direction) {
                case (true, .down): target = .up
                case (true, .up): target = .down
                case (true, .north): target = .south
                case (true, .south): target = .north
                default: target = direction
                }
                faces[target] = .init(material: .init(texture: texture, forceTranslucent: false), uv: region,
                                      rotation: vertical || turnX ? 0 : 180, tintIndex: nil, cullFace: nil)
            }
            result.append(.init(from: from, to: to, faces: faces, rotation: nil,
                                shadeDirectionOverride: nil, lightEmission: 0))
        }
        return result
    }
}
