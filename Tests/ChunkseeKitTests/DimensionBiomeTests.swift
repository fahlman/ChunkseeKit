import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct DimensionBiomeTests {
    @Test func standardDimensionsReadTheirOwnTagWithoutVersionInventories() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root)
        let jar = try assets([
            tag("is_overworld", ["example:unfamiliar", "plains"]),
            tag("is_nether", ["example:underground"]), tag("is_end", ["example:island"])
        ])
        #expect(try world.possibleBiomes(in: "overworld", assets: jar) == ["example:unfamiliar", "minecraft:plains"])
        #expect(try world.possibleBiomes(in: "minecraft:the_nether", assets: jar) == ["example:underground"])
        #expect(try world.possibleBiomes(in: "minecraft:the_end", assets: jar) == ["example:island"])
        #expect(try world.possibleBiomes(in: "example:overworld", assets: jar) == nil)
    }

    @Test func packsAddNestedBiomesThenReplaceTheListWithoutAReaderChange() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla", "file/biomes"])
        let jar = try assets([tag("is_overworld", ["plains"])])
        try pack(root, entries: [tag("is_overworld", ["#example:added"]),
                                tag("example:added", ["example:brand_new", "plains"])])
        #expect(try world.possibleBiomes(in: "overworld", assets: jar) == ["minecraft:plains", "example:brand_new"])
        try pack(root, entries: [tag("is_overworld", ["example:replacement"], replace: true)])
        #expect(try world.possibleBiomes(in: "overworld", assets: jar) == ["example:replacement"])
        try pack(root, entries: [tag("is_overworld", [], replace: true)])
        #expect(try world.possibleBiomes(in: "overworld", assets: jar) == [])
    }

    @Test func everySavedVersionUsesTheSelectedGamesBiomeTags() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try assets([tag("is_overworld", ["example:current_game_biome"])])
        for version in [nil, 1, 999_998, 999_999, 1_000_000] as [Int32?] {
            let world = try world(root, version: version)
            #expect(try world.possibleBiomes(in: "overworld", assets: jar) == ["example:current_game_biome"])
        }
    }

    @Test func absentResourcesAndMalformedInputsDoNotInventBiomes() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root)
        #expect(try world.possibleBiomes(in: "overworld", assets: nil) == nil)
        #expect(try world.possibleBiomes(in: "overworld", assets: assets([], version: 1)) == nil)
        #expect(try world.possibleBiomes(in: "overworld", assets: assets([])) == nil)
        let jar = try assets([tag("is_overworld", ["plains"])])
        try pack(root, entries: [.init(path: "data/minecraft/tags/worldgen/biome/is_overworld.json", text: "invalid")])
        let overridden = try self.world(root, packs: ["vanilla", "file/biomes"])
        #expect(try overridden.possibleBiomes(in: "overworld", assets: jar) == nil)
        let disabled = try self.world(root, packs: [])
        #expect(try disabled.possibleBiomes(in: "overworld", assets: jar) == nil)
    }

    @Test func aCompletePackTagIsReadableWithoutVanillaAndDoesNotWriteTheWorld() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla", "file/biomes"])
        try pack(root, entries: [tag("is_overworld", ["example:pack_biome"], replace: true)])
        let level = root.appendingPathComponent("level.dat"), before = try Data(contentsOf: root.appendingPathComponent("level.dat"))
        #expect(try world.possibleBiomes(in: "overworld", assets: nil) == ["example:pack_biome"])
        #expect(try Data(contentsOf: level) == before)
    }

    private func tag(_ id: String, _ members: [String], replace: Bool = false) throws -> TestZIP.Entry {
        let id = Identifier(id)!
        let json = try JSONSerialization.data(withJSONObject: ["values": members, "replace": replace])
        return .init(path: "data/\(id.namespace)/tags/worldgen/biome/\(id.path).json", text: String(decoding: json, as: UTF8.self))
    }

    private func assets(_ entries: [TestZIP.Entry], version: Int = 999_999) throws -> GameAssets {
        let bytes = try TestZIP.zip([.init(path: "version.json", text: "{\"id\":\"future\",\"world_version\":\(version)}")] + entries)
        return try #require(GameAssets(data: Data(bytes)))
    }

    private func world(_ root: URL, packs: [String] = ["vanilla"], version: Int32? = 999_999) throws -> World {
        var fields: [String: NBT] = ["DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))])]
        fields["DataVersion"] = version.map(NBT.int)
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func pack(_ root: URL, entries: [TestZIP.Entry]) throws {
        let folder = root.appendingPathComponent("datapacks/biomes")
        for entry in [TestZIP.Entry(path: "pack.mcmeta", text: "{\"pack\":{\"description\":\"Fixture\"}}" )] + entries {
            try Fixtures.write(Array(entry.text.utf8), to: folder.appendingPathComponent(entry.path))
        }
    }
}
