import Foundation

/// One enabled data-pack order and safe-path policy for dimension, biome and lighting resources.
enum WorldResourcePack {
    case vanilla
    case folder(URL, listed: Set<String>? = nil)
    case zip(ZipResources)
    case unavailable

    enum Resource {
        case absent, unavailable, vanilla
        case data(Data)
    }

    private struct Location {
        let identifier: String
        let path: String
        init?(_ reference: String, directory: String) {
            guard let id = Identifier(reference), !id.path.isEmpty else { return nil }
            let path = "data/\(id.namespace)/\(directory)/\(id.path).json"
            guard WorldResourcePack.validPath(path) else { return nil }
            identifier = id.description
            self.path = path
        }
    }

    // First-wins definitions and composed tag stacks share the same containment, listing and
    // read-error rules. A present but unreadable resource is distinct from an absent resource.
    private func resource(at location: Location) throws -> Resource {
        switch self {
        case .vanilla: return .vanilla
        case .unavailable: return .unavailable
        case .folder(let root, let listed):
            if let listed, !listed.contains(location.identifier) { return .absent }
            guard let file = Self.file(location.path, under: root) else { return .unavailable }
            guard FileManager.default.fileExists(atPath: file.path) else { return .absent }
            return .data(try Data(contentsOf: file))
        case .zip(let resources):
            guard resources.contains(location.path) else { return .absent }
            guard let data = resources.read(location.path) else { return .unavailable }
            return .data(data)
        }
    }

    private static func read<Value>(_ reference: String, directory: String, in packs: [Self],
                                    vanilla: (String) -> Value?, json: (Data) -> Value?) throws -> Value? {
        guard let location = Location(reference, directory: directory) else { return nil }
        for pack in packs {
            switch try pack.resource(at: location) {
            case .absent: continue
            case .vanilla:
                if let value = vanilla(location.identifier) { return value }
            case .unavailable: return nil
            case .data(let data): return json(data)
            }
        }
        return nil
    }

    static func load(enabled ids: [String], in world: URL, vanilla: Self) throws -> [Self] {
        try ids.reversed().map { try load($0, in: world, vanilla: vanilla) }
    }

    /// Saved-world registries use listed resources even when the caller requests only a few
    /// IDs. Prepare each category once; payload reads keep the shared priority/error rules.
    struct Registry {
        private let directory: String
        private let sources: [WorldResourcePack]
        private let identifiers: Set<String>

        init(directory: String, in packs: [WorldResourcePack]) throws {
            self.directory = directory
            var ids = Set<String>(), sources: [WorldResourcePack] = []
            for pack in packs {
                try Task.checkCancellation()
                // Dimension readers supply verified vanilla facts by ID instead of a jar.
                // They are still available, but do not contribute IDs to a complete catalog.
                if case .vanilla = pack { sources.append(pack); continue }
                guard let found = try pack.identifiers(in: directory) else {
                    sources.append(.unavailable)
                    break
                }
                ids.formUnion(found)
                if case .folder(let root, _) = pack { sources.append(.folder(root, listed: found)) }
                else { sources.append(pack) }
            }
            self.sources = sources
            identifiers = ids
        }

        func read<Value>(_ saved: NBT?, vanilla: (String) -> Value?, inline: (NBT) -> Value?,
                         json: (Data) -> Value?) throws -> Value? {
            guard let saved else { return nil }
            guard let reference = saved.string else { return inline(saved) }
            return try read(reference, vanilla: vanilla, json: json)
        }

        func read<Value>(_ reference: String, vanilla: (String) -> Value?, json: (Data) -> Value?) throws -> Value? {
            try Task.checkCancellation()
            return try WorldResourcePack.read(reference, directory: directory, in: sources, vanilla: vanilla, json: json)
        }

        /// First present resource in normal pack priority, retaining absence versus unreadability.
        func resource(_ reference: String) throws -> Resource {
            guard let location = Location(reference, directory: directory) else { return .unavailable }
            for source in sources {
                try Task.checkCancellation()
                let resource = try source.resource(at: location)
                if case .absent = resource { continue }
                return resource
            }
            return .absent
        }

        /// Low-to-high tag layers. Unknown sources or unreadable entries invalidate the stack;
        /// callers must not mistake an incomplete stack for a missing optional tag.
        func stack(_ reference: String, maximumBytes: Int) throws -> [Data]? {
            guard let location = Location(reference, directory: directory) else { return nil }
            var result: [Data] = [], remaining = maximumBytes
            for source in sources {
                try Task.checkCancellation()
                switch try source.resource(at: location) {
                case .absent: continue
                case .unavailable, .vanilla: return nil
                case .data(let data):
                    guard data.count <= ZipResources.maximumResourceSize, data.count <= remaining else { return nil }
                    remaining -= data.count
                    result.append(data)
                }
            }
            return Array(result.reversed())
        }

        func readAll<Value>(json: (Data) -> Value?) throws -> [String: Value] {
            var result: [String: Value] = [:]
            for id in identifiers.sorted() {
                result[id] = try read(id, vanilla: { _ in nil }, json: json)
            }
            return result
        }
    }

    /// Candidate IDs only. The ordinary reader still decides priority and whether a present
    /// resource is usable; listing an invalid override must never expose a lower definition.
    /// Nil means this source has unknown contents, so lower sources cannot add candidates.
    func identifiers(in directory: String) throws -> Set<String>? {
        switch self {
        case .vanilla, .unavailable: return nil
        case .zip(let resources):
            guard let paths = resources.paths(under: "data/") else { return nil }
            return Set(paths.compactMap {
                Self.identifier(for: $0, in: directory)
            })
        case .folder(let root, _):
            let fm = FileManager.default
            guard let data = Self.file("data", under: root) else { return nil }
            guard Self.isDirectory(data) else { return [] }
            var result = Set<String>()
            for namespace in try fm.contentsOfDirectory(atPath: data.path).sorted() {
                try Task.checkCancellation()
                let base = "data/\(namespace)/\(directory)"
                guard GameAssets.resourceID("\(namespace):probe") != nil,
                      let folder = Self.file(base, under: root),
                      try Self.fileType(root.appendingPathComponent(base)) == .typeDirectory else { continue }
                var pending: [(path: String, url: URL)] = [(base, folder)]
                while let current = pending.popLast() {
                    try Task.checkCancellation()
                    for name in try fm.contentsOfDirectory(atPath: current.url.path).sorted() {
                        try Task.checkCancellation()
                        let path = current.path + "/" + name
                        guard let url = Self.file(path, under: root) else { continue }
                        // PathPackResources.listPath uses Files.find without FOLLOW_LINKS.
                        // Inspect the original node, not the resolved destination used for containment.
                        switch try Self.fileType(root.appendingPathComponent(path)) {
                        case .some(.typeDirectory): pending.append((path, url))
                        case .some(.typeRegular):
                            if let id = Self.identifier(for: path, in: directory) { result.insert(id) }
                        default: break
                        }
                    }
                }
            }
            return result
        }
    }

    private static func identifier(for path: String, in directory: String) -> String? {
        guard validPath(path), path.hasSuffix(".json") else { return nil }
        let parts = path.split(separator: "/"), category = directory.split(separator: "/")
        guard parts.count > category.count + 2, parts[0] == "data",
              parts[2..<(2 + category.count)].elementsEqual(category) else { return nil }
        let name = parts[(2 + category.count)...].joined(separator: "/").dropLast(5)
        return GameAssets.resourceID("\(parts[1]):\(name)")?.description
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static func fileType(_ url: URL) throws -> FileAttributeType? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        return try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    }

    private static func load(_ id: String, in world: URL, vanilla: Self) throws -> Self {
        if id == "vanilla" { return vanilla }
        guard id.hasPrefix("file/") else { return .unavailable }
        let name = String(id.dropFirst(5))
        guard !name.isEmpty, !name.contains("/"), let root = file("datapacks", under: world),
              let folder = file(name, under: root) else { return .unavailable }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { return .unavailable }
        let result: Self, data: Data
        if isDirectory.boolValue {
            guard let metadata = file("pack.mcmeta", under: folder), FileManager.default.fileExists(atPath: metadata.path) else { return .unavailable }
            data = try Data(contentsOf: metadata)
            result = .folder(folder)
        } else {
            guard name.hasSuffix(".zip"), let resources = try ZipResources(contentsOf: folder),
                  let metadata = resources.read("pack.mcmeta") else { return .unavailable }
            data = metadata
            result = .zip(resources)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["pack"] is [String: Any], json["overlays"] == nil, json["filter"] == nil else { return .unavailable }
        return result
    }

    static func validPath(_ path: String) -> Bool {
        !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Identifier syntax permits dot segments; file lookup must separately stay inside the pack.
    static func file(_ path: String, under root: URL) -> URL? {
        guard validPath(path) else { return nil }
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.pathComponents.starts(with: root.pathComponents), file.pathComponents.count > root.pathComponents.count else { return nil }
        return file
    }
}
