import Foundation

/// A stack of items: in a container, a player's inventory, an item frame, or inside another item
/// (a shulker box or bundle).
///
/// Reads the current format (`{id, count, components}`, 1.20.5+) and the older one
/// (`{id, Count, tag}`), since items are only upgraded when their chunk or player is loaded.
public struct ItemStack: Sendable, Equatable, Codable {
    /// Item id, e.g. `minecraft:diamond_sword`.
    public var id: String
    public var count: Int
    /// The slot in its container or inventory, when recorded.
    public var slot: Int?
    /// A name given with an anvil or name tag, as plain text.
    public var customName: String?
    /// Items stored inside this one: a shulker box's or bundle's contents.
    public var contents: [ItemStack]
    /// The item's components (or legacy `tag`), for details this type doesn't model.
    public var components: NBT?

    public init(id: String, count: Int = 1, slot: Int? = nil, customName: String? = nil, contents: [ItemStack] = [], components: NBT? = nil) {
        self.id = id
        self.count = count
        self.slot = slot
        self.customName = customName
        self.contents = contents
        self.components = components
    }

    /// Reads an item; `nil` for an empty or malformed entry.
    public init?(_ nbt: NBT) {
        guard let id = nbt["id"]?.string, !id.isEmpty, id != "minecraft:air" else { return nil }
        self.id = id
        count = nbt["count"]?.int ?? nbt["Count"]?.int ?? 1
        slot = nbt["Slot"]?.int ?? nbt["slot"]?.int
        if let components = nbt["components"] {
            self.components = components
            customName = components["minecraft:custom_name"].flatMap(TextComponent.plainText)
            let shulker = (components["minecraft:container"]?.list ?? []).compactMap { entry -> ItemStack? in
                guard var item = entry["item"].flatMap(ItemStack.init) else { return nil }
                item.slot = entry["slot"]?.int ?? item.slot
                return item
            }
            let bundle = (components["minecraft:bundle_contents"]?.list ?? []).compactMap(ItemStack.init)
            contents = shulker + bundle
        } else if let tag = nbt["tag"] {
            components = tag
            customName = tag["display"]?["Name"].flatMap(TextComponent.plainText)
            contents = (tag["BlockEntityTag"]?["Items"]?.list ?? []).compactMap(ItemStack.init)
        } else {
            components = nil
            customName = nil
            contents = []
        }
    }

    /// This stack and everything nested inside it.
    public var allItems: [ItemStack] { [self] + contents.flatMap(\.allItems) }

    /// Reads a list of items, skipping empty slots.
    public static func list(_ nbt: NBT?) -> [ItemStack] { (nbt?.list ?? []).compactMap(ItemStack.init) }
}

/// Something that holds items at a place in the world: a chest, barrel, hopper, furnace, chest
/// minecart, chest boat, item frame and so on.
public struct ItemContainer: Sendable, Equatable, Codable {
    /// Block entity or entity id, e.g. `minecraft:chest`, `minecraft:chest_minecart`.
    public var kind: String
    public var x: Int
    public var y: Int
    public var z: Int
    public var items: [ItemStack]
    /// A name given to the container itself (renamed in an anvil before placing).
    public var customName: String?
    /// Generated loot nobody has opened yet: it has a loot table and no items until opened.
    public var isSealedLoot: Bool
    /// True for entities (minecarts, boats, item frames), which can move.
    public var isEntity: Bool

    /// Every item, including the contents of shulker boxes and bundles inside it.
    public var allItems: [ItemStack] { items.flatMap(\.allItems) }

    /// Containers among a chunk's block entities: those with items or sealed loot.
    public static func containers(inChunk nbt: NBT) -> [ItemContainer] {
        (nbt["block_entities"]?.list ?? []).compactMap { entity in
            guard let kind = entity["id"]?.string, let x = entity["x"]?.int, let y = entity["y"]?.int, let z = entity["z"]?.int else {
                return nil
            }
            // Most containers keep `Items`; decorated pots and suspicious blocks keep `item`,
            // lecterns `Book` and jukeboxes `RecordItem`.
            let single = ["item", "Book", "RecordItem"].compactMap { entity[$0].flatMap(ItemStack.init) }
            let items = ItemStack.list(entity["Items"]) + single
            let sealed = entity["LootTable"] != nil
            guard !items.isEmpty || sealed else { return nil }
            return ItemContainer(kind: kind, x: x, y: y, z: z, items: items,
                                 customName: entity["CustomName"].flatMap(TextComponent.plainText),
                                 isSealedLoot: sealed && items.isEmpty, isEntity: false)
        }
    }

    /// Containers among an entity chunk's entities (`entities/` region files): container
    /// minecarts and boats, animals with chests, and item frames.
    public static func containers(inEntityChunk nbt: NBT) -> [ItemContainer] {
        (nbt["Entities"]?.list ?? []).compactMap { entity in
            guard let kind = entity["id"]?.string, let pos = entity["Pos"]?.list?.compactMap(\.double), pos.count == 3 else {
                return nil
            }
            // Dropped items despawn and players' items are read from player files, so neither counts.
            guard kind != "minecraft:item", kind != "minecraft:player" else { return nil }
            let items = ItemStack.list(entity["Items"]) + (entity["Item"].flatMap(ItemStack.init).map { [$0] } ?? [])
            let sealed = entity["LootTable"] != nil
            guard !items.isEmpty || sealed else { return nil }
            return ItemContainer(kind: kind, x: Int(pos[0].rounded(.down)), y: Int(pos[1].rounded(.down)), z: Int(pos[2].rounded(.down)),
                                 items: items, customName: entity["CustomName"].flatMap(TextComponent.plainText),
                                 isSealedLoot: sealed && items.isEmpty, isEntity: true)
        }
    }
}

extension Chunk {
    /// Entries a container scan doesn't need: block data, light, ticks and other bookkeeping.
    /// Keeps `block_entities`, which `keysNotNeededForTerrain` drops.
    public static let keysNotNeededForContainers: Set<String> =
        keysNotNeededForTerrain.subtracting(["block_entities"]).union(["sections", "Heightmaps", "structures"])
}

extension Dimension {
    /// Every container in one region; see `contents(regionX:regionZ:)`.
    public func containers(regionX: Int, regionZ: Int) throws -> [ItemContainer] {
        try contents(regionX: regionX, regionZ: regionZ).containers
    }
}
