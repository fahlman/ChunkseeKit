import Foundation

/// Minecraft text components (custom names, sign text, book pages) reduced to plain text.
public enum TextComponent {
    /// Accepts a literal string, a JSON-encoded component (older worlds), an NBT compound with
    /// `text`/`translate` and `extra`, or a list of components. Removes legacy `§` formatting
    /// codes after joining the fragments, preserving their spaces and line breaks.
    public static func plainText(_ nbt: NBT) -> String? {
        guard let text = componentText(nbt) else { return nil }
        let plain = removingFormattingCodes(text)
        return plain.isEmpty ? nil : plain
    }

    private static func componentText(_ nbt: NBT) -> String? {
        let text: String
        switch nbt {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, "{[\"".contains(first),
               let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]) {
                text = plainText(json: json)
            } else {
                text = s
            }
        case .compound:
            text = (nbt["text"]?.string ?? nbt["translate"]?.string ?? "") + (nbt["extra"]?.list ?? []).compactMap(componentText).joined()
        case .list(_, let items):
            text = items.compactMap(componentText).joined()
        default:
            return nil
        }
        return text.isEmpty ? nil : text
    }

    private static func plainText(json: Any) -> String {
        switch json {
        case let s as String: return s
        case let array as [Any]: return array.map(plainText(json:)).joined()
        case let dict as [String: Any]:
            let base = (dict["text"] as? String) ?? (dict["translate"] as? String) ?? ""
            return base + ((dict["extra"] as? [Any]) ?? []).map(plainText(json:)).joined()
        default: return ""
        }
    }

    /// Strips `§` formatting codes, which server plugins put in names (`§aSummer` → `Summer`).
    private static func removingFormattingCodes(_ text: String) -> String {
        var result = ""
        var skipNext = false
        for character in text {
            if skipNext { skipNext = false; continue }
            if character == "§" { skipNext = true; continue }
            result.append(character)
        }
        return result
    }
}


/// A sign or hanging sign with its text.
public struct Sign: Sendable, Equatable, Codable {
    /// Block entity id: `minecraft:sign` or `minecraft:hanging_sign`.
    public var kind: String
    public var x: Int
    public var y: Int
    public var z: Int
    /// The four lines on each side, as plain text; blank lines are empty strings.
    public var front: [String]
    public var back: [String]

    public init(kind: String, x: Int, y: Int, z: Int, front: [String], back: [String] = []) {
        self.kind = kind
        self.x = x
        self.y = y
        self.z = z
        self.front = front
        self.back = back
    }

    /// Reads a sign block entity: `front_text`/`back_text` (1.20+) or `Text1`…`Text4` (older).
    public init?(blockEntity nbt: NBT) {
        guard let kind = nbt["id"]?.string, kind.hasSuffix("sign"),
              let position = nbt.blockEntityPosition else { return nil }
        func lines(_ side: NBT?) -> [String] {
            (side?["messages"]?.list ?? []).map { TextComponent.plainText($0) ?? "" }
        }
        var front = lines(nbt["front_text"])
        if nbt["front_text"] == nil {
            front = (1...4).map { nbt["Text\($0)"].flatMap(TextComponent.plainText) ?? "" }
        }
        self.init(kind: kind, x: position.x, y: position.y, z: position.z, front: front, back: lines(nbt["back_text"]))
    }

    /// Whether either side has any text.
    public var hasText: Bool { !(front + back).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Signs with text among a chunk's block entities.
    public static func signs(inChunk nbt: NBT) -> [Sign] {
        Chunk.blockEntities(in: nbt).compactMap(Sign.init(blockEntity:)).filter(\.hasText)
    }
}

/// A written book's or book and quill's contents, as plain text.
public struct BookContent: Sendable, Equatable, Codable {
    /// Only written (signed) books have a title and author.
    public var title: String?
    public var author: String?
    public var pages: [String]

    public init(title: String? = nil, author: String? = nil, pages: [String]) {
        self.title = title
        self.author = author
        self.pages = pages
    }
}

extension ItemStack {
    /// The book's contents, for a written book or a book and quill.
    ///
    /// Reads the `written_book_content`/`writable_book_content` components (1.20.5+) and the older
    /// `title`/`author`/`pages` tag.
    public var book: BookContent? {
        guard let components else { return nil }
        // Titles and pages may be stored as `{raw, filtered}` for chat filtering, or bare.
        func raw(_ nbt: NBT) -> NBT { nbt["raw"] ?? nbt }
        if let written = components["minecraft:written_book_content"] {
            return BookContent(title: written["title"].map(raw).flatMap(TextComponent.plainText),
                               author: written["author"]?.string,
                               pages: (written["pages"]?.list ?? []).map { TextComponent.plainText(raw($0)) ?? "" })
        }
        if let writable = components["minecraft:writable_book_content"] {
            // A book and quill's pages are plain strings, never text components.
            return BookContent(pages: (writable["pages"]?.list ?? []).map { raw($0).string ?? "" })
        }
        guard id.hasSuffix("written_book") || id.hasSuffix("writable_book"), let pages = components["pages"]?.list else { return nil }
        if id.hasSuffix("writable_book") {
            return BookContent(pages: pages.map { $0.string ?? "" })
        }
        return BookContent(title: components["title"]?.string, author: components["author"]?.string,
                           pages: pages.map { TextComponent.plainText($0) ?? "" })
    }
}

/// What a region holds that people search for: containers with their items, signs, and
/// creatures with names.
public struct RegionContents: Sendable, Equatable, Codable {
    public var containers: [ItemContainer]
    public var signs: [Sign]
    public var namedCreatures: [Creature] = []
    public var spawners: [Spawner] = []
}

extension Dimension {
    /// Every container, sign with text, spawner and named creature in one region, read in one pass:
    /// block entities from `region/`, and container entities and creatures from `entities/`. Chunks that
    /// can't be read are skipped.
    public func contents(regionX: Int, regionZ: Int) throws -> RegionContents {
        var found = RegionContents(containers: [], signs: [])
        for chunk in try chunks(.terrain, regionX: regionX, regionZ: regionZ, skipping: Chunk.keysNotNeededForContainers) {
            found.containers += ItemContainer.containers(inChunk: chunk.nbt)
            found.signs += Sign.signs(inChunk: chunk.nbt)
            found.spawners += Spawner.spawners(inChunk: chunk.nbt)
        }
        for chunk in try chunks(.entities, regionX: regionX, regionZ: regionZ) {
            found.containers += ItemContainer.containers(inEntityChunk: chunk.nbt)
            found.namedCreatures += Creature.creatures(inEntityChunk: chunk.nbt).filter { $0.customName != nil }
        }
        return found
    }
}
