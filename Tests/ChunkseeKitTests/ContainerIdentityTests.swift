import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct ContainerIdentityTests {
    private func cart(_ identity: [String: NBT], x: Double = -0.5) -> NBT {
        .compound(identity.merging([
            "id": .string("minecraft:chest_minecart"),
            "Pos": .list([.double(x), .double(30), .double(2)]),
            "LootTable": .string("minecraft:chests/abandoned_mineshaft"),
        ]) { _, required in required })
    }

    @Test func colocatedCartsKeepSavedIdentityAcrossMovementAndUUIDFormats() throws {
        let first = UUID(uuidString: "00000001-0000-0002-0000-000300000004")!
        let second = UUID(uuidString: "00000005-0000-0006-0000-000700000008")!
        let modern: [String: NBT] = ["UUID": .intArray([1, 2, 3, 4])]
        let legacy: [String: NBT] = ["UUIDMost": .long(0x0000000500000006), "UUIDLeast": .long(0x0000000700000008)]
        func read(_ entities: [NBT]) -> [ItemContainer] {
            ItemContainer.containers(inEntityChunk: .compound(["Entities": .list(entities)]))
        }
        let before = read([cart(modern), cart(legacy)])
        #expect(before.map(\.uuid) == [first, second])
        #expect(before.allSatisfy { $0.x == -1 && $0.y == 30 && $0.z == 2 && $0.isSealedLoot })
        // Movement and a different saved encoding do not replace the entity's identity.
        let after = read([cart(["UUID": .string(second.uuidString)], x: 18.5), cart(modern)])
        #expect(after.map(\.uuid) == [second, first])
        #expect(after.map(\.x) == [18, -1])
        let restored = try JSONDecoder().decode([ItemContainer].self, from: JSONEncoder().encode(after))
        #expect(restored == after)
    }

    @Test func missingIdentitiesStayUnavailableAndOldContainerCachesStillDecode() throws {
        let entities = [cart([:]), cart(["UUID": .intArray([1, 2])]), cart(["UUID": .string("broken")])]
        let containers = ItemContainer.containers(inEntityChunk: .compound(["Entities": .list(entities)]))
        #expect(containers.count == 3 && containers.allSatisfy { $0.uuid == nil && $0.isEntity })
        // A UUID-shaped field on a block does not turn a fixed block container into an entity.
        let blocks = ItemContainer.containers(inChunk: .compound(["block_entities": .list([
            .compound(["id": .string("minecraft:chest"), "x": .int(1), "y": .int(30), "z": .int(2),
                       "LootTable": .string("minecraft:chests/simple_dungeon"), "UUID": .intArray([1, 2, 3, 4])]),
        ])]))
        let block = try #require(blocks.first)
        #expect(block.uuid == nil && !block.isEntity)
        let identified = try #require(ItemContainer.containers(inEntityChunk: .compound([
            "Entities": .list([cart(["UUID": .intArray([1, 2, 3, 4])])]),
        ])).first)
        let data = try JSONEncoder().encode(identified)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "uuid")
        let decoded = try JSONDecoder().decode(ItemContainer.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.uuid == nil && decoded.isEntity && decoded.isSealedLoot)
        #expect(decoded.lootTable == identified.lootTable && decoded.x == identified.x)
    }
}
