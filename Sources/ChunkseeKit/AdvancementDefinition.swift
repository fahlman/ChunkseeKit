import Foundation

/// Readable presentation metadata from an advancement definition, independent of saved progress.
public struct AdvancementDefinition: Sendable, Hashable {
    /// Nil when display/title is absent, malformed, dynamic or exceeds the text bounds.
    /// An absent title must not be used to discard the player's saved advancement progress.
    public let title: TextComponent.Content?

    public init?(data: Data) {
        var budget = ResourceReadBudget()
        guard let value = Self.read(data, budget: &budget) else { return nil }
        self = value
    }

    private init(title: TextComponent.Content?) { self.title = title }

    private static func read(_ data: Data, budget: inout ResourceReadBudget) -> Self? {
        guard budget.charge(data), let json = try? AssetJSON.object(TextComponent.jsonValue(from: data)) else { return nil }
        let title = (json["display"] as? [String: Any])?["title"]
        return Self(title: title.flatMap { try? TextComponent.content($0, budget: &budget) })
    }

    fileprivate static func read(_ identifiers: Set<String>, in packs: [WorldResourcePack]) throws -> [String: Self] {
        try Task.checkCancellation()
        guard !identifiers.isEmpty, identifiers.count <= 4096 else { return [:] }
        let ids = Set(identifiers.compactMap { GameAssets.resourceID($0)?.description })
        guard !ids.isEmpty else { return [:] }
        let registry = try WorldResourcePack.Registry(directory: "advancement", in: packs)
        var budget = ResourceReadBudget(), result: [String: Self] = [:]
        for id in ids.sorted() {
            result[id] = try registry.read(id) { read($0, budget: &budget) }
        }
        return result
    }
}

extension GameAssets {
    /// Reads only the requested advancement definitions from this jar. IDs are normalized;
    /// missing/malformed definitions are omitted, while unavailable titles remain nil.
    public func advancementDefinitions(for identifiers: Set<String>) throws -> [String: AdvancementDefinition] {
        try AdvancementDefinition.read(identifiers, in: [.zip(resources)])
    }
}

extension World {
    /// Reads requested advancement definitions from enabled packs over the supplied game jar.
    /// Uses the shared priority, containment and invalid-override policy. Limits: 64 packs,
    /// 4,096 requested IDs, 16 MiB per file, 64 MiB total, and 65,536 text/argument visits.
    /// No files are written. Keep this snapshot separately from saved advancement progress.
    public func advancementDefinitions(for identifiers: Set<String>, assets: GameAssets?) throws -> [String: AdvancementDefinition] {
        try Task.checkCancellation()
        guard !identifiers.isEmpty, identifiers.count <= 4096,
              let packs = try resourcePacks(assets: assets) else { return [:] }
        return try AdvancementDefinition.read(identifiers, in: packs)
    }
}
