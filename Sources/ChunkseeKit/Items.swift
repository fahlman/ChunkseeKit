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
    /// The item's components (or legacy `tag`, including normalized top-level `Damage`).
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
        } else {
            let tag = nbt["tag"]
            var legacy = tag?.compound ?? [:]
            // Before 1.13, Damage lived beside id/Count even when the item also had a tag.
            if let damage = nbt["Damage"] { legacy["Damage"] = damage }
            components = legacy.isEmpty ? tag : .compound(legacy)
            customName = tag?["display"]?["Name"].flatMap(TextComponent.plainText)
            contents = (tag?["BlockEntityTag"]?["Items"]?.list ?? []).compactMap(ItemStack.init)
        }
    }

    /// Enchantments on the item, or stored in an enchanted book, by id with their level, e.g.
    /// `["minecraft:mending": 1]`. Empty when the item has none.
    public var enchantments: [String: Int] {
        readEnchantments(components: ["minecraft:enchantments", "minecraft:stored_enchantments"],
                         legacy: ["Enchantments", "StoredEnchantments"])
    }

    /// Stored book enchantments describe contents; only active enchantments affect equipped health.
    var activeEnchantments: [String: Int] {
        guard components?["!minecraft:enchantments"] == nil else { return [:] }
        return readEnchantments(components: ["minecraft:enchantments"], legacy: ["Enchantments"])
    }

    private func readEnchantments(components componentKeys: [String], legacy legacyKeys: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for key in componentKeys {
            guard let value = components?[key]?.compound else { continue }
            // 1.20.5–1.21.4 wrapped the levels in `levels` beside `show_in_tooltip`; later versions
            // store the map directly. Enchantment ids are namespaced, which skips any other key.
            for (id, level) in value["levels"]?.compound ?? value where id.contains(":") {
                if let level = level.int { result[id] = level }
            }
        }
        // Before 1.20.5, item tags held lists of `{id, lvl}`.
        for key in legacyKeys {
            for entry in components?[key]?.list ?? [] {
                if let id = entry["id"]?.string, let level = entry["lvl"]?.int { result[id] = level }
            }
        }
        return result
    }

    /// Remaining durability from saved wear and an explicit or known vanilla maximum.
    /// Known undamaged vanilla items use their prototype's damage component/default maximum.
    /// Removed damage components, unbreakable items and unknown damageability leave it nil.
    public var durability: ItemDurability? {
        guard components?["minecraft:unbreakable"] == nil, components?["Unbreakable"]?.int != 1,
              components?["!minecraft:max_damage"] == nil, components?["!minecraft:damage"] == nil else { return nil }
        let maximum: Int
        if let value = components?["minecraft:max_damage"] {
            guard let number = value.int else { return nil }
            maximum = number
        } else if let known = VanillaItemDurability.values[id] {
            maximum = known
        } else { return nil }
        guard maximum > 0 else { return nil }
        let damageTag = components?["minecraft:damage"] ?? components?["Damage"]
        guard VanillaItemDurability.values[id] != nil || damageTag != nil else { return nil }
        guard damageTag == nil || damageTag?.int != nil else { return nil }
        let damage = damageTag?.int ?? 0
        guard damage >= 0 else { return nil }
        return ItemDurability(remaining: max(0, maximum - min(damage, maximum)), maximum: maximum)
    }

    /// This stack and everything nested inside it.
    public var allItems: [ItemStack] { [self] + contents.flatMap(\.allItems) }

    /// Reads a list of items, skipping empty slots.
    public static func list(_ nbt: NBT?) -> [ItemStack] { (nbt?.list ?? []).compactMap(ItemStack.init) }
}

/// Durability points, not health points or hearts.
public struct ItemDurability: Sendable, Equatable {
    public var remaining: Int
    public var maximum: Int

    public init(remaining: Int, maximum: Int) {
        self.remaining = remaining
        self.maximum = maximum
    }
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
        Chunk.blockEntities(in: nbt).compactMap { entity in
            guard let kind = entity["id"]?.string, let position = entity.blockEntityPosition else {
                return nil
            }
            // Most containers keep `Items`; decorated pots and suspicious blocks keep `item`,
            // lecterns `Book` and jukeboxes `RecordItem`.
            let single = ["item", "Book", "RecordItem"].compactMap { entity[$0].flatMap(ItemStack.init) }
            let items = ItemStack.list(entity["Items"]) + single
            let sealed = entity["LootTable"] != nil
            guard !items.isEmpty || sealed else { return nil }
            return ItemContainer(kind: kind, x: position.x, y: position.y, z: position.z, items: items,
                                 customName: entity["CustomName"].flatMap(TextComponent.plainText),
                                 isSealedLoot: sealed && items.isEmpty, isEntity: false)
        }
    }

    /// Containers among an entity chunk's entities (`entities/` region files): container
    /// minecarts and boats, animals with chests, and item frames.
    public static func containers(inEntityChunk nbt: NBT) -> [ItemContainer] {
        (nbt["Entities"]?.list ?? []).compactMap { entity in
            guard let kind = entity["id"]?.string, let pos = entity["Pos"]?.list, pos.count == 3,
                  let savedX = pos[0].double, let savedY = pos[1].double, let savedZ = pos[2].double,
                  let position = BlockPosition(x: savedX, y: savedY, z: savedZ) else {
                return nil
            }
            // Dropped items despawn and players' items are read from player files, so neither counts.
            guard kind != "minecraft:item", kind != "minecraft:player" else { return nil }
            let items = ItemStack.list(entity["Items"]) + (entity["Item"].flatMap(ItemStack.init).map { [$0] } ?? [])
            let sealed = entity["LootTable"] != nil
            guard !items.isEmpty || sealed else { return nil }
            return ItemContainer(kind: kind, x: position.x, y: position.y, z: position.z,
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
