import Foundation

/// One codec and segment walker for numeric, color and discrete attributes.
struct TimelineTrack<Value: LightingValue>: Sendable, Equatable {
    private struct Frame: Sendable, Equatable {
        let ticks: Int
        let value: Value
    }
    private struct Segment: Sendable, Equatable {
        let from: Frame
        let to: Frame
    }
    private let segments: [Segment]
    private let easing: TimelineEasing
    private let modifier: LightingModifier

    init(json: [String: Any], period: Int?, budget: inout Int, overrideRange: ClosedRange<Float>?) throws {
        let modifier: LightingModifier
        let rawModifier = json["modifier"]
        if rawModifier == nil || rawModifier is NSNull {
            modifier = .override
        } else {
            guard let text = rawModifier as? String, let value = LightingModifier(rawValue: text) else {
                throw InvalidLighting.data
            }
            modifier = value
        }
        guard Value.modifiers.contains(modifier) else { throw InvalidLighting.data }
        self.modifier = modifier
        easing = try TimelineEasing(json: json["ease"])
        let values = try AssetJSON.array(json["keyframes"])
        guard !values.isEmpty, values.count <= budget else { throw InvalidLighting.data }
        budget -= values.count
        let frames = try values.map { raw -> Frame in
            let frame = try AssetJSON.object(raw)
            let ticks = try AssetJSON.integer(frame["ticks"])
            guard ticks >= 0, period.map({ ticks <= $0 }) ?? true else { throw InvalidLighting.data }
            let value = try Value.argument(.json(frame["value"]), modifier: modifier, overrideRange: overrideRange)
            return Frame(ticks: ticks, value: value)
        }
        let first = frames[0], last = frames[frames.count - 1]
        var previous = last.ticks, repeats = 0
        for (index, frame) in frames.enumerated() {
            if index > 0, frame.ticks < previous { throw InvalidLighting.data }
            // Match KeyframeTrack's cyclic duplicate validation without sorting or deduplicating.
            repeats = frame.ticks == previous ? repeats + 1 : 0
            guard repeats <= 2 else { throw InvalidLighting.data }
            previous = frame.ticks
        }
        if frames.count == 1 {
            let constant = Frame(ticks: 0, value: first.value)
            segments = [Segment(from: constant, to: constant)]
        } else {
            var result: [Segment] = []
            if let period { result.append(Segment(from: Frame(ticks: last.ticks - period, value: last.value), to: first)) }
            for (from, to) in zip(frames, frames.dropFirst()) { result.append(Segment(from: from, to: to)) }
            if let period { result.append(Segment(from: last, to: Frame(ticks: first.ticks + period, value: first.value))) }
            guard result.allSatisfy({ Int32(exactly: $0.from.ticks) != nil && Int32(exactly: $0.to.ticks) != nil &&
                Int32(exactly: $0.to.ticks - $0.from.ticks) != nil }) else { throw InvalidLighting.data }
            segments = result
        }
    }

    func applying(at ticks: Int64, to base: Value) throws -> Value {
        // The strict end comparison selects the post-jump segment at equal-tick keyframes.
        let segment = segments.first { ticks < Int64($0.to.ticks) } ?? segments[segments.count - 1]
        let value: Value
        if ticks <= Int64(segment.from.ticks) {
            value = segment.from.value
        } else if ticks >= Int64(segment.to.ticks) {
            value = segment.to.value
        } else {
            let progress = Float(ticks - Int64(segment.from.ticks)) / Float(segment.to.ticks - segment.from.ticks)
            value = Value.interpolate(segment.from.value, segment.to.value, try easing.apply(progress))
        }
        guard value.isFinite else { throw InvalidLighting.data }
        let result = try Value.apply(modifier, to: base, argument: value)
        guard result.isFinite else { throw InvalidLighting.data }
        return result
    }
}
