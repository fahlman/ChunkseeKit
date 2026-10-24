import Foundation

/// Gameplay sky light and a declared midnight are independent of the visual projection.
struct MonsterLightTimeline: WorldTimelineProjection {
    struct Midnight: Equatable {
        let clock: String
        let ticks: Int
        let period: Int?
    }
    private enum Marker: String { case midnight = "minecraft:midnight" }
    let clockID: String
    let periodTicks: Int?
    let midnight: Midnight?
    private let sky: TimelineTrack<Float>?
    var hasLightTrack: Bool { sky != nil }

    init?(json: Data) {
        do {
            let input = try TimelineInput(json: json)
            clockID = input.clockID
            periodTicks = input.periodTicks
            let tracks = try EnvironmentAttributeMap<MonsterLightAttribute>.selected(input.tracks)
            var budget = 4096
            if let raw = tracks[.skyLevel] {
                sky = try TimelineTrack(json: AssetJSON.object(raw), period: periodTicks,
                                        budget: &budget, overrideRange: 0...15)
            } else { sky = nil }
            if let raw = input.markers, !(raw is NSNull) {
                let markers = try EnvironmentAttributeMap<Marker>.selected(AssetJSON.object(raw))
                if let marker = markers[.midnight] {
                    let ticks: Int
                    if let fields = marker as? [String: Any] {
                        ticks = try AssetJSON.integer(fields["ticks"])
                        if let show = fields["show_in_commands"], !(show is NSNull) { _ = try AssetJSON.boolean(show) }
                    } else { ticks = try AssetJSON.integer(marker) }
                    guard ticks >= 0, periodTicks.map({ ticks < $0 }) ?? true else { return nil }
                    midnight = Midnight(clock: clockID, ticks: ticks, period: periodTicks)
                } else { midnight = nil }
            } else { midnight = nil }
        } catch { return nil }
    }

    static func nightLevel(_ timelines: [Self], base: Float) -> Float? {
        guard timelines.contains(where: \.hasLightTrack) else { return base }
        let markers = timelines.compactMap(\.midnight)
        guard let midnight = markers.first, markers.allSatisfy({ $0 == midnight }) else { return nil }
        var value = base
        for timeline in timelines where timeline.hasLightTrack {
            // This snapshot is the first declared midnight on one clock. Other relevant
            // clocks have no implied matching time and must not quietly become tick zero.
            guard timeline.clockID == midnight.clock, timeline.periodTicks == midnight.period,
                  let next = try? timeline.sky?.applying(
                    at: TimelineInput.sampleTime(Int64(midnight.ticks), period: timeline.periodTicks), to: value) else { return nil }
            value = next
        }
        return value
    }
}
