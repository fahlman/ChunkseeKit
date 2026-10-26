import ChunkseeIndex
import ChunkseeKit
import Foundation
import Testing

@Suite struct CreatureEntryTests {
    @Test func categoryPrecedenceAndIdentityMatchExistingCreatureSelection() throws {
        let uuid = try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        var creature = Creature(id: "minecraft:wolf", x: -8.7, y: 62, z: 0)
        #expect(CreatureEntry(creature)?.group == .mob)
        creature.customName = "Summer"
        #expect(CreatureEntry(creature)?.group == .named)
        #expect(CreatureEntry(creature)?.id == "minecraft:wolf@-8.7,62.0,0.0")
        creature.owner = uuid
        #expect(CreatureEntry(creature)?.group == .pet)
        creature.villager = Villager(.compound(["VillagerData": .compound([
            "profession": .string("minecraft:farmer")])]))
        #expect(CreatureEntry(creature)?.group == .villager)
        creature.uuid = uuid
        let original = try #require(CreatureEntry(creature))
        creature.x = 512.5
        #expect(CreatureEntry(creature)?.id == original.id)
        #expect(original.id == "creature:00112233-4455-6677-8899-aabbccddeeff")
    }

    @Test func invalidLocationsAreExcludedWithoutTrapping() throws {
        let located = Creature(id: "minecraft:cat", x: -0.1, y: -64.5, z: 0, customName: "Cat")
        #expect(CreatureEntry(located)?.creature == located)
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max)] {
            var creature = located
            creature.x = value; #expect(CreatureEntry(creature) == nil)
            creature = located; creature.y = value; #expect(CreatureEntry(creature) == nil)
            creature = located; creature.z = value; #expect(CreatureEntry(creature) == nil)
        }
        var creature = located
        creature.x = Double(Int32.min); creature.z = Double(Int32.max) + 0.5
        #expect(CreatureEntry(creature) != nil)
        creature.x -= 0.5
        #expect(CreatureEntry(creature) == nil)
        creature.x = 0; creature.z = Double(Int32.max) + 1
        #expect(CreatureEntry(creature) == nil)
    }
}
