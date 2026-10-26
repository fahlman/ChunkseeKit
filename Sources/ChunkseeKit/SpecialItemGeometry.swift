/// Generated model facts become ordinary elements through the same item transform owner.
/// Materials still come from the selected definition, saved components and resource files.
enum SpecialItemGeometry {
    enum Material: Sendable { case primary, plain, front, back, left, right }

    struct Face: Sendable {
        let uv: SIMD4<Float>
        let rotation: Int
    }

    struct Part: Sendable {
        let from: SIMD3<Float>, to: SIMD3<Float>
        let rotation: AssetModel.Rotation?
        let faces: [AssetModel.Direction: Face]
        let textureAspectRatio: Float
        let material: Material

        func element(transform: AssetItemTransform, material: AssetModel.Material) throws -> AssetModel.Element {
            let a = transform.applying(to: from), b = transform.applying(to: to)
            let low = SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
            let high = SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
            guard (0..<3).allSatisfy({ (-16...32).contains(low[$0]) && (-16...32).contains(high[$0]) }) else { throw AssetReadError.unsupportedFeature }
            let surface = AssetModel.Material(texture: material.texture, forceTranslucent: material.forceTranslucent,
                overlays: material.overlays, staticTextureAspectRatio: textureAspectRatio)
            let mappedFaces = Dictionary(uniqueKeysWithValues: faces.map { direction, source in
                let face = AssetModel.Face(material: surface, uv: source.uv, rotation: source.rotation, tintIndex: nil, cullFace: nil)
                return (transform.applying(to: direction), transform.applying(to: face, facing: direction))
            })
            return .init(from: low, to: high, faces: mappedFaces,
                         rotation: try rotation.map { try transform.applying(to: $0) },
                         shadeDirectionOverride: nil, lightEmission: 0)
        }
    }

}
