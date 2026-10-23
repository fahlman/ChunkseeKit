import Foundation
import ChunkseeKit
import Testing

@Suite struct AssetPalettedTextureTests {
    private let generated: [String: Any] = [
        "type": "paletted_permutations", "textures": ["demo:trims/helmet"],
        "palette_key": "keys:base", "permutations": ["blue": "colors:blue"]
    ]
    private let base = TestZIP.Entry(path: "assets/demo/textures/trims/helmet.png", text: "", data: Data([1, 2, 3]))

    private func assets(_ sources: [[String: Any]], files: [TestZIP.Entry]? = nil,
                        version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        let json = try JSONSerialization.data(withJSONObject: ["sources": sources])
        let entries = [
            TestZIP.Entry(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            TestZIP.Entry(path: "assets/demo/atlases/items.json", text: "", data: json)
        ] + (files ?? [base])
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    @Test func generatedSpritePreservesNamespacesAndUsesPaletteImagePaths() throws {
        let files = [base,
                     TestZIP.Entry(path: "assets/keys/textures/palettes/base.png", text: "", data: Data([4])),
                     TestZIP.Entry(path: "assets/colors/textures/palettes/blue.png", text: "", data: Data([5]))]
        let reader = try assets([generated], files: files)
        let source = try #require(reader.palettedTexture("demo:trims/helmet_blue", in: "demo:items"))
        #expect(source.texture.description == "demo:trims/helmet")
        #expect(source.paletteKey.description == "keys:palettes/base")
        #expect(source.palette.description == "colors:palettes/blue")
        #expect(reader.texture(source.texture.description) == Data([1, 2, 3]))
        #expect(reader.texture(source.paletteKey.description) == Data([4]))
        #expect(reader.texture(source.palette.description) == Data([5]))
        #expect(reader.texture("demo:trims/helmet_blue") == nil)
        #expect(reader.palettedTexture("other:trims/helmet_blue", in: "demo:items") == nil)
        #expect(reader.palettedTexture("demo:trims/helmet", in: "demo:items") == nil)
    }

    @Test func explicitSeparatorsAndNestedNamesComeFromTheDefinition() throws {
        var source = generated
        source["separator"] = "/"
        source["permutations"] = ["dark/blue": "colors:group/blue"]
        let reader = try assets([source])
        let recipe = try #require(reader.palettedTexture("demo:trims/helmet/dark/blue", in: "demo:items"))
        #expect(recipe.palette.description == "colors:palettes/group/blue")
        #expect(reader.palettedTexture("demo:trims/helmet_dark/blue", in: "demo:items") == nil)
        source["separator"] = ""
        source["permutations"] = ["": "colors:blue"]
        #expect(try assets([source]).palettedTexture("demo:trims/helmet", in: "demo:items") != nil)
    }

    @Test func laterSourcesReplaceExistingSpritesButMissingBaseImagesDoNot() throws {
        var later = generated
        later["palette_key"] = "keys:later"
        let reader = try assets([generated, later])
        #expect(reader.palettedTexture("demo:trims/helmet_blue", in: "demo:items")?.paletteKey.description == "keys:palettes/later")
        later["textures"] = ["demo:trims/helmet_"]
        later["separator"] = ""
        later["permutations"] = ["blue": "colors:blue"]
        #expect(try assets([generated, later]).palettedTexture("demo:trims/helmet_blue", in: "demo:items")?.paletteKey.description == "keys:palettes/base")
        #expect(try assets([generated], files: []).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        // Missing palette data does not restore an earlier sprite. The selected reference remains
        // readable, and its image is unavailable through the existing bounded resource reader.
        let selected = try #require(reader.palettedTexture("demo:trims/helmet_blue", in: "demo:items"))
        #expect(reader.texture(selected.paletteKey.description) == nil)
    }

    @Test func plainOverridesRespectDirectoryNamespacesAndSourceOrder() throws {
        let single: [String: Any] = ["type": "single", "resource": "other:plain", "sprite": "demo:trims/helmet_blue"]
        let directory: [String: Any] = ["type": "directory", "source": "plain", "prefix": "trims/"]
        let files = [base, TestZIP.Entry(path: "assets/other/textures/plain.png", text: "", data: Data([9])),
                     TestZIP.Entry(path: "assets/demo/textures/plain/helmet_blue.png", text: "", data: Data([8]))]
        for plain in [single, directory] {
            #expect(try assets([generated, plain], files: files).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
            #expect(try assets([plain, generated], files: files).palettedTexture("demo:trims/helmet_blue", in: "demo:items") != nil)
            #expect(try assets([generated, plain]).palettedTexture("demo:trims/helmet_blue", in: "demo:items") != nil)
        }
        let foreign = [base, TestZIP.Entry(path: "assets/other/textures/plain/helmet_blue.png", text: "", data: Data([8]))]
        #expect(try assets([generated, directory], files: foreign).palettedTexture("demo:trims/helmet_blue", in: "demo:items") != nil)
    }

    @Test func malformedPathsUnsupportedSourcesAndUnknownVersionsStayUnavailable() throws {
        for (key, value) in [("textures", ["../escape"] as Any), ("textures", true as Any),
                             ("palette_key", "../escape" as Any), ("separator", false as Any),
                             ("permutations", ["blue": "bad path"] as Any),
                             ("permutations", ["/../escape": "colors:blue"] as Any)] {
            var source = generated; source[key] = value
            #expect(try assets([source]).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        }
        for unknown in ["filter", "unstitch", "mod:paletted_permutations"] {
            #expect(try assets([generated, ["type": unknown]]).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        }
        for (version, number) in [("26.4", 5023), ("26.3", 5024)] {
            #expect(try assets([generated], version: version, dataVersion: number).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        }
        #expect(try assets([generated]).palettedTexture("../escape", in: "demo:items") == nil)
        #expect(try assets([generated]).palettedTexture("demo:trims/helmet_blue", in: "../escape") == nil)
    }

    @Test func atlasWorkIsBoundedAcrossAllSources() throws {
        #expect(try assets(Array(repeating: generated, count: 257)).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        var source = generated
        source["textures"] = Array(repeating: "demo:trims/helmet", count: 4097)
        #expect(try assets([source]).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
        source["textures"] = Array(repeating: "demo:trims/helmet", count: 2049)
        #expect(try assets([source, source]).palettedTexture("demo:trims/helmet_blue", in: "demo:items") == nil)
    }

    @Test func paletteMappingMatchesRGBAndCombinesUnpremultipliedAlpha() throws {
        let mapping = try #require(AssetPaletteMapping(key: [0xFF123456, 0x80123456, 0x00010203, 0xFF99AABB],
                                                     palette: [0xFFFF0000, 0x80654321, 0xFF998877, 0x00998877]))
        #expect(mapping.color(0xFF123456) == 0x80654321)
        #expect(mapping.color(0x80123456) == 0x40654321)
        #expect(mapping.color(0x01123456) == 0x00654321)
        #expect(mapping.color(0x00123456) == 0x00123456)
        #expect(mapping.color(0x80010203) == 0x80010203)
        #expect(mapping.color(0xFF99AABB) == 0x00998877)
        #expect(mapping.color(0x7FFEDCBA) == 0x7FFEDCBA)
        #expect(AssetPaletteMapping(key: [], palette: [])?.color(0x12345678) == 0x12345678)
        #expect(AssetPaletteMapping(key: [0], palette: []) == nil)
        #expect(AssetPaletteMapping(key: Array(repeating: 0, count: 4097), palette: Array(repeating: 0, count: 4097)) == nil)
    }
}
