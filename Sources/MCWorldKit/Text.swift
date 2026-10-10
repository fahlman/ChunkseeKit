import Foundation

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
              let x = nbt["x"]?.int, let y = nbt["y"]?.int, let z = nbt["z"]?.int else { return nil }
        func lines(_ side: NBT?) -> [String] {
            (side?["messages"]?.list ?? []).map { TextComponent.plainText($0) ?? "" }
        }
        var front = lines(nbt["front_text"])
        if nbt["front_text"] == nil {
            front = (1...4).map { nbt["Text\($0)"].flatMap(TextComponent.plainText) ?? "" }
        }
        self.init(kind: kind, x: x, y: y, z: z, front: front, back: lines(nbt["back_text"]))
    }

    /// Whether either side has any text.
    public var hasText: Bool { !(front + back).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Signs with text among a chunk's block entities.
    public static func signs(inChunk nbt: NBT) -> [Sign] {
        (nbt["block_entities"]?.list ?? []).compactMap(Sign.init(blockEntity:)).filter(\.hasText)
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
}

extension Dimension {
    /// Every container, sign with text and named creature in one region, read in one pass: block
    /// entities from `region/`, and container entities and creatures from `entities/`. Chunks that
    /// can't be read are skipped.
    public func contents(regionX: Int, regionZ: Int) throws -> RegionContents {
        var found = RegionContents(containers: [], signs: [])
        if let region = try Self.region(in: regionDirectory, x: regionX, z: regionZ) {
            for (x, z) in region.chunkCoordinates {
                guard let nbt = try? region.chunkNBT(localX: x, localZ: z, skipping: Chunk.keysNotNeededForContainers) else { continue }
                found.containers += ItemContainer.containers(inChunk: nbt)
                found.signs += Sign.signs(inChunk: nbt)
            }
        }
        if let entities = try Self.region(in: entitiesDirectory, x: regionX, z: regionZ) {
            for (x, z) in entities.chunkCoordinates {
                guard let nbt = try? entities.chunkNBT(localX: x, localZ: z) else { continue }
                found.containers += ItemContainer.containers(inEntityChunk: nbt)
                found.namedCreatures += Creature.creatures(inEntityChunk: nbt).filter { $0.customName != nil }
            }
        }
        return found
    }
}
