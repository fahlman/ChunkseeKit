import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct GameTagTests {
    @Test func anyRegistryKeepsNestedIDsOptionalDeclarationsAndFirstOccurrence() throws {
        for registry in ["block", "item", "worldgen/biome", "worldgen/structure", "point_of_interest_type", "entity_type", "custom/new_registry"] {
            let jar = try assets([
                tag(registry, "test:child", ["test:first", ["id": "test:optional", "required": false]]),
                tag(registry, "test:root", ["#test:child", "test:second", "test:first", "test:optional"])
            ])
            let result = try #require(try jar.tag("test:root", in: registry))
            #expect(result.members.map(\.id) == ["test:first", "test:optional", "test:second"])
            #expect(result.members.allSatisfy { $0.required })
            #expect(try jar.tag("test:child", in: "other:" + registry)?.members.last?.required == false)
        }
    }

    @Test func folderZipAndJarComposeAndReplaceWithoutATypeOrVersionList() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try assets([tag("block", "air", ["air", "test:new_air"])])
        try folder("low", root: root, entries: [tag("block", "air", ["test:pack_air", "air"])])
        try zip("high.zip", root: root, entries: [tag("block", "air", ["test:top_air"])])
        let world = try world(root, packs: ["vanilla", "file/low", "file/high.zip"])
        let before = try Data(contentsOf: root.appendingPathComponent("level.dat"))
        #expect(try world.tags(for: ["air"], in: "block", assets: jar)["minecraft:air"]?.members.map(\.id)
            == ["minecraft:air", "test:new_air", "test:pack_air", "test:top_air"])
        try zip("high.zip", root: root, entries: [tag("block", "air", ["test:replacement"], replace: true)])
        #expect(try world.tags(for: ["air"], in: "block", assets: jar)["minecraft:air"]?.members.map(\.id) == ["test:replacement"])
        #expect(try Data(contentsOf: root.appendingPathComponent("level.dat")) == before)
    }

    @Test func replacementDoesNotNeedLowerSourcesButAdditionsDo() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try folder("known", root: root, entries: [tag("item", "test:replace", [], replace: true),
                                                   tag("item", "test:add", ["test:item"])])
        let world = try world(root, packs: ["vanilla", "experiment", "file/known"])
        for jar in [nil, try assets([], version: 123)] {
            let tags = try world.tags(for: ["test:replace", "test:add"], in: "item", assets: jar)
            #expect(tags["test:replace"]?.members == [] && tags["test:add"] == nil)
        }
        let disabled = try self.world(root, packs: [])
        #expect(try disabled.tags(for: ["test:replace"], in: "item", assets: nil).isEmpty)
    }

    @Test func selectedJarSuppliesResourcesForOlderNewerAndUnlabeledSaves() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try folder("override", root: root, entries: [tag("block", "air", ["test:pack_air"])])
        for savedVersion in [nil, 1, 5023, 999999] as [Int32?] {
            let world = try world(root, packs: ["vanilla", "file/override"], version: savedVersion)
            let file = root.appendingPathComponent("level.dat"), before = try Data(contentsOf: file)
            for jarVersion in [1, 5023, 999999] {
                let jar = try assets([tag("block", "air", ["test:game_air"])], version: jarVersion)
                let result = try world.tags(for: ["air", "test:missing"], in: "block", assets: jar)
                #expect(result["minecraft:air"]?.members.map(\.id) == ["test:game_air", "test:pack_air"])
                #expect(result["test:missing"] == nil)
            }
            #expect(try world.tags(for: ["air"], in: "block", assets: nil).isEmpty)
            #expect(world.level.dataVersion == savedVersion.map(Int.init))
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test func optionalMissingTagsAreSkippedButMalformedOrCyclicTagsStayUnknown() throws {
        let jar = try assets([
            tag("block", "test:optional", [["id": "#test:absent", "required": false], "test:real"]),
            tag("block", "test:required", ["#test:absent", "test:real"]),
            .init(path: "data/test/tags/block/bad.json", text: "invalid"),
            tag("block", "test:bad_parent", [["id": "#test:bad", "required": false]]),
            tag("block", "test:cycle", [["id": "#test:cycle", "required": false]]),
            tag("block", "test:empty", [])
        ])
        #expect(try jar.tag("test:optional", in: "block")?.members.map(\.id) == ["test:real"])
        for id in ["test:required", "test:bad", "test:bad_parent", "test:cycle", "test:absent"] {
            #expect(try jar.tag(id, in: "block") == nil)
        }
        #expect(try jar.tag("test:empty", in: "block")?.members == [])
    }

    @Test func malformedOverridesAndUnsafePathsDoNotExposeLowerTags() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = try assets([tag("block", "test:root", ["test:good"])])
        try folder("bad", root: root, entries: [.init(path: "data/test/tags/block/root.json", text: "invalid")])
        let world = try world(root, packs: ["vanilla", "file/bad"])
        #expect(try world.tags(for: ["test:root"], in: "block", assets: jar).isEmpty)
        for registry in ["../block", "block/..", "block//child", "Bad Registry", ""] {
            #expect(try jar.tag("test:root", in: registry) == nil)
        }
        for id in ["test:../root", "test:root/..", "test:", "test:root//leaf"] {
            #expect(try jar.tag(id, in: "block") == nil)
        }
    }

    @Test func directMemberIdentifiersArePreservedWithoutOpeningThemAsPaths() throws {
        let jar = try assets([tag("entity_type", "test:unusual", ["test:../declared", "test:nested//declared"])])
        #expect(try jar.tag("test:unusual", in: "entity_type")?.members.map(\.id)
                == ["test:../declared", "test:nested//declared"])
    }

    @Test func deepWideAndCorruptInputsRemainUnavailable() throws {
        var entries = try [tag("block", "test:wide", Array(repeating: "air", count: 4097))]
        for depth in 0...64 {
            entries.append(try tag("block", "test:depth\(depth)", [depth == 64 ? "air" : "#test:depth\(depth + 1)"]))
        }
        var corrupt = try tag("block", "test:corrupt", ["air"])
        corrupt.wrongCRC = true
        let jar = try assets(entries + [corrupt])
        for id in ["test:wide", "test:depth0", "test:corrupt"] { #expect(try jar.tag(id, in: "block") == nil) }
    }

    @Test func cancellationPropagatesBeforeReading() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(root, packs: ["vanilla"])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try world.tags(for: ["air"], in: "block", assets: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func tag(_ registry: String, _ id: String, _ values: [Any], replace: Bool = false) throws -> TestZIP.Entry {
        let identifier = Identifier(id)!
        let data = try JSONSerialization.data(withJSONObject: ["values": values, "replace": replace])
        return .init(path: "data/\(identifier.namespace)/tags/\(registry)/\(identifier.path).json", text: String(decoding: data, as: UTF8.self))
    }

    private func assets(_ entries: [TestZIP.Entry], version: Int = 999_999) throws -> GameAssets {
        let bytes = try TestZIP.zip([.init(path: "version.json", text: "{\"id\":\"future\",\"world_version\":\(version)}")] + entries)
        return try #require(GameAssets(data: Data(bytes)))
    }

    private func folder(_ name: String, root: URL, entries: [TestZIP.Entry]) throws {
        let folder = root.appendingPathComponent("datapacks/\(name)")
        for entry in [TestZIP.Entry(path: "pack.mcmeta", text: "{\"pack\":{\"description\":\"Fixture\"}}" )] + entries {
            try Fixtures.write(Array(entry.text.utf8), to: folder.appendingPathComponent(entry.path))
        }
    }

    private func zip(_ name: String, root: URL, entries: [TestZIP.Entry]) throws {
        let metadata = TestZIP.Entry(path: "pack.mcmeta", text: "{\"pack\":{\"description\":\"Fixture\"}}")
        try Fixtures.write(TestZIP.zip([metadata] + entries), to: root.appendingPathComponent("datapacks/\(name)"))
    }

    private func world(_ root: URL, packs: [String], version: Int32? = 999_999) throws -> World {
        var fields: [String: NBT] = ["DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))])]
        fields["DataVersion"] = version.map(NBT.int)
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(fields)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }
}
