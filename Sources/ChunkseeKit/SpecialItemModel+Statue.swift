import Foundation

extension SpecialItemModel {
    enum StatuePose: String { case standing, sitting, running, star }

    /// CopperGolemStatueModel uses these fixed 26.3 poses, with its root at Y=0,
    /// rotated pi around Z. The item's own transform is composed by the shared cuboid owner.
    static func statueBoxes(_ pose: StatuePose) -> [Box] {
        func part(_ from: SIMD3<Float>, _ size: SIMD3<Float>, _ uv: SIMD2<Float>,
                  at offset: SIMD3<Float>, radians: SIMD3<Float> = .zero, deformation: Float = 0) -> Box {
            let rotation: AssetModel.Rotation? = radians == .zero ? nil :
                .init(origin: offset, angles: .eulerXYZ(radians * (180 / .pi)), rescale: false)
            return .init(from + offset, from + size + offset, uv, rotation: rotation, deformation: deformation,
                         pose: .init(scale: SIMD3(-1, -1, 1), translation: .zero))
        }
        func head(at offset: SIMD3<Float>, running: Bool = false, inflation: Float = 0) -> [Box] {
            let y: Float = running ? -0.1 : 0, x: Float = running ? -0.02 : 0
            return [
                part(SIMD3(-4, -5 + y, -5), SIMD3(8, 5, 10), .zero, at: offset, deformation: inflation),
                part(SIMD3(-1 + x, -2 + y, -6), SIMD3(2, 3, 2), SIMD2(56, 0), at: offset),
                part(SIMD3(-1 + x, -9 + y, -1), SIMD3(2, 4, 2), SIMD2(37, 8), at: offset, deformation: -0.015),
                part(SIMD3(-2, -13 + y, -2), SIMD3(4, 4, 4), SIMD2(37, 0), at: offset, deformation: -0.015)
            ]
        }
        let leg = SIMD3<Float>(4, 5, 4), arm = SIMD3<Float>(3, 10, 4), body = SIMD3<Float>(8, 6, 6)
        switch pose {
        case .standing:
            return [
                part(SIMD3(0, 0, -2), leg, SIMD2(16, 27), at: SIMD3(0, -5, 0)),
                part(SIMD3(-4, 0, -2), leg, SIMD2(0, 27), at: SIMD3(0, -5, 0)),
                part(SIMD3(-4, -6, -3), body, SIMD2(0, 15), at: SIMD3(0, -5, 0))
            ] + head(at: SIMD3(0, -11, 0), inflation: 0.015) + [
                part(SIMD3(-3, -1, -2), arm, SIMD2(36, 16), at: SIMD3(-4, -11, 0)),
                part(SIMD3(0, -1, -2), arm, SIMD2(50, 16), at: SIMD3(4, -11, 0))
            ]
        case .star:
            return [
                part(SIMD3(-2, -2.5, -2), leg, SIMD2(16, 27), at: SIMD3(2.65, -3, 0), radians: SIMD3(0, 0, -0.2618)),
                part(SIMD3(-2, -2.5, -2), leg, SIMD2(0, 27), at: SIMD3(-2.65, -3, 0.01), radians: SIMD3(0, 0, 0.2618)),
                part(SIMD3(-4, -6, -3), body, SIMD2(0, 15), at: SIMD3(0, -5, 0))
            ] + head(at: SIMD3(0, -11, 0)) + [
                part(SIMD3(-1.5, -5, -2), arm, SIMD2(36, 16), at: SIMD3(-3, -10, 0), radians: SIMD3(0, 0, 1.9199)),
                part(SIMD3(-1.5, -5, -2), arm, SIMD2(50, 16), at: SIMD3(3, -10, 0), radians: SIMD3(0, 0, -1.9199))
            ]
        case .running:
            return [
                part(SIMD3(-2.088, -0.1, -2), leg, SIMD2(16, 27), at: SIMD3(1.936, -5, 0), radians: SIMD3(0.7854, 0, 0)),
                part(SIMD3(-1.856, -0.1, -1.09), leg, SIMD2(0, 27), at: SIMD3(-3.064 + 1.048, -5, -0.9), radians: SIMD3(-0.8727, 0, 0))
            ] + head(at: SIMD3(-1.064 + 0.7, -10.6, -1.8), running: true) + [
                part(SIMD3(-3.052, -1.11, -2.036), arm, SIMD2(36, 16), at: SIMD3(-1.064 - 4 + 0.7, -11.248, -1.62), radians: SIMD3(1.0036, 0, 0)),
                part(SIMD3(0.032, -1.1, -2), arm, SIMD2(50, 16), at: SIMD3(-1.064 + 4 + 0.732, -11, 0), radians: SIMD3(-0.8715, -0.0535, -0.0449)),
                part(SIMD3(-4.02, -6.116, -3.5), body, SIMD2(0, 15), at: SIMD3(-1.064 + 1.1, -4.9, 0.7), radians: SIMD3(0.1204, -0.0064, -0.0779))
            ]
        case .sitting:
            // The forearms are children of an X-rotated parent. Compose their offsets and
            // rotations before passing them to the same element-rotation representation.
            func forearm(_ from: SIMD3<Float>, _ uv: SIMD2<Float>, at offset: SIMD3<Float>, child: SIMD3<Float>) -> Box {
                let angle: Float = 0.4363, c = cos(angle), s = sin(angle)
                let moved = SIMD3(child.x, c * child.y - s * child.z, s * child.y + c * child.z)
                return part(from, arm, uv, at: offset + moved, radians: SIMD3(angle - 1.0472, 0, 0))
            }
            return [
                part(SIMD3(-2, 0.975, 0), leg, SIMD2(16, 27), at: SIMD3(2.05, -4, -1), radians: SIMD3(-1.5708, 0, 0)),
                part(SIMD3(-2, 0.975, 0), leg, SIMD2(0, 27), at: SIMD3(-2.1 + 0.05, -2.1 - 1.9, -1), radians: SIMD3(-1.5708, 0, 0)),
                part(SIMD3(-3, -4, -4.525), SIMD3(6, 1, 6), SIMD2(3, 19), at: SIMD3(0, -3, 2.325)),
                part(SIMD3(-4, -3, -3.525), body, SIMD2(0, 15), at: SIMD3(0, -3, 2.325)),
                part(SIMD3(-1, -7, -3.3), SIMD3(2, 4, 2), SIMD2(37, 8), at: SIMD3(0, -9, 2.125), deformation: -0.015),
                part(SIMD3(-2, -11, -4.3), SIMD3(4, 4, 4), SIMD2(37, 0), at: SIMD3(0, -9, 2.125), deformation: -0.015),
                part(SIMD3(-4, -3, -7.325), SIMD3(8, 5, 10), .zero, at: SIMD3(0, -9, 2.125)),
                part(SIMD3(-1, 0, -8.325), SIMD3(2, 3, 2), SIMD2(56, 0), at: SIMD3(0, -9, 2.125)),
                forearm(SIMD3(-3.075, -0.9733, -1.9966), SIMD2(36, 16), at: SIMD3(-4, -8.6, 2.325 - 1.8), child: SIMD3(0, 0.0893, 0.1198)),
                forearm(SIMD3(0.075, -1.0443, -1.8997), SIMD2(50, 16), at: SIMD3(4, -8.6, 2.325 - 1.7), child: SIMD3(0, -0.0015, -0.0808)),
                part(SIMD3(-4, -3, -2.2), SIMD3(8, 6, 3), SIMD2(3, 18), at: SIMD3(0, -4, -2), radians: SIMD3(0, 0, -3.1416))
            ]
        }
    }
}
