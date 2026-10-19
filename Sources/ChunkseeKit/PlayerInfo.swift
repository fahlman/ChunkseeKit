import Foundation

/// What a player file says about where a player was, died and will respawn.
///
/// Player files are upgraded only when that player joins, so one world can hold several formats:
/// 1.16+ string dimensions, older integer dimensions, the 1.21+ `respawn` compound, older
/// `SpawnX`/`SpawnY`/`SpawnZ` fields, and files written by Bukkit servers, whose positions may
/// belong to a different world of the same server.
public struct PlayerInfo: Sendable {
    /// A position in a dimension.
    public struct Location: Sendable, Equatable {
        /// Namespaced dimension ID, e.g. `minecraft:the_nether`.
        public var dimension: String
        public var x: Double
        public var y: Double
        public var z: Double

        /// The containing whole block, distinct from this location's exact saved decimals.
        public var blockPosition: BlockPosition? { BlockPosition(x: x, y: y, z: z) }

        public init(dimension: String, x: Double, y: Double, z: Double) {
            self.dimension = dimension
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public let uuid: UUID
    public let dataVersion: Int?
    /// When the player file was last written, if known.
    public let lastSaved: Date?
    /// Where the player was when the file was saved, or `nil` if the dimension isn't recognized
    /// (see `unrecognizedDimension`).
    public let position: Location?
    /// The raw dimension value when it couldn't be mapped, e.g. `"21"` for a Bukkit world ID.
    public let unrecognizedDimension: String?
    public let lastDeath: Location?
    /// The bed or respawn anchor the player will respawn at, if set.
    public let respawn: Location?
    /// True when the file was written by a Bukkit-based server, whose worlds share player files:
    /// every location here (position, death, respawn) may be in a different world than the one
    /// being read, even when its dimension looks familiar.
    public let isFromBukkitServer: Bool
    /// Whether saved current, death and respawn locations belong to the world holding this file.
    /// Bukkit servers share player files across worlds, so those locations cannot be assigned to
    /// this world. This does not guarantee a location exists or its coordinates are representable.
    public var locationsBelongToWorld: Bool { !isFromBukkitServer }
    /// The world a Bukkit server recorded for the player's spawn (`SpawnWorld`), if any.
    public let bukkitWorldName: String?
    /// The full player NBT, for fields this type doesn't model.
    public let nbt: NBT

    public init(uuid: UUID, nbt: NBT, lastSaved: Date? = nil) {
        self.uuid = uuid
        self.nbt = nbt
        self.lastSaved = lastSaved
        dataVersion = nbt["DataVersion"]?.int

        let dimension = nbt["Dimension"]?.dimensionID
        if let dimension, let pos = nbt["Pos"]?.list?.compactMap(\.double), pos.count == 3 {
            position = Location(dimension: dimension, x: pos[0], y: pos[1], z: pos[2])
        } else {
            position = nil
        }
        unrecognizedDimension = dimension == nil ? nbt["Dimension"].map(Self.describe) : nil

        lastDeath = Self.location(nbt["LastDeathLocation"])

        if let respawn = Self.location(nbt["respawn"]) {
            self.respawn = respawn
        } else if let x = nbt["SpawnX"]?.int, let y = nbt["SpawnY"]?.int, let z = nbt["SpawnZ"]?.int {
            let dimension = nbt["SpawnDimension"]?.dimensionID ?? "minecraft:overworld"
            respawn = Location(dimension: dimension, x: Double(x), y: Double(y), z: Double(z))
        } else {
            respawn = nil
        }

        bukkitWorldName = nbt["SpawnWorld"]?.string
        isFromBukkitServer = nbt["WorldUUIDMost"] != nil || nbt["bukkit"] != nil || bukkitWorldName != nil
    }

    /// `{dimension: "…", pos: [I; x, y, z]}`, as used by `LastDeathLocation` and `respawn`.
    static func location(_ nbt: NBT?) -> Location? {
        guard let location = SavedBlockLocation(nbt) else { return nil }
        return Location(dimension: location.dimension, x: Double(location.position.x),
                        y: Double(location.position.y), z: Double(location.position.z))
    }

    private static func describe(_ nbt: NBT) -> String {
        nbt.string ?? nbt.int.map(String.init) ?? "\(nbt)"
    }
}

extension World {
    /// Every player with saved data, most recently saved first. Files that can't be read are
    /// skipped. Older singleplayer worlds without a player file contribute the player embedded in
    /// `level.dat`.
    public func players() -> [PlayerInfo] {
        var players = playerUUIDs().compactMap { uuid -> PlayerInfo? in
            let file = playerDataDirectory.appendingPathComponent(uuid.uuidString.lowercased() + ".dat")
            guard let nbt = try? NBT.read(contentsOf: file) else { return nil }
            let saved = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
            return PlayerInfo(uuid: uuid, nbt: nbt, lastSaved: saved)
        }
        if let embedded = level.nbt["Player"], embedded.compound != nil,
           let uuid = embedded.uuid ?? level.singleplayerUUID,
           !players.contains(where: { $0.uuid == uuid }) {
            players.append(PlayerInfo(uuid: uuid, nbt: embedded, lastSaved: level.lastPlayed))
        }
        return players.sorted { ($0.lastSaved ?? .distantPast) > ($1.lastSaved ?? .distantPast) }
    }
}

/// A player's game mode, from `playerGameType`.
public enum GameMode: Int, Sendable {
    case survival = 0, creative, adventure, spectator
}

extension PlayerInfo {
    /// Health in half-hearts, 0–20 for a player without health boosts.
    public var health: Double? { nbt["Health"]?.double }
    /// Extra health from golden apples and the like, shown as golden hearts.
    public var absorption: Double? { nbt["AbsorptionAmount"]?.double }
    /// Hunger in half-drumsticks, 0–20.
    public var foodLevel: Int? { nbt["foodLevel"]?.int }
    /// Hidden food reserve used up before hunger drops.
    public var saturation: Double? { nbt["foodSaturationLevel"]?.double }
    public var experienceLevel: Int? { nbt["XpLevel"]?.int }
    /// Progress toward the next level, 0–1.
    public var experienceProgress: Double? { nbt["XpP"]?.double }
    /// Experience points collected since the player last died.
    public var experienceTotal: Int? { nbt["XpTotal"]?.int }
    public var gameMode: GameMode? { nbt["playerGameType"]?.int.flatMap(GameMode.init(rawValue:)) }
    /// The selected hotbar slot, 0–8.
    public var selectedSlot: Int? { nbt["SelectedItemSlot"]?.int }
}

extension PlayerInfo {
    /// The main inventory (slots 9–35) and hotbar (slots 0–8).
    public var inventory: [ItemStack] {
        ItemStack.list(nbt["Inventory"]).filter { ($0.slot ?? 0) >= 0 && ($0.slot ?? 0) < 36 }
    }

    /// Worn armor and the offhand item, keyed by slot name (`head`, `chest`, `legs`, `feet`,
    /// `offhand`, and `body`/`saddle` where present): the `equipment` compound in 1.21.5+, or the
    /// special inventory slots before that.
    public var equipment: [String: ItemStack] {
        EntityEquipment.player(nbt)
    }

    /// The player's ender chest, which every ender chest in the world opens for them.
    public var enderChest: [ItemStack] { ItemStack.list(nbt["EnderItems"]) }
}
