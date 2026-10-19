import Foundation

extension PlayerInfo {
    /// Parrots saved on the left and right shoulders, in that order, decoded like entity-chunk
    /// creatures. Empty, malformed and non-parrot records are omitted; saved owners are retained.
    ///
    /// These are serialized entity snapshots from when the birds mounted the player. Their
    /// `x`, `y` and `z` are not their current location. Use this player's `position` to locate
    /// shoulder pets, with the same unavailable-dimension/Bukkit checks as the player itself.
    /// Pets remain available here even when the player's current location is unavailable.
    public var shoulderPets: [Creature] {
        ["ShoulderEntityLeft", "ShoulderEntityRight"].compactMap { key in
            guard let entity = nbt[key], entity["id"]?.string == "minecraft:parrot" else { return nil }
            return Creature(entity, dataVersion: dataVersion)
        }
    }
}
