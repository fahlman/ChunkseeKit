import Foundation

enum ResourceRead<Value> { case missing, unavailable, value(Value) }

/// One query budget spans tag expansion and any definitions its consumer validates.
struct ResourceReadBudget {
    private var bytes = 64 * 1024 * 1024
    private var work = 65_536

    mutating func consume(_ amount: Int) -> Bool {
        guard amount <= work else { return false }
        work -= amount
        return true
    }

    /// Charge each selected resource once, whether it is a tag layer or a typed definition.
    mutating func charge(_ data: Data) -> Bool {
        charge(bytes: data.count)
    }

    mutating func charge(bytes count: Int) -> Bool {
        guard count >= 0, count <= ZipResources.maximumResourceSize, count <= bytes else { return false }
        bytes -= count
        return true
    }
}

/// Query-local tag composition shared by registry declarations and typed timeline reads.
struct ResourceTagReader {
    private struct Entry {
        let id: String
        let isTag: Bool
        let required: Bool

        init(_ raw: Any) throws {
            let text: String
            if let shorthand = raw as? String {
                text = shorthand; required = true
            } else {
                let fields = try AssetJSON.object(raw)
                guard let id = fields["id"] as? String else { throw Invalid.data }
                text = id
                required = try Self.flag(fields["required"], default: true)
            }
            isTag = text.hasPrefix("#")
            // Member IDs are data, not file paths. Only a tag/resource lookup applies the
            // pack's containment policy; a readable direct ID must not be discarded here.
            guard let id = Identifier(isTag ? String(text.dropFirst()) : text), !id.path.isEmpty else { throw Invalid.data }
            self.id = id.description
        }

        static func flag(_ raw: Any?, default fallback: Bool) throws -> Bool {
            guard let raw, !(raw is NSNull) else { return fallback }
            return try AssetJSON.boolean(raw)
        }
    }

    private enum Invalid: Error { case data }
    private let resources: WorldResourcePack.Registry
    private var tags: [String: ResourceRead<GameTag>] = [:]
    private var visiting: Set<String> = []

    init(registry: String, packs: [WorldResourcePack]) throws {
        resources = try WorldResourcePack.Registry(directory: "tags/" + registry, in: packs)
    }

    mutating func read(_ id: String, budget: inout ResourceReadBudget,
                       element: (String, inout ResourceReadBudget) throws -> ResourceRead<Void>) throws -> ResourceRead<GameTag> {
        try Task.checkCancellation()
        if let cached = tags[id] { return cached }
        guard visiting.count < 64, !visiting.contains(id), budget.consume(1) else { return .unavailable }
        visiting.insert(id)
        defer { visiting.remove(id) }
        let result = try build(id, budget: &budget, element: element)
        tags[id] = result
        return result
    }

    private mutating func build(_ id: String, budget: inout ResourceReadBudget,
                               element: (String, inout ResourceReadBudget) throws -> ResourceRead<Void>) throws -> ResourceRead<GameTag> {
        guard let stack = try resources.stack(id, budget: &budget, decode: { data, budget -> (value: [Entry], replace: Bool)? in
            do {
                let root = try AssetJSON.object(AssetJSON.value(from: data, limitsNumbers: false))
                let values = try AssetJSON.array(root["values"])
                guard values.count <= 4096, budget.consume(values.count) else { return nil }
                return (try values.map(Entry.init), try Entry.flag(root["replace"], default: false))
            } catch { return nil }
        }) else { return .unavailable }
        guard !stack.isEmpty else { return .missing }
        guard stack.reduce(0, { $0 + $1.count }) <= 4096 else { return .unavailable }
        var members: [GameTag.Member] = [], indices: [String: Int] = [:]
        for entry in stack.joined() {
            try Task.checkCancellation()
            let resolved: ResourceRead<GameTag>
            if entry.isTag {
                resolved = try read(entry.id, budget: &budget, element: element)
            } else {
                switch try element(entry.id, &budget) {
                case .missing: resolved = .missing
                case .unavailable: resolved = .unavailable
                case .value: resolved = .value(GameTag(members: [.init(id: entry.id, required: entry.required)]))
                }
            }
            switch resolved {
            case .missing:
                if entry.required { return .missing }
            case .unavailable: return .unavailable
            case .value(let tag):
                guard budget.consume(tag.members.count) else { return .unavailable }
                for member in tag.members {
                    if let index = indices[member.id] {
                        // One declaration can require an ID that another mentions optionally.
                        if member.required { members[index] = member }
                    } else {
                        guard members.count < 4096 else { return .unavailable }
                        indices[member.id] = members.count
                        members.append(member)
                    }
                }
            }
        }
        return .value(GameTag(members: members))
    }
}
