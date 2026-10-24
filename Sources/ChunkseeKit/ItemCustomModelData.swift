/// Saved choices for an item's static model, using the 26.3 custom-model-data component.
/// Colors are 0xRRGGBB. An absent or removed component has empty lists; malformed data is nil.
public struct ItemCustomModelData: Sendable, Hashable {
    public let floats: [Float]
    public let flags: [Bool]
    public let strings: [String]
    public let colors: [UInt32]

    static let empty = Self(floats: [], flags: [], strings: [], colors: [])

    // Java Float and String identity matters here: signed zero can select a different range
    // entry, NaN must be a stable cache key, and string cases do not normalize Unicode.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.floats.elementsEqual(rhs.floats, by: { bits($0) == bits($1) }) &&
        lhs.flags == rhs.flags && lhs.colors == rhs.colors &&
        lhs.strings.elementsEqual(rhs.strings, by: { $0.utf8.elementsEqual($1.utf8) })
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(floats.count)
        for value in floats { hasher.combine(Self.bits(value)) }
        hasher.combine(flags)
        hasher.combine(colors)
        hasher.combine(strings.count)
        for value in strings {
            hasher.combine(value.utf8.count)
            for byte in value.utf8 { hasher.combine(byte) }
        }
    }

    private static func bits(_ value: Float) -> UInt32 {
        value.isNaN ? 0x7fc0_0000 : value.bitPattern
    }
}

extension ItemStack {
    /// Reads current lists and older numeric custom-model data, including legacy tag.CustomModelData.
    /// Current values and explicit removal suppress the legacy tag. Empty data is a known default;
    /// malformed or over-budget data remains unavailable instead of choosing a guessed model.
    public var customModelData: ItemCustomModelData? {
        guard components == nil || components?.compound != nil else { return nil }
        guard components?["!minecraft:custom_model_data"] == nil,
              let value = components?["minecraft:custom_model_data"] ?? components?["CustomModelData"] else {
            return .empty
        }
        if let number = value.javaFloat {
            return .init(floats: [number], flags: [], strings: [], colors: [])
        }
        guard let fields = value.compound else { return nil }
        var remaining = 4096
        guard let floats = customList(fields["floats"], remaining: &remaining, convert: { $0.javaFloat }),
              let flags = customList(fields["flags"], remaining: &remaining, convert: { $0.double.map { $0 != 0 } }),
              let strings = customList(fields["strings"], remaining: &remaining, convert: { $0.string }),
              let colors = customList(fields["colors"], remaining: &remaining, convert: ItemColor.dye) else { return nil }
        var remainingBytes = 16 * 1024 * 1024
        for string in strings {
            guard string.utf8.count <= remainingBytes else { return nil }
            remainingBytes -= string.utf8.count
        }
        return .init(floats: floats, flags: flags, strings: strings, colors: colors)
    }
}

/// NbtOps exposes all four collection tags as lists. Bound their size before materializing values.
private func customList<Value>(_ value: NBT?, remaining: inout Int,
                               convert: (NBT) -> Value?) -> [Value]? {
    guard let value else { return [] }
    let values: [NBT]
    switch value {
    case .list(_, let list):
        guard list.count <= remaining else { return nil }
        values = list.map(\.unwrappedListElement)
    case .byteArray(let list):
        guard list.count <= remaining else { return nil }
        values = list.map(NBT.byte)
    case .intArray(let list):
        guard list.count <= remaining else { return nil }
        values = list.map(NBT.int)
    case .longArray(let list):
        guard list.count <= remaining else { return nil }
        values = list.map(NBT.long)
    default: return nil
    }
    remaining -= values.count
    var result = [Value]()
    result.reserveCapacity(values.count)
    for value in values {
        guard let decoded = convert(value) else { return nil }
        result.append(decoded)
    }
    return result
}
