/// Five environment values affected by the game's daylight and moon timelines.
/// These are intermediate attributes, not a rendered light level or a spawnability result.
public struct SkyLighting: Sendable, Equatable {
    public let sunAngle: Float
    public let moonAngle: Float
    public let skyLightFactor: Float
    public let skyLightColor: SIMD3<Float>
    public let moonPhase: MoonPhase

    public enum MoonPhase: String, Sendable, CaseIterable {
        case fullMoon = "full_moon"
        case waningGibbous = "waning_gibbous"
        case thirdQuarter = "third_quarter"
        case waningCrescent = "waning_crescent"
        case newMoon = "new_moon"
        case waxingCrescent = "waxing_crescent"
        case firstQuarter = "first_quarter"
        case waxingGibbous = "waxing_gibbous"
    }

    /// Angles use degrees; RGB channels retain floating precision. No defaults, angle wrapping
    /// or final attribute-range clamping are imposed here, so successive timeline modifiers can
    /// compose. Nonfinite values are unavailable. DimensionType.baseSkyLighting supplies
    /// the static dimension layer.
    public init?(sunAngle: Float, moonAngle: Float, skyLightFactor: Float,
                 skyLightColor: SIMD3<Float>, moonPhase: MoonPhase) {
        guard sunAngle.isFinite, moonAngle.isFinite, skyLightFactor.isFinite,
              skyLightColor.x.isFinite, skyLightColor.y.isFinite, skyLightColor.z.isFinite else { return nil }
        self.sunAngle = sunAngle
        self.moonAngle = moonAngle
        self.skyLightFactor = skyLightFactor
        self.skyLightColor = skyLightColor
        self.moonPhase = moonPhase
    }
}

// Static dimension entries and timeline tracks use the same normalized identity and bounds.
extension SkyLighting {
    enum Attribute: String {
        case sunAngle = "minecraft:visual/sun_angle", moonAngle = "minecraft:visual/moon_angle"
        case skyLightFactor = "minecraft:visual/sky_light_factor", skyLightColor = "minecraft:visual/sky_light_color"
        case moonPhase = "minecraft:visual/moon_phase"
    }
}
