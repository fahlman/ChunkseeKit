/// Static special-item geometry verified against 26.3's baked models and ModelPart.Cube.
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
            guard let raw = definition["color"] as? String, let color = DyeColor(rawValue: raw) else { throw Invalid.asset }
            return try AssetPatternMaterial.banner(color: color, design: selection?.bannerDesign, assets: assets, budget: &budget)
        }
        if self == .playerHead { return try Head.playerMaterial(selection?.headSkin ?? .defaultSkin) }
        if self == .conduit {
            return .init(texture: try AssetJSON.identifier("minecraft:entity/conduit/base"), forceTranslucent: false)
        }
        if self == .decoratedPot {
            return .init(texture: try AssetJSON.identifier("minecraft:entity/decorated_pot/decorated_pot_base"),
                         forceTranslucent: false)
        }
        if self == .copperStatue {
            // This renderer takes a full image resource, unlike Sheets' sprite identifiers.
            let image = try AssetJSON.identifier(definition["texture"])
            guard image.path.hasPrefix("textures/"), image.path.hasSuffix(".png") else { throw Invalid.asset }
            let path = image.path.dropFirst("textures/".count).dropLast(".png".count)
            return .init(texture: try AssetJSON.identifier("\(image.namespace):\(path)"), forceTranslucent: false)
        }
        // Sheets' SpriteMapper preserves the identifier's namespace and prefixes its path.
        let name = try AssetJSON.identifier(definition["texture"])
        let folder = self == .chest ? "chest" : "shulker"
        return .init(texture: try AssetJSON.identifier("\(name.namespace):entity/\(folder)/\(name.path)"),
                     forceTranslucent: false)
    }

    func elements(transform: AssetItemTransform, definition: [String: Any], selection: ItemModelSelection?,
                  assets: GameAssets, budget: inout AssetReadBudget) throws -> [AssetModel.Element] {
        let head = self == .head ? try Head(definition) : nil
        let material = try head?.material ?? material(definition, selection: selection, assets: assets, budget: &budget)
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
        case .conduit:
            boxes = [.init(SIMD3(repeating: -3), SIMD3(repeating: 3), .zero)]
        case .copperStatue:
            guard let name = definition["pose"] as? String, let pose = StatuePose(rawValue: name) else { throw Invalid.asset }
            boxes = Self.statueBoxes(pose)
        case .head:
            guard let head else { throw Invalid.asset }
            boxes = head.boxes
        case .playerHead:
            boxes = Head.humanoidBoxes
        case .decoratedPot:
            let pose = AssetItemTransform(scale: SIMD3(1, -1, -1), translation: SIMD3(0, 37.0 / 16, 1))
            var body: [Box] = [
                .init(SIMD3(4, 17, 4), SIMD3(12, 20, 12), .zero, skinSize: SIMD2(32, 32), deformation: -0.1, pose: pose),
                .init(SIMD3(5, 20, 5), SIMD3(11, 21, 11), SIMD2(0, 5), skinSize: SIMD2(32, 32), deformation: 0.2, pose: pose),
                .init(SIMD3(1, 16, 1), SIMD3(15, 16, 15), SIMD2(-14, 13), skinSize: SIMD2(32, 32)),
                .init(SIMD3(1, 0, 1), SIMD3(15, 0, 15), SIMD2(-14, 13), skinSize: SIMD2(32, 32))
            ]
            let decorations = selection?.potDecorations ?? .empty
            let sides: [(AssetModel.Direction, SIMD3<Float>, SIMD3<Float>, ItemPotDecorations.Decoration?)] = [
                (.north, SIMD3(1, 0, 1), SIMD3(15, 16, 1), decorations.back),
                (.west, SIMD3(1, 0, 1), SIMD3(1, 16, 15), decorations.left),
                (.east, SIMD3(15, 0, 1), SIMD3(15, 16, 15), decorations.right),
                (.south, SIMD3(1, 0, 15), SIMD3(15, 16, 15), decorations.front)
            ]
            for (face, from, to, decoration) in sides {
                body.append(.init(from, to, .zero,
                    material: try AssetPatternMaterial.pot(decoration, assets: assets, budget: &budget),
                    skinSize: SIMD2(16, 16), faceUVs: [face: SIMD4(1, 0, 15, 16)], sideRotation: 0))
            }
            boxes = body
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
        // Deformation moves the geometry but not its texture layout; each part can name its skin.
        let skinSize: SIMD2<Float> = self == .conduit ? SIMD2(32, 16) : SIMD2(repeating: 64)
        var result = [AssetModel.Element]()
        for box in boxes {
            let transform = try transform.appending(box.pose)
            let skin = box.skinSize ?? skinSize
            let source = box.material ?? material
            let surface = AssetModel.Material(texture: source.texture, forceTranslucent: source.forceTranslucent,
                                              overlays: source.overlays, staticTextureAspectRatio: skin.x / skin.y)
            let uvScale = SIMD4(16 / skin.x, 16 / skin.y, 16 / skin.x, 16 / skin.y)
            let a = transform.applying(to: box.from - SIMD3(repeating: box.deformation))
            let b = transform.applying(to: box.to + SIMD3(repeating: box.deformation))
            let from = SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
            let to = SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
            guard (0..<3).allSatisfy({ (-16...32).contains(from[$0]) && (-16...32).contains(to[$0]) }) else { throw Invalid.asset }
            let size = box.to - box.from, uv = box.uv
            let u = uv.x, v = uv.y, x = size.x, y = size.y, z = size.z
            let regions: [(AssetModel.Direction, SIMD4<Float>)] = box.faceUVs.map { Array($0) } ?? [
                (.down, SIMD4(u + z, v, u + z + x, v + z)),
                (.up, SIMD4(u + z + x, v + z, u + z + 2 * x, v)),
                (.west, SIMD4(u, v + z, u + z, v + z + y)),
                (.north, SIMD4(u + z, v + z, u + z + x, v + z + y)),
                (.east, SIMD4(u + z + x, v + z, u + 2 * z + x, v + z + y)),
                (.south, SIMD4(u + 2 * z + x, v + z, u + 2 * z + 2 * x, v + z + y))
            ]
            var faces = [AssetModel.Direction: AssetModel.Face]()
            for (direction, region) in regions {
                // ModelPart.Cube mirrors its X endpoints and polygon winding. The bounds stay
                // the same; the east/west skins swap sides and every face reverses U.
                let facing: AssetModel.Direction = box.mirror && direction == .east ? .west :
                    (box.mirror && direction == .west ? .east : direction)
                let uv = box.mirror ? SIMD4(region.z, region.y, region.x, region.w) : region
                let vertical = direction == .down || direction == .up
                let face = AssetModel.Face(material: surface, uv: uv * uvScale,
                                           rotation: vertical ? 0 : box.sideRotation, tintIndex: nil, cullFace: nil)
                faces[transform.applying(to: facing)] = transform.applying(to: face, facing: facing)
            }
            let rotation = try box.rotation.map { try transform.applying(to: $0) }
            result.append(.init(from: from, to: to, faces: faces, rotation: rotation,
                                shadeDirectionOverride: nil, lightEmission: 0))
        }
        return result
    }

    struct Box {
        let from: SIMD3<Float>, to: SIMD3<Float>, uv: SIMD2<Float>
        let material: AssetModel.Material?
        let rotation: AssetModel.Rotation?
        let skinSize: SIMD2<Float>?
        let deformation: Float
        let pose: AssetItemTransform
        let faceUVs: [AssetModel.Direction: SIMD4<Float>]?
        let sideRotation: Int
        let mirror: Bool

        init(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ uv: SIMD2<Float>,
             material: AssetModel.Material? = nil, rotation: AssetModel.Rotation? = nil,
             skinSize: SIMD2<Float>? = nil, deformation: Float = 0, pose: AssetItemTransform = .identity,
             faceUVs: [AssetModel.Direction: SIMD4<Float>]? = nil, sideRotation: Int = 180, mirror: Bool = false) {
            self.from = from; self.to = to; self.uv = uv
            self.material = material; self.rotation = rotation
            self.skinSize = skinSize; self.deformation = deformation; self.pose = pose
            self.faceUVs = faceUVs; self.sideRotation = sideRotation
            self.mirror = mirror
        }
    }

    private enum Invalid: Error { case asset }
}
