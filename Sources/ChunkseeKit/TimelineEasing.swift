import Foundation

/// The easing forms needed by the supplied daylight/moon definitions. Unknown forms fail closed.
enum TimelineEasing: Sendable, Equatable {
    case linear, constant
    case cubicBezier(x: Curve, y: Curve)

    struct Curve: Sendable, Equatable {
        let a: Float, b: Float, c: Float
        init(_ first: Float, _ second: Float) throws {
            a = 3 * first - 3 * second + 1
            b = -6 * first + 3 * second
            c = 3 * first
            guard a.isFinite, b.isFinite, c.isFinite else { throw InvalidTimeline.data }
        }
        func sample(_ t: Float) -> Float { ((a * t + b) * t + c) * t }
        func gradient(_ t: Float) -> Float { (3 * a * t + 2 * b) * t + c }
    }

    init(json: Any?) throws {
        if json == nil || json is NSNull { self = .linear; return }
        if let name = json as? String {
            switch name {
            case "linear": self = .linear
            case "constant": self = .constant
            default: throw InvalidTimeline.data
            }
        } else {
            let controls = try AssetJSON.numbers(AssetJSON.object(json)["cubic_bezier"], count: 4)
            guard (0...1).contains(controls[0]), (0...1).contains(controls[2]) else { throw InvalidTimeline.data }
            self = try .cubicBezier(x: Curve(controls[0], controls[2]), y: Curve(controls[1], controls[3]))
        }
    }

    func apply(_ progress: Float) throws -> Float {
        switch self {
        case .constant: return 0
        case .linear: return progress
        case .cubicBezier(let x, let y):
            var t = progress
            for _ in 0..<4 {
                let error = x.sample(t) - progress
                if abs(error) < 0.00001 { return y.sample(t) }
                let gradient = x.gradient(t)
                if gradient < 0.00001 { break }
                t -= min(max(error / gradient, -0.25), 0.25)
            }
            var low: Float = 0, high: Float = 1
            // Same tolerance and Newton/bisection order as 26.3, with a finite work bound.
            for _ in 0..<32 {
                let error = x.sample(t) - progress
                if abs(error) < 0.00001 { return y.sample(t) }
                if error < 0 { low = t } else { high = t }
                let next = (low + high) / 2
                guard next != t else { throw InvalidTimeline.data }
                t = next
            }
            throw InvalidTimeline.data
        }
    }
}
