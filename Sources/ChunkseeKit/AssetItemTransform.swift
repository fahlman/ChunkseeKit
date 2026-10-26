/// Composes the supported item-node transforms. Special cuboids accept the axis-aligned subset;
/// ordinary element models support translations and half-turns. Other transforms remain unavailable.
struct AssetItemTransform: Equatable {
    let scale: SIMD3<Float>
    let translation: SIMD3<Float>

    static let identity = Self(scale: .one, translation: .zero)

    /// Item-node translation is in blocks; resolved model points are in sixteenths of a block.
    func applying(to point: SIMD3<Float>) -> SIMD3<Float> {
        point * scale + translation * 16
    }

    func applying(to model: AssetModel) throws -> AssetModel {
        if self == .identity { return model }
        guard (0..<3).allSatisfy({ abs(scale[$0]) == 1 }),
              case .elements(let source) = model.geometry else { throw AssetReadError.unsupportedFeature }
        let elements = try source.map { element in
            let a = applying(to: element.from), b = applying(to: element.to)
            var from = a, to = b
            for axis in 0..<3 where scale[axis] < 0 { swap(&from[axis], &to[axis]) }
            let rotation = try element.rotation.map { try applying(to: $0) }
            guard [from, to, rotation?.origin ?? .zero].allSatisfy({ point in
                (0..<3).allSatisfy { point[$0].isFinite }
            }) else { throw AssetReadError.unsupportedFeature }
            // Conjugating an element's rotation preserves its original order before the node
            // transform. Remap faces without resampling UVs from the moved corner coordinates.
            let faces = Dictionary(uniqueKeysWithValues: element.faces.map { direction, face in
                (applying(to: direction), applying(to: face, facing: direction))
            })
            return AssetModel.Element(from: from, to: to, faces: faces, rotation: rotation,
                                      shadeDirectionOverride: element.shadeDirectionOverride.map { applying(to: $0) },
                                      lightEmission: element.lightEmission)
        }
        return .init(geometry: .elements(elements), guiTransform: model.guiTransform,
                     guiLight: model.guiLight, ambientOcclusion: model.ambientOcclusion)
    }

    func applying(to direction: AssetModel.Direction) -> AssetModel.Direction {
        switch direction {
        case .down: scale.y < 0 ? .up : .down
        case .up: scale.y < 0 ? .down : .up
        case .north: scale.z < 0 ? .south : .north
        case .south: scale.z < 0 ? .north : .south
        case .west: scale.x < 0 ? .east : .west
        case .east: scale.x < 0 ? .west : .east
        }
    }

    func applying(to face: AssetModel.Face, facing direction: AssetModel.Direction) -> AssetModel.Face {
        // A proper axis-aligned half-turn preserves face winding. Top/bottom UV orientation
        // follows the X axis; all four side faces follow the vertical axis.
        let turned = direction == .up || direction == .down ? scale.x < 0 : scale.y < 0
        return .init(material: face.material, uv: face.uv, rotation: (face.rotation + (turned ? 180 : 0)) % 360,
                     tintIndex: face.tintIndex, cullFace: face.cullFace.map { applying(to: $0) })
    }

    func applying(to rotation: AssetModel.Rotation) throws -> AssetModel.Rotation {
        let angles: AssetModel.Rotation.Angles
        let signs = SIMD3<Float>(scale.x < 0 ? -1 : 1, scale.y < 0 ? -1 : 1, scale.z < 0 ? -1 : 1)
        switch rotation.angles {
        case .axis(let axis, let angle):
            let (first, second, sign) = switch axis {
            case .x: (scale.y, scale.z, signs.x)
            case .y: (scale.x, scale.z, signs.y)
            case .z: (scale.x, scale.y, signs.z)
            }
            // Unequal perpendicular scaling would shear the rotated box. The model's rotation
            // cannot represent that, so leave such selected special transforms unavailable.
            guard abs(first) == abs(second) else { throw AssetReadError.unsupportedFeature }
            angles = .axis(axis, angle * sign)
        case .eulerXYZ(let value):
            guard abs(scale.x) == abs(scale.y), abs(scale.y) == abs(scale.z) else { throw AssetReadError.unsupportedFeature }
            angles = .eulerXYZ(value * signs)
        }
        return .init(origin: applying(to: rotation.origin), angles: angles, rescale: rotation.rescale)
    }

    func appending(_ raw: Any?) throws -> Self {
        guard let raw else { return self }
        let value = try AssetJSON.object(raw)
        let left = try AssetJSON.numbers(value["left_rotation"], count: 4)
        let right = try AssetJSON.numbers(value["right_rotation"], count: 4)
        let s = try AssetJSON.numbers(value["scale"], count: 3)
        let t = try AssetJSON.numbers(value["translation"], count: 3)
        guard right[0...2].allSatisfy({ $0 == 0 }), abs(right[3]) == 1,
              s[0] > 0, s[1] != 0, s[2] != 0, (s[1] < 0) == (s[2] < 0) else { throw AssetReadError.unsupportedFeature }
        let turn: SIMD3<Float>
        if left[0...2].allSatisfy({ $0 == 0 }), abs(left[3]) == 1 { turn = .one }
        else if abs(left[0]) == 1, left[1] == 0, left[2] == 0, left[3] == 0 { turn = SIMD3(1, -1, -1) }
        else if left[0] == 0, abs(left[1]) == 1, left[2] == 0, left[3] == 0 { turn = SIMD3(-1, 1, -1) }
        else if left[0] == 0, left[1] == 0, abs(left[2]) == 1, left[3] == 0 { turn = SIMD3(-1, -1, 1) }
        else { throw AssetReadError.unsupportedFeature }
        return try appending(Self(scale: SIMD3(s[0], s[1], s[2]) * turn,
                                  translation: SIMD3(t[0], t[1], t[2])))
    }

    /// Transformation.compose multiplies parent by child, including the parent's scale
    /// on the child's translation. Baked special-model part poses use this same rule.
    func appending(_ child: Self) throws -> Self {
        let result = Self(scale: scale * child.scale, translation: translation + scale * child.translation)
        guard (0..<3).allSatisfy({ result.scale[$0].isFinite && result.scale[$0] != 0
            && result.translation[$0].isFinite }) else { throw AssetReadError.unsupportedFeature }
        return result
    }

}
