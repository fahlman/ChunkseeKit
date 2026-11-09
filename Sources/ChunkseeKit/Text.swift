import Foundation

/// Minecraft text components: plain saved text and language-independent resource content.
public enum TextComponent {
    /// Accepts a literal string, an NBT compound with `text`/`translate` and `extra`, or a list
    /// of components. Save readers upgrade older JSON text first. Removes legacy `§` formatting
    /// codes after joining the fragments, preserving their spaces and line breaks.
    public static func plainText(_ nbt: NBT) -> String? {
        guard let content = content(nbt) else { return nil }
        let plain = removingFormattingCodes(plainText(content))
        return plain.isEmpty ? nil : plain
    }

    private static func plainText(_ content: Content) -> String {
        switch content {
        case .literal(let text): text
        // Keep the existing language-free projection; structured clients resolve the key.
        case .translated(let key, _, _): key
        case .sequence(let children): children.map(plainText).joined()
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
    /// The saved block entity ID, including custom sign types.
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
    /// Text must already have been upgraded using its containing save's version.
    public init?(blockEntity nbt: NBT) {
        self.init(blockEntity: nbt, text: nbt)
    }

    static func hasTextFields(_ nbt: NBT) -> Bool {
        nbt["front_text"]?.compound != nil || nbt["back_text"]?.compound != nil
            || (1...4).contains { nbt["Text\($0)"] != nil }
    }

    private init?(blockEntity nbt: NBT, text: NBT) {
        guard Self.hasTextFields(nbt), let kind = nbt["id"]?.string,
              let position = nbt.blockEntityPosition else { return nil }
        func lines(_ side: NBT?) -> [String] {
            (side?["messages"]?.list ?? []).map { TextComponent.plainText($0.unwrappedListElement) ?? "" }
        }
        var front = lines(text["front_text"])
        if nbt["front_text"] == nil {
            front = (1...4).map { text["Text\($0)"].flatMap(TextComponent.plainText) ?? "" }
        }
        self.init(kind: kind, x: position.x, y: position.y, z: position.z, front: front, back: lines(text["back_text"]))
    }

    /// Whether either side has any text.
    public var hasText: Bool { !(front + back).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Signs with text among a chunk's block entities.
    public static func signs(inChunk nbt: NBT) -> [Sign] {
        signs(in: ChunkRecords(nbt, needs: .signs))
    }

    static func signs(in records: ChunkRecords) -> [Sign] {
        zip(records.blocks.saved, records.blocks.upgraded)
            .compactMap { Sign(blockEntity: $0, text: $1) }.filter(\.hasText)
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
            // WrittenBookContent's title is a Filterable<String>, unlike its component pages.
            let title = written["title"].map(raw).flatMap(\.string).flatMap { TextComponent.plainText(.string($0)) }
            return BookContent(title: title,
                               author: written["author"]?.string,
                               pages: (written["pages"]?.list ?? []).map { TextComponent.plainText(raw($0.unwrappedListElement)) ?? "" })
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
                           pages: pages.map { TextComponent.plainText($0.unwrappedListElement) ?? "" })
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
        try forEachChunk(.terrain, regionX: regionX, regionZ: regionZ,
                         skipping: Chunk.keysNotNeededForContainers) { _, _, nbt in
            let records = ChunkRecords(nbt)
            found.containers += ItemContainer.containers(in: records)
            found.signs += Sign.signs(in: records)
            found.spawners += Spawner.spawners(in: records)
            found.namedCreatures += Creature.creatures(in: records.entities).filter { $0.customName != nil }
        }
        try forEachChunk(.entities, regionX: regionX, regionZ: regionZ) { _, _, nbt in
            let entities = NormalizedEntities(nbt)
            found.containers += ItemContainer.containers(in: entities)
            found.namedCreatures += Creature.creatures(in: entities).filter { $0.customName != nil }
        }
        return found
    }
}
