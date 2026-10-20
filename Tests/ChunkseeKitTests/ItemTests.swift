import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct ItemTests {
    func item(_ id: String, _ count: Int32, slot: Int8? = nil, components: [String: NBT]? = nil) -> NBT {
        var c: [String: NBT] = ["id": .string(id), "count": .int(count)]
        if let slot { c["Slot"] = .byte(slot) }
        if let components { c["components"] = .compound(components) }
        return .compound(c)
    }

    @Test func currentFormatWithShulkerAndBundleContents() throws {
        let shulker = item("minecraft:shulker_box", 1, slot: 3, components: [
            "minecraft:custom_name": .string("Valuables"),
            "minecraft:container": .list([.compound(["slot": .int(0), "item": item("minecraft:diamond", 64)])]),
        ])
        let stack = try #require(ItemStack(shulker))
        #expect(stack.slot == 3 && stack.customName == "Valuables")
        #expect(stack.contents.map(\.id) == ["minecraft:diamond"])
        #expect(stack.allItems.map(\.count) == [1, 64])
        let bundle = try #require(ItemStack(item("minecraft:bundle", 1, components: ["minecraft:bundle_contents": .list([item("minecraft:emerald", 5)])])))
        #expect(bundle.contents.first?.count == 5)
        #expect(ItemStack(item("minecraft:air", 1)) == nil)
    }

    @Test func legacyFormatAndTextComponents() throws {
        let legacy = NBT.compound(["id": .string("minecraft:chest"), "Count": .byte(2), "Slot": .byte(1), "tag": .compound([
            "display": .compound(["Name": .string(#"{"text":"Old ","extra":[{"text":"Box"}]}"#)]),
            "BlockEntityTag": .compound(["Items": .list([.compound(["id": .string("minecraft:gold_ingot"), "Count": .byte(9)])])]),
        ])])
        let stack = try #require(ItemStack(legacy))
        #expect(stack.count == 2 && stack.customName == "Old Box" && stack.contents.first?.count == 9)
        #expect(TextComponent.plainText(.compound(["text": .string("A"), "extra": .list([.string("B")])])) == "AB")
        #expect(TextComponent.plainText(.string("plain")) == "plain")
    }

    @Test func enchantmentsInEveryFormat() throws {
        func item(_ fields: [String: NBT]) throws -> ItemStack { try #require(ItemStack(.compound(fields))) }
        // 26.x and 1.21.5+: the map directly.
        let book = try item(["id": .string("minecraft:enchanted_book"), "count": .int(1), "components": .compound([
            "minecraft:stored_enchantments": .compound(["minecraft:mending": .int(1)])])])
        #expect(book.enchantments == ["minecraft:mending": 1])
        // 1.20.5–1.21.4: wrapped in `levels`, beside `show_in_tooltip`.
        let sword = try item(["id": .string("minecraft:diamond_sword"), "count": .int(1), "components": .compound([
            "minecraft:enchantments": .compound(["levels": .compound(["minecraft:sharpness": .int(5), "minecraft:looting": .int(3)]),
                                                 "show_in_tooltip": .byte(0)])])])
        #expect(sword.enchantments == ["minecraft:sharpness": 5, "minecraft:looting": 3])
        // Before 1.20.5: lists of {id, lvl} in the tag.
        let legacy = try item(["id": .string("minecraft:enchanted_book"), "Count": .byte(1), "tag": .compound([
            "StoredEnchantments": .list([.compound(["id": .string("minecraft:unbreaking"), "lvl": .short(3)])])])])
        #expect(legacy.enchantments == ["minecraft:unbreaking": 3])
        #expect(try item(["id": .string("minecraft:torch"), "count": .int(4)]).enchantments.isEmpty)
    }

    @Test func containersFromBlockEntitiesAndEntities() {
        let chunk = NBT.compound(["block_entities": .list([
            .compound(["id": .string("minecraft:chest"), "x": .int(1), "y": .int(64), "z": .int(2), "Items": .list([item("minecraft:wheat", 8, slot: 0)])]),
            .compound(["id": .string("minecraft:chest"), "x": .int(5), "y": .int(40), "z": .int(5), "LootTable": .string("minecraft:chests/simple_dungeon")]),
            .compound(["id": .string("minecraft:lectern"), "x": .int(9), "y": .int(64), "z": .int(9), "Book": item("minecraft:written_book", 1)]),
            .compound(["id": .string("minecraft:sign"), "x": .int(0), "y": .int(64), "z": .int(0)]),
        ])])
        let blocks = ItemContainer.containers(inChunk: chunk)
        #expect(blocks.map(\.kind) == ["minecraft:chest", "minecraft:chest", "minecraft:lectern"])
        #expect(blocks[1].isSealedLoot && blocks[1].items.isEmpty)
        #expect(blocks[1].lootTable == "minecraft:chests/simple_dungeon")
        #expect(blocks[0].lootTable == nil && !blocks[0].isSealedLoot)
        #expect(blocks[2].items.first?.id == "minecraft:written_book")

        let entities = NBT.compound(["Entities": .list([
            .compound(["id": .string("minecraft:chest_minecart"), "Pos": .list([.double(-10.5), .double(30), .double(4.2)]), "Items": .list([item("minecraft:rail", 16)])]),
            .compound(["id": .string("minecraft:item_frame"), "Pos": .list([.double(1), .double(2), .double(3)]), "Item": item("minecraft:map", 1)]),
            .compound(["id": .string("minecraft:item"), "Pos": .list([.double(0), .double(0), .double(0)]), "Item": item("minecraft:dirt", 1)]),
        ])])
        let moving = ItemContainer.containers(inEntityChunk: entities)
        #expect(moving.map(\.kind) == ["minecraft:chest_minecart", "minecraft:item_frame"])
        #expect((moving[0].x, moving[0].y, moving[0].z) == (-11, 30, 4) && moving[0].isEntity)
    }

    @Test(arguments: ["nan", "infinity", "negative infinity", "out of range"])
    func invalidContainerPositionsDoNotDiscardOtherContainersInTheRegion(_ value: String) throws {
        let invalid: Double = switch value {
        case "nan": .nan
        case "infinity": .infinity
        case "negative infinity": -.infinity
        default: .greatestFiniteMagnitude
        }
        func container(_ kind: String, at pos: [NBT]) -> NBT {
            var fields: [String: NBT] = ["id": .string(kind), "Pos": .list(pos)]
            switch kind {
            case "minecraft:item_frame": fields["Item"] = item("minecraft:map", 1)
            case "minecraft:chest_minecart": fields["LootTable"] = .string("minecraft:chests/abandoned_mineshaft")
            default: fields["Items"] = .list([item("minecraft:diamond", 2)])
            }
            return .compound(fields)
        }
        var entities: [NBT] = []
        for axis in 0..<3 {
            var pos: [NBT] = [.double(-0.1), .double(63.9), .double(-16.1)]
            pos[axis] = .double(invalid)
            for kind in ["minecraft:donkey", "minecraft:item_frame", "minecraft:chest_minecart"] {
                entities.append(container(kind, at: pos))
            }
        }
        entities += [
            container("minecraft:donkey", at: [.string("x"), .string("y"), .string("z")]),
            container("minecraft:donkey", at: [.double(1), .double(2), .double(3), .double(4)]),
            container("minecraft:donkey", at: [.double(-0.1), .double(63.9), .double(-16.1)]),
            container("minecraft:chest_minecart", at: [.double(2.2), .double(-0.1), .double(3.4)]),
        ]
        let nbt = NBT.compound(["Entities": .list(entities)])
        let parsed = ItemContainer.containers(inEntityChunk: nbt)
        #expect(parsed.count == 2)
        #expect(parsed.first.map { [$0.x, $0.y, $0.z] } == [-1, 63, -17])
        #expect(parsed.first?.allItems.first?.id == "minecraft:diamond")
        #expect(parsed.last.map { [$0.x, $0.y, $0.z] } == [2, -1, 3])
        #expect(parsed.last?.isSealedLoot == true)
        #expect(parsed.last?.lootTable == "minecraft:chests/abandoned_mineshaft")

        let url = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Coordinates")])]),
                                     to: url.appendingPathComponent("level.dat"))
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]),
                           to: url.appendingPathComponent("dimensions/minecraft/overworld/entities/r.0.0.mca"))
        let dimension = try #require(try World(contentsOf: url).dimension("overworld"))
        #expect(try dimension.contents(regionX: 0, regionZ: 0).containers == parsed)
    }

    @Test func playerInventoryEquipmentAndEnderChest() {
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Inventory": .list([item("minecraft:elytra", 1, slot: 5)]),
            "EnderItems": .list([item("minecraft:netherite_ingot", 4, slot: 0)]),
            "equipment": .compound(["head": item("minecraft:turtle_helmet", 1)]),
        ]))
        #expect(player.inventory.map(\.id) == ["minecraft:elytra"])
        #expect(player.enderChest.first?.count == 4)
        #expect(player.equipment["head"]?.id == "minecraft:turtle_helmet")
    }

    @Test func legacyArmorSlotsAreEquipmentNotInventory() {
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Inventory": .list([item("minecraft:torch", 64, slot: 0), item("minecraft:iron_boots", 1, slot: 100),
                                item("minecraft:diamond_helmet", 1, slot: 103), item("minecraft:shield", 1, slot: -106)]),
        ]))
        #expect(player.inventory.map(\.id) == ["minecraft:torch"])
        #expect(player.equipment.mapValues(\.id) == ["feet": "minecraft:iron_boots", "head": "minecraft:diamond_helmet", "offhand": "minecraft:shield"])
    }

    @Test func spawnersAndTheirMobs() {
        let chunk = NBT.compound(["block_entities": .list([
            .compound(["id": .string("minecraft:mob_spawner"), "x": .int(-5252), "y": .int(-27), "z": .int(-5731),
                       "SpawnData": .compound(["entity": .compound(["id": .string("minecraft:zombie")])])]),
            .compound(["id": .string("minecraft:mob_spawner"), "x": .int(1), "y": .int(2), "z": .int(3), "SpawnData": .compound([:])]),
            .compound(["id": .string("minecraft:trial_spawner"), "x": .int(4), "y": .int(5), "z": .int(6)]),
            .compound(["id": .string("minecraft:chest"), "x": .int(7), "y": .int(8), "z": .int(9)]),
        ])])
        #expect(Spawner.spawners(inChunk: chunk) == [Spawner(x: -5252, y: -27, z: -5731, mob: "minecraft:zombie"),
                                                    Spawner(x: 1, y: 2, z: 3, mob: nil)])   // an empty spawner
    }
}
