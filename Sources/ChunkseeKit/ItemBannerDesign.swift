/// Saved banner-pattern inputs used by shields and banner items. These facts do not resolve a
/// registry, choose texture paths, truncate the pattern stack for drawing, or supply a base dye.
public struct ItemBannerDesign: Sendable, Hashable {
    public let baseColor: DyeColor?
    public let layers: [Layer]

    public struct Layer: Sendable, Hashable {
        public let pattern: Pattern
        public let color: DyeColor
    }

    /// A named holder needs the world's pattern registry. Inline holders carry their own asset.
    public enum Pattern: Sendable, Hashable {
        case reference(Identifier)
        case inline(assetID: Identifier, translationKey: String)
    }
}

extension ItemStack {
    /// Reads current base_color/banner_patterns components and legacy BlockEntityTag fields.
    /// Missing/removed values are a known empty design, not an invented white base. A malformed
    /// present field returns nil. Each current value/removal suppresses only its legacy counterpart.
    /// Named and inline pattern holders follow the verified 26.3 codecs; registry resolution and
    /// sprite compositing remain separate. Work is bounded to 4,096 layers and 16 MiB of strings.
    public var bannerDesign: ItemBannerDesign? {
        guard components == nil || components?.compound != nil else { return nil }
        let baseKey = "minecraft:base_color", layersKey = "minecraft:banner_patterns"
        let currentBase = components?[baseKey], currentLayers = components?[layersKey]
        let removedBase = components?["!" + baseKey] != nil, removedLayers = components?["!" + layersKey] != nil
        let legacy: [String: NBT]
        if (!removedBase && currentBase == nil) || (!removedLayers && currentLayers == nil),
           let tag = components?["BlockEntityTag"] {
            guard let fields = tag.compound else { return nil }
            legacy = fields
        } else { legacy = [:] }

        let base: DyeColor?
        if removedBase { base = nil }
        else if let currentBase {
            guard let name = currentBase.string, let color = DyeColor(rawValue: name) else { return nil }
            base = color
        } else if let value = legacy["Base"] {
            guard let id = value.javaInt, let color = DyeColor(legacyID: Int(id)) else { return nil }
            base = color
        } else { base = nil }

        let layers: [ItemBannerDesign.Layer]
        if removedLayers { layers = [] }
        else if let currentLayers {
            guard let parsed = BannerDesignReader.layers(currentLayers, legacy: false) else { return nil }
            layers = parsed
        } else if let value = legacy["patterns"] {
            guard legacy["Patterns"] == nil,
                  let parsed = BannerDesignReader.layers(value, legacy: false) else { return nil }
            layers = parsed
        } else if let value = legacy["Patterns"] {
            guard let parsed = BannerDesignReader.layers(value, legacy: true) else { return nil }
            layers = parsed
        } else { layers = [] }
        return .init(baseColor: base, layers: layers)
    }
}

private enum BannerDesignReader {
    static func layers(_ raw: NBT, legacy: Bool) -> [ItemBannerDesign.Layer]? {
        let values: [NBT]
        switch raw {
        case .list(_, let list): values = list
        // NbtOps also exposes empty numeric arrays as empty lists. Nonempty arrays cannot be layers.
        case .byteArray(let list) where list.isEmpty: values = []
        case .intArray(let list) where list.isEmpty: values = []
        case .longArray(let list) where list.isEmpty: values = []
        default: return nil
        }
        guard values.count <= 4096 else { return nil }
        var remainingBytes = 16 * 1024 * 1024
        func string(_ tag: NBT?) -> String? {
            guard let value = tag?.string, value.utf8.count <= remainingBytes else { return nil }
            remainingBytes -= value.utf8.count
            return value
        }
        var result: [ItemBannerDesign.Layer] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard let fields = value.unwrappedListElement.compound else { return nil }
            let color: DyeColor
            let pattern: ItemBannerDesign.Pattern
            if legacy {
                // BannerPatternFormatFix uses white for a missing legacy Color. Unreadable or
                // out-of-range values stay unavailable here rather than being silently repaired.
                guard let id = fields["Color"]?.javaInt ?? (fields["Color"] == nil ? 0 : nil),
                      let dye = DyeColor(legacyID: Int(id)), let name = string(fields["Pattern"]),
                      let identifier = Identifier(legacyPatterns[name] ?? name) else { return nil }
                color = dye
                pattern = .reference(identifier)
            } else {
                guard let name = string(fields["color"]), let dye = DyeColor(rawValue: name),
                      let value = fields["pattern"] else { return nil }
                color = dye
                if value.string != nil {
                    guard let name = string(value), let id = Identifier(name) else { return nil }
                    pattern = .reference(id)
                } else {
                    guard let object = value.compound, let name = string(object["asset_id"]),
                          let asset = Identifier(name), let key = string(object["translation_key"]) else { return nil }
                    pattern = .inline(assetID: asset, translationKey: key)
                }
            }
            result.append(.init(pattern: pattern, color: color))
        }
        return result
    }

    /// The old short IDs migrate through BannerPatternFormatFix, not an asset-name heuristic.
    private static let legacyPatterns = [
        "b": "minecraft:base", "bl": "minecraft:square_bottom_left", "br": "minecraft:square_bottom_right",
        "tl": "minecraft:square_top_left", "tr": "minecraft:square_top_right", "bs": "minecraft:stripe_bottom",
        "ts": "minecraft:stripe_top", "ls": "minecraft:stripe_left", "rs": "minecraft:stripe_right",
        "cs": "minecraft:stripe_center", "ms": "minecraft:stripe_middle", "drs": "minecraft:stripe_downright",
        "dls": "minecraft:stripe_downleft", "ss": "minecraft:small_stripes", "cr": "minecraft:cross",
        "sc": "minecraft:straight_cross", "bt": "minecraft:triangle_bottom", "tt": "minecraft:triangle_top",
        "bts": "minecraft:triangles_bottom", "tts": "minecraft:triangles_top", "ld": "minecraft:diagonal_left",
        "rd": "minecraft:diagonal_up_right", "lud": "minecraft:diagonal_up_left", "rud": "minecraft:diagonal_right",
        "mc": "minecraft:circle", "mr": "minecraft:rhombus", "vh": "minecraft:half_vertical",
        "hh": "minecraft:half_horizontal", "vhr": "minecraft:half_vertical_right", "hhb": "minecraft:half_horizontal_bottom",
        "bo": "minecraft:border", "cbo": "minecraft:curly_border", "gra": "minecraft:gradient", "gru": "minecraft:gradient_up",
        "bri": "minecraft:bricks", "glb": "minecraft:globe", "cre": "minecraft:creeper", "sku": "minecraft:skull",
        "flo": "minecraft:flower", "moj": "minecraft:mojang", "pig": "minecraft:piglin"
    ]
}
