import Foundation

/// A living mob from an entity chunk (`entities/` region files): its kind, position, name, owner
/// and, for villagers, their profession and trades.
public struct Creature: Sendable, Equatable, Codable {
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
    /// Saved current health in half-hearts; nil when unavailable, including older cached records.
    public var health: Double?
    /// Maximum health in half-hearts, from saved attributes or a verified version's defaults.
    /// Saved effect modifiers are included; unsupported transient equipment modifiers leave it nil.
    public var maxHealth: Double?
    /// The saved sitting command for a pet wolf, cat or parrot, rather than its current pose.
    public var sittingOrder: Bool?
    /// Readable appearance facts, including coat/pattern, markings, colors and genes.
    public var appearance: CreatureAppearance?
    /// A saved collar dye name such as `orange`; owned wolves/cats default to red when omitted.
    public var collarColor: String?
    /// Equipped items by slot; the derived `storage` key represents an attached chest.
    /// Empty when saved empty or omitted by the mob's save format; nil when unavailable.
    public var equipment: [String: ItemStack]?
    /// The individual entity's stable identity, retained across movement and shared positions.
    public var uuid: UUID?

    public init(id: String, x: Double, y: Double, z: Double, customName: String? = nil, owner: UUID? = nil, villager: Villager? = nil, health: Double? = nil, maxHealth: Double? = nil, sittingOrder: Bool? = nil, appearance: CreatureAppearance? = nil, collarColor: String? = nil, equipment: [String: ItemStack]? = nil, uuid: UUID? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.z = z
        self.customName = customName
        self.owner = owner
        self.villager = villager
        self.health = health
        self.maxHealth = maxHealth
        self.sittingOrder = sittingOrder
        self.appearance = appearance
        self.collarColor = collarColor
        self.equipment = equipment
        self.uuid = uuid
    }

    /// Reads Minecraft's saved mob format, including new and modded type IDs.
    /// Health and the type's name alone do not establish that the saved record is a mob.
    public init?(_ nbt: NBT) {
        self.init(nbt, dataVersion: nil)
    }

    /// The saved mob format establishes membership independently of the game's version.
    /// The version is retained for facts such as omitted health defaults, not a type list.
    /// Active enchantments require a resource-derived definition snapshot to establish maximum health.
    public init?(_ nbt: NBT, dataVersion: Int?, enchantments: [String: EnchantmentDefinition] = [:]) {
        guard let savedID = nbt["id"]?.string, let identifier = Identifier(savedID),
              !identifier.path.isEmpty,
              let pos = nbt["Pos"]?.list?.compactMap(\.double), pos.count == 3 else { return nil }
        // Mob.addAdditionalSaveData always writes these three booleans, even when false.
        // Unlike Health or Owner, they identify the mob record written by the game. Reading
        // that format admits new IDs without maintaining a creature list. See Tools/EntityTypes.
        guard ["CanPickUpLoot", "PersistenceRequired", "LeftHanded"].allSatisfy({
            nbt[$0]?.bool != nil
        }) else { return nil }
        let id = identifier.description
        self.init(id: id, x: pos[0], y: pos[1], z: pos[2],
                  customName: nbt["CustomName"].flatMap(TextComponent.plainText)
                      .map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 },
                  owner: nbt["Owner"]?.uuid ?? nbt["OwnerUUID"]?.uuid,
                  villager: Villager(nbt), health: nbt["Health"]?.double)
        let isTamed: Bool? = owner != nil ? true : (nbt["Owner"] == nil && nbt["OwnerUUID"] == nil ? false : nil)
        maxHealth = EntityHealth.maximumHealth(nbt, species: id, dataVersion: dataVersion, isTamed: isTamed, enchantments: enchantments)
        uuid = nbt.uuid
        if owner != nil { sittingOrder = CreatureData.sittingOrder(nbt, species: id) }
        appearance = CreatureData.appearance(nbt, species: id, villager: villager)
        collarColor = CreatureData.collarColor(nbt, species: id, isOwned: owner != nil)
        equipment = CreatureData.equipment(nbt)
    }

    /// Living mobs among an entity chunk's entities, including all nested passengers.
    /// Each mob keeps its own saved position and the chunk's data version.
    public static func creatures(inEntityChunk nbt: NBT, enchantments: [String: EnchantmentDefinition] = [:]) -> [Creature] {
        creatures(in: nbt["Entities"]?.list ?? [], dataVersion: nbt["DataVersion"]?.int, enchantments: enchantments)
    }

    static func creatures(in entities: [NBT], dataVersion: Int?, enchantments: [String: EnchantmentDefinition] = [:]) -> [Creature] {
        EntityTraversal.flatten(entities).compactMap { Creature($0, dataVersion: dataVersion, enchantments: enchantments) }
    }
}

/// A villager's (or wandering trader's) profession and trades.
public struct Villager: Sendable, Equatable, Codable {
    /// e.g. `minecraft:farmer`, or `minecraft:none` for an unemployed villager.
    public var profession: String?
    /// Whether the saved profession is Minecraft's explicit `none` category. Missing, empty
    /// or malformed identifiers are unknown. Nitwits have a distinct category and return false;
    /// this does not determine whether a villager can work or trade.
    public var isUnemployed: Bool? {
        professionID.map { $0.namespace == "minecraft" && $0.path == "none" }
    }
    /// Whether saved offers or a vanilla 26.3 profession establish trading. Readable saved
    /// trades take precedence, including command-edited villagers. Without them, the 13
    /// trading professions return true, `none` and `nitwit` return false, and unknown,
    /// custom or malformed professions return nil. Does not determine interaction readiness
    /// (such as age or sleeping), nor whether an offer is sold out.
    public var supportsTrading: Bool? {
        if !trades.isEmpty { return true }
        guard let id = professionID, id.namespace == "minecraft" else { return nil }
        switch id.path {
        case "none", "nitwit": return false
        case "armorer", "butcher", "cartographer", "cleric", "farmer", "fisherman",
             "fletcher", "leatherworker", "librarian", "mason", "shepherd", "toolsmith",
             "weaponsmith": return true
        default: return nil
        }
    }
    /// Saved level, normally 1 (novice) to 5 (master); an omitted VillagerData level defaults to 1.
    public var level: Int?
    /// The biome style, e.g. `minecraft:desert`.
    public var type: String?
    public var trades: [Trade]

    private var professionID: Identifier? {
        guard let profession, let id = Identifier(profession), !id.path.isEmpty else { return nil }
        return id
    }

    public init?(_ nbt: NBT) {
        let data = nbt["VillagerData"]
        let trades = (nbt["Offers"]?["Recipes"]?.list ?? []).compactMap(Trade.init)
        guard data != nil || !trades.isEmpty else { return nil }
        profession = data?["profession"]?.string
        // The VillagerData codec defaults an absent field, not a malformed one, to novice.
        if let fields = data?.compound, fields["level"] == nil {
            level = 1
        } else {
            level = data?["level"]?.int
        }
        type = data?["type"]?.string
        self.trades = trades
    }
}

/// One trade a villager offers.
public struct Trade: Sendable, Equatable, Codable {
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
    /// Living mobs in one entity chunk, preserving its saved version for omitted attributes.
    /// Unlike constructing creatures from raw `entities`, this retains the DataVersion context.
    public func creatures(chunkX: Int, chunkZ: Int, enchantments: [String: EnchantmentDefinition] = [:]) throws -> [Creature] {
        guard let nbt = try entityChunk(x: chunkX, z: chunkZ) else { return [] }
        return Creature.creatures(inEntityChunk: nbt, enchantments: enchantments)
    }

    /// Living mobs in one region's entity file.
    public func creatures(regionX: Int, regionZ: Int, enchantments: [String: EnchantmentDefinition] = [:]) throws -> [Creature] {
        try chunks(.entities, regionX: regionX, regionZ: regionZ).flatMap { Creature.creatures(inEntityChunk: $0.nbt, enchantments: enchantments) }
    }
}
