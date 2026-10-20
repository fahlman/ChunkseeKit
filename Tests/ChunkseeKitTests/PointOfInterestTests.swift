import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct PointOfInterestTests {
    func record(_ type: String, _ pos: [Int32], tickets: Int32) -> NBT {
        .compound(["type": .string(type), "pos": .intArray(pos), "free_tickets": .int(tickets)])
    }

    var poiChunk: NBT {
        .compound(["DataVersion": .int(5023), "Sections": .compound([
            "4": .compound(["Valid": .byte(1), "Records": .list([
                record("minecraft:home", [-5245, 78, -779], tickets: 0),
                record("minecraft:meeting", [-5243, 70, -759], tickets: 32),
            ])]),
            "-1": .compound(["Valid": .byte(1), "Records": .list([record("minecraft:nether_portal", [10, -12, 4], tickets: 0)])]),
            "6": .compound(["Valid": .byte(0), "Records": .list([record("minecraft:bee_nest", [1, 100, 1], tickets: 0)])]),
        ])])
    }

    @Test func readsRecordsSkippingInvalidSections() {
        let records = PointOfInterest.records(inChunk: poiChunk)
        #expect(records.map(\.type) == ["minecraft:nether_portal", "minecraft:home", "minecraft:meeting"])  // by section Y
        #expect(records[1] == PointOfInterest(type: "minecraft:home", x: -5245, y: 78, z: -779, freeTickets: 0))
        #expect(!records.contains { $0.type == "minecraft:bee_nest" })
    }

    @Test func readsADimensionsPoiRegion() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(5023)])]), to: dir.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/minecraft/overworld/region"), withIntermediateDirectories: true)
        // Chunk (0, 0) points at a missing external file: damaged, so it's skipped.
        try Fixtures.write(try Fixtures.region([.init(localX: 3, localZ: 7, nbt: poiChunk), .init(localX: 0, localZ: 0, nbt: poiChunk, compression: 0x82)]),
                           to: dir.appendingPathComponent("dimensions/minecraft/overworld/poi/r.-11.-2.mca"))
        let overworld = try #require(try World(contentsOf: dir).dimension("overworld"))
        #expect(overworld.regionFiles(.pointsOfInterest).map { [$0.x, $0.z] } == [[-11, -2]])
        #expect(overworld.regionFiles().isEmpty)
        #expect(try overworld.pointsOfInterest(regionX: -11, regionZ: -2).count == 3)
        #expect(try overworld.pointsOfInterest(regionX: 0, regionZ: 0).isEmpty)
    }
}
