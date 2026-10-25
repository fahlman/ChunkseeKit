/// The saved dye identities, in Minecraft's legacy numeric order. Display names stay client-owned.
public enum DyeColor: String, CaseIterable, Sendable, Hashable {
    case white, orange, magenta
    case lightBlue = "light_blue"
    case yellow, lime, pink, gray
    case lightGray = "light_gray"
    case cyan, purple, blue, brown, green, red, black

    /// Invalid IDs remain unavailable instead of wrapping to another color.
    public init?(legacyID: Int) {
        guard Self.allCases.indices.contains(legacyID) else { return nil }
        self = Self.allCases[legacyID]
    }

    /// The game's texture multiplier, identical in 26.3 DyeColor and Snapshot 5 CommonColors.
    /// Only the version-gated special-model reader uses it; this is not a UI color palette.
    var textureDiffuseRGB: UInt32 {
        switch self {
        case .white: 0xf9fffe
        case .orange: 0xf9801d
        case .magenta: 0xc74ebd
        case .lightBlue: 0x3ab3da
        case .yellow: 0xfed83d
        case .lime: 0x80c71f
        case .pink: 0xf38baa
        case .gray: 0x474f52
        case .lightGray: 0x9d9d97
        case .cyan: 0x169c9c
        case .purple: 0x8932b8
        case .blue: 0x3c44aa
        case .brown: 0x835432
        case .green: 0x5e7c16
        case .red: 0xb02e26
        case .black: 0x1d1d21
        }
    }
}
