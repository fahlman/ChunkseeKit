extension ItemStack {
    /// An explicit saved dye override as 0xRRGGBB. Nil leaves the model's default dye in use.
    /// Reads current components, their older `rgb` wrapper, and legacy display.color tags.
    public var dyedColor: UInt32? {
        guard components?["!minecraft:dyed_color"] == nil else { return nil }
        if let value = components?["minecraft:dyed_color"] {
            if value.compound != nil { return ItemColor.integer(value["rgb"]) }
            return ItemColor.dye(value)
        }
        return ItemColor.integer(components?["display"]?["color"])
    }

    /// An explicit saved potion override as 0xRRGGBB, not a color inferred from potion effects.
    /// Absent overrides leave the normal effect/definition color to a separate resolver.
    public var customPotionColor: UInt32? {
        guard components?["!minecraft:potion_contents"] == nil else { return nil }
        if let value = components?["minecraft:potion_contents"] {
            return ItemColor.integer(value["custom_color"])
        }
        return ItemColor.integer(components?["CustomPotionColor"])
    }
}

private enum ItemColor {
    static func integer(_ value: NBT?) -> UInt32? {
        value?.javaInt.map { UInt32(bitPattern: $0) & 0x00ff_ffff }
    }

    /// ExtraCodecs.RGB_COLOR_CODEC accepts an integer or three floating-point channels.
    /// Unbounded/nonfinite channel lists stay unavailable rather than become a guessed color.
    static func dye(_ value: NBT) -> UInt32? {
        if let integer = integer(value) { return integer }
        let values: [Double]
        switch value {
        case .list(_, let list):
            guard list.count == 3 else { return nil }
            values = list.compactMap(\.double)
        case .intArray(let list):
            guard list.count == 3 else { return nil }
            values = list.map(Double.init)
        case .longArray(let list):
            guard list.count == 3 else { return nil }
            values = list.map(Double.init)
        case .byteArray(let list):
            guard list.count == 3 else { return nil }
            values = list.map(Double.init)
        default: return nil
        }
        let channels = values.map(Float.init)
        guard channels.count == 3, channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        // ARGB.as8BitChannel uses floor(channel * 255) at Float precision.
        let rgb = channels.map { UInt32(($0 * 255).rounded(.down)) }
        return rgb[0] << 16 | rgb[1] << 8 | rgb[2]
    }
}
