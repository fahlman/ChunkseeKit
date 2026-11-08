/// Format adapters for the shared lighting codecs. Native tags keep their numeric kind and
/// integer bits until the selected FLOAT or packed-color INT codec consumes them.
enum LightingInput {
    case json(Any?)
    case nbt(NBT)

    var string: String? {
        switch self {
        case .json(let value): value as? String
        case .nbt(let value): value.string
        }
    }

    func number() throws -> Float {
        switch self {
        case .json(let value): return try AssetJSON.number(value)
        case .nbt(let value):
            guard let number = value.javaFloat else { throw InvalidLighting.data }
            // Attribute ranges and final finite-lighting requirements have separate owners.
            return number
        }
    }

    func colorVector() throws -> SIMD3<Float> {
        let value: NBT
        switch self {
        case .json(let json): return try AssetJSON.colorVector(json)
        case .nbt(let nbt): value = nbt
        }
        if let text = value.string { return RGBColor.vector(try AssetJSON.stringColor(text)) }
        if let number = value.javaInt { return RGBColor.vector(RGBColor.integer(number)) }
        let channels: [Float]
        switch value {
        case .list(_, let values):
            guard values.count == 3 else { throw InvalidLighting.data }
            channels = try values.map {
                guard let number = $0.unwrappedListElement.javaFloat else { throw InvalidLighting.data }
                return number
            }
        case .byteArray(let values):
            guard values.count == 3 else { throw InvalidLighting.data }
            channels = values.map { NBT.byte($0).javaFloat! }
        case .intArray(let values):
            guard values.count == 3 else { throw InvalidLighting.data }
            channels = values.map { NBT.int($0).javaFloat! }
        case .longArray(let values):
            guard values.count == 3 else { throw InvalidLighting.data }
            channels = values.map { NBT.long($0).javaFloat! }
        default: throw InvalidLighting.data
        }
        return SIMD3(channels[0], channels[1], channels[2])
    }
}
