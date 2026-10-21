import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct AirInterpretationTests {
    @Test func airItemsAreEmptyInCurrentLegacyAndNestedReads() throws {
        for id in ["minecraft:air", "air", ":air"] {
            for count in ["count", "Count"] {
                #expect(ItemStack(.compound(["id": .string(id), count: .int(1)])) == nil)
            }
        }
        let items: [NBT] = ["air", ":air", "example:air", "minecraft:stone"].enumerated().map { slot, id in
            .compound(["id": .string(id), "count": .int(1), "Slot": .byte(Int8(slot))])
        }
        let player = PlayerInfo(uuid: UUID(), nbt: .compound(["Inventory": .list(items)]))
        #expect(player.inventory.map(\.id) == ["example:air", "minecraft:stone"])
        let bundle = try #require(ItemStack(.compound([
            "id": .string("minecraft:bundle"), "count": .int(1),
            "components": .compound(["minecraft:bundle_contents": .list(items)]),
        ])))
        #expect(bundle.contents.map(\.id) == ["example:air", "minecraft:stone"])
    }

    @Test func chunkCommandUsesTheSharedAirClassification() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        var sections = ["air", "minecraft:cave_air", "minecraft:void_air"].enumerated().map {
            Fixtures.section(y: $0.offset, palette: [.string($0.element)])
        }
        sections.append(Fixtures.section(y: 3, palette: [.string(":air"), .string("cave_air")],
                                        indices: (0..<4096).map { $0 % 2 }))
        sections.append(Fixtures.section(y: 4, palette: [.string("example:air")]))
        sections.append(Fixtures.section(y: 5, palette: [.string("minecraft:stone")]))
        let chunk = Fixtures.chunk(x: 0, z: 0, dataVersion: 5023, sections: sections)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)]),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.0.0.mca"))
        let result = try Fixtures.runCLI(root, command: "chunk", arguments: ["0", "0"])
        #expect(result.status == 0)
        for y in 0...3 { #expect(!result.output.contains("section y=\(y):")) }
        for y in 4...5 { #expect(result.output.contains("section y=\(y):")) }
        #expect(result.output.contains("example:air"))
    }
}
