import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct CustomModelAssetsTests {
    private func leaf(_ name: String) -> String { "{\"type\":\"model\",\"model\":\"item/\(name)\"}" }

    private func assets(_ node: String, version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        let names = ["fallback", "true", "false", "empty", "rare", "composed", "decomposed"] + (0..<17).map { "branch\($0)" }
        let files = [
            TestZIP.Entry(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            TestZIP.Entry(path: "assets/minecraft/items/sample.json", text: "{\"model\":\(node)}")
        ] + names.map { TestZIP.Entry(path: "assets/minecraft/models/item/\($0).json",
            text: "{\"parent\":\"builtin/generated\",\"textures\":{\"layer0\":\"item/\($0)\"}}") }
        return try #require(GameAssets(data: Data(TestZIP.zip(files))))
    }

    private func item(_ fields: [String: NBT] = [:]) throws -> ItemModelSelection {
        try #require(ItemStack(id: "sample", components: .compound([
            "minecraft:custom_model_data": .compound(fields)
        ])).itemModelSelection)
    }

    private func chosen(_ assets: GameAssets, _ fields: [String: NBT] = [:]) throws -> String? {
        guard let part = assets.itemModel(for: try item(fields))?.parts.first,
              case .layers(let layers) = part.model.geometry else { return nil }
        return layers.first?.material.texture.description
    }

    private func range(_ entries: String, scale: String = "1", fallback: Bool = true) -> String {
        "{\"type\":\"range_dispatch\",\"property\":\"custom_model_data\",\"scale\":\(scale),\"entries\":[\(entries)]\(fallback ? ",\"fallback\":\(leaf("fallback"))" : "")}"
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func savedFlagsSelectTheTrueBranchAndMissingIndicesSelectFalse(dataVersion: Int) throws {
        for index in [0, 1, Int(Int32.max)] {
            let definition = "{\"type\":\"condition\",\"property\":\"custom_model_data\",\"index\":\(index),\"on_true\":\(leaf("true")),\"on_false\":\(leaf("false"))}"
            let reader = try assets(definition, version: "format-fixture", dataVersion: dataVersion)
            #expect(try chosen(reader, ["flags": .byteArray([0, 1])]) == "minecraft:item/\(index == 1 ? "true" : "false")")
            #expect(try chosen(reader) == "minecraft:item/false")
            #expect(reader.defaultItemModel("sample") == reader.itemModel(for: try item()))
        }
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func stringCasesAreExactIncludingEmptyAndDistinctUnicodeSpellings(dataVersion: Int) throws {
        let cases = "{\"when\":\"\",\"model\":\(leaf("empty"))},{\"when\":[\"Rare\",\"other\"],\"model\":\(leaf("rare"))},{\"when\":\"é\",\"model\":\(leaf("composed"))},{\"when\":\"e\u{301}\",\"model\":\(leaf("decomposed"))}"
        let reader = try assets("{\"type\":\"select\",\"property\":\"custom_model_data\",\"cases\":[\(cases)],\"fallback\":\(leaf("fallback"))}",
                                version: "format-fixture", dataVersion: dataVersion)
        for (value, expected) in [("", "empty"), ("Rare", "rare"), ("rare", "fallback"), ("é", "composed"), ("e\u{301}", "decomposed")] {
            #expect(try chosen(reader, ["strings": .list(.string, [.string(value)])]) == "minecraft:item/\(expected)")
        }
        #expect(try chosen(reader) == "minecraft:item/fallback")
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func rangesUseFloatScaleSortedThresholdsAndZeroForMissingValues(dataVersion: Int) throws {
        let entries = "{\"threshold\":2,\"model\":\(leaf("branch2"))},{\"threshold\":0,\"model\":\(leaf("branch0"))},{\"threshold\":1,\"model\":\(leaf("branch1"))}"
        let reader = try assets(range(entries, scale: "2"), version: "format-fixture", dataVersion: dataVersion)
        for (value, expected) in [(Float(-1), "fallback"), (0, "branch0"), (0.5, "branch1"), (1, "branch2"), (.infinity, "branch2"), (-.infinity, "fallback"), (.nan, "fallback")] {
            #expect(try chosen(reader, ["floats": .list(.float, [.float(value)])]) == "minecraft:item/\(expected)")
        }
        #expect(try chosen(reader) == "minecraft:item/branch0")
        #expect(try chosen(assets(range(""))) == "minecraft:item/fallback")
        #expect(try chosen(assets(range("", fallback: false))) == nil)
        let zeroScale = try assets(range(entries, scale: "0"))
        #expect(try chosen(zeroScale, ["floats": .list(.float, [.float(.infinity)])]) == "minecraft:item/fallback")
        // With no saved selection, the older default reader still deliberately chooses fallback.
        #expect(reader.defaultItemModel("sample") != reader.itemModel(for: try item()))
    }

    @Test func duplicateThresholdsMatchTheGamesLinearAndBinarySearchBoundary() throws {
        for count in [15, 16, 17] {
            let entries = (0..<count).map { "{\"threshold\":1,\"model\":\(leaf("branch\($0)"))}" }.joined(separator: ",")
            let expected = count < 16 ? count - 1 : (count - 1) / 2
            #expect(try chosen(assets(range(entries)), ["floats": .intArray([1])]) == "minecraft:item/branch\(expected)")
        }
    }

    @Test func signedZeroUsesTheGamesSortAndSearchOrder() throws {
        for count in [15, 16] {
            let entries = (0..<count).map { "{\"threshold\":\($0.isMultiple(of: 2) ? "0.0" : "-0.0"),\"model\":\(leaf("branch\($0)"))}" }.joined(separator: ",")
            let reader = try assets(range(entries))
            #expect(try chosen(reader, ["floats": .intArray([0])]) == "minecraft:item/branch\(count == 15 ? 14 : 6)")
            #expect(try chosen(reader, ["floats": .list(.double, [.double(-1e-300)])]) == "minecraft:item/branch\(count == 15 ? 14 : 15)")
        }
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func savedColorsBecomeConstantTintsWithDefinitionDefaultsForMissingEntries(dataVersion: Int) throws {
        let definition = "{\"type\":\"model\",\"model\":\"item/true\",\"tints\":[{\"type\":\"custom_model_data\",\"default\":[1,0.5,0]},{\"type\":\"custom_model_data\",\"index\":1,\"default\":123}]}"
        let reader = try assets(definition, version: "format-fixture", dataVersion: dataVersion)
        #expect(reader.itemModel(for: try item(["colors": .intArray([0x123456])]))?.parts.first?.tints == [.constant(0x123456), .constant(123)])
        #expect(reader.itemModel(for: try item())?.parts.first?.tints == [.constant(0xff7f00), .constant(123)])
        #expect(reader.defaultItemModel("sample") == nil)
    }

    @Test func selectedUnsupportedModelDoesNotRecoverFallbackAndOtherLiveChoicesStayStatic() throws {
        let conditional = "{\"type\":\"condition\",\"property\":\"custom_model_data\",\"on_true\":{\"type\":\"pack:unknown\"},\"on_false\":\(leaf("false"))}"
        let reader = try assets(conditional)
        #expect(reader.itemModel(for: try item(["flags": .byteArray([1])])) == nil)
        #expect(try chosen(reader) == "minecraft:item/false")
        let live = try assets(conditional.replacingOccurrences(of: "\"custom_model_data\"", with: "\"using_item\""))
        #expect(try chosen(live, ["flags": .byteArray([1])]) == "minecraft:item/false")
    }

    @Test func malformedAndOverBudgetPropertiesStayUnavailable() throws {
        let definition = "{\"type\":\"condition\",\"property\":\"custom_model_data\",\"index\":INDEX,\"on_true\":\(leaf("true")),\"on_false\":\(leaf("false"))}"
        for index in ["-1", "true", "2147483648", "\"0\""] {
            #expect(try chosen(assets(definition.replacingOccurrences(of: "INDEX", with: index))) == nil)
        }
        let fractional = try assets(definition.replacingOccurrences(of: "INDEX", with: "0.5"))
        #expect(try chosen(fractional, ["flags": .byteArray([1])]) == "minecraft:item/true")
        let entry = "{\"threshold\":0,\"model\":\(leaf("true"))}"
        #expect(try chosen(assets(range(Array(repeating: entry, count: 4097).joined(separator: ",")))) == nil)
        #expect(try chosen(assets(range("{\"threshold\":0}"))) == nil)
        let duplicate = "{\"type\":\"select\",\"property\":\"custom_model_data\",\"cases\":[{\"when\":[\"\",\"\"],\"model\":\(leaf("true"))}],\"fallback\":\(leaf("false"))}"
        #expect(try chosen(assets(duplicate)) == nil)
    }
}
