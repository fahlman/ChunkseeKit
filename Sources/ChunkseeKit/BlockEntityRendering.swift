extension BlockState {
    /// Whether Minecraft registers a block entity renderer for this block's code.
    /// Such a renderer may supply geometry missing from its resource model. This does not
    /// establish that a saved block entity exists, or that its picture covers a whole face.
    /// Unknown block code returns nil; generated facts apply across save and game versions.
    public var hasBlockEntityRenderer: Bool? {
        GeneratedBlockEntityRenderers.values[id]
            ?? Identifier(id).flatMap { GeneratedBlockEntityRenderers.values[$0.description] }
    }
}
