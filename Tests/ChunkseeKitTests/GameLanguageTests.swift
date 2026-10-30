import CryptoKit
import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct GameLanguageTests {
    @Test func declaredLanguageIdentityComesFromTheRequestedFilesWithoutEnglishFallback() throws {
        let reader = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"language.code":"en_us"}"#),
            .init(path: "assets/example/lang/en_pt.json", text: #"{"language.code":"qpe","greeting":"Ahoy"}"#),
            .init(path: "assets/example/lang/fra_de.json", text: #"{"language.code":"vmf_DE"}"#),
            .init(path: "assets/example/lang/sr_cs.json", text: #"{"language.code":"srp-Latn_RS"}"#),
            .init(path: "assets/example/lang/sr_sp.json", text: #"{"language.code":"srp-Cyrl_RS"}"#),
            .init(path: "assets/example/lang/no_identity.json", text: #"{"greeting":"Readable"}"#),
            .init(path: "assets/example/lang/bad_identity.json", text: #"{"language.code":{},"greeting":"Readable"}"#),
        ])
        for (file, identity) in [("en-US", "en_us"), ("en_pt", "qpe"), ("fra_de", "vmf_DE"),
                                 ("SR-cs", "srp-Latn_RS"), ("sr_sp", "srp-Cyrl_RS")] {
            let language = reader.language(file)
            #expect(language.declaredLanguageCode == identity)
            #expect(language["language.code"] == identity)
            #expect(language["block.minecraft.stone"] == "Stone")
        }
        for code in ["no_identity", "bad_identity", "unavailable", "../en_us"] {
            let language = reader.language(code)
            #expect(language.declaredLanguageCode == nil)
            #expect(language["language.code"] == "en_us")
            #expect(language["block.minecraft.stone"] == "Stone")
        }
        #expect(reader.language("no_identity")["greeting"] == "Readable")
    }

    @Test func declaredIdentityFollowsNamespaceAndInstalledFilePrecedence() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try assets([
            .init(path: "assets/a/lang/sr_sp.json", text: #"{"language.code":"srp-Latn_RS"}"#),
            .init(path: "assets/z/lang/sr_sp.json", text: #"{"language.code":"srp-Cyrl_RS"}"#),
        ])
        #expect(reader.language("sr_sp").declaredLanguageCode == "srp-Cyrl_RS")
        let object = try install(Data(#"{"language.code":"srp-Latn_RS","greeting":"Zdravo"}"#.utf8),
                                 locale: "sr_sp", under: root)
        let before = try Data(contentsOf: object)
        let installed = reader.language("sr_sp", minecraftDirectory: root)
        #expect(installed.declaredLanguageCode == "srp-Latn_RS")
        #expect(installed["greeting"] == "Zdravo" && installed["block.minecraft.stone"] == "Stone")
        #expect(try Data(contentsOf: object) == before)
        try Data(#"{"language.code":{},"greeting":"Still readable"}"#.utf8).write(to: object)
        #expect(reader.language("sr_sp", minecraftDirectory: root).declaredLanguageCode == "srp-Cyrl_RS")
        try FileManager.default.removeItem(at: object)
        #expect(reader.language("sr_sp", minecraftDirectory: root).declaredLanguageCode == "srp-Cyrl_RS")
    }

    @Test func equalityKeepsDeclaredIdentitySeparateFromFallbackText() throws {
        func language(declared: Bool) throws -> GameLanguage {
            try assets([
                .init(path: "assets/example/lang/en_us.json", text: #"{"language.code":"en_us"}"#),
                .init(path: "assets/example/lang/custom.json", text: declared ? #"{"language.code":"en_us"}"# : "{}"),
            ]).language("custom")
        }
        let declared = try language(declared: true), fallback = try language(declared: false)
        #expect(declared["language.code"] == fallback["language.code"])
        #expect(declared != fallback)
        #expect(declared == (try language(declared: true)))
    }

    @Test func languageCodesComeFromReadableFilesAndKeepNamespacesOutOfTheChoice() throws {
        let reader = try assets([
            .init(path: "assets/example/lang/fr_fr.json", text: #"{"greeting":"Bonjour"}"#),
            .init(path: "assets/another/lang/fr_fr.json", text: #"{"other":"Autre"}"#),
            .init(path: "assets/example/lang/zh_cn.json", text: "malformed JSON"),
            .init(path: "assets/minecraft/lang/deprecated.json", text: #"{"removed":[],"renamed":{}}"#),
            .init(path: "assets/example/lang/ES_es.json", text: "{}"),
            .init(path: "assets/example/lang/nested/de_de.json", text: "{}"),
            .init(path: "assets/example/notlang/de_de.json", text: "{}"),
        ])
        #expect(reader.languageCodes() == ["en_us", "fr_fr", "zh_cn"])
        #expect(reader.language("fr_FR")["greeting"] == "Bonjour")
        // Listing a readable file is not a claim that every translation inside it is valid.
        #expect(reader.language("zh_cn")["block.minecraft.stone"] == "Stone")
    }

    @Test func indexedChoicesRequireLocalBoundedRegularFilesAndValidHashes() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try install(Data(#"{"block.minecraft.stone":"Pierre"}"#.utf8), under: root)
        let indexPath = root.appendingPathComponent("assets/indexes/chosen-index.json")
        let goodHash = object.lastPathComponent, missingHash = String(repeating: "a", count: 40),
            directoryHash = String(repeating: "b", count: 40), hugeHash = String(repeating: "c", count: 40)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets/objects/bb/\(directoryHash)"), withIntermediateDirectories: true)
        try write(Data(), "assets/objects/cc/\(hugeHash)", under: root)
        let huge = try FileHandle(forWritingTo: root.appendingPathComponent("assets/objects/cc/\(hugeHash)"))
        try huge.truncate(atOffset: 17 * 1024 * 1024); try huge.close()
        let files: [String: Any] = [
            "minecraft/lang/fr_fr.json": ["hash": goodHash],
            "custom/lang/es_mx.json": ["hash": goodHash],
            "minecraft/lang/de_de.json": ["hash": missingHash],
            "minecraft/lang/it_it.json": ["hash": directoryHash],
            "minecraft/lang/nl_nl.json": ["hash": hugeHash],
            "minecraft/lang/pt_br.json": ["hash": "../outside"],
            "minecraft/lang/deprecated.json": ["hash": goodHash],
        ]
        try JSONSerialization.data(withJSONObject: ["objects": files]).write(to: indexPath)
        let reader = try assets()
        #expect(reader.languageCodes(minecraftDirectory: root) == ["en_us", "es_mx", "fr_fr"])
        #expect(reader.language("es_MX", minecraftDirectory: root)["block.minecraft.stone"] == "Pierre")
        try FileManager.default.removeItem(at: object)
        #expect(reader.languageCodes(minecraftDirectory: root) == ["en_us"])
    }

    @Test func languageChoicesDoNotFollowAnIndexedObjectOutsideTheSelectedFolder() throws {
        let root = try Fixtures.tempDirectory(), outside = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let object = try install(Data(#"{"block.minecraft.stone":"Pierre"}"#.utf8), under: root)
        let moved = outside.appendingPathComponent("language.json")
        try FileManager.default.moveItem(at: object, to: moved)
        try FileManager.default.createSymbolicLink(at: object, withDestinationURL: moved)
        #expect(try assets().languageCodes(minecraftDirectory: root) == ["en_us"])
        #expect(try assets().language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
    }

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
        #expect(reader.languageCodes(minecraftDirectory: root) == ["en_us"])
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
        #expect(reader.languageCodes(minecraftDirectory: root) == ["en_us"])
        #expect(reader.language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
        #expect(try assets(version: "../outside").languageCodes(minecraftDirectory: root) == ["en_us"])
        #expect(try assets(version: "../outside").language("fr_fr", minecraftDirectory: root)["block.minecraft.stone"] == "Stone")
    }

    @Test func legacyRuleKeysExposeTheGamesReplacementWithSelectedAndEnglishNames() throws {
        let language = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"gamerule.keepInventory":"Keep inventory after death","gamerule.doDaylightCycle":"Advance time"}"#),
            .init(path: "assets/example/lang/fr_fr.json", text: #"{"gamerule.keepInventory":"Conserver l'inventaire"}"#),
            .init(path: "assets/minecraft/lang/deprecated.json", text: #"{"removed":[],"renamed":{"gamerule.keepInventory":"gamerule.minecraft.keep_inventory","gamerule.doDaylightCycle":"gamerule.minecraft.advance_time"}}"#),
        ]).language("fr_fr")
        let inventory = try #require(language.replacementKey(for: "gamerule.keepInventory"))
        let time = try #require(language.replacementKey(for: "gamerule.doDaylightCycle"))
        #expect(inventory == "gamerule.minecraft.keep_inventory")
        #expect(time == "gamerule.minecraft.advance_time")
        #expect(language[inventory] == "Conserver l'inventaire")
        #expect(language[time] == "Advance time")
        #expect(language["gamerule.keepInventory"] == nil && language["gamerule.doDaylightCycle"] == nil)
        #expect(language.replacementKey(for: inventory) == nil)
        #expect(language.replacementKey(for: "gamerule.unknown") == nil)
    }

    @Test func replacementMetadataDoesNotInventTranslationsOrFollowChains() throws {
        let language = try assets([
            .init(path: "assets/example/lang/en_us.json", text: #"{"removed":"Gone","destination":"Discarded","first":"Moved","identity":"Kept"}"#),
            .init(path: "assets/minecraft/lang/deprecated.json", text: #"{"removed":["removed"],"renamed":{"absent":"destination","removed":"removed.destination","first":"second","second":"last","identity":"identity"}}"#),
        ]).language("en_us")
        #expect(language.replacementKey(for: "removed") == "removed.destination")
        #expect(language["removed"] == nil && language["removed.destination"] == nil)
        #expect(language.replacementKey(for: "absent") == "destination")
        #expect(language["absent"] == nil && language["destination"] == nil)
        #expect(language.replacementKey(for: "first") == "second")
        #expect(language.replacementKey(for: "second") == "last")
        #expect(language["first"] == nil && language["second"] == nil && language["last"] == "Moved")
        #expect(language.replacementKey(for: "identity") == "identity" && language["identity"] == "Kept")
    }

    @Test func missingOrMalformedReplacementMetadataKeepsDirectTranslations() throws {
        #expect(try assets().language("en_us").replacementKey(for: "block.minecraft.stone") == nil)
        for metadata in ["not JSON", "{}", #"{"removed":[],"renamed":[]}"#,
                         #"{"removed":[],"renamed":{"block.minecraft.stone":3}}"#] {
            let language = try assets([
                .init(path: "assets/minecraft/lang/deprecated.json", text: metadata),
            ]).language("en_us")
            #expect(language.replacementKey(for: "block.minecraft.stone") == nil)
            #expect(language["block.minecraft.stone"] == "Stone")
        }
    }

    @Test func equalityIncludesReplacementMetadataWithoutTranslatedValues() throws {
        func language(_ destination: String) throws -> GameLanguage {
            let rules: [String: Any] = ["removed": [], "renamed": ["old": destination]]
            let metadata = try JSONSerialization.data(withJSONObject: rules)
            return try assets([
                .init(path: "assets/minecraft/lang/deprecated.json", text: String(decoding: metadata, as: UTF8.self)),
            ]).language("en_us")
        }
        let first = try language("first"), second = try language("second")
        #expect(first["old"] == nil && first["first"] == nil && second["second"] == nil)
        #expect(first["block.minecraft.stone"] == second["block.minecraft.stone"])
        #expect(first.replacementKey(for: "old") == "first" && second.replacementKey(for: "old") == "second")
        #expect(first != second)
        #expect(first == (try language("first")))
    }
}
