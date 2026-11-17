import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct CLIDiscoveryTests {
    private static let commands = ["", "summary", "scan", "time", "structures", "poi", "creatures", "find", "text"]

    @Test(arguments: CLIDiscoveryTests.commands)
    func unavailableFolderIsAnError(_ command: String) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = directory(in: root).appendingPathComponent(command == "poi" ? "poi" : "region")
        try Data().write(to: folder)

        let result = try run(root, command: command)
        #expect(result.status == 1)
        #expect(result.standardError.contains("could not list region folder: \(folder.path)"))
        #expect(!result.output.contains("minecraft:overworld: 0"))
    }

    @Test(arguments: CLIDiscoveryTests.commands, [false, true])
    func missingAndEmptyFoldersRemainSuccessful(_ command: String, _ empty: Bool) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        if empty {
            for folder in ["region", "entities", "poi"] {
                try FileManager.default.createDirectory(at: directory(in: root).appendingPathComponent(folder),
                                                        withIntermediateDirectories: true)
            }
        }

        let result = try run(root, command: command)
        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
    }

    @Test(arguments: ["find", "text", "creatures"])
    func readableEntitiesSurviveAnUnavailableTerrainFolder(_ command: String) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: directory(in: root).appendingPathComponent("region"))
        let entities: [NBT] = [
            .compound(["id": .string("minecraft:chest_minecart"),
                       "Pos": .list([.double(1), .double(64), .double(1)]), "Items": .list([book])]),
            Fixtures.mob(["id": .string("minecraft:wolf"), "CustomName": .string("Needle wolf"),
                          "Pos": .list([.double(2), .double(64), .double(2)])]),
        ]
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0,
            nbt: .compound(["DataVersion": .int(5023), "Entities": .list(entities)]))]),
            to: directory(in: root).appendingPathComponent("entities/r.0.0.mca"))

        let result = try run(root, command: command)
        #expect(result.status == 1)
        #expect(result.standardError.contains("/overworld/region"))
        #expect(result.output.contains(command == "creatures" ? "Needle wolf" : "Needle book"))
        #expect(result.output.contains(command == "creatures" ? "1 minecraft:wolf" : command == "find" ? "1 containers" : "1 matches"))
    }

    @Test(arguments: ["find", "text"])
    func readableTerrainSurvivesAnUnavailableEntitiesFolder(_ command: String) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: directory(in: root).appendingPathComponent("entities"))
        let chest = NBT.compound(["id": .string("minecraft:chest"), "x": .int(1), "y": .int(64), "z": .int(1),
                                  "Items": .list([book])])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0,
            nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: ["block_entities": .list([chest])]))]),
            to: directory(in: root).appendingPathComponent("region/r.0.0.mca"))

        let result = try run(root, command: command)
        #expect(result.status == 1)
        #expect(result.standardError.contains("/overworld/entities"))
        #expect(result.output.contains("Needle book"))
        #expect(result.output.contains(command == "find" ? "1 containers" : "1 matches"))
    }

    @Test(arguments: ["", "summary", "scan", "structures", "poi"])
    func laterReadableDimensionsAreStillReported(_ command: String) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = command == "poi" ? "poi" : "region"
        try Data().write(to: directory(in: root).appendingPathComponent(folder))
        let structure = NBT.compound([
            "id": .string("custom:temple"), "ChunkX": .int(0), "ChunkZ": .int(0),
            "Children": .list([.compound(["id": .string("minecraft:jigsaw"), "BB": .intArray([0, 60, 0, 1, 64, 1])])]),
        ])
        let chunk = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: [], extra: [
            "structures": .compound(["starts": .compound(["custom:temple": structure])]),
        ])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]),
                           to: directory(in: root, dimension: "the_nether").appendingPathComponent("region/r.0.0.mca"))
        let poi = NBT.compound(["DataVersion": .int(5023), "Sections": .compound([
            "4": .compound(["Valid": .byte(1), "Records": .list([.compound([
                "type": .string("minecraft:home"), "pos": .intArray([1, 64, 1]), "free_tickets": .int(0),
            ])])]),
        ])])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: poi)]),
                           to: directory(in: root, dimension: "the_nether").appendingPathComponent("poi/r.0.0.mca"))

        let result = try run(root, command: command)
        let unit = command == "scan" ? "chunks" : command == "structures" ? "structures" : command == "poi" ? "points of interest" : "region files"
        #expect(result.status == 1)
        #expect(result.standardError.contains("/overworld/\(folder)"))
        #expect(result.output.contains("minecraft:the_nether: 1 \(unit)"))
        #expect(!result.output.contains("minecraft:overworld: 0"))
    }

    @Test func allUnavailableFoldersAreReportedAfterPlayerResults() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["region", "entities"] { try Data().write(to: directory(in: root).appendingPathComponent(folder)) }
        try Fixtures.writeGzippedNBT(.compound(["Inventory": .list([book])]),
                                    to: root.appendingPathComponent("players/data/01234567-89ab-cdef-0123-456789abcdef.dat"))

        let result = try run(root, command: "find")
        #expect(result.status == 1)
        #expect(result.output.contains("player 01234567 inventory: 1 \"Needle book\""))
        #expect(result.standardError.contains("/overworld/region"))
        #expect(result.standardError.contains("/overworld/entities"))
        #expect(result.standardError.split(separator: "\n").count == 2)
    }

    private func world() throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Discovery"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: directory(in: root), withIntermediateDirectories: true)
        return root
    }

    private func directory(in root: URL, dimension: String = "overworld") -> URL {
        root.appendingPathComponent("dimensions/minecraft/\(dimension)")
    }

    private func run(_ root: URL, command: String) throws -> (status: Int32, output: String, standardError: String) {
        try Fixtures.runCLI(root, command: command.isEmpty ? nil : command,
                            arguments: command == "find" || command == "text" ? ["needle"] : [])
    }

    private var book: NBT {
        .compound(["id": .string("minecraft:written_book"), "count": .int(1), "components": .compound([
            "minecraft:custom_name": .string("Needle book"),
            "minecraft:written_book_content": .compound([
                "title": .compound(["raw": .string("Needle book")]), "author": .string("Tester"),
                "pages": .list([.compound(["raw": .string("Needle in a page")])]),
            ]),
        ])])
    }
}
