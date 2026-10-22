import Foundation
import ChunkseeKit
import Testing

@Suite struct ContainerItemModelTests {
    private let transform = #"{"left_rotation":[1,0,0,0],"right_rotation":[0,0,0,1],"scale":[0.9995,0.9995,0.9995],"translation":[0.5,1.4995,0.5]}"#
    private let colors = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                          "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]

    private func definition(_ type: String = "chest", texture: String = "normal", extra: String = "", transform: String? = nil) -> String {
        let local = transform.map { ",\"transformation\":\($0)" } ?? ""
        return "{\"type\":\"special\",\"base\":\"item/container\",\"model\":{\"type\":\"\(type)\",\"texture\":\"\(texture)\"\(extra)}\(local)}"
    }

    private func assets(_ definition: String, version: String = "26.3", dataVersion: Int = 5023,
                        base: String? = nil) throws -> GameAssets {
        let inherited = #"{"gui_light":"front","ambientocclusion":false,"display":{"gui":{"rotation":[30,45,0],"translation":[1,2,3],"scale":[0.625,0.625,0.625]}}}"#
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/sample.json", text: "{\"model\":\(definition)}"),
            .init(path: "assets/minecraft/models/item/container.json", text: base ?? #"{"parent":"item/template"}"#),
            .init(path: "assets/minecraft/models/item/template.json", text: inherited)
        ]
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func elements(_ reader: GameAssets) throws -> [AssetModel.Element] {
        let part = try #require(reader.defaultItemModel("sample")?.parts.first)
        guard case .elements(let boxes) = part.model.geometry else { throw TestError.geometry }
        return boxes
    }

    @Test func all28ContainersUseCuboidsAndInheritedInventoryPresentation() throws {
        var cases: [(String, String, String)] = [("chest", "chest", "normal"), ("trapped_chest", "chest", "trapped"),
                                               ("ender_chest", "chest", "ender")]
        for (item, texture) in [("copper", "copper"), ("exposed_copper", "copper_exposed"),
                                ("weathered_copper", "copper_weathered"), ("oxidized_copper", "copper_oxidized")] {
            cases += [(item + "_chest", "chest", texture), ("waxed_" + item + "_chest", "chest", texture)]
        }
        cases.append(("shulker_box", "shulker_box", "shulker"))
        cases += colors.map { ($0 + "_shulker_box", "shulker_box", "shulker_" + $0) }
        #expect(cases.count == 28)
        for (item, type, texture) in cases {
            let shulker = type == "shulker_box"
            var node = definition(type, texture: texture, transform: shulker ? transform : nil)
            if item == "chest" || item == "trapped_chest" {
                // The unsupported seasonal branch must not replace the normal static fallback.
                node = "{\"type\":\"select\",\"property\":\"local_time\",\"cases\":[{\"when\":\"12-25\",\"model\":\(definition(texture: "christmas"))}],\"fallback\":\(node)}"
            }
            let reader = try assets(node), model = try #require(reader.defaultItemModel("sample"))
            #expect(model.parts.count == 1 && model.parts[0].tints.isEmpty)
            let part = model.parts[0], inherited = try #require(reader.model("item/container"))
            #expect(part.model.guiTransform == inherited.guiTransform)
            #expect(part.model.guiLight == .front && !part.model.ambientOcclusion)
            let boxes = try elements(reader)
            #expect(boxes.count == (shulker ? 2 : 3), "\(item)")
            let expected = "minecraft:entity/\(shulker ? "shulker" : "chest")/\(texture)"
            for box in boxes {
                #expect(box.faces.count == 6 && box.rotation == nil)
                #expect(box.faces.values.allSatisfy { $0.material.texture.description == expected && $0.tintIndex == nil })
            }
        }
    }

    @Test func closedChestKeepsTheBodyLidLatchAndEntityUVRegions() throws {
        let boxes = try elements(assets(definition()))
        #expect(boxes.map(\.from) == [SIMD3(1, 0, 1), SIMD3(1, 9, 1), SIMD3(7, 7, 15)])
        #expect(boxes.map(\.to) == [SIMD3(15, 10, 15), SIMD3(15, 14, 15), SIMD3(9, 11, 16)])
        #expect(boxes[0].faces[.up]?.uv == SIMD4(7, 8.25, 10.5, 4.75))
        #expect(boxes[0].faces[.south]?.uv == SIMD4(10.5, 8.25, 14, 10.75))
        #expect(boxes[1].faces[.up]?.uv == SIMD4(7, 3.5, 10.5, 0))
        #expect(boxes[2].faces[.south]?.uv == SIMD4(1, 0.25, 1.5, 1.25))
        #expect(boxes[0].faces[.up]?.rotation == 0 && boxes[0].faces[.south]?.rotation == 180)
    }

    @Test func shulkerDefinitionTransformPreservesTheTopAndSideRegions() throws {
        let boxes = try elements(assets(definition("shulker_box", texture: "shulker_red", transform: transform)))
        let expectedFrom: [SIMD3<Float>] = [SIMD3(0.004, 4.002, 0.004), SIMD3(0.004, 0.004, 0.004)]
        let expectedTo: [SIMD3<Float>] = [SIMD3(15.996, 15.996, 15.996), SIMD3(15.996, 8, 15.996)]
        for index in boxes.indices {
            for axis in 0..<3 {
                #expect(abs(boxes[index].from[axis] - expectedFrom[index][axis]) < 0.00001)
                #expect(abs(boxes[index].to[axis] - expectedTo[index][axis]) < 0.00001)
            }
        }
        #expect(boxes[0].faces[.up]?.uv == SIMD4(4, 0, 8, 4))
        #expect(boxes[0].faces[.north]?.uv == SIMD4(12, 4, 16, 7))
        #expect(boxes[0].faces[.south]?.uv == SIMD4(4, 4, 8, 7))
        #expect(boxes.allSatisfy { $0.faces.values.allSatisfy { $0.rotation == 0 } })
        let shifted = transform.replacingOccurrences(of: "[0.5,1.4995,0.5]", with: "[0.75,1.4995,0.5]")
        let changed = try elements(assets(definition("shulker_box", texture: "shulker_red", transform: shifted)))
        #expect(abs(changed[0].from.x - boxes[0].from.x - 4) < 0.00001)
    }

    @Test func unverifiedVersionsAndSpecialKindsStayUnavailable() throws {
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999), ("modded", 5023)] {
            let reader = try assets(definition(), version: name, dataVersion: version)
            #expect(reader.defaultItemModel("sample") == nil)
            #expect(reader.model("item/container") != nil)
        }
        for node in [definition(texture: "christmas"), definition(texture: "unknown"), definition(texture: "mod:normal"),
                     definition(texture: "../normal"), definition("shulker_box", texture: "shulker_unknown", transform: transform),
                     definition("mod:chest"), definition("bed"), definition(extra: #", "chest_type":"left""#),
                     definition(extra: #", "chest_type":null"#), definition(extra: #", "openness":0.5"#),
                     definition(extra: #", "openness":true"#), definition(extra: #", "openness":null"#),
                     definition().replacingOccurrences(of: "item/container", with: "item/missing")] {
            #expect(try assets(node).defaultItemModel("sample") == nil, "\(node)")
        }
        #expect(try assets(definition(extra: #", "chest_type":"single", "openness":0"#)).defaultItemModel("sample") != nil)
    }

    @Test func unsupportedOrMalformedLocalTransformsNeverDisappearSilently() throws {
        let invalid = ["null", "[]", "{}", transform.replacingOccurrences(of: "[1,0,0,0]", with: "[0,1,0,0]"),
                       transform.replacingOccurrences(of: "[0,0,0,1]", with: "[1,0,0,0]"),
                       transform.replacingOccurrences(of: "[1,0,0,0]", with: "[2,0,0,0]"),
                       transform.replacingOccurrences(of: "0.9995", with: "-1"),
                       transform.replacingOccurrences(of: "0.9995", with: "0"),
                       transform.replacingOccurrences(of: "0.9995", with: "true"),
                       transform.replacingOccurrences(of: "0.9995", with: "1e100"),
                       transform.replacingOccurrences(of: "[0.5,1.4995,0.5]", with: "[100,0,0]"),
                       transform.replacingOccurrences(of: "[0.5,1.4995,0.5]", with: "[0,0]")]
        for value in invalid {
            #expect(try assets(definition("shulker_box", texture: "shulker", transform: value)).defaultItemModel("sample") == nil, "\(value)")
        }
    }

    @Test func containersSharePartAndGeometryBudgetsWithOrdinaryModels() throws {
        let node = definition()
        let wide = "{\"type\":\"composite\",\"models\":[\(Array(repeating: node, count: 33).joined(separator: ","))]}"
        #expect(try assets(wide).defaultItemModel("sample") == nil)
        let mixed = "{\"type\":\"composite\",\"models\":[\(node),\(definition(texture: "unknown"))]}"
        #expect(try assets(mixed).defaultItemModel("sample") == nil)
        let element = ##"{"from":[0,0,0],"to":[16,16,16],"faces":{"up":{"texture":"#all"}}}"##
        let base = "{\"textures\":{\"all\":\"block/stone\"},\"elements\":[\(Array(repeating: element, count: 4094).joined(separator: ","))]}"
        let reader = try assets(node, base: base)
        #expect(reader.model("item/container") != nil)
        #expect(reader.defaultItemModel("sample") == nil)
    }

    private enum TestError: Error { case geometry }
}
