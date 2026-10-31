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
    /// Maximum health in half-hearts, from saved attributes or generated game-code defaults.
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
    /// With no file version, names receive the game's oldest-save upgrades. For current data,
    /// pass its containing entity-chunk or player-file DataVersion to the versioned initializer.
    public init?(_ nbt: NBT) {
        self.init(nbt, dataVersion: nil)
    }

    /// The saved mob format establishes membership independently of the game's version.
    /// The version selects saved-name upgrades, not a type list or health-default catalog.
    /// Active enchantments require a resource-derived definition snapshot to establish maximum health.
    public init?(_ nbt: NBT, dataVersion: Int?, enchantments: [String: EnchantmentDefinition] = [:]) {
        self.init(normalized: NormalizedEntity(nbt, dataVersion: dataVersion), enchantments: enchantments)
    }

    init?(normalized entity: NormalizedEntity, enchantments: [String: EnchantmentDefinition] = [:]) {
        let nbt = entity.nbt
        guard let savedID = nbt["id"]?.string, let identifier = Identifier(savedID),
              !identifier.path.isEmpty,
              let pos = nbt["Pos"]?.list?.compactMap(\.double), pos.count == 3 else { return nil }
        // Mob.addAdditionalSaveData always writes these three booleans, even when false.
        // Unlike Health or Owner, they identify the mob record written by the game. Reading
        // that format admits new IDs without maintaining a creature list. See Tools/EntityTypes.
        guard ["CanPickUpLoot", "PersistenceRequired", "LeftHanded"].allSatisfy({
            nbt[$0]?.compoundBoolean != nil
        }) else { return nil }
        let id = identifier.description
        self.init(id: id, x: pos[0], y: pos[1], z: pos[2],
                  customName: nbt["CustomName"].flatMap(TextComponent.plainText)
                      .map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 },
                  owner: nbt["Owner"]?.uuid ?? nbt["OwnerUUID"]?.uuid,
                  villager: Villager(nbt), health: nbt["Health"]?.double)
        let isTamed: Bool? = owner != nil ? true : (nbt["Owner"] == nil && nbt["OwnerUUID"] == nil ? false : nil)
        maxHealth = EntityHealth.maximumHealth(nbt, species: id, isTamed: isTamed, enchantments: enchantments)
        uuid = nbt.uuid
        if owner != nil { sittingOrder = CreatureData.sittingOrder(nbt, species: id) }
        appearance = CreatureData.appearance(nbt, species: id, villager: villager)
        collarColor = CreatureData.collarColor(nbt, species: id, isOwned: owner != nil)
        equipment = CreatureData.equipment(nbt)
    }

    /// Living mobs among an entity chunk's entities, including all nested passengers.
    /// Each mob keeps its own saved position and the chunk's data version.
    public static func creatures(inEntityChunk nbt: NBT, enchantments: [String: EnchantmentDefinition] = [:]) -> [Creature] {
        creatures(in: NormalizedEntities(nbt), enchantments: enchantments)
    }

    static func creatures(in entities: [NBT], dataVersion: Int?, enchantments: [String: EnchantmentDefinition] = [:]) -> [Creature] {
        creatures(in: NormalizedEntities(entities, dataVersion: dataVersion), enchantments: enchantments)
    }

    static func creatures(in entities: NormalizedEntities, enchantments: [String: EnchantmentDefinition] = [:]) -> [Creature] {
        entities.records.compactMap { Creature(normalized: $0, enchantments: enchantments) }
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
    /// Whether saved offers or the profession's runtime definitions establish potential trading.
    /// Readable offers win, including custom/edited villagers. Saved empty offers return false;
    /// unreadable recipes or older cached offer state remain unknown. Only uninitialized offers let the saved
    /// level select its code-linked trade set, with the game's minimum level of one. No link returns false;
    /// missing code, level or definitions returns nil. The caller retains one resource snapshot.
    /// This does not roll offers or evaluate merchant conditions, age, sleep or sold-out status.
    public func supportsTrading(using definitions: TradingDefinitions?) -> Bool? {
        if !trades.isEmpty { return true }
        switch offerState {
        case .complete: return false
        case .uninitialized: break
        case .incomplete, nil: return nil
        }
        guard let id = professionID?.description,
              let sets = GeneratedTradingFacts.professions[id], let level else { return nil }
        guard let set = sets[max(GeneratedTradingFacts.minimumLevel, level)] else { return false }
        return definitions?.tradeSets[set]
    }
    /// Saved level, normally 1 (novice) to 5 (master); an omitted VillagerData level defaults to 1.
    public var level: Int?
    /// The biome style, e.g. `minecraft:desert`.
    public var type: String?
    /// Readable saved recipes, including the readable portion of an incomplete list.
    public var trades: [Trade]
    /// The game's initialized-list state and Kit's recipe readability. Nil in older standalone
    /// Codable records, which cannot establish whether an empty array was saved or uninitialized.
    public var offerState: OfferState?

    public enum OfferState: String, Sendable, Codable {
        /// Offers was absent or not a compound; the game may initialize current definitions.
        case uninitialized
        /// Every retained recipe supplied readable trade items, including a known empty list.
        case complete
        /// At least one list entry could not be read by Kit; other recipes are retained.
        case incomplete
    }

    private var professionID: Identifier? {
        guard let profession, let id = Identifier(profession), !id.path.isEmpty else { return nil }
        return id
    }

    public init?(_ nbt: NBT) {
        let data = nbt["VillagerData"]
        let offers = nbt["Offers"]
        guard data != nil || offers != nil else { return nil }
        let recipes = offers?["Recipes"]?.list
        let trades = (recipes ?? []).compactMap(Trade.init)
        if offers?.compound == nil {
            // TagValueInput.read uses codec partial values. A non-compound Offers has
            // no partial value, so AbstractVillager initializes it just like an absent field.
            offerState = .uninitialized
        } else {
            // Missing Recipes defaults to empty; a non-list Recipes decodes to an empty
            // partial list. Unreadable individual entries stay unknown to Kit's Trade reader.
            offerState = recipes == nil || recipes?.count == trades.count ? .complete : .incomplete
        }
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
    /// Living mobs in one chunk's terrain and separate entity file, preserving each saved version.
    /// Unlike constructing creatures from raw `entities`, this retains the DataVersion context.
    public func creatures(chunkX: Int, chunkZ: Int, enchantments: [String: EnchantmentDefinition] = [:]) throws -> [Creature] {
        try entityChunks(x: chunkX, z: chunkZ).flatMap {
            Creature.creatures(inEntityChunk: $0, enchantments: enchantments)
        }
    }

    /// Living mobs in one region's older embedded records and separate entity file.
    public func creatures(regionX: Int, regionZ: Int, enchantments: [String: EnchantmentDefinition] = [:]) throws -> [Creature] {
        var result: [Creature] = []
        try forEachChunk(.terrain, regionX: regionX, regionZ: regionZ,
                         skipping: Chunk.keysNotNeededForEmbeddedEntities) { _, _, nbt in
            result += Creature.creatures(in: ChunkRecords(nbt, needs: .creatures).entities, enchantments: enchantments)
        }
        try forEachChunk(.entities, regionX: regionX, regionZ: regionZ) { _, _, nbt in
            result += Creature.creatures(inEntityChunk: nbt, enchantments: enchantments)
        }
        return result
    }
}
