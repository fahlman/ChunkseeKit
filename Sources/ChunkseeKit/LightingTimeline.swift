import Foundation

/// Immutable lighting projection of a 26.3 timeline. Other attributes and time markers are
/// outside this reader; it does not validate a complete game registry or resolve timeline tags.
public struct LightingTimeline: Sendable, Equatable {
    /// This timeline's clock, which need not be the dimension's default clock.
    public let clockID: String
    public let periodTicks: Int?

    private let sun: TimelineTrack<Float>?
    private let moon: TimelineTrack<Float>?
    private let factor: TimelineTrack<Float>?
    private let color: TimelineTrack<SIMD3<Float>>?
    private let phase: TimelineTrack<SkyLighting.MoonPhase>?

    /// Applies this timeline at whole ticks from clockID, preserving absent attributes from base.
    /// Periodic tracks wrap negative times; nonperiodic tracks hold their first/last values.
    /// Returns nil on nonfinite arithmetic or an unsolvable easing curve, never partial lighting.
    /// No time simulation, final attribute clamping, weather or spatial layers are applied.
    public func applying(at ticks: Int64, to base: SkyLighting) -> SkyLighting? {
        do {
            let time: Int64
            if let periodTicks {
                let remainder = ticks % Int64(periodTicks)
                time = remainder < 0 ? remainder + Int64(periodTicks) : remainder
            } else {
                time = ticks
            }
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
        guard json.count <= ZipResources.maximumResourceSize else { return nil }
        do {
            let root = try AssetJSON.object(JSONSerialization.jsonObject(with: json))
            guard let clock = root["clock"] as? String, let id = Identifier(clock) else { return nil }
            clockID = id.description
            if let raw = root["period_ticks"], !(raw is NSNull) {
                let period = try AssetJSON.integer(raw)
                guard period > 0 else { return nil }
                periodTicks = period
            } else {
                periodTicks = nil
            }
            let rawTracks: [String: Any]
            if let raw = root["tracks"], !(raw is NSNull) {
                rawTracks = try AssetJSON.object(raw)
            } else {
                rawTracks = [:]
            }
            guard rawTracks.count <= 256 else { return nil }
            var tracks: [String: Any] = [:]
            for (rawID, value) in rawTracks {
                guard let id = Identifier(rawID) else { continue }
                let name = id.description
                guard Self.attributes.contains(name) else { continue }
                // Aliases must not make a dictionary's iteration order choose a different track.
                guard tracks.updateValue(value, forKey: name) == nil else { return nil }
            }
            var remainingFrames = 4096
            sun = try Self.read(tracks[Self.attributes[0]], period: periodTicks, budget: &remainingFrames)
            moon = try Self.read(tracks[Self.attributes[1]], period: periodTicks, budget: &remainingFrames)
            factor = try Self.read(tracks[Self.attributes[2]], period: periodTicks, budget: &remainingFrames,
                                   overrideRange: 0...1)
            color = try Self.read(tracks[Self.attributes[3]], period: periodTicks, budget: &remainingFrames)
            phase = try Self.read(tracks[Self.attributes[4]], period: periodTicks, budget: &remainingFrames)
        } catch {
            return nil
        }
    }

    private static let attributes = ["minecraft:visual/sun_angle", "minecraft:visual/moon_angle",
                                     "minecraft:visual/sky_light_factor", "minecraft:visual/sky_light_color",
                                     "minecraft:visual/moon_phase"]

    private static func read<Value: TimelineValue>(_ raw: Any?, period: Int?, budget: inout Int,
                                    overrideRange: ClosedRange<Float>? = nil) throws -> TimelineTrack<Value>? {
        guard let raw else { return nil }
        return try TimelineTrack(json: AssetJSON.object(raw), period: period,
                                 budget: &budget, overrideRange: overrideRange)
    }
}

extension GameAssets {
    /// Reads a supplied jar's lighting timeline, verified only for 26.3/5023. Missing, malformed
    /// or unsupported relevant tracks return nil. Supports linear, constant and cubic-Bezier
    /// easing; scalar override/add/subtract/multiply/minimum/maximum, RGB override/add/subtract/
    /// multiply, and moon-phase override. Other relevant operations are explicitly unavailable.
    /// Limits: 16 MiB JSON, 256 track entries, 4,096 relevant keyframes and Int32 segment endpoints
    /// and lengths. Other tracks/markers are not interpreted. No cache or image decoding is added.
    public func lightingTimeline(_ identifier: String) -> LightingTimeline? {
        guard Int(version.dataVersion) == SaveVersion.java26_3, let id = Self.resourceID(identifier),
              let data = resources.read("data/\(id.namespace)/timeline/\(id.path).json") else { return nil }
        return LightingTimeline(json: data)
    }
}
