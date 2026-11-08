enum InvalidLighting: Error { case data }

enum LightingModifier: String, Sendable, Hashable {
    case override, add, subtract, multiply, minimum, maximum
}

protocol LightingValue: Sendable, Equatable {
    static var modifiers: Set<LightingModifier> { get }
    static func read(_ raw: LightingInput) throws -> Self
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self
    static func apply(_ modifier: LightingModifier, to base: Self, argument: Self) throws -> Self
    var isFinite: Bool { get }
}

extension LightingValue {
    static func argument(_ raw: LightingInput, modifier: LightingModifier, overrideRange: ClosedRange<Float>?) throws -> Self {
        guard modifiers.contains(modifier) else { throw InvalidLighting.data }
        let value = try read(raw)
        if modifier == .override, let overrideRange, let number = value as? Float,
           !overrideRange.contains(number) { throw InvalidLighting.data }
        return value
    }
}

extension Float: LightingValue {
    static let modifiers: Set<LightingModifier> = [.override, .add, .subtract, .multiply, .minimum, .maximum]
    static func read(_ raw: LightingInput) throws -> Float { try raw.number() }
    static func interpolate(_ from: Float, _ to: Float, _ progress: Float) -> Float { from + progress * (to - from) }
    static func apply(_ modifier: LightingModifier, to base: Float, argument: Float) -> Float {
        switch modifier {
        case .override: argument
        case .add: base + argument
        case .subtract: base - argument
        case .multiply: base * argument
        case .minimum, .maximum:
            // Minecraft uses Math.min/max: propagate either NaN and order signed zeros.
            if base.isNaN { return base }
            if argument.isNaN { return argument }
            if base == 0, argument == 0 {
                let sign: FloatingPointSign = modifier == .minimum ? .minus : .plus
                return base.sign == sign ? base : argument
            }
            return modifier == .minimum ? min(base, argument) : max(base, argument)
        }
    }
}

extension SIMD3: LightingValue where Scalar == Float {
    static var modifiers: Set<LightingModifier> { [.override, .add, .subtract, .multiply] }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    static func read(_ raw: LightingInput) throws -> Self { try raw.colorVector() }
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self { from + progress * (to - from) }
    static func apply(_ modifier: LightingModifier, to base: Self, argument: Self) throws -> Self {
        switch modifier {
        case .override: argument
        case .multiply: base * argument
        case .add: Self(Swift.min(base.x + argument.x, 1), Swift.min(base.y + argument.y, 1), Swift.min(base.z + argument.z, 1))
        case .subtract: Self(Swift.max(base.x - argument.x, 0), Swift.max(base.y - argument.y, 0), Swift.max(base.z - argument.z, 0))
        case .minimum, .maximum: throw InvalidLighting.data
        }
    }
}

extension SkyLighting.MoonPhase: LightingValue {
    static let modifiers: Set<LightingModifier> = [.override]
    var isFinite: Bool { true }
    static func read(_ raw: LightingInput) throws -> Self {
        guard let name = raw.string, let phase = Self(rawValue: name) else { throw InvalidLighting.data }
        return phase
    }
    static func interpolate(_ from: Self, _ to: Self, _ progress: Float) -> Self { progress >= 1 ? to : from }
    static func apply(_ modifier: LightingModifier, to base: Self, argument: Self) -> Self { argument }
}
