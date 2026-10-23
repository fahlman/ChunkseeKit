import Foundation

/// One enabled data-pack order and safe-path policy for dimension and biome definitions.
enum WorldResourcePack {
    case vanilla
    case folder(URL, listed: Set<String>? = nil)
    case zip(ZipResources)
    case unavailable

    static func read<Value>(_ saved: NBT?, directory: String, in packs: [Self],
                            vanilla: (String) -> Value?, inline: (NBT) -> Value?,
                            json: (Data) -> Value?) throws -> Value? {
        guard let saved else { return nil }
        guard let reference = saved.string else { return inline(saved) }
        return try read(reference, directory: directory, in: packs, vanilla: vanilla, json: json)
    }

    static func read<Value>(_ reference: String, directory: String, in packs: [Self],
                            vanilla: (String) -> Value?, json: (Data) -> Value?) throws -> Value? {
        guard let id = Identifier(reference), !id.path.isEmpty else { return nil }
        let path = "data/\(id.namespace)/\(directory)/\(id.path).json"
        guard validPath(path) else { return nil }
        for pack in packs {
            switch pack {
            case .vanilla:
                if let value = vanilla(id.description) { return value }
            case .unavailable: return nil
            case .folder(let root, let listed):
                if let listed, !listed.contains(id.description) { continue }
                guard let file = Self.file(path, under: root) else { return nil }
                if FileManager.default.fileExists(atPath: file.path) {
                    // An invalid override is still an override, never a reason to try a lower pack.
                    return json(try Data(contentsOf: file))
                }
            case .zip(let resources):
                if resources.contains(path) {
                    guard let data = resources.read(path) else { return nil }
                    return json(data)
                }
            }
        }
        return nil
    }

    static func load(enabled ids: [String], in world: URL, vanilla: Self) throws -> [Self] {
        try ids.reversed().map { try load($0, in: world, vanilla: vanilla) }
    }

    /// Registry discovery considers only resources a pack lists. A higher linked file is not
    /// a registry entry and cannot override a lower real file; a listed malformed file can.
    static func readAll<Value>(directory: String, in packs: [Self], json: (Data) -> Value?) throws -> [String: Value] {
        var ids = Set<String>(), sources: [Self] = []
        for pack in packs {
            try Task.checkCancellation()
            guard let found = try pack.identifiers(in: directory) else {
                sources.append(.unavailable)
                break
            }
            ids.formUnion(found)
            if case .folder(let root, _) = pack { sources.append(.folder(root, listed: found)) }
            else { sources.append(pack) }
        }
        var result: [String: Value] = [:]
        for id in ids.sorted() {
            try Task.checkCancellation()
            result[id] = try read(id, directory: directory, in: sources, vanilla: { _ in nil }, json: json)
        }
        return result
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
