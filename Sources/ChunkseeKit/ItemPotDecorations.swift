/// The four saved item templates used as a decorated pot's sides. Pattern defaults belong to
/// the matching game version; named holders need its registry and inline holders supply an asset.
public struct ItemPotDecorations: Sendable, Hashable {
    public let back: Decoration?
    public let left: Decoration?
    public let right: Decoration?
    public let front: Decoration?

    public struct Decoration: Sendable, Hashable {
        public let itemID: Identifier
        public let pattern: Pattern
    }

    public enum Pattern: Sendable, Hashable {
        case itemDefault
        case removed
        case reference(Identifier)
        case inline(assetID: Identifier)
    }

    static let empty = Self(back: nil, left: nil, right: nil, front: nil)
}

extension ItemStack {
    /// Reads 26.3's named side templates, earlier pot_decorations lists, and legacy sherds.
    /// Missing/removed decorations are empty; malformed present values are unavailable.
    /// Count and unrelated template components do not affect picture identity.
    public var potDecorations: ItemPotDecorations? {
        guard components == nil || components?.compound != nil else { return nil }
        let key = "minecraft:pot_decorations"
        if components?["!" + key] != nil { return .empty }
        let raw: NBT?
        if let current = components?[key] { raw = current }
        else if let tag = components?["BlockEntityTag"] {
            guard let fields = tag.compound else { return nil }
            raw = fields["sherds"]
        } else { raw = nil }
        guard let raw else { return .empty }
        var reader = PotDecorationReader()
        return try? reader.read(raw)
    }
}

private struct PotDecorationReader {
    private var remainingBytes = 16 * 1024 * 1024

    mutating func identifier(_ raw: NBT?) throws -> Identifier {
        guard let text = raw?.string, text.utf8.count <= remainingBytes,
              let id = Identifier(text) else { throw Invalid.decoration }
        remainingBytes -= text.utf8.count
        return id
    }

    mutating func read(_ raw: NBT) throws -> ItemPotDecorations {
        let values: [NBT?]
        if let sides = raw.compound {
            values = [sides["back"], sides["left"], sides["right"], sides["front"]]
        } else {
            let list: [NBT]
            switch raw {
            case .list(_, let entries): list = entries
            case .byteArray(let entries) where entries.isEmpty: list = []
            case .intArray(let entries) where entries.isEmpty: list = []
            case .longArray(let entries) where entries.isEmpty: list = []
            default: throw Invalid.decoration
            }
            // The official migration orders back/left/right/front and fills absent entries
            // with brick. Reject malformed/extra values instead of silently repairing them.
            guard list.count <= 4 else { throw Invalid.decoration }
            values = try (0..<4).map { index in
                let value = index < list.count ? list[index].unwrappedListElement : .string("minecraft:brick")
                guard value.string != nil else { throw Invalid.decoration }
                return value
            }
        }
        let sides = try values.map { try decoration($0) }
        return .init(back: sides[0], left: sides[1], right: sides[2], front: sides[3])
    }

    mutating func decoration(_ raw: NBT?) throws -> ItemPotDecorations.Decoration? {
        guard let raw else { return nil }
        if raw.string != nil { return .init(itemID: try identifier(raw), pattern: .itemDefault) }
        guard let fields = raw.compound else { throw Invalid.decoration }
        let id = try identifier(fields["id"])
        if let count = fields["count"] {
            guard let count = count.javaInt, (1...99).contains(count) else { throw Invalid.decoration }
        }
        guard fields["components"] == nil || fields["components"]?.compound != nil else { throw Invalid.decoration }
        let components = fields["components"], key = "minecraft:provides_pottery_pattern"
        let pattern: ItemPotDecorations.Pattern
        if components?["!" + key] != nil { pattern = .removed }
        else if let raw = components?[key] {
            if raw.string != nil { pattern = .reference(try identifier(raw)) }
            else {
                guard let fields = raw.compound else { throw Invalid.decoration }
                pattern = .inline(assetID: try identifier(fields["asset_id"]))
            }
        } else { pattern = .itemDefault }
        return .init(itemID: id, pattern: pattern)
    }

    private enum Invalid: Error { case decoration }
}
