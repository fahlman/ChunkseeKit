import Foundation

/// Immutable, read-only access to a supplied Minecraft game jar. Nothing is extracted.
/// Opening and resolving resources are synchronous; clients perform this work off their UI actor.
public struct GameAssets: Sendable {
    public let version: Version
    let resources: ZipResources

    public struct Version: Sendable, Equatable, Decodable {
        public let id: String
        public let dataVersion: Int32
        private enum CodingKeys: String, CodingKey { case id, dataVersion = "world_version" }
    }

    /// Read errors propagate. Unsupported archives or missing/malformed version.json return nil.
    public init?(contentsOf url: URL) throws {
        self.init(data: try Data(contentsOf: url))
    }

    public init?(data: Data) {
        guard let resources = ZipResources(data: data), let metadata = resources.read("version.json"),
              let version = try? JSONDecoder().decode(Version.self, from: metadata), !version.id.isEmpty else { return nil }
        self.resources = resources
        self.version = version
    }

    /// Resolves inherited textures, elements and GUI settings, including builtin/generated layers.
    /// Missing, cyclic, unsupported or malformed models return nil. Resolution is bounded to 64
    /// parents/references and 16 MiB of model JSON in total; no shared mutable cache is introduced.
    public func model(_ identifier: String) -> AssetModel? {
        try? AssetModelReader(assets: self).read(identifier)
    }

    /// Resolves a static inventory illustration using display-context GUI cases, other select/range
    /// fallbacks, false condition branches, and the lowest-threshold range entry without a fallback.
    /// This explicitly chooses a default variant, not live property evaluation or a saved override.
    /// Selected unsupported/malformed resources return nil. Resolution shares a 16 MiB JSON
    /// and 4096-element budget across at most 64 selected nodes and 32 model parts.
    /// Closed single chests and shulker boxes use verified 26.3 geometry as ordinary elements;
    /// unverified versions and special transforms remain unsupported. Texture IDs follow the jar.
    public func defaultItemModel(_ identifier: String) -> AssetItem? {
        try? AssetItemReader(assets: self).read(identifier)
    }

    /// Original PNG bytes, CRC-checked and bounded to 16 MiB. Decoding and animation are client work.
    public func texture(_ identifier: String) -> Data? {
        resource(identifier, directory: "textures", extension: "png")
    }

    func resource(_ identifier: String, directory: String, extension suffix: String) -> Data? {
        guard let id = Self.resourceID(identifier) else { return nil }
        return resources.read("assets/\(id.namespace)/\(directory)/\(id.path).\(suffix)")
    }

    static func resourceID(_ value: String) -> Identifier? {
        guard let id = Identifier(value), id.namespace != ".",
              !id.path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return id
    }
}
