import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct VersionedHealthTests {
    func entity(_ species: String, fields: [String: NBT] = [:]) -> NBT {
        Fixtures.mob(["id": .string("minecraft:" + species), "Health": .float(7),
                   "Pos": .list([.double(-520), .double(64), .double(-8)])].merging(fields) { $1 })
    }

    @Test func generatedDefaultsMatchGameValuesAcrossSaveVersions() {
        for version in [nil, 100, 4786, 5023, 9999] as [Int?] {
            for (id, maximum) in GeneratedHealthDefaultProofs.defaultMaximums {
                let saved = Fixtures.mob(["id": .string(id), "Health": .float(7),
                    "Pos": .list([.double(0), .double(64), .double(0)])])
                #expect(Creature(saved, dataVersion: version)?.maxHealth == maximum, "\(id), version \(String(describing: version))")
            }
        }
        let unknown = Fixtures.mob(["id": .string("example:new_mob"), "Health": .float(7),
            "Pos": .list([.double(0), .double(64), .double(0)])])
        #expect(Creature(unknown)?.maxHealth == nil)
        let saved = entity("cat", fields: ["attributes": .list([.compound([
            "id": .string("minecraft:max_health"), "base": .double(12),
        ])])])
        #expect(Creature(saved, dataVersion: 9999)?.maxHealth == 12)
    }

    @Test func wolfLoadingReplacesOnlyTheUntamedBaseAndKeepsSavedModifiers() {
        let attribute = NBT.compound(["id": .string("minecraft:max_health"), "base": .double(40),
                                      "modifiers": .list([
            .compound(["id": .string("test:add"), "amount": .double(4), "operation": .string("add_value")]),
            .compound(["id": .string("test:base"), "amount": .double(0.5), "operation": .string("add_multiplied_base")]),
            .compound(["id": .string("test:total"), "amount": .double(1), "operation": .string("add_multiplied_total")]),
        ])])
        for version in [nil, 100, 4786, 5023, 9999] as [Int?] {
            let wild = entity("wolf", fields: ["attributes": .list([attribute])])
            #expect(Creature(wild, dataVersion: version)?.maxHealth == 36) // (8 + 4) * 1.5 * 2
            let owner = NBT.intArray([1, 2, 3, 4])
            var owned = wild.compound!
            owned["Owner"] = owner
            #expect(Creature(.compound(owned), dataVersion: version)?.maxHealth == 132) // (40 + 4) * 1.5 * 2
            owned["Owner"] = .string("a legacy owner name")
            #expect(Creature(.compound(owned), dataVersion: version)?.maxHealth == nil)
        }
        let explicit = entity("wolf", fields: ["attributes": .list([.compound([
            "id": .string("minecraft:max_health"), "base": .double(40),
        ])])])
        #expect(Creature(explicit, dataVersion: 5023)?.maxHealth == 8)
        #expect(Creature(explicit, dataVersion: 9999)?.maxHealth == 8)
    }

    @Test func cubeSizeDefaultsMatchTheGameAndYieldToSavedAttributes() {
        for (id, maximums) in GeneratedHealthDefaultProofs.cubeMaximums {
            for (index, maximum) in maximums.enumerated() {
                let saved = Fixtures.mob(["id": .string(id), "Size": .int(Int32(index)),
                    "Health": .float(7), "Pos": .list([.double(0), .double(64), .double(0)])])
                #expect(Creature(saved, dataVersion: 9999)?.maxHealth == maximum, "\(id), size \(index)")
            }
        }
        let attribute = NBT.compound(["id": .string("minecraft:max_health"), "base": .double(37),
            "modifiers": .list([.compound(["id": .string("test:add"), "amount": .double(4), "operation": .string("add_value")])])])
        #expect(Creature(entity("slime", fields: ["Size": .int(126), "attributes": .list([attribute])]))?.maxHealth == 41)
        for size in [NBT.int(Int32.max), .int(-1), .string("unreadable"), .double(.nan)] {
            #expect(Creature(entity("slime", fields: ["Size": size]))?.maxHealth == 1)
        }
        #expect(Creature(entity("slime", fields: ["Size": .double(3.9)]))?.maxHealth == 16)
        #expect(Creature(entity("slime", fields: ["Size": .int(10_000)]))?.maxHealth == 1024)
    }

    @Test(arguments: [100, 4786, 5023, 9999])
    func perChunkCreatureReadPreservesVersionAndNegativeCoordinates(_ version: Int) throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Version Context"), "DataVersion": .int(5023),
        ])]), to: dir.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("region"), withIntermediateDirectories: true)
        let old = NBT.compound(["DataVersion": .int(4787), "Entities": .list([entity("cat")])])
        let verified = NBT.compound(["DataVersion": .int(Int32(version)), "Entities": .list([
            entity("cat"), entity("parrot"), entity("wolf"),
            .compound(["id": .string("minecraft:item"), "Pos": .list([.double(0), .double(64), .double(0)])]),
        ])])
        try Fixtures.write(Fixtures.region([
            .init(localX: 30, localZ: 31, nbt: old), .init(localX: 31, localZ: 31, nbt: verified),
        ]), to: dir.appendingPathComponent("entities/r.-2.-1.mca"))
        let dimension = try #require(World(contentsOf: dir).dimension("overworld"))
        let raw = try dimension.entities(chunkX: -33, chunkZ: -1)
        #expect(raw.count == 4 && Creature(raw[0])?.maxHealth == 10)
        #expect(try dimension.creatures(chunkX: -33, chunkZ: -1).map(\.maxHealth) == [10, 6, 8])
        #expect(try dimension.creatures(chunkX: -34, chunkZ: -1).first?.maxHealth == 10)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0).isEmpty)
        #expect(try dimension.creatures(chunkX: -35, chunkZ: -1).isEmpty)
        #expect(try dimension.creatures(regionX: -2, regionZ: -1).count == 4)
    }
}
