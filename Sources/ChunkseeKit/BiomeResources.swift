import Foundation

extension GameAssets {
    /// Color and spawn projections share path validation and the same resource limit.
    func biomeResource<Value>(_ identifier: String, decode: (Data) -> Value?) -> Value? {
        guard let data = resource(identifier, directory: "worldgen/biome", extension: "json", domain: .data) else { return nil }
        var budget = ResourceReadBudget()
        guard budget.charge(data) else { return nil }
        return decode(data)
    }
}

extension World {
    /// One owner for biome discovery, requested IDs, enabled-pack priority and query bounds.
    /// A nil request discovers the registry; each projection reads only the facts it owns.
    func biomeResources<Value>(for identifiers: Set<String>? = nil, assets: GameAssets?,
                               decode: (Data) -> Value?) throws -> [String: Value] {
        try Task.checkCancellation()
        let maximumCount = 4096
        if let identifiers, identifiers.isEmpty || identifiers.count > maximumCount { return [:] }
        let requestedIDs = identifiers.map { Set($0.compactMap { GameAssets.resourceID($0)?.description }) }
        if requestedIDs?.isEmpty == true { return [:] }
        guard let packs = try resourcePacks(assets: assets) else { return [:] }
        let registry = try WorldResourcePack.Registry(directory: "worldgen/biome", in: packs)
        var budget = ResourceReadBudget()
        func read(_ data: Data) -> Value? {
            guard budget.charge(data) else { return nil }
            return decode(data)
        }
        guard let ids = requestedIDs else { return try registry.readAll(maximumCount: maximumCount, json: read) }
        var result: [String: Value] = [:]
        for id in ids.sorted() { result[id] = try registry.read(id, json: read) }
        return result
    }
}
