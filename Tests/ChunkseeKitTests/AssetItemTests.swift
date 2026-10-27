import ChunkseeKitTestSupport
import Foundation
import ChunkseeKit
import Testing

@Suite struct AssetItemTests {
    private let version = TestZIP.Entry(path: "version.json", text: #"{"id":"fixture","world_version":5023}"#)
    private let flat = #"{"parent":"builtin/generated","textures":{"layer0":"item/base","layer1":"item/overlay"}}"#
    private let node = #"{"type":"model","model":"item/flat"}"#

    private func entry(_ directory: String, _ path: String, _ json: String) -> TestZIP.Entry {
        .init(path: "assets/minecraft/\(directory)/\(path).json", text: json)
    }

    private func assets(_ definition: String, models: [TestZIP.Entry] = []) throws -> GameAssets {
        let entries = [version, entry("items", "sample", "{\"model\":\(definition)}"), entry("models", "item/flat", flat)] + models
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    @Test func flatAndCubeItemsUseTheExistingModelOwner() throws {
        let reader = try assets(node)
        let part = try #require(reader.defaultItemModel("sample")?.parts.first)
        #expect(part.model == reader.model("item/flat"))
        #expect(part.tints.isEmpty)
        guard case .layers(let layers) = part.model.geometry else { Issue.record("Expected layers"); return }
        #expect(layers.map(\.tintIndex) == [0, 1])
        let cube = ##"{"textures":{"all":"block/stone"},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{"up":{"texture":"#all"},"south":{"texture":"#all"},"east":{"texture":"#all"}}}]}"##
        let block = try assets(#"{"type":"model","model":"block/stone"}"#,
                               models: [entry("models", "block/stone", #"{"parent":"block/base"}"#), entry("models", "block/base", cube)])
        #expect(block.defaultItemModel("sample")?.parts.first?.model == block.model("block/stone"))
    }

    @Test func defaultSelectionDoesNotEvaluateUnsupportedLiveBranches() throws {
        let selected = "{\"type\":\"select\",\"property\":\"trim_material\",\"cases\":[{\"when\":\"mod:trim\",\"model\":{\"type\":\"mod:renderer\"}}],\"fallback\":{\"type\":\"condition\",\"property\":\"using_item\",\"on_true\":{\"type\":\"special\"},\"on_false\":\(node)}}"
        #expect(try assets(selected).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
        let ranged = "{\"type\":\"range_dispatch\",\"property\":\"use_duration\",\"entries\":[{\"threshold\":1,\"model\":{\"type\":\"special\"}}],\"fallback\":\(node)}"
        #expect(try assets(ranged).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
    }

    @Test func rangeWithoutFallbackUsesItsLowestThresholdRepresentative() throws {
        let empty = #"{"type":"empty"}"#
        let ranged = "{\"type\":\"range_dispatch\",\"property\":\"compass\",\"entries\":[{\"threshold\":31.5,\"model\":\(empty)},{\"threshold\":0,\"model\":\(node)},{\"threshold\":0.5,\"model\":\(empty)}]}"
        #expect(try assets(ranged).defaultItemModel("sample")?.parts.count == 1)
        let duplicate = ranged.replacingOccurrences(of: "31.5", with: "0")
        #expect(try assets(duplicate).defaultItemModel("sample")?.parts.isEmpty == true)
    }

    @Test func inventoryContextSelectsItsStringOrListCaseInsteadOfTheHandModel() throws {
        for property in ["display_context", "minecraft:display_context"] {
            for value in [#""gui""#, #"["ground","gui","fixed","on_shelf"]"#] {
                let selected = "{\"type\":\"select\",\"property\":\"\(property)\",\"cases\":[{\"when\":\(value),\"model\":\(node)}],\"fallback\":{\"type\":\"special\"}}"
                #expect(try assets(selected).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
                let noFallback = selected.replacingOccurrences(of: ",\"fallback\":{\"type\":\"special\"}", with: "")
                #expect(try assets(noFallback).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
            }
        }
        let unrelated = "{\"type\":\"select\",\"property\":\"mod:display_context\",\"cases\":[{\"when\":\"gui\",\"model\":{\"type\":\"special\"}}],\"fallback\":\(node)}"
        #expect(try assets(unrelated).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
    }

    @Test func inventoryContextFallsBackOnlyWhenNoGUICaseMatches() throws {
        let definition = "{\"type\":\"select\",\"property\":\"display_context\",\"cases\":[{\"when\":\"ground\",\"model\":{\"type\":\"special\"}}],\"fallback\":\(node)}"
        #expect(try assets(definition).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
        #expect(try assets(definition.replacingOccurrences(of: "ground", with: "gui")).defaultItemModel("sample") == nil)
        let empty = definition.replacingOccurrences(of: "ground", with: "gui").replacingOccurrences(of: "special", with: "empty")
        #expect(try assets(empty).defaultItemModel("sample")?.parts.isEmpty == true)
        let bundle = "{\"type\":\"select\",\"property\":\"display_context\",\"cases\":[{\"when\":\"gui\",\"model\":{\"type\":\"condition\",\"property\":\"bundle/has_selected_item\",\"on_true\":{\"type\":\"special\"},\"on_false\":\(node)}}]}"
        #expect(try assets(bundle).defaultItemModel("sample") == assets(node).defaultItemModel("sample"))
    }

    @Test func malformedOrUnboundedInventoryCaseTablesStayUnavailable() throws {
        let duplicate = "{\"when\":\"gui\",\"model\":\(node)}"
        for cases in ["null", "{}", "[]", "[{}]", #"[{"when":true}]"#, #"[{"when":[]}]"#,
                      #"[{"when":["gui",false]}]"#, #"[{"when":["gui","gui"]}]"#,
                      #"[{"when":"gui"}]"#, "[\(duplicate),\(duplicate)]",
                      "[\(Array(repeating: duplicate, count: 4097).joined(separator: ","))]"] {
            let definition = "{\"type\":\"select\",\"property\":\"display_context\",\"cases\":\(cases),\"fallback\":\(node)}"
            #expect(try assets(definition).defaultItemModel("sample") == nil, "\(cases.prefix(100))")
        }
    }

    @Test func compositePartsKeepOrderAndNeverReturnAPartialPicture() throws {
        let tinted = #"{"type":"model","model":"item/flat","tints":[{"type":"constant","value":123}]}"#
        let composite = "{\"type\":\"composite\",\"models\":[\(tinted),{\"type\":\"empty\"},\(node)]}"
        let parts = try #require(try assets(composite).defaultItemModel("sample")?.parts)
        #expect(parts.count == 2)
        #expect(parts[0].tints == [.constant(123)])
        #expect(parts[1].tints.isEmpty)
        #expect(try assets(#"{"type":"empty"}"#).defaultItemModel("sample")?.parts.isEmpty == true)
        for unsupported in [#"{"type":"special"}"#, #"{"type":"mod:model","model":"item/flat"}"#,
                            #"{"type":"model","model":"item/missing"}"#] {
            #expect(try assets("{\"type\":\"composite\",\"models\":[\(node),\(unsupported)]}").defaultItemModel("sample") == nil)
        }
    }

    @Test func tintSourcesPreserveIndexesAndShareRGBConversion() throws {
        let definition = #"{"type":"model","model":"item/flat","tints":[{"type":"constant","value":-1},{"type":"dye","default":[1,0.5,0]},{"type":"potion","default":-13083194},{"type":"firework","default":-7697782},{"type":"grass","temperature":0.5,"downfall":1}]}"#
        let tints = try #require(try assets(definition).defaultItemModel("sample")?.parts.first?.tints)
        #expect(tints == [.constant(0xffffff), .dye(defaultColor: 0xff7f00), .potion(defaultColor: 0x385dc6),
                          .firework(defaultColor: 0x8a8a8a), .colorMap(texture: try #require(Identifier("colormap/grass")), pixel: SIMD2(127, 127))])
        for (temperature, downfall, expected) in [(0, 0, SIMD2(255, 255)), (1, 0, SIMD2(0, 255)), (1, 1, SIMD2(0, 0))] {
            let tint = "{\"type\":\"model\",\"model\":\"item/flat\",\"tints\":[{\"type\":\"grass\",\"temperature\":\(temperature),\"downfall\":\(downfall)}]}"
            guard case .colorMap(_, let pixel) = try #require(try assets(tint).defaultItemModel("sample")?.parts.first?.tints.first) else { Issue.record("Expected colormap"); return }
            #expect(pixel == expected)
        }
    }

    @Test func malformedSelectedValuesAndMissingResourcesStayUnavailable() throws {
        for invalid in ["null", "[]", "{}", #"{"type":false}"#, #"{"type":"select","property":"trim_material"}"#,
                        #"{"type":"condition","property":"using_item","on_false":null}"#,
                        #"{"type":"range_dispatch","property":"compass","entries":[]}"#,
                        #"{"type":"range_dispatch","property":"compass","entries":[{"threshold":true,"model":{"type":"empty"}}]}"#,
                        #"{"type":"model","model":"../unsafe"}"#, #"{"type":"model","model":"item/flat","tints":null}"#] {
            #expect(try assets(invalid).defaultItemModel("sample") == nil, "\(invalid)")
        }
        for invalidTint in [#"{"type":"unknown"}"#, #"{"type":"constant","value":true}"#,
                            #"{"type":"dye","default":[1,0]}"#, #"{"type":"dye","default":[1,2,0]}"#,
                            #"{"type":"dye","default":[1,0,false]}"#, #"{"type":"potion","default":null}"#,
                            #"{"type":"grass","temperature":0.5}"#, #"{"type":"grass","temperature":1e100,"downfall":1}"#,
                            #"{"type":"grass","temperature":0.5,"downfall":-1}"#] {
            #expect(try assets("{\"type\":\"model\",\"model\":\"item/flat\",\"tints\":[\(invalidTint)]}").defaultItemModel("sample") == nil)
        }
        let reader = try assets(node)
        for id in ["unknown", "../sample", "mod:sample"] { #expect(reader.defaultItemModel(id) == nil) }
    }

    @Test func packedTintsUseTheGamesIntegerConversion() throws {
        let definition = #"{"type":"model","model":"item/flat","tints":[{"type":"constant","value":1.5},{"type":"dye","default":2147483648}]}"#
        let tints = try #require(try assets(definition).defaultItemModel("sample")?.parts.first?.tints)
        #expect(tints == [.constant(1), .dye(defaultColor: 0)])
    }

    @Test func nestedAndWideDefinitionsHaveBoundedWork() throws {
        var nested = node
        for _ in 0..<64 { nested = "{\"type\":\"condition\",\"property\":\"using_item\",\"on_false\":\(nested)}" }
        #expect(try assets(nested).defaultItemModel("sample") == nil)
        let wide = "{\"type\":\"composite\",\"models\":[\(Array(repeating: node, count: 33).joined(separator: ","))]}"
        #expect(try assets(wide).defaultItemModel("sample") == nil)
    }

    @Test func compositeModelsShareGeometryAndJSONBudgets() throws {
        let face = ##"{"from":[0,0,0],"to":[16,16,16],"faces":{"up":{"texture":"#all"}}}"##
        let model = "{\"textures\":{\"all\":\"block/a\"},\"elements\":[\(Array(repeating: face, count: 2049).joined(separator: ","))]}"
        let composite = #"{"type":"composite","models":[{"type":"model","model":"block/a"},{"type":"model","model":"block/a"}]}"#
        let geometry = try assets(composite, models: [entry("models", "block/a", model)])
        #expect(geometry.model("block/a") != nil)
        #expect(geometry.defaultItemModel("sample") == nil)
        let largeModel = "{\"ignored\":\"\(String(repeating: "a", count: 8 * 1024 * 1024))\"}"
        let json = try assets(composite, models: [entry("models", "block/a", largeModel)])
        #expect(json.model("block/a") != nil)
        #expect(json.defaultItemModel("sample") == nil)
    }
}
