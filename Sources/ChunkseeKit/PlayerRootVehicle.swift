extension PlayerInfo {
    /// Mobs saved in RootVehicle.Entity: the root vehicle and its nested passengers, in
    /// saved order. Non-mob vehicles are omitted, but their mob passengers remain readable.
    ///
    /// Use each creature's own saved coordinates and this player's dimension. Unlike shoulder
    /// pets, these are current saved positions. Missing player coordinates do not discard them.
    /// RootVehicle.Attach identifies the player's immediate vehicle, not an owner or player;
    /// this property preserves the saved tree even if that attachment cannot be reconstructed.
    public var rootVehicleCreatures: [Creature] {
        guard let entity = nbt["RootVehicle"]?["Entity"] else { return [] }
        return Creature.creatures(in: [entity], dataVersion: dataVersion, enchantments: enchantments)
    }
}
