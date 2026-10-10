import Foundation

/// A living mob from an entity chunk (`entities/` region files): its kind, position, name, owner
/// and, for villagers, their job and trades.
public struct Creature: Sendable, Equatable {
    /// Entity id, e.g. `minecraft:wolf`.
    public var id: String
    public var x: Double
    public var y: Double
    public var z: Double
    /// A name given with a name tag, as plain text without formatting codes.
    public var customName: String?
    /// The player who tamed it.
    public var owner: UUID?
    public var villager: Villager?

    public init(id: String, x: Double, y: Double, z: Double, customName: String? = nil, owner: UUID? = nil, villager: Villager? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.z = z
        self.customName = customName
        self.owner = owner
        self.villager = villager
    }

    /// Reads a living entity; `nil` for anything without health (items, minecarts, falling blocks).
    public init?(_ nbt: NBT) {
        guard let id = nbt["id"]?.string, nbt["Health"] != nil,
              let pos = nbt["Pos"]?.list?.compactMap(\.double), pos.count == 3 else { return nil }
        self.init(id: id, x: pos[0], y: pos[1], z: pos[2],
                  customName: nbt["CustomName"].flatMap(TextComponent.plainText).map(Self.removingFormattingCodes).flatMap { $0.isEmpty ? nil : $0 },
                  // 1.16+ stores an int array; older versions a string, as `Owner` or `OwnerUUID`.
                  owner: nbt["Owner"]?.uuid ?? (nbt["Owner"]?.string ?? nbt["OwnerUUID"]?.string).flatMap(UUID.init(uuidString:)),
                  villager: Villager(nbt))
    }

    /// Strips `§` formatting codes, which server plugins put in names (`§aSummer` → `Summer`).
    static func removingFormattingCodes(_ text: String) -> String {
        var result = ""
        var skipNext = false
        for character in text {
            if skipNext { skipNext = false; continue }
            if character == "§" { skipNext = true; continue }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Living mobs among an entity chunk's entities.
    public static func creatures(inEntityChunk nbt: NBT) -> [Creature] {
        (nbt["Entities"]?.list ?? []).compactMap(Creature.init)
    }
}

/// A villager's (or wandering trader's) job and trades.
public struct Villager: Sendable, Equatable {
    /// e.g. `minecraft:farmer`, or `minecraft:none` for an unemployed villager.
    public var profession: String?
    /// 1 (novice) to 5 (master).
    public var level: Int?
    /// The biome style, e.g. `minecraft:desert`.
    public var type: String?
    public var trades: [Trade]

    public init?(_ nbt: NBT) {
        let data = nbt["VillagerData"]
        let trades = (nbt["Offers"]?["Recipes"]?.list ?? []).compactMap(Trade.init)
        guard data != nil || !trades.isEmpty else { return nil }
        profession = data?["profession"]?.string
        level = data?["level"]?.int
        type = data?["type"]?.string
        self.trades = trades
    }
}

/// One trade a villager offers.
public struct Trade: Sendable, Equatable {
    public var buy: ItemStack
    /// A second item some trades also ask for.
    public var buyB: ItemStack?
    public var sell: ItemStack
    public var uses: Int
    public var maxUses: Int

    public init?(_ nbt: NBT) {
        guard let buy = nbt["buy"].flatMap(ItemStack.init), let sell = nbt["sell"].flatMap(ItemStack.init) else { return nil }
        self.buy = buy
        buyB = nbt["buyB"].flatMap(ItemStack.init)
        self.sell = sell
        uses = nbt["uses"]?.int ?? 0
        maxUses = nbt["maxUses"]?.int ?? 0
    }

    /// Used up until the villager restocks.
    public var isSoldOut: Bool { maxUses > 0 && uses >= maxUses }
}

extension Dimension {
    /// Living mobs in one region's entity file.
    public func creatures(regionX: Int, regionZ: Int) throws -> [Creature] {
        guard let entities = try Self.region(in: entitiesDirectory, x: regionX, z: regionZ) else { return [] }
        var found: [Creature] = []
        for (x, z) in entities.chunkCoordinates {
            guard let nbt = try? entities.chunkNBT(localX: x, localZ: z) else { continue }
            found += Creature.creatures(inEntityChunk: nbt)
        }
        return found
    }
}
