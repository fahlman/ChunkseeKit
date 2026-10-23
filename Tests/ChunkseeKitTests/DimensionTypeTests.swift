import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct DimensionTypeTests {
    private func definition(minY: Int32 = -64, height: Int32 = 384, logical: Int32 = 384,
                            ceiling: Bool = false) -> NBT {
        .compound(["min_y": .int(minY), "height": .int(height), "logical_height": .int(logical),
                   "has_ceiling": .byte(ceiling ? 1 : 0)])
    }

    private func world(at root: URL, types: [String: NBT], packs: [String] = ["vanilla"],
                       version: Int32 = 5023, modern: Bool = true) throws -> World {
        let settings = NBT.compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        var data: [String: NBT] = ["LevelName": .string("Dimension Types"), "DataVersion": .int(version),
                                  "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))])]
        if modern {
            try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(version), "data": settings]),
                                         to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        } else { data["WorldGenSettings"] = settings }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(data)]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    private func pack(_ name: String, at root: URL, id: String = "minecraft:overworld",
                      json: String = "{\"min_y\":-128,\"height\":512,\"logical_height\":256,\"has_ceiling\":true}",
                      metadata: String = "{\"pack\":{\"min_format\":121,\"max_format\":121,\"description\":\"Test\"}}") throws -> URL {
        let folder = root.appendingPathComponent("datapacks/" + name)
        try Fixtures.write(Array(metadata.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        let id = try #require(Identifier(id))
        try Fixtures.write(Array(json.utf8), to: folder.appendingPathComponent("data/\(id.namespace)/dimension_type/\(id.path).json"))
        return folder
    }

    @Test func savedTypesControlLimitsRegardlessOfDimensionName() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, types: ["minecraft:overworld": .string("minecraft:the_nether"),
            "example:sky": .string("overworld"), "example:caves": .string("minecraft:overworld_caves"),
            "example:empty": .string("the_end"), "example:unknown": .string("example:missing")])
        let files = ["level.dat", "data/minecraft/world_gen_settings.dat"].map { root.appendingPathComponent($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let types = try world.dimensionTypes()
        #expect(types.count == 4)
        #expect(types["minecraft:overworld"]?.buildRange == 0...255)
        #expect(types["minecraft:overworld"]?.logicalHeight == 128)
        #expect(types["minecraft:overworld"]?.hasCeiling == true)
        #expect(types["example:sky"]?.buildRange == -64...319)
        #expect(types["example:sky"]?.hasCeiling == false)
        #expect(types["example:caves"]?.buildRange == -64...319)
        #expect(types["example:caves"]?.hasCeiling == true)
        #expect(types["example:empty"]?.buildRange == 0...255)
        #expect(types["example:empty"]?.logicalHeight == 256)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func inlineTypesKeepLegacyLayoutAndUnknownVersionsUsable() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, types: ["example:deep": definition(minY: -2032, height: 4064, logical: 0),
            "example:high": definition(minY: 2016, height: 16, logical: 16, ceiling: true),
            "example:unverified": .string("minecraft:overworld")], packs: ["unavailable"], version: 9999, modern: false)
        let types = try world.dimensionTypes()
        #expect(types.count == 2)
        #expect(types["example:deep"]?.buildRange == -2032...2031)
        #expect(types["example:deep"]?.logicalHeight == 0)
        #expect(types["example:high"]?.buildRange == 2016...2031)
        #expect(types["example:high"]?.hasCeiling == true)
    }

    @Test func invalidInlineTypesCannotProduceGuessedOrOverflowingLimits() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bad: [NBT] = [definition(minY: -2033), definition(minY: 2032, height: 16, logical: 16),
            definition(minY: 1), definition(height: 0), definition(height: 17), definition(height: 4080),
            definition(minY: 2016, height: 32, logical: 16), definition(logical: -1), definition(logical: 385),
            definition(minY: .max), definition(height: .max), .compound(["min_y": .long(.min)]),
            .compound(["min_y": .int(-64), "height": .int(384), "logical_height": .int(384)]),
            .string("Not A Type"), .string("")]
        let world = try world(at: root, types: Dictionary(uniqueKeysWithValues: bad.enumerated().map { ("example:bad\($0.offset)", $0.element) }))
        #expect(try world.dimensionTypes().isEmpty)
    }

    @Test func folderOverridesFollowEnabledPriorityAndRefreshWithoutWriting() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try pack("Lower", at: root)
        let upper = try pack("Upper", at: root, json: "{\"min_y\":0,\"height\":128,\"logical_height\":64,\"has_ceiling\":false}")
        _ = try pack("Disabled", at: root, json: "invalid")
        let world = try world(at: root, types: ["example:sky": .string("minecraft:overworld")],
                              packs: ["vanilla", "file/Lower", "file/Upper"])
        #expect(try world.dimensionTypes()["example:sky"]?.buildRange == 0...127)
        try FileManager.default.removeItem(at: upper.appendingPathComponent("data/minecraft/dimension_type/overworld.json"))
        #expect(try world.dimensionTypes()["example:sky"]?.buildRange == -128...383)
        try Fixtures.write(Array("{}".utf8), to: upper.appendingPathComponent("data/minecraft/dimension_type/overworld.json"))
        #expect(try world.dimensionTypes().isEmpty) // An invalid override must not expose a lower definition.
    }

    @Test func nestedCustomTypeCanResolveBelowVanilla() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try pack("Custom", at: root, id: "example:deep/caves")
        let world = try world(at: root, types: ["example:mine": .string("example:deep/caves")],
                              packs: ["file/Custom", "vanilla"])
        let type = try #require(try world.dimensionTypes()["example:mine"])
        #expect(type.minY == -128 && type.height == 512 && type.maxY == 383)
        #expect(type.logicalHeight == 256 && type.hasCeiling)
    }

    @Test(arguments: ["{\"min_y\":-64.5,\"height\":384,\"logical_height\":384,\"has_ceiling\":true}",
                      "{\"min_y\":0,\"height\":1e100,\"logical_height\":0,\"has_ceiling\":true}",
                      "{\"min_y\":0,\"height\":16,\"logical_height\":16,\"has_ceiling\":\"true\"}"])
    func invalidJSONOverrideDoesNotFallBack(json: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try pack("Invalid", at: root, json: json)
        let world = try world(at: root, types: ["overworld": .string("overworld")], packs: ["vanilla", "file/Invalid"])
        #expect(try world.dimensionTypes().isEmpty)
    }

    @Test(arguments: ["file/Missing", "file/Archive.zip", "minecart_improvements", "file/../Outside",
                      "file/Overlay", "file/Filtered", "file/BadMetadata"])
    func unresolvedHigherPacksPreventVanillaGuessing(packID: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.write([0], to: root.appendingPathComponent("datapacks/Archive.zip"))
        _ = try pack("Overlay", at: root, metadata: "{\"pack\":{},\"overlays\":{\"entries\":[]}}")
        _ = try pack("Filtered", at: root, metadata: "{\"pack\":{},\"filter\":{\"block\":[]}}")
        _ = try pack("BadMetadata", at: root, metadata: "invalid")
        let world = try world(at: root, types: ["minecraft:overworld": .string("minecraft:overworld"),
                                               "example:inline": definition()], packs: ["vanilla", packID])
        let types = try world.dimensionTypes()
        #expect(types.count == 1 && types["example:inline"]?.buildRange == -64...319)
    }

    @Test func unverifiedVanillaAndMissingPackListStayUnknown() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unknown = try world(at: root, types: ["overworld": .string("overworld")], version: 9999)
        #expect(try unknown.dimensionTypes().isEmpty)
        let noPacks = try world(at: root, types: ["overworld": .string("overworld")], packs: [])
        #expect(try noPacks.dimensionTypes().isEmpty)
    }

    @Test func modernRecordDoesNotResurrectLegacyTypesAndAliasesStayAmbiguous() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try world(at: root, types: ["overworld": definition()], modern: false)
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5023), "data": .compound([:])]),
                                     to: root.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        #expect(try legacy.dimensionTypes().isEmpty)
        let aliases = try world(at: root, types: ["overworld": definition(), "minecraft:overworld": definition(),
                                                  "example:valid": definition(), "invalid ID": definition()])
        #expect(try aliases.dimensionTypes().keys.sorted() == ["example:valid"])
    }

    @Test func typePathsDoNotEscapePackAndFileReadErrorsPropagate() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try pack("Custom", at: root, id: "example:valid")
        let world = try world(at: root, types: ["example:dot": .string("example:../valid"),
            "example:symlink": .string("example:escape"), "example:readerror": .string("example:directory")],
                              packs: ["file/Custom"])
        let definitions = pack.appendingPathComponent("data/example/dimension_type")
        let outside = root.appendingPathComponent("outside.json")
        try FileManager.default.copyItem(at: definitions.appendingPathComponent("valid.json"), to: outside)
        try FileManager.default.createSymbolicLink(at: definitions.appendingPathComponent("escape.json"), withDestinationURL: outside)
        #expect(try world.dimensionTypes().isEmpty)
        let unreadable = definitions.appendingPathComponent("directory.json")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
        #expect(try world.dimensionTypes().isEmpty)
        try FileManager.default.removeItem(at: unreadable)
        try FileManager.default.copyItem(at: definitions.appendingPathComponent("valid.json"), to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        #expect(throws: (any Error).self) { try world.dimensionTypes() }
    }
}
