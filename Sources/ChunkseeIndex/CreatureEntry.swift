import ChunkseeKit
import Foundation

/// A saved mob with a location supported by the map index.
/// Display names, symbols and player-carried projections belong to clients.
public struct CreatureEntry: Identifiable, Equatable, Sendable {
    /// Saved category raw values are also used by clients' visibility settings.
    public enum Group: String, CaseIterable, Codable, Sendable {
        case named, pet, villager, mob

        /// A villager's trades take precedence over ownership and a custom name.
        public static func group(for creature: Creature) -> Self {
            if creature.villager != nil { return .villager }
            if creature.owner != nil { return .pet }
            if creature.customName != nil { return .named }
            return .mob
        }
    }

    public let id: String
    public let creature: Creature
    public let group: Group

    public init?(_ creature: Creature) {
        guard BlockPosition.mapCoordinates(x: creature.x, y: creature.y, z: creature.z) != nil else { return nil }
        self.creature = creature
        group = Group.group(for: creature)
        id = creature.uuid.map { "creature:\($0.uuidString.lowercased())" }
            ?? "\(creature.id)@\(creature.x),\(creature.y),\(creature.z)"
    }
}
