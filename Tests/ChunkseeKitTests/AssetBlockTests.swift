import Foundation
import ChunkseeKit
import Testing

@Suite struct AssetBlockTests {
    private let top = ##"{"from":[0,0,0],"to":[16,16,16],"faces":{"up":{"texture":"#top","tintindex":0}}}"##

    private func assets(_ definition: String, models: [String: String] = ["block/a": "{}", "block/b": "{}"],
                        version: Int = 5023) throws -> GameAssets {
        let entries = [TestZIP.Entry(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}"),
                       .init(path: "assets/example/blockstates/test.json", text: definition)] + models.map {
            .init(path: "assets/minecraft/models/\($0.key).json", text: $0.value)
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func state(_ properties: [String: String] = [:]) -> BlockState { .init("example:test", properties: properties) }

    @Test func variantsResolveInheritedGeometryAndKeepBlockTransformsSeparate() throws {
        let reader = try assets(##"{"variants":{"axis=x,waterlogged=false":{"model":"block/a","x":90,"y":450,"z":-90,"uvlock":true},"axis=y,waterlogged=false":{"model":"block/missing"}}}"##,
                                models: ["block/base": "{\"textures\":{\"top\":\"block/old\"},\"elements\":[\(top)],\"display\":{\"gui\":{\"rotation\":[30,225,0]}}}",
                                         "block/a": ##"{"parent":"block/base","textures":{"top":"example:block/new"}}"##])
        let model = try #require(reader.blockModel(for: state(["axis": "x", "waterlogged": "false"])))
        let choice = try #require(model.parts.first?.alternatives.first)
        #expect(model.parts.count == 1)
        #expect(choice.modelID.description == "minecraft:block/a")
        #expect(choice.rotation == SIMD3(90, 90, 270))
        #expect(choice.uvLock)
        #expect(choice.model.guiTransform.rotation == SIMD3(30, 225, 0))
        guard case .elements(let elements) = choice.model.geometry else { Issue.record("Expected geometry"); return }
        #expect(elements.first?.faces[.up]?.material.texture.description == "example:block/new")
        #expect(elements.first?.faces[.up]?.tintIndex == 0)
        #expect(reader.blockModel(for: state(["axis": "y", "waterlogged": "false"])) == nil)
        #expect(reader.blockModel(for: state()) == nil)
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func multipartKeepsEveryMatchingPartAndUsesPerTermNegation(version: Int) throws {
        let reader = try assets(##"{"multipart":[{"apply":{"model":"block/a"}},{"when":{"AND":[{"OR":[{"facing":"north|south"},{"powered":true}]},{"level":2}]},"apply":{"model":"block/b","y":180}},{"when":{"facing":"!north|south"},"apply":{"model":"block/b","x":90}},{"when":{"OR":[]},"apply":{"model":"missing"}}]}"##, version: version)
        let south = try #require(reader.blockModel(for: state(["facing": "south", "powered": "false", "level": "2"])))
        #expect(south.parts.map { $0.alternatives[0].rotation } == [.zero, SIMD3(0, 180, 0), SIMD3(90, 0, 0)])
        let north = try #require(reader.blockModel(for: state(["facing": "north", "powered": "false", "level": "2"])))
        #expect(north.parts.count == 2)
        let east = try #require(reader.blockModel(for: state(["facing": "east", "powered": "false", "level": "1"])))
        #expect(east.parts.count == 2)
        #expect(east.parts[1].alternatives[0].rotation == SIMD3(90, 0, 0))
        let unknown = state(["facing": "north", "level": "2"])
        #expect(reader.blockModel(for: unknown)?.parts.count == 2) // Known OR branch settles missing powered.
        #expect(reader.blockModel(for: state(["facing": "east", "level": "2"])) == nil)
        let bothNegated = try assets(##"{"multipart":[{"when":{"facing":"!north|!south"},"apply":{"model":"block/a"}}]}"##)
        #expect(bothNegated.blockModel(for: state(["facing": "north"]))?.parts.count == 1)
        let older = try assets(##"{"multipart":[{"when":{"facing":"!north"},"apply":{"model":"block/a"}}]}"##, version: 4903)
        #expect(older.blockModel(for: state(["facing": "south"]))?.parts.count == 1)
    }

    @Test func weightedAlternativesKeepTheirOrderAndSingleVariantsIgnoreWeight() throws {
        let reader = try assets(##"{"variants":{"": [{"model":"block/b","weight":3,"y":-450},{"model":"block/a"}]}}"##)
        let choices = try #require(reader.blockModel(for: state())?.parts.first?.alternatives)
        #expect(choices.map(\.modelID.description) == ["minecraft:block/b", "minecraft:block/a"])
        #expect(choices.map(\.weight) == [3, 1])
        #expect(choices.map(\.rotation) == [SIMD3(0, 270, 0), .zero])
        let single = try assets(##"{"variants":{"":{"model":"block/a","weight":false}}}"##)
        #expect(single.blockModel(for: state())?.parts.first?.alternatives.first?.weight == 1)
        let maximum = try assets(##"{"variants":{"": [{"model":"block/a","weight":2147483647}]}}"##)
        #expect(maximum.blockModel(for: state())?.parts.first?.alternatives.first?.weight == Int(Int32.max))
    }

    @Test func explicitVariantsPrecedeMultipartAndMissingPropertiesNeverInventDefaults() throws {
        let reader = try assets(##"{"variants":{"axis=x":{"model":"block/a"}},"multipart":[{"when":{"axis":"y|z"},"apply":{"model":"block/b"}}]}"##)
        #expect(reader.blockModel(for: state(["axis": "x"]))?.parts.first?.alternatives.first?.modelID.path == "block/a")
        #expect(reader.blockModel(for: state(["axis": "y"]))?.parts.first?.alternatives.first?.modelID.path == "block/b")
        #expect(reader.blockModel(for: state()) == nil)
        let unusedMissing = try assets(##"{"variants":{"axis=x,enabled=true":{"model":"block/missing"}},"multipart":[{"apply":{"model":"block/a"}}]}"##)
        #expect(unusedMissing.blockModel(for: state(["enabled": "false"]))?.parts.count == 1)
        #expect(try assets(##"{"multipart":[]}"##).blockModel(for: state())?.parts.isEmpty == true)
        #expect(try assets(##"{"multipart":[{"when":{"AND":[]},"apply":{"model":"block/a"}}]}"##).blockModel(for: state())?.parts.count == 1)
    }

    @Test func malformedOrAmbiguousDefinitionsAndSelectedResourcesAreUnavailable() throws {
        let definitions = [
            "[]", "{}", ##"{"variants":null}"##, ##"{"variants":{}}"##,
            ##"{"variants":{"":{"model":"block/a"},"axis=x":{"model":"block/b"}}}"##,
            ##"{"variants":{"axis=x,axis=y":{"model":"block/a"}}}"##,
            ##"{"variants":{"axis":{"model":"block/a"}}}"##,
            ##"{"variants":{"axis=":{"model":"block/a"}}}"##,
            ##"{"variants":{"":[]}}"##,
            ##"{"variants":{"":{"model":"../block/a"}}}"##,
            ##"{"variants":{"":{"model":"missing"}}}"##,
            ##"{"multipart":[{"when":{},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"OR":[{}]},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"OR":[],"axis":"x"},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"axis":"x||y"},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"axis":"!"},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"axis":null},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"level":1.5},"apply":{"model":"block/a"}}]}"##,
            ##"{"multipart":[{"when":{"axis":"x"}}]}"##,
            ##"{"multipart":[{"apply":{"model":"block/a"}},{"apply":{"model":"missing"}}]}"##
        ]
        for json in definitions {
            #expect(try assets(json).blockModel(for: state(["axis": "x"])) == nil, "\(json)")
        }
        let reader = try assets(##"{"variants":{"":{"model":"block/a"}}}"##, models: ["block/a": ##"{"parent":"block/a"}"##])
        #expect(reader.blockModel(for: state()) == nil)
        #expect(reader.blockModel(for: .init("../test")) == nil)
    }

    @Test func invalidNumbersAndWeightsCannotTrapOrCoerceBooleans() throws {
        for field in ["\"x\":45", "\"y\":1.5", "\"z\":true", "\"x\":2147483648", "\"uvlock\":1", "\"uvlock\":null"] {
            #expect(try assets("{\"variants\":{\"\":{\"model\":\"block/a\",\(field)}}}").blockModel(for: state()) == nil)
        }
        for weight in ["0", "-1", "true", "1.5", "2147483648", "null"] {
            #expect(try assets("{\"variants\":{\"\":[{\"model\":\"block/a\",\"weight\":\(weight)}]}}").blockModel(for: state()) == nil)
        }
        let overflow = try assets(##"{"variants":{"": [{"model":"block/a","weight":2147483647},{"model":"block/b"}]}}"##)
        #expect(overflow.blockModel(for: state()) == nil)
    }

    @Test func selectedModelsElementsAndConditionTraversalShareBounds() throws {
        for count in [256, 257] {
            let choices = Array(repeating: ##"{"model":"block/a"}"##, count: count).joined(separator: ",")
            #expect((try assets("{\"variants\":{\"\":[\(choices)]}}").blockModel(for: state()) != nil) == (count == 256))
        }
        for elements in [16, 17] {
            let model = "{\"textures\":{\"top\":\"block/a\"},\"elements\":[\(Array(repeating: top, count: elements).joined(separator: ","))]}"
            let choices = Array(repeating: ##"{"model":"block/a"}"##, count: 256).joined(separator: ",")
            #expect((try assets("{\"variants\":{\"\":[\(choices)]}}", models: ["block/a": model]).blockModel(for: state()) != nil) == (elements == 16))
        }
        var condition = ##"{"axis":"x"}"##
        for _ in 0..<63 { condition = "{\"AND\":[\(condition)]}" }
        for allowed in [true, false] {
            #expect((try assets("{\"multipart\":[{\"when\":\(condition),\"apply\":{\"model\":\"block/a\"}}]}").blockModel(for: state(["axis": "x"])) != nil) == allowed)
            condition = "{\"AND\":[\(condition)]}"
        }
        let many = Array(repeating: ##"{"when":{"axis":"y"},"apply":{"model":"block/a"}}"##, count: 4097).joined(separator: ",")
        #expect(try assets("{\"multipart\":[\(many)]}").blockModel(for: state(["axis": "x"])) == nil)
        let terms = Array(repeating: "x", count: 4096).joined(separator: "|")
        #expect(try assets("{\"multipart\":[{\"when\":{\"axis\":\"\(terms)\"},\"apply\":{\"model\":\"block/a\"}}]}").blockModel(for: state(["axis": "x"])) == nil)
    }

    @Test func definitionAndAllModelsShareTheJSONByteLimit() throws {
        let padding = String(repeating: " ", count: 9 * 1024 * 1024)
        let model = "{\"unused\":\"\(padding)\"}"
        let one = try assets(##"{"variants":{"":{"model":"block/a"}}}"##, models: ["block/a": model])
        #expect(one.blockModel(for: state()) != nil)
        let two = try assets(##"{"variants":{"": [{"model":"block/a"},{"model":"block/b"}]}}"##,
                             models: ["block/a": model, "block/b": model])
        #expect(two.blockModel(for: state()) == nil)
    }
}
