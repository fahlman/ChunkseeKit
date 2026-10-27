import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct GameAssetsTests {
    private let version = TestZIP.Entry(path: "version.json", text: ##"{"id":"fixture","world_version":5023}"##)
    private let face = ##"{"from":[1,2,3],"to":[13,14,15],"faces":{"up":{"texture":"#all"}}}"##

    private func model(_ path: String, _ json: String) -> TestZIP.Entry {
        .init(path: "assets/minecraft/models/\(path).json", text: json)
    }

    private func assets(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([version] + entries))))
    }

    @Test func generatedLayersFollowParentsAndChildTextureOverrides() throws {
        let reader = try assets([
            model("item/base", ##"{"parent":"builtin/generated","textures":{"layer0":"#color","layer1":"item/overlay","color":"item/old"}}"##),
            model("item/tool", ##"{"parent":"item/base","textures":{"color":"example:item/new"}}"##)
        ])
        let result = try #require(reader.model("item/tool"))
        guard case .layers(let layers) = result.geometry else { Issue.record("Expected generated layers"); return }
        #expect(layers.map(\.material.texture.description) == ["example:item/new", "minecraft:item/overlay"])
        #expect(layers.map(\.tintIndex) == [0, 1])
        #expect(result.guiLight == .front)
        #expect(result.guiTransform.rotation == .zero)
        #expect(result.guiTransform.scale == .one)
        #expect(reader.version.id == "fixture")
        #expect(reader.version.dataVersion == 5023)
        let gap = try assets([model("item/gap", ##"{"parent":"builtin/generated","textures":{"layer0":"item/a","layer2":"item/c"}}"##)])
        guard case .layers(let partial) = try #require(gap.model("item/gap")).geometry else { Issue.record("Expected layers"); return }
        #expect(partial.count == 1)
    }

    @Test func cubeInheritanceUsesFinalTexturesAndOneGUITransform() throws {
        let faces = AssetModel.Direction.allCases.map { "\"\($0.rawValue)\":{\"texture\":\"#all\"}" }.joined(separator: ",")
        let reader = try assets([
            model("block/base", ##"{"gui_light":"side","ambientocclusion":false,"display":{"gui":{"rotation":[30,225,0],"translation":[0,16,0],"scale":[0.625,0.625,0.625]}}}"##),
            model("block/cube", "{\"parent\":\"block/base\",\"textures\":{\"all\":\"block/old\"},\"elements\":[{\"from\":[1,2,3],\"to\":[13,14,15],\"faces\":{\(faces)}}]}"),
            model("block/new", ##"{"parent":"block/cube","textures":{"all":"example:block/new"},"display":{"ground":{"rotation":[1,2,3]}}}"##),
            model("block/empty", ##"{"parent":"block/new","elements":[],"display":{"gui":{}}}"##)
        ])
        let result = try #require(reader.model("minecraft:block/new"))
        guard case .elements(let elements) = result.geometry else { Issue.record("Expected cube"); return }
        let cube = try #require(elements.first)
        #expect(cube.faces.count == 6)
        #expect(cube.faces.values.allSatisfy { $0.material.texture.description == "example:block/new" })
        #expect(cube.faces[.down]?.uv == SIMD4(1, 1, 13, 13))
        #expect(cube.faces[.up]?.uv == SIMD4(1, 3, 13, 15))
        #expect(cube.faces[.north]?.uv == SIMD4(3, 2, 15, 14))
        #expect(cube.faces[.south]?.uv == SIMD4(1, 2, 13, 14))
        #expect(cube.faces[.west]?.uv == SIMD4(3, 2, 15, 14))
        #expect(cube.faces[.east]?.uv == SIMD4(1, 2, 13, 14))
        #expect(result.guiTransform.rotation == SIMD3(30, 225, 0))
        #expect(result.guiTransform.translation == SIMD3(0, 1, 0))
        #expect(result.guiTransform.scale == SIMD3(repeating: 0.625))
        #expect(!result.ambientOcclusion)
        let empty = try #require(reader.model("block/empty"))
        #expect(empty.geometry == .elements([]))
        #expect(empty.guiTransform.rotation == .zero)
        #expect(empty.guiTransform.scale == .one)
    }

    @Test func facesAndRotationsRetainTintUVAndTranslucentMaterial() throws {
        let json = ##"{"textures":{"all":{"sprite":"block/color","force_translucent":true}},"elements":[{"from":[0,0,0],"to":[16,16,16],"rotation":{"origin":[8,8,8],"axis":"Y","angle":22.5,"rescale":true},"shade_direction_override":"up","light_emission":7,"faces":{"up":{"texture":"all","uv":[2,3,12,13],"rotation":-90,"tintindex":0,"cullface":"up"},"down":{"texture":"#all","tintindex":-2},"east":null}},{"from":[0,0,0],"to":[1,1,1],"rotation":{"origin":[8,8,8],"x":10,"z":25},"faces":{"north":{"texture":"#all"}}}]}"##
        let reader = try assets([model("block/color", json)])
        guard case .elements(let elements) = try #require(reader.model("block/color")).geometry else { Issue.record("Expected elements"); return }
        #expect(elements.count == 2)
        let element = elements[0], top = try #require(element.faces[.up])
        #expect(top.material.texture.description == "minecraft:block/color")
        #expect(top.material.forceTranslucent)
        #expect(top.uv == SIMD4(2, 3, 12, 13))
        #expect(top.rotation == 270)
        #expect(top.tintIndex == 0)
        #expect(top.cullFace == .up)
        #expect(element.faces[.down]?.tintIndex == nil)
        #expect(element.faces[.east] == nil)
        #expect(element.rotation?.origin == SIMD3(repeating: 8))
        #expect(element.rotation?.angles == .axis(.y, 22.5))
        #expect(element.rotation?.rescale == true)
        #expect(element.shadeDirectionOverride == .up)
        #expect(element.lightEmission == 7)
        #expect(elements[1].rotation?.angles == .eulerXYZ(SIMD3(10, 0, 25)))
    }

    @Test func guiTransformClampsLikeTheGame() throws {
        let reader = try assets([model("item/clamped", ##"{"display":{"gui":{"translation":[160,-160,8],"scale":[10,-10,0.5]}}}"##)])
        let transform = try #require(reader.model("item/clamped")).guiTransform
        #expect(transform.translation == SIMD3(5, -5, 0.5))
        #expect(transform.scale == SIMD3(4, -4, 0.5))
    }

    @Test func unresolvedResourcesAndCyclesStayUnavailable() throws {
        let reader = try assets([
            model("item/a", ##"{"parent":"item/b"}"##), model("item/b", ##"{"parent":"item/a"}"##),
            model("item/missing", ##"{"parent":"item/absent"}"##),
            model("item/texture-cycle", ##"{"parent":"builtin/generated","textures":{"layer0":"#other","other":"#layer0"}}"##),
            model("item/dangling", ##"{"parent":"builtin/generated","textures":{"layer0":"#absent"}}"##),
            model("item/unsupported", ##"{"parent":"builtin/entity"}"##),
            model("item/null", ##"{"parent":"builtin/generated","elements":null}"##),
            model("item/bad", "[]")
        ])
        for path in ["item/a", "item/b", "item/missing", "item/texture-cycle", "item/dangling", "item/unsupported", "item/null", "item/bad", "item/absent", "", "/item/a", "item/../item/a", "item//a", "UPPER:a"] {
            #expect(reader.model(path) == nil, "\(path)")
        }
    }

    @Test func modelIntegerFieldsUseGameConversionBeforeFieldValidation() throws {
        let cases: [(tint: String, rotation: String, light: String, expectedTint: Int?, expectedRotation: Int, expectedLight: Int)] = [
            ("1.9", "90.9", "15.9", 1, 90, 15),
            ("-1.9", "-90.9", "-0.9", nil, 270, 0),
            ("2147483648", "4294967386.9", "4294967303.9", nil, 90, 7),
            ("18446744073709551617.9", "1e100", "1e100", 1, 0, 0),
            ("99999999999999999999999999999999999999999", "360.9", "0", nil, 0, 0),
        ]
        for test in cases {
            let json = ##"{"textures":{"all":"block/a"},"elements":[{"from":[0,0,0],"to":[16,16,16],"light_emission":\##(test.light),"faces":{"up":{"texture":"#all","rotation":\##(test.rotation),"tintindex":\##(test.tint)}}}]}"##
            let reader = try assets([model("block/numbers", json)])
            guard case .elements(let elements) = try #require(reader.model("block/numbers")).geometry else {
                Issue.record("Missing numeric model"); return
            }
            let element = try #require(elements.first), face = try #require(element.faces[.up])
            #expect(element.lightEmission == test.expectedLight)
            #expect(face.rotation == test.expectedRotation && face.tintIndex == test.expectedTint)
        }
        for field in ["tintindex", "rotation"] {
            for value in ["true", "null", #""1""#, "[]", "{}"] {
                let element = face.replacingOccurrences(of: "\"#all\"", with: "\"#all\",\"\(field)\":\(value)")
                #expect(try assets([model("bad", "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(element)]}")]).model("bad") == nil)
            }
        }
        for value in ["16.9", "-1.9", "true", "null", #""7""#] {
            let element = face.replacingOccurrences(of: "\"from\"", with: "\"light_emission\":\(value),\"from\"")
            #expect(try assets([model("bad", "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(element)]}")]).model("bad") == nil)
        }
    }

    @Test func modelFloatFieldsParseTheOriginalDecimalWithoutDoubleRounding() throws {
        let element = face.replacingOccurrences(of: "[1,2,3]", with: "[1.0000000596046448,2,3]")
        let reader = try assets([model("numbers", "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(element)]}")])
        guard case .elements(let elements) = try #require(reader.model("numbers")).geometry else {
            Issue.record("Missing float model"); return
        }
        #expect(elements.first?.from.x.bitPattern == 0x3f80_0001)
    }

    @Test func malformedNumericAndShapeFieldsStayUnavailable() throws {
        let badElements = [
            face.replacingOccurrences(of: "[1,2,3]", with: "[1,2]"),
            face.replacingOccurrences(of: "[1,2,3]", with: "[true,2,3]"),
            face.replacingOccurrences(of: "[1,2,3]", with: "[1e100,2,3]"),
            face.replacingOccurrences(of: "[1,2,3]", with: "[-17,2,3]"),
            face.replacingOccurrences(of: "[13,14,15]", with: "[33,14,15]"),
            face.replacingOccurrences(of: "\"up\"", with: "\"diagonal\""),
            face.replacingOccurrences(of: "\"#all\"", with: "\"#all\",\"rotation\":45"),
            face.replacingOccurrences(of: "\"#all\"", with: "\"#all\",\"rotation\":1.5"),
            face.replacingOccurrences(of: "\"#all\"", with: "\"#all\",\"tintindex\":true"),
            face.replacingOccurrences(of: "\"#all\"", with: "\"#all\",\"uv\":[0,0,1e100,16]")
        ]
        for element in badElements {
            let reader = try assets([model("block/bad", "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(element)]}")])
            #expect(reader.model("block/bad") == nil, "\(element)")
        }
        for json in [##"{"textures":{"a":true}}"##, ##"{"gui_light":"unknown"}"##, ##"{"ambientocclusion":1}"##,
                     ##"{"display":{"gui":{"scale":[1e100,1,1]}}}"##, ##"{"parent":42}"##] {
            #expect(try assets([model("bad", json)]).model("bad") == nil)
        }
    }

    @Test func boundedParentAndTextureChains() throws {
        for count in [64, 65] {
            let entries = (0..<count).map { index in
                model("chain/\(index)", index == count - 1 ? "{}" : "{\"parent\":\"chain/\(index + 1)\"}")
            }
            #expect((try assets(entries).model("chain/0") != nil) == (count == 64))
            var textures = ["layer0": "#slot1"]
            for index in 1..<count { textures["slot\(index)"] = index == count - 1 ? "item/a" : "#slot\(index + 1)" }
            let json = try JSONSerialization.data(withJSONObject: ["parent": "builtin/generated", "textures": textures])
            #expect((try assets([model("item/chain", String(decoding: json, as: UTF8.self))]).model("item/chain") != nil) == (count == 64))
        }
        let many = Array(repeating: face, count: 4097).joined(separator: ",")
        #expect(try assets([model("block/many", "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(many)]}")]).model("block/many") == nil)
    }

    @Test func archiveValidationAndTextureReadsNeverExtractOrWrite() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let texture = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let bytes = Data(try TestZIP.zip([version, .init(path: "assets/minecraft/textures/item/a.png", text: "", data: texture, compressed: true)]))
        let url = root.appendingPathComponent("fixture.jar")
        try bytes.write(to: url)
        let reader = try #require(try GameAssets(contentsOf: url))
        #expect(reader.texture("item/a") == texture)
        #expect(reader.texture("minecraft:item/a") == texture)
        #expect(reader.texture("item/missing") == nil)
        #expect(reader.texture("../version") == nil)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["fixture.jar"])
        #expect(throws: (any Error).self) { try GameAssets(contentsOf: root.appendingPathComponent("absent.jar")) }
        #expect(GameAssets(data: Data("broken".utf8)) == nil)
        #expect(try GameAssets(data: Data(TestZIP.zip([]))) == nil)
        let badVersion = TestZIP.Entry(path: "version.json", text: ##"{"id":"x","world_version":true}"##)
        #expect(try GameAssets(data: Data(TestZIP.zip([badVersion]))) == nil)
        let badTexture = TestZIP.Entry(path: "assets/minecraft/textures/item/a.png", text: "bad", wrongCRC: true)
        #expect(try assets([badTexture]).texture("item/a") == nil)
    }
}
