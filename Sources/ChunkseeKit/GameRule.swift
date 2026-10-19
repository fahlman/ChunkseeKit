/// A game rule whose current and legacy saved identifiers the library recognizes.
public enum GameRule: String, Sendable {
    case wanderingTraderSpawning = "minecraft:spawn_wandering_traders"

    /// Looks up an explicit saved value without relying on a display name or inventing a default.
    /// A current identifier takes precedence over its legacy spelling, even when malformed.
    public func value(in rules: [String: GameRuleValue]) -> GameRuleValue? {
        switch self {
        case .wanderingTraderSpawning:
            guard case .bool(let enabled)? = rules[rawValue] ?? rules["doTraderSpawning"] else { return nil }
            return .bool(enabled)
        }
    }
}
