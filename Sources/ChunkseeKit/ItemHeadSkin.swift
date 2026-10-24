/// The saved skin information needed by a player-head item picture. Resource skins are
/// local assets; unresolved profiles may require an account lookup or skin download.
public enum ItemHeadSkin: Sendable, Hashable {
    case defaultSkin
    case resource(Identifier)
    case unresolved
}

extension ItemStack {
    /// Missing/removed profiles use the game's unprofiled head. Current profile.texture
    /// supplies a local body resource; other current and legacy profiles stay unresolved.
    /// This reads only head-picture facts, not the complete account/profile codec.
    public var headSkin: ItemHeadSkin? {
        guard components == nil || components?.compound != nil else { return nil }
        if components?["!minecraft:profile"] != nil { return .defaultSkin }
        if let profile = components?["minecraft:profile"] {
            if profile.string != nil { return .unresolved }
            guard let fields = profile.compound else { return nil }
            guard let raw = fields["texture"] else { return .unresolved }
            guard let text = raw.string, text.utf8.count <= 16 * 1024 * 1024,
                  let texture = Identifier(text) else { return nil }
            return .resource(texture)
        }
        if let owner = components?["SkullOwner"] {
            guard owner.string != nil || owner.compound != nil else { return nil }
            return .unresolved
        }
        return .defaultSkin
    }
}
