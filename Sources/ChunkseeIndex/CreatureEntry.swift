import ChunkseeKit
import Foundation

/// A named creature, owned pet or villager with a location supported by the map index.
/// Display names, symbols and player-carried projections belong to clients.
public struct CreatureEntry: Identifiable, Equatable, Sendable {
    /// Saved category raw values are also used by clients' visibility settings.
    public enum Group: String, CaseIterable, Codable, Sendable {
        case named, pet, villager

        /// A villager's trades take precedence over ownership and a custom name.
        public static func group(for creature: Creature) -> Self? {
            if creature.villager != nil { return .villager }
            if creature.owner != nil { return .pet }
            if creature.customName != nil { return .named }
            return nil
        }
    }

    public let id: String
    public let creature: Creature
    public let group: Group

    public init?(_ creature: Creature) {
        guard let group = Group.group(for: creature),
              let block = BlockPosition(x: creature.x, y: creature.y, z: creature.z),
              Int32(exactly: block.x) != nil, Int32(exactly: block.z) != nil else { return nil }
        self.creature = creature
        self.group = group
        id = creature.uuid.map { "creature:\($0.uuidString.lowercased())" }
            ?? "\(creature.id)@\(creature.x),\(creature.y),\(creature.z)"
    }
}
