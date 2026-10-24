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
}
