import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct TypedSaveTests {
    @Test(arguments: [-513, -512, -17, -16, -1, 0, 15, 16, 511, 512])
    func containingChunksAndRegionsPreserveNegativeBoundaries(_ x: Int) throws {
        let block = BlockPosition(blockX: x, blockY: 73, blockZ: -x)
        #expect(block.chunk.x == Int(floor(Double(x) / 16)))
        #expect(block.region.z == Int(floor(Double(-x) / 512)))
        let origin = try #require(block.chunk.blockOrigin)
        #expect((0..<16).contains(block.x - origin.x))
        #expect((0..<16).contains(block.z - origin.z))
        let regionStart = try #require(block.region.chunkOrigin)
        #expect(regionStart.x + block.chunk.localX == block.chunk.x)
        #expect(regionStart.z + block.chunk.localZ == block.chunk.z)
        #expect(ChunkPosition(containing: block) == block.chunk)
        #expect(RegionPosition(containing: block.chunk) == block.region)
    }

    @Test func enormousOriginsAreUnavailableAndIntegerConstructionKeepsPrecision() throws {
        let block = BlockPosition(blockX: .max, blockY: .min, blockZ: .min)
        #expect(block.x == Int.max && block.y == Int.min)
        #expect(ChunkPosition(x: .max, z: 0).blockOrigin == nil)
        #expect(RegionPosition(x: 0, z: .min).chunkOrigin == nil)
        #expect(RegionPosition(x: .max, z: 0).blockOrigin == nil)
        let decoded = try JSONDecoder().decode(BlockPosition.self, from: JSONEncoder().encode(block))
        #expect(decoded == block)
        let exact = PlayerInfo.Location(dimension: "minecraft:overworld", x: -8.7, y: 63.9, z: -513.1)
        #expect(exact.x == -8.7)
        #expect(exact.blockPosition == BlockPosition(blockX: -9, blockY: 63, blockZ: -514))
        #expect(PlayerInfo.Location(dimension: "minecraft:overworld", x: .nan, y: 0, z: 0).blockPosition == nil)
    }

    @Test(arguments: [("stone", "minecraft:stone"), (":stone", "minecraft:stone"),
                      ("mod_a:deep/caves", "mod_a:deep/caves"), ("", "minecraft:"),
                      ("minecraft:", "minecraft:"), ("mod-1:./a_2", "mod-1:./a_2")])
    func identifiersUseTheGameNamespaceAndCharacterRules(_ source: String, _ expected: String) throws {
        let id = try #require(Identifier(source))
        #expect(id.description == expected)
        #expect(try JSONDecoder().decode(Identifier.self, from: JSONEncoder().encode(id)) == id)
        #expect(Identifier(namespace: "", path: "stone") == Identifier("stone"))
    }

    @Test(arguments: ["Minecraft:stone", "minecraft:Stone", "a:b:c", "stone block", "m:é", "../:x", "..:x", "m:a\\b"])
    func malformedIdentifiersAreRejectedByTheirConsumers(_ source: String) throws {
        #expect(Identifier(source) == nil)
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "Dimension": .string(source), "Pos": .list([.double(1), .double(2), .double(3)]),
        ]))
        #expect(player.position == nil && player.unrecognizedDimension == source)
        #expect(StatusEffect(.compound(["id": .string(source), "duration": .int(20)])) == nil)
        let data = try JSONEncoder().encode(source)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Identifier.self, from: data) }
    }

    @Test func blockPositionReadersKeepTheirDifferentFormats() throws {
        let point: NBT = .intArray([-9, 63, -17])
        #expect(point.blockPosition == BlockPosition(blockX: -9, blockY: 63, blockZ: -17))
        for invalid in [NBT.intArray([1, 2]), .intArray([1, 2, 3, 4]), .list([.int(1), .int(2), .int(3)]),
                        .compound(["x": .int(1), "y": .int(2), "z": .int(3)])] {
            #expect(invalid.blockPosition == nil)
        }
        let position: [String: NBT] = ["x": .int(-9), "y": .int(63), "z": .int(-17)]
        var sign = position
        sign["id"] = .string("minecraft:sign"); sign["Text1"] = .string("hello")
        var chest = position
        chest["id"] = .string("minecraft:chest"); chest["LootTable"] = .string("minecraft:chests/simple_dungeon")
        var spawner = position
        spawner["id"] = .string("minecraft:mob_spawner")
        spawner["SpawnData"] = .compound(["entity": .compound(["id": .string("minecraft:zombie")])])
        let entities = [sign, chest, spawner].map(NBT.compound)
        let modern = NBT.compound(["block_entities": .list(entities)])
        #expect(Sign.signs(inChunk: modern).first?.x == -9)
        #expect(ItemContainer.containers(inChunk: modern).first?.y == 63)
        #expect(Spawner.spawners(inChunk: modern).first?.z == -17)
        let malformed = NBT.compound(["block_entities": .list([.compound(["id": .string("minecraft:mob_spawner"), "x": .int(1)])] + entities)])
        #expect(Spawner.spawners(inChunk: malformed).count == 1)
        let legacy = NBT.compound(["Level": .compound(["TileEntities": .list(entities)])])
        #expect(Sign.signs(inChunk: legacy).first?.x == -9)
        #expect(ItemContainer.containers(inChunk: legacy).first?.y == 63)
        #expect(Spawner.spawners(inChunk: legacy).first?.z == -17)
    }

}
