import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct AssetReadErrorTests {
    private let version = TestZIP.Entry(path: "version.json", text: #"{"id":"any-game","world_version":1}"#)

    private func assets(_ entries: [TestZIP.Entry] = []) throws -> GameAssets {
        let data = Data(try TestZIP.zip([version] + entries))
        return try #require(GameAssets(data: data))
    }

    @Test func confirmedMissingDefinitionsNameTheirArchivePaths() throws {
        let assets = try assets()
        #expect(throws: AssetReadError.missingModel("assets/example/models/absent.json")) {
            try assets.readModel("example:absent")
        }
        #expect(throws: AssetReadError.missingModel("assets/example/items/absent.json")) {
            try assets.readDefaultItemModel("example:absent")
        }
        #expect(throws: AssetReadError.missingModel("assets/example/blockstates/absent.json")) {
            try assets.readBlockModel(for: .init("example:absent"))
        }
        #expect(assets.model("example:absent") == nil)
        #expect(assets.defaultItemModel("example:absent") == nil)
        #expect(assets.blockModel(for: .init("example:absent")) == nil)
    }

    @Test func aMissingInheritedModelIsNotAnUnsupportedFeature() throws {
        let assets = try assets([.init(path: "assets/example/models/child.json", text: #"{"parent":"example:parent"}"#)])
        #expect(throws: AssetReadError.missingModel("assets/example/models/parent.json")) {
            try assets.readModel("example:child")
        }
    }

    @Test func validModelsAndPlainTextureFailuresStaySeparate() throws {
        let assets = try assets([
            .init(path: "assets/example/models/item.json", text: #"{"parent":"minecraft:builtin/generated","textures":{"layer0":"example:absent"}}"#),
            .init(path: "assets/example/textures/present.png", text: "original bytes; image decode belongs to the client"),
        ])
        #expect(try assets.readModel("example:item") == assets.model("example:item"))
        #expect(throws: AssetReadError.missingTexture("assets/example/textures/absent.png")) {
            try assets.readTexture("example:absent")
        }
        #expect(assets.texture("example:absent") == nil)
        #expect(try assets.readTexture("example:present") == assets.texture("example:present"))
    }

    @Test func unsupportedSelectedNodesKeepFallbackRatherThanClaimMissingFiles() throws {
        let assets = try assets([
            .init(path: "assets/example/items/unsupported.json", text: #"{"model":{"type":"example:future_renderer"}}"#),
            .init(path: "assets/example/items/supported.json", text: #"{"model":{"type":"minecraft:condition","property":"minecraft:using_item","on_true":{"type":"example:future_renderer"},"on_false":{"type":"minecraft:empty"}}}"#),
        ])
        #expect(throws: AssetReadError.unsupportedFeature) { try assets.readDefaultItemModel("example:unsupported") }
        #expect(assets.defaultItemModel("example:unsupported") == nil)
        #expect(try assets.readDefaultItemModel("example:supported").parts.isEmpty)
    }

    @Test func malformedCyclicAndUnsafeResourcesAreNotMissing() throws {
        let assets = try assets([
            .init(path: "assets/example/models/bad.json", text: "{"),
            .init(path: "assets/example/items/bad.json", text: "{"),
            .init(path: "assets/example/models/cycle.json", text: #"{"parent":"example:cycle"}"#),
        ])
        #expect(throws: AssetReadError.invalidData) { try assets.readModel("example:bad") }
        #expect(throws: AssetReadError.invalidData) { try assets.readDefaultItemModel("example:bad") }
        #expect(throws: AssetReadError.invalidData) { try assets.readModel("example:cycle") }
        #expect(throws: AssetReadError.invalidData) { try assets.readTexture("example:../escape") }
    }

    @Test func corruptPresentEntriesAreUnavailableRatherThanMissing() throws {
        let assets = try assets([
            .init(path: "assets/example/models/corrupt.json", text: "{}", wrongCRC: true),
            .init(path: "assets/example/textures/corrupt.png", text: "PNG", wrongCRC: true),
        ])
        #expect(throws: AssetReadError.unavailableResource("assets/example/models/corrupt.json")) {
            try assets.readModel("example:corrupt")
        }
        #expect(throws: AssetReadError.unavailableResource("assets/example/textures/corrupt.png")) {
            try assets.readTexture("example:corrupt")
        }
    }

    @Test func changedArchiveCannotEstablishResourceAbsence() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jar = root.appendingPathComponent("game.jar")
        let bytes = Data(try TestZIP.zip([version, .init(path: "assets/example/models/present.json", text: "{}")]))
        try bytes.write(to: jar)
        let assets = try #require(try GameAssets(contentsOf: jar))
        try (bytes + Data([0])).write(to: jar)
        for name in ["present", "absent"] {
            #expect(throws: AssetReadError.unavailableResource("assets/example/models/\(name).json")) {
                try assets.readModel("example:\(name)")
            }
        }
    }

    @Test func missingSavedPropertyIsSeparateFromAnAbsentBlockModel() throws {
        let assets = try assets([
            .init(path: "assets/example/blockstates/custom.json", text: #"{"variants":{"stage=one":{"model":"example:shape"}}}"#),
            .init(path: "assets/example/models/shape.json", text: "{}"),
        ])
        #expect(throws: AssetReadError.incompleteState) {
            try assets.readBlockModel(for: .init("example:custom"))
        }
        #expect(try assets.readBlockModel(for: .init("example:custom", properties: ["stage":"one"])).parts.count == 1)
    }

    @Test func referenceBudgetDoesNotMasqueradeAsMissingData() throws {
        let entries = (0..<65).map { index in
            TestZIP.Entry(path: "assets/example/models/p\(index).json", text: index == 64 ? "{}" : "{\"parent\":\"example:p\(index+1)\"}")
        }
        let assets = try assets(entries)
        #expect(throws: AssetReadError.limitExceeded) { try assets.readModel("example:p0") }
    }

    @Test func noGameFilesCannotEstablishMissingResources() throws {
        let assets: GameAssets? = nil
        #expect(try assets?.readModel("example:unknown") == nil)
        #expect(try assets?.readTexture("example:unknown") == nil)
        #expect(assets?.containsBlockDefinition("example:unknown") == nil)
    }

    @Test func savedItemSelectionsUseTheSameFailureDetails() throws {
        let assets = try assets([
            .init(path: "assets/example/items/sample.json", text: #"{"model":{"type":"minecraft:select","property":"minecraft:custom_model_data","cases":[{"when":"chosen","model":{"type":"example:renderer"}}],"fallback":{"type":"minecraft:empty"}}}"#),
        ])
        let ordinary = try #require(ItemStack(id: "example:sample").itemModelSelection)
        let selected = try #require(ItemStack(id: "example:sample", components: .compound([
            "minecraft:custom_model_data": .compound(["strings": .list(.string, [.string("chosen")])])
        ])).itemModelSelection)
        #expect(try assets.readItemModel(for: ordinary).parts.isEmpty)
        #expect(throws: AssetReadError.unsupportedFeature) { try assets.readItemModel(for: selected) }
        #expect(assets.itemModel(for: selected) == nil)
    }

    @Test func unsupportedTransformsAndAnimatedHeadsAreNotMissingModels() throws {
        let assets = try assets([
            .init(path: "assets/example/items/transform.json", text: #"{"model":{"type":"minecraft:model","model":"example:shape","transformation":{"left_rotation":[0,0,0.70710677,0.70710677],"right_rotation":[0,0,0,1],"scale":[1,1,1],"translation":[0,0,0]}}}"#),
            .init(path: "assets/example/items/head.json", text: #"{"model":{"type":"minecraft:special","base":"example:shape","model":{"type":"minecraft:head","kind":"dragon","animation":1}}}"#),
            .init(path: "assets/example/models/shape.json", text: "{}"),
        ])
        for name in ["transform", "head"] {
            #expect(throws: AssetReadError.unsupportedFeature) { try assets.readDefaultItemModel("example:\(name)") }
        }
    }

    @Test func aRemotePlayerSkinNeedsUnavailableSavedContext() throws {
        let assets = try assets([
            .init(path: "assets/example/items/head.json", text: #"{"model":{"type":"minecraft:special","base":"example:shape","model":{"type":"minecraft:player_head"}}}"#),
            .init(path: "assets/example/models/shape.json", text: "{}"),
        ])
        let selection = try #require(ItemStack(id: "example:head", components: .compound([
            "minecraft:profile": .string("Someone")
        ])).itemModelSelection)
        #expect(throws: AssetReadError.incompleteState) { try assets.readItemModel(for: selection) }
    }

    @Test func atlasFailuresCannotBecomeMissingTextureVerdicts() throws {
        let assets = try assets([
            .init(path: "assets/example/atlases/unsupported.json", text: #"{"sources":[{"type":"example:source"}]}"#),
            .init(path: "assets/example/atlases/bad.json", text: "{"),
            .init(path: "assets/example/atlases/empty.json", text: #"{"sources":[]}"#),
        ])
        #expect(throws: AssetReadError.unsupportedFeature) {
            try assets.readPalettedTexture("example:sprite", in: "example:unsupported")
        }
        #expect(throws: AssetReadError.invalidData) { try assets.readPalettedTexture("example:sprite", in: "example:bad") }
        #expect(throws: AssetReadError.unavailableResource("assets/example/atlases/absent.json")) {
            try assets.readPalettedTexture("example:sprite", in: "example:absent")
        }
        #expect(try assets.readPalettedTexture("example:sprite", in: "example:empty") == nil)
    }

    @Test func plainSpriteAliasesAreUnsupportedUntilReplacedByAPaletteRecipe() throws {
        let alias = #"{"type":"single","resource":"example:plain","sprite":"example:base_blue"}"#
        let recipe = #"{"type":"paletted_permutations","textures":["example:base"],"palette_key":"example:key","permutations":{"blue":"example:blue"}}"#
        let identity = #"{"type":"single","resource":"example:plain"}"#
        let assets = try assets([
            .init(path: "assets/example/atlases/alias.json", text: "{\"sources\":[\(recipe),\(alias)]}"),
            .init(path: "assets/example/atlases/palette.json", text: "{\"sources\":[\(alias),\(recipe)]}"),
            .init(path: "assets/example/atlases/plain.json", text: "{\"sources\":[\(identity)]}"),
            .init(path: "assets/example/textures/plain.png", text: "plain"),
            .init(path: "assets/example/textures/base.png", text: "base"),
        ])
        #expect(throws: AssetReadError.unsupportedFeature) {
            try assets.readPalettedTexture("example:base_blue", in: "example:alias")
        }
        #expect(assets.palettedTexture("example:base_blue", in: "example:alias") == nil)
        let source = try #require(try assets.readPalettedTexture("example:base_blue", in: "example:palette"))
        #expect(source.texture.description == "example:base")
        #expect(throws: AssetReadError.missingTexture("assets/example/textures/palettes/key.png")) {
            try assets.readTexture(source.paletteKey.description)
        }
        #expect(try assets.readPalettedTexture("example:plain", in: "example:plain") == nil)
        #expect(try assets.readTexture("example:plain") == Data("plain".utf8))
    }
}
