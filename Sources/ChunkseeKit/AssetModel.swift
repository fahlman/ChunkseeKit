/// A resolved Minecraft model. Coordinates and UVs use the game's 16-unit model space.
/// This is format data; image decoding, projection, lighting and caching belong to the client.
public struct AssetModel: Sendable, Equatable {
    public let geometry: Geometry
    public let guiTransform: Transform
    public let guiLight: GuiLight
    public let ambientOcclusion: Bool

    public enum Geometry: Sendable, Equatable {
        /// Ordered front-facing layers of a builtin/generated item, before image extrusion.
        case layers([Layer])
        case elements([Element])
    }

    public struct Material: Sendable, Hashable {
        public let texture: Identifier
        public let forceTranslucent: Bool
        /// Composite these dyed textures over the base, in order, before projecting the model.
        /// Empty for ordinary materials. Decoding and alpha compositing remain client-owned.
        public let overlays: [Overlay]

        public struct Overlay: Sendable, Hashable {
            public let texture: Identifier
            /// Packed 0xRRGGBB multiplier; the texture supplies alpha.
            public let color: UInt32
        }

        init(texture: Identifier, forceTranslucent: Bool, overlays: [Overlay] = []) {
            self.texture = texture
            self.forceTranslucent = forceTranslucent
            self.overlays = overlays
        }
    }

    public struct Layer: Sendable, Equatable {
        public let material: Material
        /// Layer N uses tint index N. The item definition supplies the corresponding tint.
        public let tintIndex: Int
    }

    public struct Element: Sendable, Equatable {
        public let from: SIMD3<Float>
        public let to: SIMD3<Float>
        public let faces: [Direction: Face]
        public let rotation: Rotation?
        public let shadeDirectionOverride: Direction?
        public let lightEmission: Int
    }

    public struct Face: Sendable, Equatable {
        public let material: Material
        /// minU, minV, maxU, maxV, including the game's default when the JSON omits UVs.
        public let uv: SIMD4<Float>
        /// Clockwise quarter turns, expressed in degrees (0, 90, 180 or 270).
        public let rotation: Int
        public let tintIndex: Int?
        public let cullFace: Direction?
    }

    public enum Direction: String, Sendable, CaseIterable, Decodable {
        case down, up, north, south, west, east
    }

    public struct Rotation: Sendable, Equatable {
        public let origin: SIMD3<Float>
        public let angles: Angles
        public let rescale: Bool

        public enum Angles: Sendable, Equatable {
            case axis(Axis, Float)
            case eulerXYZ(SIMD3<Float>)
        }
        public enum Axis: String, Sendable, Decodable { case x, y, z }
    }

    public struct Transform: Sendable, Equatable {
        /// Euler angles in degrees, as specified by the model.
        public let rotation: SIMD3<Float>
        /// Translation in block units (model JSON divided by 16 and clamped to -5...5).
        public let translation: SIMD3<Float>
        public let scale: SIMD3<Float>

        static let identity = Self(rotation: .zero, translation: .zero, scale: .one)
    }

    public enum GuiLight: String, Sendable, Decodable { case front, side }
}
