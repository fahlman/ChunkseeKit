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

    /// Opens a local file and retains its read-only handle, not its complete contents. Opening
    /// and directory-read errors propagate; unsupported archives or unavailable version.json
    /// return nil. Later resource reads return nil after an in-place edit or truncation.
    /// Sandboxed callers keep any required security-scoped access while using these resources.
    public init?(contentsOf url: URL) throws {
        guard let resources = try ZipResources(contentsOf: url) else { return nil }
        self.init(resources: resources)
    }

    public init?(data: Data) {
        guard let resources = ZipResources(data: data) else { return nil }
        self.init(resources: resources)
    }

    private init?(resources: ZipResources) {
        guard let metadata = resources.read("version.json"),
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
    /// Closed single chests, shulker boxes and plain shields use verified 26.3 geometry as
    /// ordinary elements. Supported ancestor transforms compose before the base GUI transform;
    /// other transforms and unverified versions remain unsupported. Textures come from the jar.
    public func defaultItemModel(_ identifier: String) -> AssetItem? {
        try? AssetItemReader(assets: self, selection: nil).read(identifier)
    }

    /// Resolves an inventory illustration with the stack's saved item-model reference and trim
    /// material, obtained from ItemStack.itemModelSelection. Trim cases are verified for 26.3/5023;
    /// other versions with that selector stay unavailable. Pattern does not affect inventory icons.
    /// Unknown live properties retain defaultItemModel's static choices and resource/work limits.
    /// Unsupported selected models return nil; they never silently recover the untrimmed picture.
    public func itemModel(for selection: ItemModelSelection) -> AssetItem? {
        try? AssetItemReader(assets: self, selection: selection).read(selection.modelID.description)
    }

    /// Matches supplied block properties and resolves the selected variant or multipart models.
    /// Weighted alternatives and block rotations are retained, not randomly chosen or baked.
    /// Missing properties that prevent a unique decision return nil: the jar's artwork does not
    /// define omitted registry defaults. Property domains are not validated against a game registry.
    /// Missing/unsupported/malformed selected resources and overlapping variants also return nil.
    /// Reads share a 16 MiB JSON / 4096-element budget across at most 256 selected models, with
    /// at most 4096 selectors/condition terms and 64 nested conditions. Images and caching stay
    /// client-owned. Multipart per-term negation is verified only for 26.3 (data version 5023).
    public func blockModel(for state: BlockState) -> AssetBlock? {
        try? AssetBlockReader(assets: self).read(state)
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
