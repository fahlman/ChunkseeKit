import Foundation

/// A saved spawner record and the entity named in its SpawnData. Trial spawners use a
/// different saved structure and aren't included.
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
        Chunk.blockEntities(in: nbt).compactMap { entity in
            // BaseSpawner can omit its nullable SpawnData. Preserve known empty spawners too.
            guard entity["SpawnData"]?.compound != nil || entity["id"]?.string == "minecraft:mob_spawner",
                  let position = entity.blockEntityPosition else { return nil }
            // Upgrade only actual spawner records; unrelated container inventories can be large.
            let entity = SaveDataUpgrade.blockEntity(entity, dataVersion: nbt["DataVersion"]?.int)
            let spawnData = entity["SpawnData"]
            let mob = (spawnData?["entity"] ?? spawnData)?["id"]?.string
            return Spawner(x: position.x, y: position.y, z: position.z, mob: mob)
        }
    }
}
