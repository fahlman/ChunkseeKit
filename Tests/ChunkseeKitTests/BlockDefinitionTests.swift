import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct BlockDefinitionTests {
    @Test(arguments: [1, 5023, 999_999])
    func selectedResourcesSupplyPresenceWithoutAVersionOrBlockInventory(_ version: Int) throws {
        let jar = try assets(version: version, entries: [
            .init(path: "assets/minecraft/blockstates/stone.json", text: "{}"),
            .init(path: "assets/custom/blockstates/new_block.json", text: "{}"),
            .init(path: "assets/minecraft/blockstates/item_frame.json", text: "{}"),
            .init(path: "assets/minecraft/blockstates/glow_item_frame.json", text: "{}"),
            .init(path: "assets/custom/blockstates/item_frame.json", text: "{}"),
            .init(path: "assets/minecraft/blockstates/broken.json", text: "invalid", wrongCRC: true)
        ])
        for id in ["stone", ":stone", "minecraft:stone", "custom:new_block", "custom:item_frame"] {
            #expect(jar.containsBlockDefinition(id) == true)
        }
        for id in ["absent", "minecraft:item_frame", "glow_item_frame", "custom:absent"] {
            #expect(jar.containsBlockDefinition(id) == false)
        }
        // Presence is not model readability. The picture-failure API is separate work.
        #expect(jar.containsBlockDefinition("broken") == true)
        #expect(jar.blockModel(for: .init("broken")) == nil)
    }

    @Test func noJarAndUnqueryablePathsRemainUnknown() throws {
        let absent: GameAssets? = nil
        #expect(absent?.containsBlockDefinition("stone") == nil)
        let jar = try assets(version: 1, entries: [])
        for id in ["", "minecraft:", "Bad Name", "minecraft:../stone", "minecraft:block//stone", ".:stone"] {
            #expect(jar.containsBlockDefinition(id) == nil)
        }
        #expect(jar.containsBlockDefinition("stone") == false)
    }

    @Test func changedArchiveDoesNotTurnUnknownContentsIntoPresenceOrAbsence() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("game.jar")
        try Fixtures.write(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":1}"#),
            .init(path: "assets/minecraft/blockstates/stone.json", text: "{}")
        ]), to: path)
        let jar = try #require(try GameAssets(contentsOf: path))
        #expect(jar.containsBlockDefinition("stone") == true)
        let writer = try FileHandle(forWritingTo: path)
        try writer.truncate(atOffset: 0)
        try writer.close()
        for id in ["stone", "absent", "item_frame"] { #expect(jar.containsBlockDefinition(id) == nil) }
    }

    private func assets(version: Int, entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}")
        ] + entries))))
    }
}
