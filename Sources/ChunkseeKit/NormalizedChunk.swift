/// Field selection is separate from terrain validation. A bad section must not hide readable
/// records, and a records-only read must not interpret sections it deliberately skipped.
struct SavedChunkFields: Sendable {
    let dataVersion: Int?
    let blockEntities: [NBT]
    let permitsContainers: Bool
    let embeddedEntityChunk: NBT?
    let inhabitedTime: Int?
    let structureStarts: NBT?

    init(_ nbt: NBT) {
        dataVersion = nbt["DataVersion"]?.int
        let rootBlocks = nbt["block_entities"]
        blockEntities = rootBlocks?.list ?? nbt["Level"]?["TileEntities"]?.list ?? []
        // Containers historically use presence fallback; signs and spawners use list fallback.
        // Keep that distinction until the field-codec audit establishes a different game rule.
        permitsContainers = rootBlocks == nil || rootBlocks?.list != nil
        if let entities = nbt["Level"]?["Entities"] ?? nbt["entities"] {
            var fields: [String: NBT] = ["Entities": entities]
            fields["DataVersion"] = nbt["DataVersion"]
            embeddedEntityChunk = .compound(fields)
        } else {
            embeddedEntityChunk = nil
        }
        inhabitedTime = (nbt["InhabitedTime"]?.compoundLong
            ?? nbt["Level"]?["InhabitedTime"]?.compoundLong).map(Int.init)
        structureStarts = nbt["structures"]?["starts"] ?? nbt["Level"]?["Structures"]?["Starts"]
    }

    var containerBlockEntities: [NBT] { permitsContainers ? blockEntities : [] }
}

/// Both views are immutable: text and spawner eligibility retain their saved-field semantics,
/// while item and entity identities use the game's generated upgrades exactly once.
struct NormalizedBlockEntities: Sendable {
    enum Upgrades: Sendable { case none, spawners, all }
    let saved: [NBT]
    let upgraded: [NBT]

    init(_ saved: [NBT], dataVersion: Int?, upgrades: Upgrades) {
        self.saved = saved
        switch upgrades {
        case .none:
            upgraded = saved
        case .spawners:
            // A spawner-only request does not walk unrelated, potentially large inventories.
            upgraded = saved.map {
                Self.isSpawner($0) ? SaveDataUpgrade.blockEntity($0, dataVersion: dataVersion) : $0
            }
        case .all:
            upgraded = SaveDataUpgrade.blockEntities(saved, dataVersion: dataVersion)
        }
    }

    static func isSpawner(_ entity: NBT) -> Bool {
        (entity["SpawnData"]?.compound != nil || entity["id"]?.string == "minecraft:mob_spawner")
            && entity.blockEntityPosition != nil
    }
}

struct NormalizedEntity: Sendable {
    let nbt: NBT

    init(_ saved: NBT, dataVersion: Int?) {
        nbt = SaveDataUpgrade.entity(saved, dataVersion: dataVersion)
    }
}

/// Flatten before upgrading so each passenger is visited once, preserving its own position.
struct NormalizedEntities: Sendable {
    let records: [NormalizedEntity]

    init(_ chunk: NBT) {
        self.init(chunk["Entities"]?.list ?? [], dataVersion: chunk["DataVersion"]?.int)
    }

    init(_ roots: [NBT] = [], dataVersion: Int? = nil) {
        records = EntityTraversal.flatten(roots).map { NormalizedEntity($0, dataVersion: dataVersion) }
    }
}

struct ChunkRecords: Sendable {
    struct Needs: OptionSet, Sendable {
        let rawValue: Int
        static let containers = Self(rawValue: 1 << 0)
        static let signs = Self(rawValue: 1 << 1)
        static let spawners = Self(rawValue: 1 << 2)
        static let creatures = Self(rawValue: 1 << 3)
        static let all: Self = [.containers, .signs, .spawners, .creatures]
    }

    let blocks: NormalizedBlockEntities
    let permitsContainers: Bool
    let entities: NormalizedEntities
    let inhabitedTime: Int?

    init(_ nbt: NBT, needs: Needs = .all) {
        let fields = SavedChunkFields(nbt)
        let readsBlocks = !needs.intersection([.containers, .signs, .spawners]).isEmpty
        let upgrades: NormalizedBlockEntities.Upgrades = needs.contains(.containers) && fields.permitsContainers
            ? .all : (needs.contains(.spawners) ? .spawners : .none)
        blocks = NormalizedBlockEntities(readsBlocks ? fields.blockEntities : [],
                                         dataVersion: fields.dataVersion, upgrades: upgrades)
        permitsContainers = fields.permitsContainers
        if !needs.intersection([.containers, .creatures]).isEmpty, let chunk = fields.embeddedEntityChunk {
            entities = NormalizedEntities(chunk)
        } else {
            entities = NormalizedEntities()
        }
        inhabitedTime = fields.inhabitedTime
    }
}

/// Layout and palette upgrades happen here; constructing Chunk only validates typed terrain.
/// Keep the original record view separate because legacy layout conversion can replace root
/// fields with Level fields. Raw record queries retain their established field precedence.
struct TerrainChunkInput: Sendable {
    let nbt: NBT
    let blockEntities: [BlockEntity]
    let inhabitedTime: Int?
    let structureStarts: NBT?
    let embeddedEntityChunk: NBT?

    init(_ saved: NBT, readingBlockEntities: Bool = true) {
        nbt = SaveDataUpgrade.chunk(saved)
        let fields = SavedChunkFields(nbt)
        let upgraded = readingBlockEntities
            ? SaveDataUpgrade.blockEntities(fields.containerBlockEntities, dataVersion: fields.dataVersion) : []
        blockEntities = upgraded.map(BlockEntity.init(nbt:))
        inhabitedTime = fields.inhabitedTime
        structureStarts = fields.structureStarts
        embeddedEntityChunk = fields.embeddedEntityChunk
    }
}

/// One interpretation for a complete chunk scan, with independent records available even when
/// the subsequent terrain validation fails. Nothing here reads another file or retains a world.
struct NormalizedChunk: Sendable {
    let records: ChunkRecords
    let terrain: TerrainChunkInput

    init(_ nbt: NBT) {
        records = ChunkRecords(nbt)
        // Region terrain facts need sections, metadata and structures. Their block/entity
        // records are already owned by records above, so terrain must not upgrade them again.
        terrain = TerrainChunkInput(nbt, readingBlockEntities: false)
    }
}
