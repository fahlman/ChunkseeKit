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
    /// Supported static special renderers use geometry generated from Minecraft's baked models,
    /// independently of version labels. Supported ancestor transforms compose before the base
    /// GUI transform; unrepresentable transforms remain unavailable. Textures come from the jar.
    public func defaultItemModel(_ identifier: String) -> AssetItem? {
        try? AssetItemReader(assets: self, selection: nil).read(identifier)
    }

    /// Resolves an inventory illustration with the stack's saved model reference, trim material
    /// custom-model data and saved shield designs. Trim selection, custom conditions, strings,
    /// numeric ranges and colors follow readable formats independently of version metadata.
    /// Obtain the key from ItemStack.itemModelSelection.
    /// Shield patterns resolve named definitions in this jar or saved inline asset holders. The
    /// material's ordered overlays carry the base dye and first sixteen pattern layers; clients
    /// composite them before projecting the existing geometry. Trim-pattern identity stays unused.
    /// Resource-pack layering and world-specific registry overrides are not resolved here.
    /// Saved block-state properties, component presence/removal, the next-damage break threshold
    /// and charged projectile contents also choose branches. Missing prototype facts or relevant
    /// unreadable saved values remain unavailable. Live properties retain the static choices.
    /// Unsupported selected models return nil; they never silently recover the untrimmed picture.
    public func itemModel(for selection: ItemModelSelection) -> AssetItem? {
        try? AssetItemReader(assets: self, selection: selection).read(selection.modelID.description)
    }

    /// Matches supplied block properties and resolves the selected variant or multipart models.
    /// Weighted alternatives and block rotations are retained, not randomly chosen or baked.
    /// Omitted properties use code defaults mechanically extracted by the release tool, without
    /// gating the lookup on the asset version. Explicit saved properties always take precedence.
    /// Otherwise, missing properties that prevent a unique decision return nil. Explicit values
    /// are preserved; property domains are not validated against a game registry.
    /// Missing/unsupported/malformed selected resources and overlapping variants also return nil.
    /// Reads share a 16 MiB JSON / 4096-element budget across at most 256 selected models, with
    /// at most 4096 selectors/condition terms and 64 nested conditions. Images and caching stay
    /// client-owned. Multipart per-term negation follows the resource format without a version gate.
    public func blockModel(for state: BlockState) -> AssetBlock? {
        try? AssetBlockReader(assets: self).read(state)
    }

    /// Original PNG bytes, CRC-checked and bounded to 16 MiB. Decoding and animation are client work.
    public func texture(_ identifier: String) -> Data? {
        resource(identifier, directory: "textures", extension: "png")
    }

    /// Resolves a generated palette sprite in one atlas, without reading its PNG payloads.
    /// Paletted, directory and single sources preserve their order; a later existing plain
    /// sprite hides a previous palette sprite. Missing base images add nothing. Missing palette
    /// images or invalid PNGs remain unavailable when the client reads/decodes the returned IDs.
    /// Palette-directory resources take precedence over older direct texture paths when present.
    /// Other source kinds and malformed resources return nil; version labels do not gate lookup.
    /// Work is bounded to 16 MiB JSON, 256 sources and 4,096 generated sprite entries.
    /// Resource-pack layering, animation, image decoding and caching are not performed here.
    public func palettedTexture(_ identifier: String, in atlas: String) -> AssetPalettedTexture? {
        try? AssetPalettedTextureReader(assets: self).read(identifier, atlas: atlas)
    }

    enum ResourceDomain: String { case assets, data }

    func resource(_ identifier: String, directory: String, extension suffix: String,
                  domain: ResourceDomain = .assets) -> Data? {
        guard let path = Self.resourcePath(identifier, directory: directory, extension: suffix, domain: domain) else { return nil }
        return resources.read(path)
    }

    func containsResource(_ identifier: String, directory: String, extension suffix: String) -> Bool {
        guard let path = Self.resourcePath(identifier, directory: directory, extension: suffix) else { return false }
        return resources.contains(path)
    }

    private static func resourcePath(_ identifier: String, directory: String, extension suffix: String,
                                     domain: ResourceDomain = .assets) -> String? {
        guard let id = resourceID(identifier) else { return nil }
        return "\(domain.rawValue)/\(id.namespace)/\(directory)/\(id.path).\(suffix)"
    }

    static func resourceID(_ value: String) -> Identifier? {
        guard let id = Identifier(value), id.namespace != ".",
              !id.path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return id
    }
}
