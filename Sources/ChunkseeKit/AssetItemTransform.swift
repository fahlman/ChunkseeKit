/// Composes the supported item-node transforms. Special cuboids accept the axis-aligned subset;
/// ordinary element models also support translations. Other transforms remain unavailable.
struct AssetItemTransform: Equatable {
    let scale: SIMD3<Float>
    let translation: SIMD3<Float>

    static let identity = Self(scale: .one, translation: .zero)

    /// Item-node translation is in blocks; resolved model points are in sixteenths of a block.
    func applying(to point: SIMD3<Float>) -> SIMD3<Float> {
        point * scale + translation * 16
    }

    func translating(_ model: AssetModel) throws -> AssetModel {
        if self == .identity { return model }
        guard scale == .one, case .elements(let source) = model.geometry else { throw Invalid.asset }
        let elements = try source.map { element in
            let from = applying(to: element.from), to = applying(to: element.to)
            let rotation = element.rotation.map {
                AssetModel.Rotation(origin: applying(to: $0.origin), angles: $0.angles, rescale: $0.rescale)
            }
            guard [from, to, rotation?.origin ?? .zero].allSatisfy({ point in
                (0..<3).allSatisfy { point[$0].isFinite }
            }) else { throw Invalid.asset }
            // Moving the rotation's origin with its vertices preserves rotation/rescaling before
            // translation. UVs are already resolved against the original model coordinates.
            return AssetModel.Element(from: from, to: to, faces: element.faces, rotation: rotation,
                                      shadeDirectionOverride: element.shadeDirectionOverride, lightEmission: element.lightEmission)
        }
        return .init(geometry: .elements(elements), guiTransform: model.guiTransform,
                     guiLight: model.guiLight, ambientOcclusion: model.ambientOcclusion)
    }

    func appending(_ raw: Any?) throws -> Self {
        guard let raw else { return self }
        let value = try AssetJSON.object(raw)
        let left = try AssetJSON.numbers(value["left_rotation"], count: 4)
        let right = try AssetJSON.numbers(value["right_rotation"], count: 4)
        let s = try AssetJSON.numbers(value["scale"], count: 3)
        let t = try AssetJSON.numbers(value["translation"], count: 3)
        guard right[0...2].allSatisfy({ $0 == 0 }), abs(right[3]) == 1,
              left[1] == 0, left[2] == 0,
              (left[0] == 0 && abs(left[3]) == 1) || (abs(left[0]) == 1 && left[3] == 0),
              s[0] > 0, s[1] != 0, s[2] != 0, (s[1] < 0) == (s[2] < 0) else { throw Invalid.asset }
        let turn = left[0] == 0 ? SIMD3<Float>.one : SIMD3(1, -1, -1)
        // Transformation.compose multiplies parent by child: the parent's scale also acts
        // on the child's translation. Y/Z sign pairs are the shield's half-turn representation.
        let result = Self(scale: scale * SIMD3(s[0], s[1], s[2]) * turn,
                          translation: translation + scale * SIMD3(t[0], t[1], t[2]))
        guard (0..<3).allSatisfy({ result.scale[$0].isFinite && result.scale[$0] != 0
            && result.translation[$0].isFinite }) else { throw Invalid.asset }
        return result
    }

    private enum Invalid: Error { case asset }
}
