import Foundation

/// Query-local memoization only; no cache or mutable state escapes the world read.
struct WorldTimelineReader<Projection: WorldTimelineProjection> {
    private let timelineResources: WorldResourcePack.Registry
    private var tagReader: ResourceTagReader
    private var timelines: [String: ResourceRead<Projection>] = [:]
    private var budget = ResourceReadBudget()

    init(world: World, assets: GameAssets?) throws {
        let vanilla: WorldResourcePack = if let assets, Int(assets.version.dataVersion) == SaveVersion.java26_3 {
            .zip(assets.resources)
        } else { .unavailable }
        try self.init(packs: WorldResourcePack.load(enabled: world.level.enabledDataPacks, in: world.url, vanilla: vanilla))
    }

    private init(packs: [WorldResourcePack]) throws {
        timelineResources = try WorldResourcePack.Registry(directory: "timeline", in: packs)
        tagReader = try ResourceTagReader(registry: "timeline", packs: packs)
    }

    mutating func read(_ references: DimensionTime.Timelines) throws -> [Projection]? {
        var budget = budget, tags = tagReader
        defer { self.budget = budget; tagReader = tags }
        let identifiers: [String]
        switch references {
        case .list(let list): identifiers = list // Direct HolderSet lists preserve duplicates.
        case .tag(let id):
            let result = try tags.read(id, budget: &budget) { id, budget in
                switch try timeline(id, budget: &budget) {
                case .missing: .missing
                case .unavailable: .unavailable
                case .value: .value(())
                }
            }
            guard case .value(let tag) = result else { return nil }
            identifiers = tag.members.map(\.id)
        }
        guard identifiers.count <= 4096, budget.consume(identifiers.count) else { return nil }
        var result: [Projection] = []
        for id in identifiers {
            try Task.checkCancellation()
            guard case .value(let value) = try timeline(id, budget: &budget) else { return nil }
            result.append(value)
        }
        return result
    }

    private mutating func timeline(_ id: String, budget: inout ResourceReadBudget) throws -> ResourceRead<Projection> {
        try Task.checkCancellation()
        if let cached = timelines[id] { return cached }
        let result: ResourceRead<Projection>
        switch try timelineResources.resource(id) {
        case .absent: result = .missing
        case .vanilla, .unavailable: result = .unavailable
        case .data(let data):
            if data.count <= budget.bytes, data.count <= ZipResources.maximumResourceSize {
                budget.bytes -= data.count
                result = Projection(json: data).map(ResourceRead.value) ?? .unavailable
            } else { result = .unavailable }
        }
        timelines[id] = result
        return result
    }

}
