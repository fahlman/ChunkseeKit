import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct CLISearchTests {
    @Test(arguments: [false, true])
    func textIncludesOffhandBooksAndFindKeepsEveryPlayerStore(_ legacy: Bool) throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let uuid = "01234567-89ab-cdef-0123-456789abcdef"
        var inventoryBook = book("Inventory", legacy: legacy).compound!
        inventoryBook["Slot"] = .byte(0)
        var offhandBook = book("Offhand", legacy: legacy).compound!
        offhandBook["Slot"] = .byte(-106)
        var fields: [String: NBT] = ["Inventory": .list([.compound(inventoryBook)]), "EnderItems": .list([book("Ender", legacy: legacy)])]
        if legacy { fields["Inventory"] = .list([.compound(inventoryBook), .compound(offhandBook)]) }
        else { fields["equipment"] = .compound(["offhand": .compound(offhandBook)]) }
        try Fixtures.writeGzippedNBT(.compound(fields), to: root.appendingPathComponent("players/data/\(uuid).dat"))
        let text = try Fixtures.runCLI(root, command: "text", arguments: ["needle"])
        #expect(text.status == 0)
        for title in ["Inventory", "Offhand", "Ender"] {
            #expect(text.output.contains("\"Needle \(title)\" by Tester"))
        }
        #expect(text.output.split(separator: "\n").filter { $0.hasPrefix("player ") }.count == 3)
        let find = try Fixtures.runCLI(root, command: "find", arguments: ["needle"])
        #expect(find.status == 0)
        for title in ["Inventory", "Offhand", "Ender"] { #expect(find.output.contains("Needle \(title)")) }
        #expect(find.output.contains("inventory:") && find.output.contains("ender chest:"))
    }

    @Test func bothSearchesIncludeEntityOnlyRegionsWithoutDuplicatingOverlap() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let chest = NBT.compound(["id": .string("minecraft:chest"), "x": .int(1), "y": .int(64), "z": .int(1),
                                  "Items": .list([book("Chest")])])
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: Fixtures.chunk(x: 0, z: 0, sections: [], extra: [
            "block_entities": .list([chest]),
        ]))]), to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        func entity(_ path: String, x: Double, localX: Int, title: String) throws {
            try Fixtures.write(try Fixtures.region([.init(localX: localX, localZ: 0, nbt: .compound(["DataVersion": .int(5023), "Entities": .list([
                .compound(["id": .string("minecraft:chest_minecart"), "Pos": .list([.double(x), .double(64), .double(1)]),
                           "Items": .list([book(title)])]),
            ])]))]), to: root.appendingPathComponent(path))
        }
        try entity("dimensions/minecraft/overworld/entities/r.0.0.mca", x: 2.5, localX: 0, title: "Overlap")
        try entity("dimensions/minecraft/overworld/entities/r.-1.0.mca", x: -8.7, localX: 31, title: "Cart")
        try entity("dimensions/minecraft/the_nether/entities/r.0.0.mca", x: 0, localX: 0, title: "Other Dimension")
        for command in ["find", "text"] {
            let result = try Fixtures.runCLI(root, command: command, arguments: ["needle", "overworld"])
            #expect(result.status == 0)
            for title in ["Chest", "Overlap", "Cart"] { #expect(result.output.contains("Needle \(title)")) }
            #expect(!result.output.contains("Other Dimension"))
            #expect(result.output.contains(command == "find" ? "3 containers" : "3 matches"))
        }
    }

    private func world() throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("CLI search"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/overworld/region"), withIntermediateDirectories: true)
        return root
    }

    private func book(_ title: String, legacy: Bool = false) -> NBT {
        let name = "Needle " + title
        if legacy {
            return .compound(["id": .string("minecraft:written_book"), "Count": .byte(1), "tag": .compound([
                "display": .compound(["Name": .string(name)]), "title": .string(name), "author": .string("Tester"),
                "pages": .list([.string("Needle in a legacy page")]),
            ])])
        }
        return .compound(["id": .string("minecraft:written_book"), "count": .int(1), "components": .compound([
            "minecraft:custom_name": .string(name), "minecraft:written_book_content": .compound([
                "title": .compound(["raw": .string(name)]), "author": .string("Tester"),
                "pages": .list([.compound(["raw": .string("Needle in a page")])]),
            ]),
        ])])
    }
}
