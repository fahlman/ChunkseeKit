import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct MobAppearanceTraitsTests {
    private func mob(_ id: String, _ fields: [String: NBT]) -> NBT {
        Fixtures.mob(["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)]),
                      "Health": .float(7)].merging(fields) { $1 })
    }

    @Test func rabbitCodesIncludeTheNoncontiguousKillerRabbit() throws {
        let variants = [0: "brown", 1: "white", 2: "black", 3: "white_splotched", 4: "gold", 5: "salt", 99: "evil"]
        for (code, variant) in variants {
            let rabbit = try #require(Creature(mob("minecraft:rabbit", ["RabbitType": .int(Int32(code))]), dataVersion: 999999))
            #expect(rabbit.appearance == CreatureAppearance(variant: "minecraft:" + variant))
        }
        #expect(Creature(mob("minecraft:rabbit", ["RabbitType": .int(6)]))?.appearance == nil)
    }

    @Test func tropicalFishPatternsAndBothDyesAreIndependent() throws {
        // Independent save-format expectations, including both body sizes and all color pairs.
        let patterns = [0: "kob", 256: "sunstreak", 512: "snooper", 768: "dasher", 1024: "brinely", 1280: "spotty",
                        1: "flopper", 257: "stripey", 513: "glitter", 769: "blockfish", 1025: "betty", 1281: "clayfish"]
        let colors = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                      "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]
        for (code, pattern) in patterns {
            for (base, baseName) in colors.enumerated() {
                for (marking, markingName) in colors.enumerated() {
                    let packed = Int32(code | base << 16 | marking << 24)
                    let fish = try #require(Creature(mob("minecraft:tropical_fish", ["Variant": .int(packed)])))
                    #expect(fish.appearance == CreatureAppearance(variant: "minecraft:" + pattern, traits: [
                        "body_shape": code & 255 == 0 ? "small" : "large",
                        "base_color": baseName, "pattern_color": markingName]))
                }
            }
        }
    }

    @Test func partialPackedAppearancesKeepEveryInterpretablePart() throws {
        let unknownPattern = try #require(Creature(mob("minecraft:tropical_fish", ["Variant": .int(0x0e0b7f00)])))
        #expect(unknownPattern.appearance == CreatureAppearance(traits: [
            "body_shape": "small", "base_color": "blue", "pattern_color": "red"]))
        let unknownBodyAndBase = try #require(Creature(mob("minecraft:tropical_fish", ["Variant": .int(0x0eff0002)])))
        #expect(unknownBodyAndBase.appearance == CreatureAppearance(traits: ["pattern_color": "red"]))
        let negative = try #require(Creature(mob("minecraft:tropical_fish", ["Variant": .int(Int32(bitPattern: 0xff0b0001))])))
        #expect(negative.appearance == CreatureAppearance(variant: "minecraft:flopper", traits: [
            "body_shape": "large", "base_color": "blue"]))
        #expect(negative.health == 7 && negative.owner == nil)
        #expect(Creature(mob("minecraft:tropical_fish", ["Variant": .long(Int64.max)]))?.appearance == nil)
        let horse = try #require(Creature(mob("minecraft:horse", ["Variant": .int(99 + 3 * 256)])))
        #expect(horse.appearance == CreatureAppearance(markings: "minecraft:white_dots"))
    }

    @Test func savedStringStylesAndVillagerProjectionDoNotUseValueInventories() throws {
        for id in ["minecraft:fox", "minecraft:mooshroom"] {
            let creature = try #require(Creature(mob(id, ["Type": .string("example:future_style")]), dataVersion: 999999))
            #expect(creature.appearance?.variant == "example:future_style")
        }
        for id in ["minecraft:villager", "minecraft:zombie_villager", "example:trader"] {
            let creature = try #require(Creature(mob(id, ["VillagerData": .compound(["type": .string("example:wetland")])])))
            #expect(creature.appearance?.variant == creature.villager?.type)
            #expect(creature.appearance?.variant == "example:wetland")
        }
        // A generic Type field has no established appearance meaning on an unfamiliar format.
        #expect(Creature(mob("example:new_mob", ["Type": .string("unrelated")]))?.appearance == nil)
        #expect(Creature(mob("minecraft:fox", ["Type": .string("")]))?.appearance == nil)
        let preferred = Creature(mob("minecraft:fox", ["variant": .string("example:new"), "Type": .string("red")]))
        #expect(preferred?.appearance?.variant == "example:new")
    }

    @Test func pandaLooksFollowGeneDominanceWhileKeepingUnknownGenes() throws {
        let genes = ["normal", "lazy", "worried", "playful", "brown", "weak", "aggressive"]
        for main in genes {
            for hidden in genes {
                let panda = try #require(Creature(mob("minecraft:panda", ["MainGene": .string(main), "HiddenGene": .string(hidden)])))
                let visible = ["brown", "weak"].contains(main) && main != hidden ? "normal" : main
                #expect(panda.appearance == CreatureAppearance(variant: "minecraft:" + visible,
                    traits: ["main_gene": main, "hidden_gene": hidden]))
            }
        }
        for id in ["minecraft:panda", "example:gene_bearing_mob"] {
            let partial = try #require(Creature(mob(id, ["HiddenGene": .string("example:future")])))
            #expect(partial.appearance == CreatureAppearance(traits: ["hidden_gene": "example:future"]))
            let unknownHidden = try #require(Creature(mob(id, ["MainGene": .string("brown"), "HiddenGene": .string("example:future")])))
            #expect(unknownHidden.appearance == CreatureAppearance(traits: ["main_gene": "brown", "hidden_gene": "example:future"]))
            let dominant = try #require(Creature(mob(id, ["MainGene": .string("lazy")])))
            #expect(dominant.appearance == CreatureAppearance(variant: "minecraft:lazy", traits: ["main_gene": "lazy"]))
            let unknownMain = try #require(Creature(mob(id, ["MainGene": .string("future"), "HiddenGene": .string("normal")])))
            #expect(unknownMain.appearance == CreatureAppearance(traits: ["main_gene": "future", "hidden_gene": "normal"]))
        }
    }

    @Test func publicRegionScanAndArchivesRetainPartialAppearance() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Traits")])]),
                                    to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let entities = [mob("minecraft:rabbit", ["RabbitType": .int(99)]),
                        mob("minecraft:fox", ["Type": .string("snow")]),
                        mob("minecraft:mooshroom", ["Type": .string("brown")]),
                        mob("minecraft:panda", ["HiddenGene": .string("future")]),
                        mob("minecraft:tropical_fish", ["Variant": .int(0x0e0b7f00)]),
                        mob("minecraft:zombie_villager", ["VillagerData": .compound(["type": .string("minecraft:desert")])])]
        let region = RegionPosition(x: 0, z: 0)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound(["Entities": .list(entities)]))]),
                           to: dimension.regionURL(.entities, at: region))
        let creatures = try dimension.creatures(chunkX: 0, chunkZ: 0)
        #expect(creatures.count == 6 && creatures.allSatisfy { $0.appearance != nil })
        let facts = try dimension.scan(region: region)
        #expect(facts.creatures == creatures)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.creatures == creatures)
        let old = try JSONDecoder().decode(CreatureAppearance.self, from: Data(#"{"variant":"minecraft:pale"}"#.utf8))
        #expect(old == CreatureAppearance(variant: "minecraft:pale"))
    }
}
