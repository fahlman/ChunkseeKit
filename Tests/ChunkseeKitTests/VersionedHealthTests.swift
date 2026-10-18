import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct VersionedHealthTests {
    func entity(_ species: String, fields: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string("minecraft:" + species), "Health": .float(7),
                   "Pos": .list([.double(-520), .double(64), .double(-8)])].merging(fields) { $1 })
    }

    @Test func defaultsApplyOnlyToTheVerifiedSpeciesAndReleaseVersions() {
        for version in [4786, 4788, 4790, 4903, 5023] {
            for (species, maximum) in [("cat", 10.0), ("parrot", 6.0), ("wolf", 8.0)] {
                #expect(Creature(entity(species), dataVersion: version)?.maxHealth == maximum)
            }
        }
        let unverified: [Int?] = [nil, 4785, 4787, 4789, 4791, 4902, 4904, 5022, 5024, 9999]
        for version in unverified {
            for species in ["cat", "parrot", "wolf"] {
                #expect(Creature(entity(species), dataVersion: version)?.maxHealth == nil)
            }
        }
        #expect(Creature(entity("horse"), dataVersion: 4786)?.maxHealth == nil)
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
        for version in [4786, 4788, 4790, 4903, 5023] {
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
        #expect(Creature(explicit, dataVersion: 9999)?.maxHealth == 40)
    }

    @Test(arguments: [4786, 4788, 4790, 4903, 5023])
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
        #expect(raw.count == 4 && Creature(raw[0])?.maxHealth == nil)
        #expect(try dimension.creatures(chunkX: -33, chunkZ: -1).map(\.maxHealth) == [10, 6, 8])
        #expect(try dimension.creatures(chunkX: -34, chunkZ: -1).first?.maxHealth == nil)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0).isEmpty)
        #expect(try dimension.creatures(chunkX: -35, chunkZ: -1).isEmpty)
        #expect(try dimension.creatures(regionX: -2, regionZ: -1).count == 4)
    }
}
