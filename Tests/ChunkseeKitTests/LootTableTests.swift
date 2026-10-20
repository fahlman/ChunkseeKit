import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct LootTableTests {
    @Test(arguments: [false, true])
    func unopenedAndOpenedContainersKeepTheSavedLootTable(isEntity: Bool) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let region = RegionPosition(x: -1, z: 0)
        let table = isEntity ? "minecraft:chests/abandoned_mineshaft" : "minecraft:chests/simple_dungeon"
        var container: [String: NBT] = ["id": .string(isEntity ? "minecraft:chest_minecart" : "minecraft:chest")]
        if isEntity { container["Pos"] = .list([.double(-2.5), .double(63.5), .double(4.5)]) }
        else { container.merge(["x": .int(-3), "y": .int(63), "z": .int(4)]) { $1 } }

        // An unopened container, the same container after opening, then after taking its items.
        for stage in 0..<3 {
            container["LootTable"] = stage == 0 ? .string(table) : nil
            container["Items"] = stage == 1 ? .list([.compound([
                "id": .string("minecraft:diamond"), "count": .int(2),
            ])]) : nil
            let nbt: NBT
            if isEntity { nbt = .compound(["DataVersion": .int(5023), "Entities": .list([.compound(container)])]) }
            else { nbt = Fixtures.chunk(x: -1, z: 0, dataVersion: 5023, sections: [], extra: [
                "status": .string("minecraft:full"), "block_entities": .list([.compound(container)]),
            ]) }
            try Fixtures.write(Fixtures.region([.init(localX: 31, localZ: 0, nbt: nbt)]),
                               to: dimension.regionURL(isEntity ? .entities : .terrain, at: region))
            let facts = try dimension.scan(region: region)
            let direct = try dimension.containers(regionX: -1, regionZ: 0)
            #expect(facts.containers == direct)
            if stage == 2 { #expect(direct.isEmpty); continue }
            let value = try #require(direct.first)
            #expect(value.isEntity == isEntity && value.x == -3 && value.y == 63 && value.z == 4)
            #expect(value.lootTable == (stage == 0 ? table : nil))
            #expect(value.isSealedLoot == (stage == 0))
            #expect(value.items.count == (stage == 1 ? 1 : 0))
            let decoded = try PropertyListDecoder().decode(RegionFacts.self, from: PropertyListEncoder().encode(facts))
            #expect(decoded.containers == direct)
        }
    }

    @Test func earlierStandaloneContainerArchivesDecodeWithoutInventingATable() throws {
        let container = ItemContainer(kind: "minecraft:chest", x: 0, y: 64, z: 0, items: [],
                                      customName: nil, lootTable: "minecraft:chests/buried_treasure",
                                      isSealedLoot: true, isEntity: false)
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(container)) as? [String: Any])
        old.removeValue(forKey: "lootTable")
        let decoded = try JSONDecoder().decode(ItemContainer.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.lootTable == nil && decoded.isSealedLoot && decoded.items.isEmpty)
    }
}
