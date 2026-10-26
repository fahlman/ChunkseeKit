/// In-memory save interpretation. Raw NBT/file APIs retain exactly what was saved.
/// Content aliases come only from the game's generated fix chain; these adapters know fields.
enum SaveDataUpgrade {
    enum Kind: Sendable { case block, item, biome, entity, blockEntity }
    struct Rename: Sendable {
        let kind: Kind
        let version: Int
        let changes: [String: String]
    }
    struct DamageChange: Sendable {
        let id: String
        let version: Int
        let changes: [Int: Int]
    }

    static func chunk(_ nbt: NBT) -> NBT {
        upgrade(nbt, as: .chunk, dataVersion: nbt["DataVersion"]?.int)
    }

    static func blockEntities(inChunk nbt: NBT) -> [NBT] {
        let entities = nbt["block_entities"] ?? .list([])
        return upgrade(entities, as: .blockEntities, dataVersion: nbt["DataVersion"]?.int).list ?? []
    }

    static func entity(_ nbt: NBT, dataVersion: Int?) -> NBT {
        upgrade(nbt, as: .entity, dataVersion: dataVersion)
    }

    static func blockEntity(_ nbt: NBT, dataVersion: Int?) -> NBT {
        upgrade(nbt, as: .blockEntity, dataVersion: dataVersion)
    }

    static func player(_ nbt: NBT, dataVersion: Int?) -> NBT {
        upgrade(nbt, as: .player, dataVersion: dataVersion)
    }

    static func item(_ nbt: NBT, dataVersion: Int?) -> NBT {
        upgrade(nbt, as: .item, dataVersion: dataVersion)
    }

    private struct Names: Sendable {
        var block: [String: String] = [:]
        var item: [String: String] = [:]
        var biome: [String: String] = [:]
        var entity: [String: String] = [:]
        var blockEntity: [String: String] = [:]
        var itemBeforeFlattening: [String: String] = [:]
        var itemAfterFlattening: [String: String] = [:]
        let flattensItems: Bool
        let damageChanges: [String: [Int: Int]]

        init(after version: Int) {
            flattensItems = version < GeneratedSaveRenames.itemNameBoundary
            damageChanges = Dictionary(uniqueKeysWithValues: GeneratedSaveRenames.itemDamageChanges
                .filter { $0.version > version }.map { ($0.id, $0.changes) })
            for step in GeneratedSaveRenames.steps where step.version > version {
                switch step.kind {
                case .block: Self.append(step.changes, to: &block)
                case .item:
                    Self.append(step.changes, to: &item)
                    if flattensItems {
                        if step.version < GeneratedSaveRenames.itemNameBoundary {
                            Self.append(step.changes, to: &itemBeforeFlattening)
                        } else {
                            Self.append(step.changes, to: &itemAfterFlattening)
                        }
                    }
                case .biome: Self.append(step.changes, to: &biome)
                case .entity: Self.append(step.changes, to: &entity)
                case .blockEntity: Self.append(step.changes, to: &blockEntity)
                }
            }
            // DFU cannot apply a rename to a record whose name did not exist in its input
            // schema. This bounds individual aliases; it never decides which records we read.
            entity = entity.filter { version >= GeneratedSaveRenames.entityIntroductions[$0.key, default: -1] }
            blockEntity = blockEntity.filter { version >= GeneratedSaveRenames.blockEntityIntroductions[$0.key, default: -1] }
        }

        private static func append(_ changes: [String: String], to names: inout [String: String]) {
            // Apply each step simultaneously: A->B and B->C in one step must leave A as B.
            // Only a later step may take an earlier result further along the chain.
            for (original, current) in names {
                if let next = changes[current] { names[original] = next }
            }
            for (old, new) in changes where names[old] == nil { names[old] = new }
        }

        func renamed(_ value: NBT, kind: Kind, namespaced: Bool = true) -> NBT {
            guard let raw = value.string else { return value }
            let key = namespaced ? Identifier(raw)?.description ?? raw : raw
            let changed: String?
            switch kind {
            case .block: changed = block[key]
            case .item: changed = item[key]
            case .biome: changed = biome[key]
            case .entity: changed = entity[key]
            case .blockEntity: changed = blockEntity[key]
            }
            return changed.map(NBT.string) ?? value
        }

        func itemName(in fields: [String: NBT]) -> NBT? {
            guard let value = fields["id"] else { return nil }
            guard flattensItems, let raw = value.string else { return renamed(value, kind: .item) }
            let identifier = Identifier(raw)?.description ?? raw
            let before = itemBeforeFlattening[identifier] ?? identifier
            let variants = GeneratedSaveRenames.itemNames[before]
            let savedDamage = Self.damage(fields["Damage"])
            let damage = damageChanges[before]?[savedDamage] ?? savedDamage
            let flattened = variants?[damage] ?? variants?[0] ?? before
            let after = itemAfterFlattening[flattened] ?? flattened
            return after == identifier ? value : .string(after)
        }

        private static func damage(_ tag: NBT?) -> Int {
            // Dynamic.asInt(0) uses Number.intValue: integral values truncate to Int32,
            // floating values truncate toward zero with Java's saturation/NaN behavior.
            if let integer = tag?.int { return Int(Int32(truncatingIfNeeded: integer)) }
            guard let number = tag?.double else { return 0 }
            if number.isNaN { return 0 }
            if number >= Double(Int32.max) { return Int(Int32.max) }
            if number <= Double(Int32.min) { return Int(Int32.min) }
            return Int(number)
        }
    }

    private struct Plan: Sendable {
        let boundary: Int
        let names: Names
    }

    // A plan changes only at a generated fix boundary, not at every saved version. Swift's
    // immutable static initialization shares these bounded plans across concurrent readers.
    // The current-save fast path never initializes them or pays for their dictionaries.
    private static let plans: [Plan] = {
        let boundaries = Set(GeneratedSaveRenames.steps.map(\.version)
            + GeneratedSaveRenames.itemDamageChanges.map(\.version)
            + Array(GeneratedSaveRenames.entityIntroductions.values)
            + Array(GeneratedSaveRenames.blockEntityIntroductions.values)
            + [GeneratedSaveRenames.itemNameBoundary])
        return boundaries.sorted().map { Plan(boundary: $0, names: Names(after: $0 - 1)) }
    }()

    private static func names(after version: Int) -> Names {
        var lower = 0, upper = plans.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if plans[middle].boundary <= version { lower = middle + 1 }
            else { upper = middle }
        }
        // upgrade returns before this lookup at/after the final generated rename boundary.
        return plans[lower].names
    }

    private enum Shape {
        case chunk, sections, section, blockPalette, biomePalette, blockStates, biomes
        case blockState, biome, item, items, itemTag, components, componentContainers, componentContainer
        case equipment, entity, player, blockEntity, blockEntities, offers, trades, trade
        case potDecorations, potSide, itemNames
        case entityTree, entityTrees, spawnData, spawnPotentials, spawnPotential, bees, bee
    }

    private enum Work {
        case visit(NBT, Shape)
        case compound([String: NBT], [String])
        case list(NBTTagType, Int)
    }

    private static func upgrade(_ nbt: NBT, as shape: Shape, dataVersion: Int?) -> NBT {
        // Missing versions have the game's oldest-save meaning. Current/newer files return
        // before allocating a traversal or initializing the generated rename dictionaries.
        let version = dataVersion ?? -1
        guard version < GeneratedSaveRenames.lastVersion else { return nbt }
        let names = names(after: version)
        var work: [Work] = [.visit(nbt, shape)]
        var results: [NBT] = []
        // An explicit stack preserves arbitrarily nested saved contents without consuming the
        // thread's call stack. Only known format fields are visited; custom data/text is opaque.
        while let next = work.popLast() {
            switch next {
            case .list(let type, let count):
                let start = results.count - count
                let values = Array(results[start...])
                results.removeLast(count)
                results.append(.list(type, values))
            case .compound(var fields, let keys):
                let start = results.count - keys.count
                for (offset, key) in keys.enumerated() { fields[key] = results[start + offset] }
                results.removeLast(keys.count)
                results.append(.compound(fields))
            case .visit(let value, let shape):
                if let child = listElement(shape), case .list(let type, let entries) = value {
                    work.append(.list(type, entries.count))
                    for entry in entries.reversed() { work.append(.visit(entry, child)) }
                    continue
                }
                if shape == .biome, value.string != nil {
                    results.append(names.renamed(value, kind: .biome)); continue
                }
                if shape == .potSide, value.string != nil {
                    results.append(names.renamed(value, kind: .item)); continue
                }
                if shape == .blockState, value.string != nil {
                    results.append(names.renamed(value, kind: .block)); continue
                }
                guard var fields = value.compound else { results.append(value); continue }
                switch shape {
                case .entity, .entityTree:
                    if let id = fields["id"] { fields["id"] = names.renamed(id, kind: .entity) }
                case .spawnData:
                    if fields["entity"] == nil, let id = fields["id"] {
                        fields["id"] = names.renamed(id, kind: .entity)
                    }
                case .blockEntity:
                    if let id = fields["id"] { fields["id"] = names.renamed(id, kind: .blockEntity) }
                case .item:
                    fields["id"] = names.itemName(in: fields)
                case .potSide:
                    if let id = fields["id"] { fields["id"] = names.renamed(id, kind: .item) }
                case .blockState:
                    // LegacyBlockRenameFix reads a state's Name literally; its separate
                    // BLOCK_NAME codec is what supplies a missing namespace for bare strings.
                    if let id = fields["Name"] { fields["Name"] = names.renamed(id, kind: .block, namespaced: false) }
                case .biome:
                    for key in ["id", "Name"] where fields[key] != nil {
                        fields[key] = names.renamed(fields[key]!, kind: .biome)
                    }
                default: break
                }
                let children: [(String, Shape)]
                if shape == .equipment {
                    children = fields.keys.sorted().map { ($0, .item) }
                } else {
                    children = childFields(shape).filter { fields[$0.0] != nil }
                }
                work.append(.compound(fields, children.map(\.0)))
                for (key, child) in children.reversed() { work.append(.visit(fields[key]!, child)) }
            }
        }
        return results[0]
    }

    private static func listElement(_ shape: Shape) -> Shape? {
        switch shape {
        case .sections: .section
        case .blockStates: .blockState
        case .biomes: .biome
        case .items: .item
        case .blockEntities: .blockEntity
        case .componentContainers: .componentContainer
        case .trades: .trade
        case .potDecorations, .itemNames: .potSide
        case .entityTrees: .entityTree
        case .spawnPotentials: .spawnPotential
        case .bees: .bee
        default: nil
        }
    }

    private static func childFields(_ shape: Shape) -> [(String, Shape)] {
        switch shape {
        case .chunk: [("sections", .sections)]
        case .section: [("block_states", .blockPalette), ("biomes", .biomePalette)]
        case .blockPalette: [("palette", .blockStates)]
        case .biomePalette: [("palette", .biomes)]
        case .item, .potSide: [("tag", .itemTag), ("components", .components)]
        case .itemTag:
            [("BlockEntityTag", .blockEntity), ("EntityTag", .entityTree),
             ("Items", .items), ("ChargedProjectiles", .items)]
        case .components:
            [("minecraft:container", .componentContainers), ("minecraft:bundle_contents", .items),
             ("minecraft:charged_projectiles", .items), ("minecraft:use_remainder", .item),
             ("minecraft:pot_decorations", .potDecorations), ("minecraft:entity_data", .entityTree),
             ("minecraft:block_entity_data", .blockEntity), ("minecraft:bees", .bees)]
        case .componentContainer: [("item", .item)]
        case .blockEntity:
            [("Items", .items), ("item", .item), ("Book", .item), ("RecordItem", .item),
             ("sherds", .itemNames), ("shards", .itemNames), ("SpawnData", .spawnData),
             ("SpawnPotentials", .spawnPotentials), ("Bees", .bees), ("bees", .bees)]
        case .entity, .player:
            // These saved formats are shared by vanilla and custom entities. Type catalogs do
            // not decide which readable inventory/equipment fields the existing readers retain.
            [("Items", .items), ("Inventory", .items), ("EnderItems", .items),
             ("ArmorItems", .items), ("HandItems", .items), ("equipment", .equipment),
             ("Item", .item), ("item", .item), ("body_armor_item", .item), ("ArmorItem", .item),
             ("DecorItem", .item), ("saddle", .item), ("SaddleItem", .item),
             ("SelectedItem", .item), ("Offers", .offers)]
        case .entityTree: childFields(.entity) + [("Passengers", .entityTrees)]
        case .spawnData: childFields(.entityTree) + [("entity", .entityTree)]
        case .spawnPotential: [("Entity", .entityTree), ("data", .spawnData)]
        case .bee: [("EntityData", .entityTree), ("entity_data", .entityTree)]
        case .offers: [("Recipes", .trades)]
        case .trade: [("buy", .item), ("buyB", .item), ("sell", .item)]
        case .potDecorations: [("back", .potSide), ("left", .potSide), ("right", .potSide), ("front", .potSide)]
        default: []
        }
    }
}
