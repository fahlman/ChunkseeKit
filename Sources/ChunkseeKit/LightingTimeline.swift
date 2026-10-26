import Foundation

/// Immutable lighting projection of a timeline. Other attributes and time markers are
/// outside this reader; it does not validate a complete game registry or resolve timeline tags.
public struct LightingTimeline: Sendable, Equatable, WorldTimelineProjection {
    /// This timeline's clock, which need not be the dimension's default clock.
    public let clockID: String
    public let periodTicks: Int?

    private let sun: TimelineTrack<Float>?
    private let moon: TimelineTrack<Float>?
    private let factor: TimelineTrack<Float>?
    private let color: TimelineTrack<SIMD3<Float>>?
    private let phase: TimelineTrack<SkyLighting.MoonPhase>?

    // Unrelated tracks must not require their clock when composing this lighting projection.
    var hasLightingTracks: Bool { sun != nil || moon != nil || factor != nil || color != nil || phase != nil }

    /// Applies this timeline at whole ticks from clockID, preserving absent attributes from base.
    /// Periodic tracks wrap negative times; nonperiodic tracks hold their first/last values.
    /// Returns nil on nonfinite arithmetic or an unsolvable easing curve, never partial lighting.
    /// No time simulation, final attribute clamping, weather or spatial layers are applied.
    public func applying(at ticks: Int64, to base: SkyLighting) -> SkyLighting? {
        do {
            let time = TimelineInput.sampleTime(ticks, period: periodTicks)
            return try SkyLighting(
                sunAngle: sun?.applying(at: time, to: base.sunAngle) ?? base.sunAngle,
                moonAngle: moon?.applying(at: time, to: base.moonAngle) ?? base.moonAngle,
                skyLightFactor: factor?.applying(at: time, to: base.skyLightFactor) ?? base.skyLightFactor,
                skyLightColor: color?.applying(at: time, to: base.skyLightColor) ?? base.skyLightColor,
                moonPhase: phase?.applying(at: time, to: base.moonPhase) ?? base.moonPhase)
        } catch {
            return nil
        }
    }

    init?(json: Data) {
        do {
            let input = try TimelineInput(json: json)
            clockID = input.clockID
            periodTicks = input.periodTicks
            let tracks = try EnvironmentAttributeMap<SkyLighting.Attribute>.selected(input.tracks)
            var remainingFrames = 4096
            sun = try Self.read(tracks[.sunAngle], period: periodTicks, budget: &remainingFrames)
            moon = try Self.read(tracks[.moonAngle], period: periodTicks, budget: &remainingFrames)
            factor = try Self.read(tracks[.skyLightFactor], period: periodTicks, budget: &remainingFrames,
                                   overrideRange: 0...1)
            color = try Self.read(tracks[.skyLightColor], period: periodTicks, budget: &remainingFrames)
            phase = try Self.read(tracks[.moonPhase], period: periodTicks, budget: &remainingFrames)
        } catch {
            return nil
        }
    }

    private static func read<Value: LightingValue>(_ raw: Any?, period: Int?, budget: inout Int,
                                    overrideRange: ClosedRange<Float>? = nil) throws -> TimelineTrack<Value>? {
        guard let raw else { return nil }
        return try TimelineTrack(json: AssetJSON.object(raw), period: period,
                                 budget: &budget, overrideRange: overrideRange)
    }
}

extension GameAssets {
    /// Reads a supplied jar's lighting timeline independently of version labels. Missing, malformed
    /// or unsupported relevant tracks return nil. Supports linear, constant and cubic-Bezier
    /// easing; scalar override/add/subtract/multiply/minimum/maximum, RGB override/add/subtract/
    /// multiply, and moon-phase override. Other relevant operations are explicitly unavailable.
    /// Limits: 16 MiB JSON, 256 track entries, 4,096 relevant keyframes and Int32 segment endpoints
    /// and lengths. Other tracks/markers are not interpreted. No cache or image decoding is added.
    public func lightingTimeline(_ identifier: String) -> LightingTimeline? {
        guard let id = Self.resourceID(identifier),
              let data = resources.read("data/\(id.namespace)/timeline/\(id.path).json") else { return nil }
        return LightingTimeline(json: data)
    }
}
