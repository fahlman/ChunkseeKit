import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct VillagerDataTests {
    @Test func wholeRecordFallbackFollowsTheEntityReader() throws {
        let inputs: [NBT?] = [nil, .string("not a compound"), .int(7), .list([])]
        for input in inputs {
            let normal = try #require(creature("minecraft:villager", data: input).villager)
            #expect(normal.profession == "minecraft:none" && normal.type == "minecraft:plains" && normal.level == 1)
            #expect(normal.savedData != nil && normal.savedData?.value == input)
            #expect(normal.savedData?.entityID == "minecraft:villager")

            let zombie = try #require(creature("minecraft:zombie_villager", data: input).villager)
            #expect(zombie.profession == nil && zombie.isUnemployed == nil)
            #expect(zombie.type == "minecraft:plains" && zombie.level == 1)
            #expect(zombie.savedData != nil && zombie.savedData?.value == input)
            #expect(zombie.supportsTrading(using: nil) == nil)
        }
        for id in ["minecraft:wandering_trader", "minecraft:cow", "example:new_mob"] {
            let mob = try creature(id, data: nil)
            #expect(mob.id == id && mob.villager == nil)
            let unreadable = try #require(creature(id, data: .string("unreadable")).villager)
            #expect(unreadable.profession == nil && unreadable.type == nil && unreadable.level == nil)
            #expect(unreadable.savedData?.value == .string("unreadable"))
        }
    }

    @Test func compoundDefaultsRetainTheReadablePartsAndOriginalFields() throws {
        let cases: [([String: NBT], String, String, Int)] = [
            ([:], "minecraft:none", "minecraft:plains", 1),
            (["profession": .string("minecraft:farmer")], "minecraft:farmer", "minecraft:plains", 1),
            (["type": .string("minecraft:desert")], "minecraft:none", "minecraft:desert", 1),
            (["profession": .int(7)], "minecraft:none", "minecraft:plains", 1),
            (["type": .int(7)], "minecraft:none", "minecraft:plains", 1),
            (["profession": .string("")], "", "minecraft:plains", 1),
            (["type": .string("")], "minecraft:none", "", 1),
            (["profession": .string("invalid ID")], "minecraft:none", "minecraft:plains", 1),
            (["type": .string("invalid ID")], "minecraft:none", "minecraft:plains", 1),
            (["profession": .string("minecraft:farmer"), "type": .string("minecraft:desert"),
              "level": .string("2")], "minecraft:farmer", "minecraft:desert", 1),
            (["profession": .string("minecraft:farmer"), "type": .string("minecraft:desert"),
              "level": .compound([:])], "minecraft:farmer", "minecraft:desert", 1),
            (["profession": .string("minecraft:farmer"), "type": .string("minecraft:desert"),
              "level": .list([])], "minecraft:farmer", "minecraft:desert", 1),
        ]
        for id in ["minecraft:villager", "minecraft:zombie_villager", "example:new_merchant"] {
            for (fields, profession, type, level) in cases {
                let value = try #require(creature(id, data: .compound(fields)).villager)
                #expect(value.profession == profession && value.type == type && value.level == level)
                #expect(value.savedData?.value == .compound(fields))
                let decoded = try JSONDecoder().decode(Villager.self, from: JSONEncoder().encode(value))
                #expect(decoded == value)
            }
        }
    }

    @Test func levelUsesJavaNumberIntValueAndTheGameMinimum() throws {
        let cases: [(NBT, Int)] = [(.int(-7), 1), (.int(0), 1), (.int(2), 2),
                                  (.int(.max), Int(Int32.max)), (.long(.max), 1), (.float(2.75), 2)]
        for (input, expected) in cases {
            let fields: NBT = .compound(["profession": .string("minecraft:farmer"),
                                        "type": .string("minecraft:desert"), "level": input])
            let value = try #require(creature("minecraft:villager", data: fields).villager)
            #expect(value.level == expected)
            #expect(value.profession == "minecraft:farmer" && value.type == "minecraft:desert")
            #expect(value.savedData?.value == fields)
        }
    }

    @Test func readableCustomIdentifiersSurviveWithoutAnAssumedRegistry() throws {
        for profession in ["example:beekeeper", "minecraft:future_profession"] {
            let input: NBT = .compound(["profession": .string(profession), "type": .string("example:cliffs"),
                                       "level": .string("bad")])
            let value = try #require(creature("minecraft:villager", data: input).villager)
            #expect(value.profession == profession && value.type == "example:cliffs" && value.level == 1)
            #expect(value.supportsTrading(using: nil) == nil)
            #expect(value.savedData?.value == input)
        }
    }

    @Test func explicitEditsRetireSavedProvenanceWithoutInventingMissingFields() throws {
        var value = try #require(creature("minecraft:villager", data: .compound([:])).villager)
        #expect(value.savedData?.value == .compound([:]))
        value.profession = nil
        #expect(value.savedData == nil && value.profession == nil)
        #expect(value.type == "minecraft:plains" && value.level == 1)
        value.level = nil
        let decoded = try JSONDecoder().decode(Villager.self, from: JSONEncoder().encode(value))
        #expect(decoded == value && decoded.savedData == nil && decoded.level == nil)

        let old = Data(#"{"trades":[]}"#.utf8)
        let historical = try JSONDecoder().decode(Villager.self, from: old)
        #expect(historical.profession == nil && historical.type == nil && historical.level == nil)
        #expect(historical.savedData == nil && historical.offerState == nil)
    }

    @Test func regionScanAndCacheRetainDefaultsRawFieldsAndCustomNames() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(.max)])]),
                                     to: root.appendingPathComponent("level.dat"))
        let entities = [entity("minecraft:villager", data: nil), entity("minecraft:zombie_villager", data: nil),
                        entity("minecraft:villager", data: .compound(["profession": .int(7), "level": .string("bad")])),
                        entity("example:new_mob", data: nil)]
        let chunk: NBT = .compound(["DataVersion": .int(.max), "Entities": .list(entities)])
        let bytes = try Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)])
        let path = root.appendingPathComponent("dimensions/example/market/entities/r.0.0.mca")
        try Fixtures.write(bytes, to: path)
        let dimension = try #require(World(contentsOf: root).dimension("example:market"))
        let direct = Creature.creatures(inEntityChunk: chunk)
        let scanned = try dimension.scan(region: .init(x: 0, z: 0))
        let cached = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(scanned))
        #expect(scanned.creatures == direct && cached.creatures == direct)
        #expect(direct.count == 4 && direct.allSatisfy { $0.customName == "Keeper" })
        #expect(direct[0].villager?.profession == "minecraft:none")
        #expect(direct[1].villager?.profession == nil && direct[1].villager?.level == 1)
        #expect(direct[2].villager?.savedData?.value?["profession"] == .int(7))
        #expect(direct[3].villager == nil)
        #expect(try Data(contentsOf: path) == Data(bytes))
    }

    private func creature(_ id: String, data: NBT?) throws -> Creature {
        try #require(Creature(entity(id, data: data), dataVersion: Int.max))
    }

    private func entity(_ id: String, data: NBT?) -> NBT {
        var fields: [String: NBT] = ["id": .string(id), "CustomName": .string("Keeper"),
                                   "Pos": .list([.double(0), .double(64), .double(0)])]
        fields["VillagerData"] = data
        return Fixtures.mob(fields)
    }
}
