extension AssetModel.Face {
    /// Texture coordinates for the face's four original vertices, after its own UV rotation.
    /// Values are normalized to texture size (16 model units = 1), without clamping.
    /// Vertex order is the game's FaceInfo order, before block or element rotation.
    /// Before the UV rotation it is (minU, minV), (minU, maxV), (maxU, maxV), (maxU, minV).
    public var textureCoordinates: [SIMD2<Float>] {
        let corners = [SIMD2(uv.x, uv.y), SIMD2(uv.x, uv.w),
                       SIMD2(uv.z, uv.w), SIMD2(uv.z, uv.y)]
        return (0..<4).map { corners[($0 + rotation / 90) % 4] / 16 }
    }
}

extension AssetBlock.Alternative {
    /// The face's normalized texture coordinates, including this alternative's UV lock.
    /// Pass the face's original direction, before element and block rotations. Coordinates
    /// remain in the original vertex order, so clients can rotate geometry independently.
    public func textureCoordinates(for face: AssetModel.Face, facing direction: AssetModel.Direction) -> [SIMD2<Float>] {
        let coordinates = face.textureCoordinates
        guard uvLock, rotation != .zero else { return coordinates }
        let source = FaceBasis(direction)
        let target = FaceBasis(normal: rotated(source.normal))
        let u = rotated(source.u), v = rotated(source.v)
        // BlockMath maps a face into its rotated face's frame; FaceBakery applies the inverse
        // to UVs around the texture center. These exact quarter-turn bases are orthonormal,
        // so transposing their two-dimensional mapping is its inverse.
        let inverseU = SIMD2(dot(u, target.u), dot(u, target.v))
        let inverseV = SIMD2(dot(v, target.u), dot(v, target.v))
        return coordinates.map {
            let centered = $0 - 0.5
            return SIMD2((centered * inverseU).sum(), (centered * inverseV).sum()) + 0.5
        }
    }

    private func rotated(_ point: SIMD3<Float>) -> SIMD3<Float> {
        var result = point
        // The definition's clockwise X, then Y, then Z rotations, without trig roundoff.
        for _ in 0..<(rotation.x / 90) { result = SIMD3(result.x, result.z, -result.y) }
        for _ in 0..<(rotation.y / 90) { result = SIMD3(-result.z, result.y, result.x) }
        for _ in 0..<(rotation.z / 90) { result = SIMD3(result.y, -result.x, result.z) }
        return result
    }
}

/// BlockMath's local-to-global texture frames. Their normal is the face's outward direction.
private struct FaceBasis {
    let u: SIMD3<Float>
    let v: SIMD3<Float>
    let normal: SIMD3<Float>

    init(_ direction: AssetModel.Direction) {
        switch direction {
        case .south: u = SIMD3(1, 0, 0); v = SIMD3(0, 1, 0); normal = SIMD3(0, 0, 1)
        case .north: u = SIMD3(-1, 0, 0); v = SIMD3(0, 1, 0); normal = SIMD3(0, 0, -1)
        case .east: u = SIMD3(0, 0, -1); v = SIMD3(0, 1, 0); normal = SIMD3(1, 0, 0)
        case .west: u = SIMD3(0, 0, 1); v = SIMD3(0, 1, 0); normal = SIMD3(-1, 0, 0)
        case .up: u = SIMD3(1, 0, 0); v = SIMD3(0, 0, -1); normal = SIMD3(0, 1, 0)
        case .down: u = SIMD3(1, 0, 0); v = SIMD3(0, 0, 1); normal = SIMD3(0, -1, 0)
        }
    }

    init(normal: SIMD3<Float>) {
        // Only exact axis unit vectors reach this initializer from validated quarter turns.
        if normal.x != 0 { self.init(normal.x > 0 ? .east : .west) }
        else if normal.y != 0 { self.init(normal.y > 0 ? .up : .down) }
        else { self.init(normal.z > 0 ? .south : .north) }
    }
}

private func dot(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    (lhs * rhs).sum()
}
