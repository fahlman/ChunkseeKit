import Foundation

/// Five visual attributes, independently projected from the shared environment-attribute codec.
struct DimensionBaseLighting {
    let value: SkyLighting

    private init(_ entries: EnvironmentAttributeMap<SkyLighting.Attribute>) throws {
        guard let value = try SkyLighting(
            sunAngle: entries.applying(.sunAngle, to: Float(0)),
            moonAngle: entries.applying(.moonAngle, to: Float(0)),
            skyLightFactor: entries.applying(.skyLightFactor, to: Float(1), overrideRange: 0...1),
            skyLightColor: entries.applying(.skyLightColor, to: SIMD3<Float>(repeating: 1)),
            moonPhase: entries.applying(.moonPhase, to: SkyLighting.MoonPhase.fullMoon)) else {
            throw InvalidLighting.data
        }
        self.value = value
    }

    init(nbt: NBT) throws { try self.init(EnvironmentAttributeMap(nbt: nbt)) }
    init(json: [String: Any]) throws { try self.init(EnvironmentAttributeMap(json: json)) }
}
