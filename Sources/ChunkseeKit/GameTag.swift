import Foundation

/// The IDs declared by a composed game tag, in first-occurrence order.
/// This describes the data, not whether every ID exists in the game's live registry.
public struct GameTag: Sendable, Equatable {
    public struct Member: Sendable, Equatable {
        public let id: String
        /// Whether a declaration requires this member. An optional ID is retained rather
        /// than guessed to be present or absent in a registry that these files do not define.
        public let required: Bool
    }
    public let members: [Member]
    /// Effective declarations after pack composition, with each readable reference resolved.
    /// Missing optional references are omitted; valid empty references remain. A tag entry's
    /// members include its nested tags, so consumers can group by the game's declared tags
    /// without rebuilding composition or maintaining their own list of subgroup names.
    public let entries: [Entry]

    public struct Entry: Sendable, Equatable {
        public let id: String
        public let isTag: Bool
        public let required: Bool
        public let members: [Member]
    }

    init(members: [Member], entries: [Entry] = []) {
        self.members = members; self.entries = entries
    }
}

extension GameAssets {
    /// Reads a tag from this jar for any registry ID, such as block, entity_type or
    /// worldgen/biome. Minecraft uses the registry ID's path as its resource directory.
    /// Nested tags, replace and optional tag references use the shared reader.
    /// Missing, malformed, cyclic or over-budget tags return nil; a valid empty tag is retained.
    /// No game-version gate or built-in membership list is applied.
    public func tag(_ identifier: String, in registry: String) throws -> GameTag? {
        guard let id = Self.resourceID(identifier) else { return nil }
        return try GameTag.read([id.description], registry: registry, packs: [.zip(resources)])[id.description]
    }
}

extension World {
    /// Reads requested tags from the world's enabled folder/ZIP packs and a supplied game jar
    /// chosen by the caller. An absent jar leaves vanilla resources unavailable.
    /// Keys are canonical tag IDs. Missing or unreadable tags are omitted, distinct from a
    /// valid empty tag. A higher replacing tag can settle its contents without a lower source.
    /// No default enabled-pack list is invented. Other read errors and cancellation propagate.
    ///
    /// Only declarations are read: optional direct member IDs retain their required flag.
    /// Consumers must establish actual registry existence separately when it matters.
    /// Query limits: 64 packs/levels, 4,096 requested tags or members per tag, 64 MiB of selected
    /// JSON and 65,536 reference/member steps. No world writes or persistent cache are made.
    public func tags(for identifiers: Set<String>, in registry: String, assets: GameAssets?) throws -> [String: GameTag] {
        try Task.checkCancellation()
        guard identifiers.count <= 4096, let packs = try resourcePacks(assets: assets) else { return [:] }
        return try GameTag.read(identifiers, registry: registry, packs: packs)
    }
}

extension GameTag {
    fileprivate static func read(_ identifiers: Set<String>, registry: String, packs: [WorldResourcePack]) throws -> [String: GameTag] {
        try Task.checkCancellation()
        guard let directory = GameAssets.resourceID(registry) else { return [:] }
        let ids = Set(identifiers.compactMap { GameAssets.resourceID($0)?.description })
        var reader = try ResourceTagReader(registry: directory.path, packs: packs)
        var budget = ResourceReadBudget(), result: [String: GameTag] = [:]
        for id in ids.sorted() {
            if case .value(let tag) = try reader.read(id, budget: &budget, element: { _, _ in .value(()) }) {
                result[id] = tag
            }
        }
        return result
    }
}
