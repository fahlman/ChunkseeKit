import Foundation

/// Static, positive-weight spawn candidates from dimension and biome environment attributes.
/// This is not spawn eligibility: counts, light, height, structures, timelines, weather and the
/// mob's own spawn rules remain separate. Unknown type IDs are retained as declared by the data.
public struct MobSpawnSettings: Sendable, Equatable {
    public struct Candidate: Sendable, Equatable {
        public let entityType: String
        /// Nil for an unreadable weight; zero is a known unselectable entry.
        public let weight: Int?
    }

    public let candidatesByCategory: [String: [Candidate]]
    private let incompleteCategories: Set<String>
    private let unknownUnlistedCategories: Bool

    /// Whether the category declares this type with positive weight. Known positive evidence
    /// survives unrelated unreadable entries. Missing base data cannot invent a negative answer.
    public func contains(_ entityType: String, in category: String) -> Bool? {
        guard let id = Identifier(entityType), !id.path.isEmpty, !category.isEmpty else { return nil }
        guard let candidates = candidatesByCategory[category] else {
            return unknownUnlistedCategories || incompleteCategories.contains(category) ? nil : false
        }
        let matching = candidates.filter { $0.entityType == id.description }
        if matching.contains(where: { ($0.weight ?? 0) > 0 }) { return true }
        if incompleteCategories.contains(category) || matching.contains(where: { $0.weight == nil }) { return nil }
        return false
    }

    static var gameDefault: Self {
        Self(candidatesByCategory: GeneratedMobSpawnFacts.defaultCandidates,
             incompleteCategories: [], unknownUnlistedCategories: false)
    }

    static func dimension(_ nbt: NBT) -> Self? { read(.nbt(nbt), base: gameDefault) }
    static func dimension(json: Data) -> Self? { read(json: json, base: gameDefault) }

    static func read(json: Data, base: Self?) -> Self? {
        guard json.count <= ZipResources.maximumResourceSize,
              let root = try? JSONSerialization.jsonObject(with: json) else { return nil }
        return read(.json(root), base: base)
    }

    private enum Attribute: String {
        case naturalSpawns = "minecraft:gameplay/natural_mob_spawns"
    }

    private static func read(_ input: Input, base: Self?) -> Self? {
        guard let root = input.object else { return nil }
        guard let rawAttributes = root["attributes"] else { return base }
        guard let attributes = rawAttributes.object,
              let selected = try? EnvironmentAttributeMap<Attribute>.selected(attributes) else { return nil }
        guard let raw = selected[.naturalSpawns] else { return base }
        // The value codec is tried before the modifier envelope, as in EnvironmentAttributeMap.
        if let replacement = table(raw) { return replacement }
        guard let entry = raw.object, let modifier = entry["modifier"]?.string,
              let argument = entry["argument"], let value = table(argument) else { return nil }
        switch modifier {
        case "override": return value
        case "overlay":
            var categories = base?.candidatesByCategory ?? [:]
            var incomplete = base?.incompleteCategories ?? []
            for (category, candidates) in value.candidatesByCategory {
                categories[category] = candidates
                incomplete.remove(category)
            }
            incomplete.formUnion(value.incompleteCategories)
            return Self(candidatesByCategory: categories, incompleteCategories: incomplete,
                        unknownUnlistedCategories: base?.unknownUnlistedCategories ?? true)
        default: return nil
        }
    }

    private static func table(_ raw: Input) -> Self? {
        guard let root = raw.object, let categories = root["spawns_by_category"]?.object,
              categories.count <= 256 else { return nil }
        var result: [String: [Candidate]] = [:], incomplete: Set<String> = []
        var remaining = 65_536
        for (category, rawEntries) in categories.sorted(by: { $0.key < $1.key }) {
            guard let entries = rawEntries.array, entries.count <= 4096, entries.count <= remaining else {
                result[category] = []; incomplete.insert(category); continue
            }
            remaining -= entries.count
            var candidates: [Candidate] = []
            for entry in entries {
                guard let fields = entry.object, let text = fields["type"]?.string,
                      let id = Identifier(text), !id.path.isEmpty else {
                    incomplete.insert(category); continue
                }
                let weight: Int?
                if let rawWeight = fields["weight"] { weight = rawWeight.integer.flatMap { $0 >= 0 ? $0 : nil } }
                else { weight = GeneratedMobSpawnFacts.defaultWeight }
                candidates.append(Candidate(entityType: id.description, weight: weight))
            }
            result[category] = candidates
        }
        return Self(candidatesByCategory: result, incompleteCategories: incomplete, unknownUnlistedCategories: false)
    }

    /// A shallow adapter: only selected attribute/table fields are traversed, with shared bounds.
    /// It avoids translating unrelated or recursive saved data just to read spawn candidates.
    private enum Input {
        case json(Any), nbt(NBT)

        var object: [String: Self]? {
            switch self {
            case .json(let value): (value as? [String: Any])?.mapValues(Self.json)
            case .nbt(let value): value.compound?.mapValues(Self.nbt)
            }
        }
        var array: [Self]? {
            switch self {
            case .json(let value): (value as? [Any])?.map(Self.json)
            case .nbt(let value): value.list?.map(Self.nbt)
            }
        }
        var string: String? {
            switch self {
            case .json(let value): value as? String
            case .nbt(let value): value.string
            }
        }
        var integer: Int? {
            switch self {
            case .json(let value): try? AssetJSON.integer(value)
            case .nbt(let value): value.double.flatMap(Int32.init(exactly:)).map(Int.init)
            }
        }
    }
}

extension GameAssets {
    /// Applies one biome's static spawn attribute to the supplied dimension base. Pass nil when
    /// that base is unavailable; an overlay can still settle the categories it explicitly names.
    /// Missing color/climate fields do not hide readable spawn data. No version gate is applied.
    public func biomeSpawnSettings(_ identifier: String, base: MobSpawnSettings?) -> MobSpawnSettings? {
        biomeResource(identifier) { MobSpawnSettings.read(json: $0, base: base) }
    }
}

extension World {
    /// Static dimension-plus-biome spawn candidates from enabled packs and the selected game.
    /// Retain the immutable result and pass the dimension type's baseMobSpawnSettings explicitly.
    /// Limits: 64 packs, 4,096 biomes, 16 MiB/file, 64 MiB total; no chunks or saves are changed.
    public func biomeSpawnSettings(for identifiers: Set<String>, base: MobSpawnSettings?,
                                   assets: GameAssets?) throws -> [String: MobSpawnSettings] {
        try biomeResources(for: identifiers, assets: assets) { MobSpawnSettings.read(json: $0, base: base) }
    }
}
