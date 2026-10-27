import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct AdvancementDefinitionTests {
    private let metadata = #"{"pack":{"min_format":121,"max_format":121,"description":"Fixture"}}"#
    private let diamond = #"{"display":{"title":{"translate":"advancements.story.mine_diamond.title"}}}"#

    private func entry(_ id: String, _ json: String) -> TestZIP.Entry {
        let parts = id.split(separator: ":", maxSplits: 1)
        return .init(path: "data/\(parts[0])/advancement/\(parts[1]).json", text: json)
    }

    private func assets(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"unfamiliar","world_version":999999}"#),
        ] + entries))))
    }

    private func write(_ text: String, at path: String, under root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func world(_ root: URL, packs: [String]) throws -> World {
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(5023), "DataPacks": .compound(["Enabled": .list(packs.map(NBT.string))]),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        return try World(contentsOf: root)
    }

    @Test func resourceTextRetainsLiteralTranslatedAndComposedContent() {
        func read(_ text: String) -> TextComponent.Content? { TextComponent.content(json: Data(text.utf8)) }
        #expect(read(#""A literal title""#) == .literal("A literal title"))
        #expect(read(#"{"text":"","color":"red","bold":true}"#) == .literal(""))
        #expect(read(#"["A ",{"translate":"example.title","fallback":"A fallback"}]"#) ==
                .sequence([.literal("A "), .translated(key: "example.title", fallback: "A fallback", arguments: [])]))
        #expect(read(#"{"translate":"example.title","with":["Alex",3.5,true,{"translate":"example.thing"}],"extra":[{"text":"!"}]}"#) ==
                .sequence([.translated(key: "example.title", fallback: nil, arguments: [
                    .string("Alex"), .number(3.5), .boolean(true),
                    .component(.translated(key: "example.thing", fallback: nil, arguments: [])),
                ]), .literal("!")]))
        #expect(read(#"{"type":"translatable","text":"Ignored","translate":"example.title","fallback":false}"#) ==
                .translated(key: "example.title", fallback: nil, arguments: []))
        #expect(read(#"{"text":"First codec","translate":"ignored.key"}"#) == .literal("First codec"))
        #expect(read(#"{"text":4,"translate":"example.title"}"#) ==
                .translated(key: "example.title", fallback: nil, arguments: []))
    }

    @Test func dynamicAndMalformedComponentsRemainUnavailable() {
        for json in ["null", "1", "true", "[]", "{}", #"{"text":4}"#, #"{"translate":false}"#,
                     #"{"text":"Title","extra":[]}"#, #"{"text":"Title","extra":[null]}"#,
                     #"{"translate":"title","with":false}"#, #"{"translate":"title","with":[null]}"#,
                     #"{"selector":"@s"}"#, #"{"keybind":"key.jump"}"#, #"{"score":{"name":"@s","objective":"score"}}"#,
                     #"{"nbt":"Name","entity":"@s"}"#, #"{"type":"future","text":"Unproven"}"#,
                     #"{"type":false,"text":"Unproven"}"#] {
            #expect(TextComponent.content(json: Data(json.utf8)) == nil, "\(json)")
        }
    }

    @Test func titlesComeFromDefinitionsWithoutInferringAKeyFromTheID() throws {
        let reader = try assets([
            entry("minecraft:story/mine_diamond", diamond),
            entry("example:literal", #"{"display":{"title":"A completely custom title"}}"#),
            entry("example:translated", #"{"display":{"title":{"translate":"unrelated.language.key"}}}"#),
            entry("example:unrequested", #"{"display":{"title":"Not requested"}}"#),
        ])
        let titles = try reader.advancementDefinitions(for: ["story/mine_diamond", "example:literal", "example:translated", "example:missing"])
        #expect(Set(titles.keys) == ["minecraft:story/mine_diamond", "example:literal", "example:translated"])
        #expect(titles["minecraft:story/mine_diamond"]?.title ==
                .translated(key: "advancements.story.mine_diamond.title", fallback: nil, arguments: []))
        #expect(titles["example:literal"]?.title == .literal("A completely custom title"))
        #expect(titles["example:translated"]?.title == .translated(key: "unrelated.language.key", fallback: nil, arguments: []))
    }

    @Test func folderAndZIPOverridesWinWithoutFallingBackThroughUnavailableTitles() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ids: Set<String> = ["minecraft:story/mine_diamond", "example:missing_title", "example:invalid_title", "example:invalid_json"]
        let reader = try assets(ids.map { entry($0, diamond) })
        let pack = root.appendingPathComponent("datapacks/custom")
        try write(metadata, at: "pack.mcmeta", under: pack)
        try write(#"{"display":{"title":"Folder title"}}"#, at: "data/minecraft/advancement/story/mine_diamond.json", under: pack)
        try write("{}", at: "data/example/advancement/missing_title.json", under: pack)
        try write(#"{"display":{"title":{"text":false}}}"#, at: "data/example/advancement/invalid_title.json", under: pack)
        try write("invalid", at: "data/example/advancement/invalid_json.json", under: pack)
        let archive = try TestZIP.zip([
            .init(path: "pack.mcmeta", text: metadata),
            entry("minecraft:story/mine_diamond", #"{"display":{"title":{"translate":"pack.diamond"}}}"#),
        ])
        try Fixtures.write(archive, to: root.appendingPathComponent("datapacks/high.zip"))
        let folderWorld = try world(root, packs: ["vanilla", "file/custom"])
        let folder = try folderWorld.advancementDefinitions(for: ids, assets: reader)
        #expect(folder["minecraft:story/mine_diamond"]?.title == .literal("Folder title"))
        #expect(folder["example:missing_title"] != nil && folder["example:missing_title"]?.title == nil)
        #expect(folder["example:invalid_title"] != nil && folder["example:invalid_title"]?.title == nil)
        #expect(folder["example:invalid_json"] == nil)
        let zipWorld = try world(root, packs: ["vanilla", "file/custom", "file/high.zip"])
        let top = try zipWorld.advancementDefinitions(for: ids, assets: reader)
        #expect(top["minecraft:story/mine_diamond"]?.title == .translated(key: "pack.diamond", fallback: nil, arguments: []))
        #expect(try zipWorld.advancementDefinitions(for: ids, assets: nil) == top)
        let disabled = try world(root, packs: ["vanilla"])
        #expect(try disabled.advancementDefinitions(for: ids, assets: reader) == reader.advancementDefinitions(for: ids))
    }

    @Test func missingOrDynamicTitlesDoNotDiscardSavedProgress() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try world(root, packs: ["vanilla"]), player = UUID()
        try write(#"{"example:unknown":{"done":true,"criteria":{"found":"2026-10-01 12:00:00 +0000"}},"example:dynamic":{"done":false,"criteria":{}}}"#,
                  at: "advancements/\(player.uuidString.lowercased()).json", under: root)
        let reader = try assets([entry("example:dynamic", #"{"display":{"title":{"selector":"@s"}}}"#)])
        let before = try #require(try current.advancements(for: player))
        let definitions = try current.advancementDefinitions(for: Set(before.map(\.id)), assets: reader)
        #expect(definitions["example:unknown"] == nil)
        #expect(definitions["example:dynamic"] != nil && definitions["example:dynamic"]?.title == nil)
        #expect(try current.advancements(for: player) == before)
        #expect(before.count == 2 && before.first(where: { $0.id == "example:unknown" })?.isDone == true)
    }

    @Test func textDepthWorkAndPayloadSizesAreBounded() throws {
        var json: Any = "End"
        for _ in 0..<63 { json = ["text": "", "extra": [json]] }
        #expect(TextComponent.content(json: try JSONSerialization.data(withJSONObject: json)) != nil)
        json = ["text": "", "extra": [json]]
        #expect(TextComponent.content(json: try JSONSerialization.data(withJSONObject: json)) == nil)
        let wide = try JSONSerialization.data(withJSONObject: Array(repeating: "", count: 65_536))
        #expect(TextComponent.content(json: wide) == nil)
        let oversized = Data(repeating: 32, count: 16 * 1024 * 1024 + 1)
        #expect(TextComponent.content(json: oversized) == nil)
        #expect(AdvancementDefinition(data: oversized) == nil)
    }

    @Test func requestedIDsAndPackCountsAreBoundedAndPathsStayContained() throws {
        let reader = try assets([entry("example:title", #"{"display":{"title":"Readable"}}"#)])
        #expect(try reader.advancementDefinitions(for: []).isEmpty)
        #expect(try reader.advancementDefinitions(for: ["../outside", "example:../title", "example:/title"]).isEmpty)
        #expect(try reader.advancementDefinitions(for: Set((0..<4097).map { "example:a\($0)" })).isEmpty)
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try world(root, packs: Array(repeating: "vanilla", count: 65))
        #expect(try current.advancementDefinitions(for: ["example:title"], assets: reader).isEmpty)
    }

    @Test func cancellationPreventsPublishingAnIncompleteTitleSnapshot() async throws {
        let reader = try assets([entry("example:title", diamond)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try reader.advancementDefinitions(for: ["example:title"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
