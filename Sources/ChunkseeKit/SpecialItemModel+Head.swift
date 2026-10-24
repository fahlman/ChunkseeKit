extension SpecialItemModel {
    struct Head {
        enum Kind: String { case skeleton, witherSkeleton = "wither_skeleton", zombie, creeper, dragon, piglin }

        let kind: Kind
        let material: AssetModel.Material

        init(_ definition: [String: Any]) throws {
            guard let name = definition["kind"] as? String, let kind = Kind(rawValue: name),
                  (try definition["animation"].map(AssetJSON.number) ?? 0) == 0 else { throw Invalid.asset }
            self.kind = kind
            // SkullSpecialRenderer's override is relative to textures/entity/, while its
            // defaults come from SkullBlockRenderer.SKIN_BY_TYPE, not the item's identifier.
            let texture: String
            if let raw = definition["texture"] {
                let id = try AssetJSON.identifier(raw)
                texture = "\(id.namespace):entity/\(id.path)"
            } else {
                let path = switch kind {
                case .skeleton: "skeleton/skeleton"
                case .witherSkeleton: "skeleton/wither_skeleton"
                case .zombie: "zombie/zombie"
                case .creeper: "creeper/creeper"
                case .dragon: "enderdragon/dragon"
                case .piglin: "piglin/piglin"
                }
                texture = "minecraft:entity/\(path)"
            }
            material = .init(texture: try AssetJSON.identifier(texture), forceTranslucent: false)
        }

        /// The official 26.3 skull layers after setupAnim at phase zero. The selected
        /// item's transform and GUI display still come from the supplied definition.
        var boxes: [Box] {
            switch kind {
            case .skeleton, .witherSkeleton, .creeper:
                return [.init(SIMD3(-4, -8, -4), SIMD3(4, 0, 4), .zero, skinSize: SIMD2(64, 32))]
            case .zombie:
                return [.init(SIMD3(-4, -8, -4), SIMD3(4, 0, 4), .zero),
                        .init(SIMD3(-4, -8, -4), SIMD3(4, 0, 4), SIMD2(32, 0), deformation: 0.25)]
            case .dragon:
                let pose = AssetItemTransform(scale: SIMD3(repeating: 0.75), translation: SIMD3(0, -5.99 / 16, 0))
                func part(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ uv: SIMD2<Float>,
                          mirror: Bool = false, rotation: AssetModel.Rotation? = nil) -> Box {
                    .init(from, to, uv, rotation: rotation, skinSize: SIMD2(repeating: 256), pose: pose, mirror: mirror)
                }
                return [
                    part(SIMD3(-6, -1, -24), SIMD3(6, 4, -8), SIMD2(176, 44)),
                    part(SIMD3(-8, -8, -10), SIMD3(8, 8, 6), SIMD2(112, 30)),
                    part(SIMD3(-5, -12, -4), SIMD3(-3, -8, 2), .zero, mirror: true),
                    part(SIMD3(-5, -3, -22), SIMD3(-3, -1, -18), SIMD2(112, 0), mirror: true),
                    part(SIMD3(3, -12, -4), SIMD3(5, -8, 2), .zero),
                    part(SIMD3(3, -3, -22), SIMD3(5, -1, -18), SIMD2(112, 0)),
                    part(SIMD3(-6, 4, -24), SIMD3(6, 8, -8), SIMD2(176, 65),
                         rotation: .init(origin: SIMD3(0, 4, -8), angles: .axis(.x, 0.2 * 180 / .pi), rescale: false))
                ]
            case .piglin:
                func ear(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ uv: SIMD2<Float>,
                         at offset: SIMD3<Float>, angle: Float) -> Box {
                    .init(from + offset, to + offset, uv,
                          rotation: .init(origin: offset, angles: .axis(.z, angle * 180 / .pi), rescale: false))
                }
                return [
                    .init(SIMD3(-5, -8, -4), SIMD3(5, 0, 4), .zero),
                    .init(SIMD3(-2, -4, -5), SIMD3(2, 0, -4), SIMD2(31, 1)),
                    .init(SIMD3(2, -2, -5), SIMD3(3, 0, -4), SIMD2(2, 4)),
                    .init(SIMD3(-3, -2, -5), SIMD3(-2, 0, -4), SIMD2(2, 0)),
                    ear(SIMD3(-1, 0, -2), SIMD3(0, 5, 2), SIMD2(39, 6), at: SIMD3(-4.5, -6, 0), angle: 0.7),
                    ear(SIMD3(0, 0, -2), SIMD3(1, 5, 2), SIMD2(51, 6), at: SIMD3(4.5, -6, 0), angle: -0.7)
                ]
            }
        }

        private enum Invalid: Error { case asset }
    }
}
