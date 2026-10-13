import Foundation

/// A monster spawner: a `minecraft:mob_spawner` block entity and the mob it spawns. Trial
/// spawners are a different block entity and aren't included.
public struct Spawner: Sendable, Equatable, Codable {
    public var x: Int
    public var y: Int
    public var z: Int
    /// The mob it spawns, e.g. `minecraft:zombie`, from `SpawnData.entity.id`; `nil` for an empty
    /// spawner, which spawns nothing until a spawn egg is used on it.
    public var mob: String?

    public init(x: Int, y: Int, z: Int, mob: String?) {
        self.x = x
        self.y = y
        self.z = z
        self.mob = mob
    }

    /// The spawners among a chunk's block entities.
    public static func spawners(inChunk nbt: NBT) -> [Spawner] {
        (nbt["block_entities"]?.list ?? []).compactMap { entity in
            guard entity["id"]?.string == "minecraft:mob_spawner",
                  let x = entity["x"]?.int, let y = entity["y"]?.int, let z = entity["z"]?.int else { return nil }
            return Spawner(x: x, y: y, z: z, mob: entity["SpawnData"]?["entity"]?["id"]?.string)
        }
    }
}
