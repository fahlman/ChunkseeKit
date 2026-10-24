import Foundation

/// Query-local memoization only; no cache or mutable state escapes the world read.
struct WorldTimelineReader<Projection: WorldTimelineProjection> {
    enum Read<Value> { case missing, unavailable, value(Value) }
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
                guard let id = fields["id"] as? String else { throw InvalidLighting.data }
                text = id
                required = try Self.flag(fields["required"], default: true)
            }
            isTag = text.hasPrefix("#")
            guard let id = Identifier(isTag ? String(text.dropFirst()) : text), !id.path.isEmpty else {
                throw InvalidLighting.data
            }
            self.id = id.description
        }

        static func flag(_ raw: Any?, default fallback: Bool) throws -> Bool {
            guard let raw, !(raw is NSNull) else { return fallback }
            return try AssetJSON.boolean(raw)
        }
    }

    private let timelineResources: WorldResourcePack.Registry
    private let tagResources: WorldResourcePack.Registry
    private var timelines: [String: Read<Projection>] = [:]
    private var tags: [String: Read<[String]>] = [:]
    private var visiting: Set<String> = []
    private var remainingBytes = 64 * 1024 * 1024
    private var remainingWork = 65_536

    init(packs: [WorldResourcePack]) throws {
        timelineResources = try WorldResourcePack.Registry(directory: "timeline", in: packs)
        tagResources = try WorldResourcePack.Registry(directory: "tags/timeline", in: packs)
    }

    mutating func read(_ references: DimensionTime.Timelines) throws -> [Projection]? {
        let identifiers: [String]
        switch references {
        case .list(let list): identifiers = list // Direct HolderSet lists preserve duplicates.
        case .tag(let id):
            guard case .value(let list) = try tag(id) else { return nil }
            identifiers = list
        }
        guard identifiers.count <= 4096, consume(identifiers.count) else { return nil }
        var result: [Projection] = []
        for id in identifiers {
            try Task.checkCancellation()
            guard case .value(let value) = try timeline(id) else { return nil }
            result.append(value)
        }
        return result
    }

    private mutating func timeline(_ id: String) throws -> Read<Projection> {
        try Task.checkCancellation()
        if let cached = timelines[id] { return cached }
        let result: Read<Projection>
        switch try timelineResources.resource(id) {
        case .absent: result = .missing
        case .vanilla, .unavailable: result = .unavailable
        case .data(let data):
            if data.count <= remainingBytes, data.count <= ZipResources.maximumResourceSize {
                remainingBytes -= data.count
                result = Projection(json: data).map(Read.value) ?? .unavailable
            } else { result = .unavailable }
        }
        timelines[id] = result
        return result
    }

    private mutating func tag(_ id: String) throws -> Read<[String]> {
        try Task.checkCancellation()
        if let cached = tags[id] { return cached }
        guard visiting.count < 64, !visiting.contains(id), consume(1) else { return .unavailable }
        visiting.insert(id)
        defer { visiting.remove(id) }
        let result = try buildTag(id)
        tags[id] = result
        return result
    }

    private mutating func buildTag(_ id: String) throws -> Read<[String]> {
        guard let stack = try tagResources.stack(id, maximumBytes: remainingBytes) else { return .unavailable }
        guard !stack.isEmpty else { return .missing }
        var entries: [Entry] = []
        for data in stack {
            try Task.checkCancellation()
            remainingBytes -= data.count
            do {
                let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
                let raw = try AssetJSON.array(root["values"])
                guard raw.count <= 4096, consume(raw.count) else { return .unavailable }
                let values = try raw.map(Entry.init)
                if try Entry.flag(root["replace"], default: false) { entries.removeAll(keepingCapacity: true) }
                guard values.count <= 4096 - entries.count else { return .unavailable }
                entries.append(contentsOf: values)
            } catch { return .unavailable } // Deliberately no partial-registry recovery for invalid tag files.
        }
        var result: [String] = [], seen: Set<String> = []
        for entry in entries {
            try Task.checkCancellation()
            let members: Read<[String]>
            if entry.isTag { members = try tag(entry.id) }
            else {
                switch try timeline(entry.id) {
                case .value: members = .value([entry.id])
                case .missing: members = .missing
                case .unavailable: members = .unavailable
                }
            }
            switch members {
            case .missing:
                if entry.required { return .missing } // A tag with a missing required member is not built.
            case .unavailable: return .unavailable
            case .value(let ids):
                guard consume(ids.count) else { return .unavailable }
                for id in ids where seen.insert(id).inserted {
                    guard result.count < 4096 else { return .unavailable }
                    result.append(id)
                }
            }
        }
        return .value(result)
    }

    private mutating func consume(_ work: Int) -> Bool {
        guard work <= remainingWork else { return false }
        remainingWork -= work
        return true
    }
}
