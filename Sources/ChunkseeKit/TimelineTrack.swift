import Foundation

enum InvalidTimeline: Error { case data }

/// One codec and segment walker for numeric, color and discrete attributes.
struct TimelineTrack<Value: TimelineValue>: Sendable, Equatable {
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
    private let modifier: TimelineModifier

    init(json: [String: Any], period: Int?, budget: inout Int, overrideRange: ClosedRange<Float>?) throws {
        let modifier: TimelineModifier
        let rawModifier = json["modifier"]
        if rawModifier == nil || rawModifier is NSNull {
            modifier = .override
        } else {
            guard let text = rawModifier as? String, let value = TimelineModifier(rawValue: text) else {
                throw InvalidTimeline.data
            }
            modifier = value
        }
        guard Value.modifiers.contains(modifier) else { throw InvalidTimeline.data }
        self.modifier = modifier
        easing = try TimelineEasing(json: json["ease"])
        let values = try AssetJSON.array(json["keyframes"])
        guard !values.isEmpty, values.count <= budget else { throw InvalidTimeline.data }
        budget -= values.count
        let frames = try values.map { raw -> Frame in
            let frame = try AssetJSON.object(raw)
            let ticks = try AssetJSON.integer(frame["ticks"])
            guard ticks >= 0, period.map({ ticks <= $0 }) ?? true else { throw InvalidTimeline.data }
            let value = try Value.read(frame["value"])
            if modifier == .override, let overrideRange, let number = value as? Float,
               !overrideRange.contains(number) { throw InvalidTimeline.data }
            return Frame(ticks: ticks, value: value)
        }
        let first = frames[0], last = frames[frames.count - 1]
        var previous = last.ticks, repeats = 0
        for (index, frame) in frames.enumerated() {
            if index > 0, frame.ticks < previous { throw InvalidTimeline.data }
            // Match KeyframeTrack's cyclic duplicate validation without sorting or deduplicating.
            repeats = frame.ticks == previous ? repeats + 1 : 0
            guard repeats <= 2 else { throw InvalidTimeline.data }
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
                Int32(exactly: $0.to.ticks - $0.from.ticks) != nil }) else { throw InvalidTimeline.data }
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
        guard value.isFinite else { throw InvalidTimeline.data }
        let result = try Value.apply(modifier, to: base, argument: value)
        guard result.isFinite else { throw InvalidTimeline.data }
        return result
    }
}

enum TimelineModifier: String, Sendable, Hashable {
    case override, add, subtract, multiply, minimum, maximum
}

protocol TimelineValue: Sendable, Equatable {
    static var modifiers: Set<TimelineModifier> { get }
    static func read(_ raw: Any?) throws -> Self
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self
    static func apply(_ modifier: TimelineModifier, to base: Self, argument: Self) throws -> Self
    var isFinite: Bool { get }
}

extension Float: TimelineValue {
    static let modifiers: Set<TimelineModifier> = [.override, .add, .subtract, .multiply, .minimum, .maximum]
    static func read(_ raw: Any?) throws -> Float { try AssetJSON.number(raw) }
    static func interpolate(_ from: Float, _ to: Float, _ progress: Float) -> Float { from + progress * (to - from) }
    static func apply(_ modifier: TimelineModifier, to base: Float, argument: Float) -> Float {
        switch modifier {
        case .override: argument
        case .add: base + argument
        case .subtract: base - argument
        case .multiply: base * argument
        case .minimum: min(base, argument)
        case .maximum: max(base, argument)
        }
    }
}

extension SIMD3: TimelineValue where Scalar == Float {
    static var modifiers: Set<TimelineModifier> { [.override, .add, .subtract, .multiply] }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    static func read(_ raw: Any?) throws -> Self { try AssetJSON.colorVector(raw) }
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self { from + progress * (to - from) }
    static func apply(_ modifier: TimelineModifier, to base: Self, argument: Self) throws -> Self {
        switch modifier {
        case .override: argument
        case .multiply: base * argument
        case .add: Self(Swift.min(base.x + argument.x, 1), Swift.min(base.y + argument.y, 1), Swift.min(base.z + argument.z, 1))
        case .subtract: Self(Swift.max(base.x - argument.x, 0), Swift.max(base.y - argument.y, 0), Swift.max(base.z - argument.z, 0))
        case .minimum, .maximum: throw InvalidTimeline.data
        }
    }
}

extension SkyLighting.MoonPhase: TimelineValue {
    static let modifiers: Set<TimelineModifier> = [.override]
    var isFinite: Bool { true }
    static func read(_ raw: Any?) throws -> Self {
        guard let name = raw as? String, let phase = Self(rawValue: name) else { throw InvalidTimeline.data }
        return phase
    }
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self { progress >= 1 ? to : from }
    static func apply(_ modifier: TimelineModifier, to base: Self, argument: Self) -> Self { argument }
}
