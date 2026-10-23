import Foundation

/// One enabled data-pack order and safe-path policy for dimension and biome definitions.
enum WorldResourcePack {
    case vanilla
    case folder(URL)
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
            case .folder(let root):
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
