import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct MapItemReadTests {
    private func makeWorld() throws -> World {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Map reads")])]),
                                    to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func map(_ path: String, in world: World, center: Int32 = 0) throws {
        try Fixtures.writeGzippedNBT(.compound(["data": .compound([
            "dimension": .string("minecraft:overworld"), "xCenter": .int(center),
            "colors": .byteArray([Int8](repeating: 4, count: MapItem.size * MapItem.size)),
        ])]), to: world.url.appendingPathComponent(path))
    }

    @Test func missingAndEmptyDirectoriesEstablishAnEmptyRead() throws {
        let world = try makeWorld()
        defer { try? FileManager.default.removeItem(at: world.url) }
        for createDirectories in [false, true] {
            if createDirectories {
                try FileManager.default.createDirectory(at: world.url.appendingPathComponent("data/minecraft/maps"),
                                                        withIntermediateDirectories: true)
            }
            let read = world.readMapItems()
            #expect(read.maps.isEmpty && read.unresolvedIDs.isEmpty && read.isListingComplete)
            #expect(world.mapItems() == read.maps)
        }
    }

    @Test func readablePrioritySortingAndOtherFilesKeepTheExistingResults() throws {
        let world = try makeWorld()
        defer { try? FileManager.default.removeItem(at: world.url) }
        try map("data/minecraft/maps/2.dat", in: world, center: 20)
        try map("data/map_2.dat", in: world, center: 200)
        try map("data/map_1.dat", in: world, center: 10)
        try Data([1, 2, 3]).write(to: world.url.appendingPathComponent("data/minecraft/maps/last_id.dat"))
        try Data([1, 2, 3]).write(to: world.url.appendingPathComponent("data/idcounts.dat"))
        let read = world.readMapItems()
        #expect(read.maps.map(\.id) == [1, 2] && read.maps.map(\.centerX) == [10, 20])
        #expect(read.unresolvedIDs.isEmpty && read.isListingComplete)
        #expect(world.mapItems() == read.maps)
    }

    @Test func failedPreferredFilesStayUnresolvedEvenWithReadableFallbacks() throws {
        let world = try makeWorld()
        defer { try? FileManager.default.removeItem(at: world.url) }
        try map("data/minecraft/maps/3.dat", in: world, center: 30)
        try map("data/map_1.dat", in: world, center: 10)
        let malformed = world.url.appendingPathComponent("data/minecraft/maps/1.dat")
        try Data([1, 2, 3]).write(to: malformed)
        let invalidMap = world.url.appendingPathComponent("data/minecraft/maps/2.dat")
        try Fixtures.writeGzippedNBT(.compound(["data": .compound([:])]), to: invalidMap)
        let failed = world.readMapItems()
        #expect(failed.maps.map(\.id) == [1, 3] && failed.maps.map(\.centerX) == [10, 30])
        #expect(failed.unresolvedIDs == [1, 2] && failed.isListingComplete)
        #expect(world.mapItems() == failed.maps)
        #expect(try Data(contentsOf: malformed) == Data([1, 2, 3]))

        try map("data/minecraft/maps/1.dat", in: world, center: 100)
        let repaired = world.readMapItems()
        #expect(repaired.maps.map(\.centerX) == [100, 30] && repaired.unresolvedIDs == [2])
        try FileManager.default.removeItem(at: invalidMap)
        let removed = world.readMapItems()
        #expect(removed.maps == repaired.maps && removed.unresolvedIDs.isEmpty && removed.isListingComplete)
    }

    @Test func failedListingLeavesAbsenceAndLowerPriorityValuesUnresolved() throws {
        let world = try makeWorld()
        defer { try? FileManager.default.removeItem(at: world.url) }
        try map("data/map_7.dat", in: world)
        try FileManager.default.createDirectory(at: world.url.appendingPathComponent("data/minecraft"),
                                                withIntermediateDirectories: true)
        let folder = world.url.appendingPathComponent("data/minecraft/maps")
        // A file in place of the directory produces a real enumeration error without depending
        // on permissions, the test user's privilege level, or a mocked file reader.
        try Data([1]).write(to: folder)
        let read = world.readMapItems()
        #expect(read.maps.map(\.id) == [7] && read.unresolvedIDs == [7] && !read.isListingComplete)
        #expect(world.mapItems() == read.maps)
        try FileManager.default.removeItem(at: folder)
        let absent = world.readMapItems()
        #expect(absent.maps == read.maps && absent.unresolvedIDs.isEmpty && absent.isListingComplete)
    }

    @Test func noncanonicalNamesCannotReplaceAFailedGameFileOrIntroduceAnotherMap() throws {
        for (directory, prefix) in [("data/minecraft/maps", ""), ("data", "map_")] {
            let world = try makeWorld()
            defer { try? FileManager.default.removeItem(at: world.url) }
            for stem in ["01", "+1", "0001", "003"] {
                try map("\(directory)/\(prefix)\(stem).dat", in: world, center: 100)
            }
            try map("\(directory)/\(prefix)2.dat", in: world, center: 20)
            for stem in ["1", "02"] {
                try Data([1, 2, 3]).write(to: world.url.appendingPathComponent("\(directory)/\(prefix)\(stem).dat"))
            }
            let read = world.readMapItems()
            #expect(read.maps.map(\.id) == [2] && read.unresolvedIDs == [1] && read.isListingComplete)
            #expect(world.mapItems() == read.maps)
            try map("\(directory)/\(prefix)1.dat", in: world, center: 10)
            let repaired = world.readMapItems()
            #expect(repaired.maps.map(\.id) == [1, 2] && repaired.maps.map(\.centerX) == [10, 20])
            #expect(repaired.unresolvedIDs.isEmpty && repaired.isListingComplete)
        }
    }

    @Test func unreadableLegacyFileDoesNotDisqualifyAReadablePreferredMap() throws {
        let world = try makeWorld()
        defer { try? FileManager.default.removeItem(at: world.url) }
        try map("data/minecraft/maps/4.dat", in: world)
        try Data([1, 2, 3]).write(to: world.url.appendingPathComponent("data/map_4.dat"))
        let read = world.readMapItems()
        #expect(read.maps.map(\.id) == [4] && read.unresolvedIDs.isEmpty && read.isListingComplete)
        #expect(world.mapItems() == read.maps)
    }
}
