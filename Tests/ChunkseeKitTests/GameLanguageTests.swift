import CryptoKit
import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct GameLanguageTests {
    private func assets(_ entries: [TestZIP.Entry] = [], version: String = "fixture") throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":999999}"),
            .init(path: "assets/minecraft/lang/en_us.json", text: #"{"block.minecraft.stone":"Stone","entity.minecraft.wolf":"Wolf","effect.minecraft.speed":"Speed","merchant.level.1":"Novice","stat.generalButton":"General","advancements.story.root.title":"Minecraft","gameMode.survival":"Survival","options.difficulty.easy":"Easy","color.minecraft.blue":"Blue"}"#),
        ] + entries))))
    }

    @Test func independentlyReadEquivalentLanguagesCompareEqual() throws {
        let first = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"shared":"English","fallback":"Kept"}"#),
            .init(path: "assets/example/lang/fr_fr.json", text: #"{"shared":"Français","number":3}"#),
        ]).language("fr_FR")
        let second = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"fallback":"Kept","shared":"Unused change"}"#),
            .init(path: "assets/example/lang/fr_fr.json", text: #"{"number":"3","shared":"Français"}"#),
        ], version: "another-source").language("fr-fr")
        #expect(first == second)
        #expect(first["shared"] == "Français" && first["fallback"] == "Kept")
        #expect(try assets().language("unavailable") == assets().language("en_US"))
    }

    @Test func equalityIncludesSelectedFallbackAndNotYetQueriedKeys() throws {
        func language(selected: String = "Français", fallback: String = "Kept", future: String = "Original") throws -> GameLanguage {
            let english = try JSONSerialization.data(withJSONObject: ["fallback": fallback, "future": future])
            let french = try JSONSerialization.data(withJSONObject: ["shared": selected])
            return try assets([
                .init(path: "assets/example/lang/en_us.json", text: String(decoding: english, as: UTF8.self)),
                .init(path: "assets/example/lang/fr_fr.json", text: String(decoding: french, as: UTF8.self)),
            ]).language("fr_fr")
        }
        let initial = try language()
        #expect(initial["shared"] == "Français")
        #expect(initial != (try language(selected: "Changed")))
        #expect(initial != (try language(fallback: "Changed")))
        #expect(initial != (try language(future: "Changed")))
    }

    private func write(_ data: Data, _ path: String, under root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    private func hash(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func install(_ data: Data, locale: String = "fr_fr", under root: URL) throws -> URL {
        let objectHash = hash(data), objectPath = "assets/objects/\(objectHash.prefix(2))/\(objectHash)"
        let object: [String: Any] = ["hash": objectHash, "size": data.count]
        let objects: [String: Any] = [
            "minecraft/lang/\(locale).json": object,
            "unrelated/malformed": "does not hide the requested language",
        ]
        let index = try JSONSerialization.data(withJSONObject: ["objects": objects])
        let reference: [String: Any] = ["id": "chosen-index", "sha1": hash(index), "size": index.count]
        let metadata = try JSONSerialization.data(withJSONObject: ["assetIndex": reference])
        try write(metadata, "versions/fixture/fixture.json", under: root)
        try write(index, "assets/indexes/chosen-index.json", under: root)
        try write(data, objectPath, under: root)
        return root.appendingPathComponent(objectPath)
    }

    @Test func allTranslationKeyCategoriesUseTheSameEnglishLookup() throws {
        let language = try assets().language("en-US")
        #expect(language["block.minecraft.stone"] == "Stone")
        #expect(language["entity.minecraft.wolf"] == "Wolf")
        #expect(language["effect.minecraft.speed"] == "Speed")
        #expect(language["merchant.level.1"] == "Novice")
        #expect(language["stat.generalButton"] == "General")
        #expect(language["advancements.story.root.title"] == "Minecraft")
        #expect(language["gameMode.survival"] == "Survival")
        #expect(language["options.difficulty.easy"] == "Easy")
        #expect(language["color.minecraft.blue"] == "Blue")
        #expect(language["item.example:unknown"] == nil)
        #expect(language[""] == nil)
    }

    @Test func installedLocaleUsesItsSelectedIndexAndFallsBackPerKey() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try install(Data(#"{"block.minecraft.stone":"Pierre","entity.minecraft.wolf":"Loup","custom.key":"Texte"}"#.utf8), under: root)
        let reader = try assets(), language = reader.language("FR-fr", minecraftDirectory: root)
        #expect(language["block.minecraft.stone"] == "Pierre" && language["entity.minecraft.wolf"] == "Loup")
        #expect(language["effect.minecraft.speed"] == "Speed" && language["custom.key"] == "Texte")
        #expect(language["example.missing"] == nil)
        #expect(reader.language("fr_fr")["block.minecraft.stone"] == "Stone")
        #expect(reader.language("es_es", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        #expect(reader.language("../fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
    }

    @Test func currentLocalFilesAreUsedAndMissingOrMalformedValuesKeepEnglish() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets()
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        let object = try install(Data(#"{"block.minecraft.stone":"Pierre"}"#.utf8), under: root)
        // The launcher index can change while older version metadata still has its download hash.
        let indexPath = root.appendingPathComponent("assets/indexes/chosen-index.json")
        var indexBytes = try Data(contentsOf: indexPath)
        indexBytes.append(contentsOf: [32, 10])
        try indexBytes.write(to: indexPath)
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Pierre")
        try Data(#"{"block.minecraft.stone":"Local text"}"#.utf8).write(to: object)
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Local text")
        try FileManager.default.removeItem(at: object)
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        try install(Data("malformed JSON".utf8), under: root)
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        try install(Data(#"{"block.minecraft.stone":{},"entity.minecraft.wolf":"Loup"}"#.utf8), under: root)
        let partial = reader.language("fr_fr", minecraftDirectory: root)
        #expect(partial["block.minecraft.stone"] == "Stone" && partial["entity.minecraft.wolf"] == "Loup")
        try write(Data("{}".utf8), "assets/indexes/chosen-index.json", under: root)
        #expect(reader.language("fr_fr", minecraftDirectory: root)["entity.minecraft.wolf"] == "Wolf")
    }

    @Test func jarNamespacesFormatsAndDeprecatedKeysFollowTheGameData() throws {
        let reader = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"item.example.new":"New Item","old.name":"Old English","removed":"Gone","missing.destination":"Remove this too","identity":"Kept"}"#),
            .init(path: "assets/example/lang/fr_fr.json", text: #"{"item.example.new":"Nouvel objet","old.name":"Ancien","format":"%2$04d / %.2f / %s","number":3,"bool":true}"#),
            .init(path: "assets/minecraft/lang/deprecated.json", text: #"{"removed":["removed"],"renamed":{"old.name":"new.name","missing.source":"missing.destination","identity":"identity"}}"#),
        ])
        let language = reader.language("fr_fr")
        #expect(language["item.example.new"] == "Nouvel objet" && language["block.minecraft.stone"] == "Stone")
        #expect(language["new.name"] == "Ancien" && language["old.name"] == nil)
        #expect(language["removed"] == nil && language["missing.destination"] == nil && language["identity"] == "Kept")
        #expect(language["format"] == "%2$s / %s / %s")
        #expect(language["number"] == "3" && language["bool"] == "true")
    }

    @Test func invalidPathsAndOversizedFilesCannotReplaceEnglish() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data(#"{"assetIndex":{"id":"../outside"}}"#.utf8), "versions/fixture/fixture.json", under: root)
        let reader = try assets()
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        try write(Data(#"{"assetIndex":{"id":"huge"}}"#.utf8), "versions/fixture/fixture.json", under: root)
        let huge = root.appendingPathComponent("assets/indexes/huge.json")
        try write(Data(), "assets/indexes/huge.json", under: root)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: 17 * 1024 * 1024)
        try handle.close()
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        #expect(try assets(version: "../outside").language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
    }
}
