import Foundation

/// A timeline's named clock and optional repeating period, read from its resource definition.
/// Track contents and time markers are not interpreted by this projection.
public struct TimelineTiming: Sendable, Equatable, WorldTimelineProjection {
    public let clockID: String
    /// Nil for a nonperiodic timeline. A saved period is a positive Int32 number of ticks.
    public let periodTicks: Int?

    /// Zero-based cycle and tick remainder, using Minecraft's signed division toward zero.
    /// Negative times retain a negative remainder. The cycle keeps the saved integer's full range
    /// instead of narrowing it for a game command. Nonperiodic timelines have no cycle.
    public func position(at ticks: Int) -> (cycle: Int, tick: Int)? {
        guard let periodTicks else { return nil }
        let (cycle, remainder) = ticks.quotientAndRemainder(dividingBy: periodTicks)
        return (cycle, remainder)
    }

    init?(json: Data) {
        guard let input = try? TimelineInput(json: json) else { return nil }
        clockID = input.clockID
        periodTicks = input.periodTicks
    }
}

extension GameAssets {
    /// Reads timing from any supplied jar whose timeline format parses. Missing or malformed
    /// headers return nil; unfamiliar track types do not hide readable clock/period metadata.
    public func timelineTiming(_ identifier: String) -> TimelineTiming? {
        guard let id = Self.resourceID(identifier),
              let data = resources.read("data/\(id.namespace)/timeline/\(id.path).json") else { return nil }
        return TimelineTiming(json: data)
    }
}

extension World {
    /// Resolves one timeline's timing from the selected game and enabled folder/ZIP packs.
    /// Present malformed overrides and unknown higher packs block fallback; missing inputs
    /// remain unavailable. Query limits, cancellation and paths share the timeline reader.
    /// Read this clock through clockTimes(); the dimension's default clock is independent.
    public func timelineTiming(_ identifier: String, assets: GameAssets?) throws -> TimelineTiming? {
        guard allowsResourceQuery, let id = GameAssets.resourceID(identifier) else { return nil }
        var reader = try WorldTimelineReader<TimelineTiming>(world: self, assets: assets)
        return try reader.read(.list([id.description]))?.first
    }
}
