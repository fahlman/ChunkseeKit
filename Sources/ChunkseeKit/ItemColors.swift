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

}

enum ItemColor {
    static func integer(_ value: NBT?) -> UInt32? {
        value?.javaInt.map(RGBColor.integer)
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
        return RGBColor.channels(values.map(Float.init))
    }
}
