import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct PortalResourceTests {
    typealias Block = NetherPortal.Block

    @Test func publicWorldUsesJarFolderAndZIPScalesAndTheSavedDestinationBorder() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        func definition(_ scale: String) -> String {
            "{\"min_y\":0,\"height\":256,\"logical_height\":256,\"has_ceiling\":false,\"coordinate_scale\":\(scale)}"
        }
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"any-game","world_version":1}"#),
            .init(path: "data/minecraft/dimension_type/overworld.json", text: definition("1")),
            .init(path: "data/minecraft/dimension_type/the_nether.json", text: definition("8")),
        ]))))
        let folder = root.appendingPathComponent("datapacks/Lower")
        let metadata = #"{"pack":{"description":"Portal overrides","min_format":1,"max_format":999}}"#
        try Fixtures.write(Array(metadata.utf8), to: folder.appendingPathComponent("pack.mcmeta"))
        let folderType = folder.appendingPathComponent("data/minecraft/dimension_type/overworld.json")
        try Fixtures.write(Array(definition("3").utf8), to: folderType)
        try Fixtures.write(TestZIP.zip([
            .init(path: "pack.mcmeta", text: metadata),
            .init(path: "data/minecraft/dimension_type/the_nether.json", text: definition("2")),
        ]), to: root.appendingPathComponent("datapacks/Upper.zip"))
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "DataVersion": .int(999999), "DataPacks": .compound(["Enabled": .list([
                .string("vanilla"), .string("file/Lower"), .string("file/Upper.zip")])]),
            "WorldGenSettings": .compound(["dimensions": .compound([
                NetherPortal.overworld: .compound(["type": .string("minecraft:overworld")]),
                NetherPortal.nether: .compound(["type": .string("minecraft:the_nether")]),
            ])]),
        ])]), to: root.appendingPathComponent("level.dat"))
        let netherFolder = root.appendingPathComponent("dimensions/minecraft/the_nether")
        try FileManager.default.createDirectory(at: netherFolder.appendingPathComponent("region"), withIntermediateDirectories: true)
        let borderFile = netherFolder.appendingPathComponent("data/minecraft/world_border.dat")
        try Fixtures.writeGzippedNBT(.compound(["data": .compound([
            "center_x": .double(50.5), "center_z": .double(-10.25), "size": .double(20.5),
            "lerp_target": .double(1), "lerp_time": .long(2000),
        ])]), to: borderFile)
        let bytes = try Data(contentsOf: borderFile)
        let world = try World(contentsOf: root)
        let types = try world.dimensionTypes(assets: assets)
        #expect(types[NetherPortal.overworld]?.coordinateScale == 3)
        #expect(types[NetherPortal.nether]?.coordinateScale == 2)
        let border = try world.worldBorder(of: #require(world.dimension("the_nether")))
        #expect(NetherPortal.destination(of: Block(x: 100, y: 64, z: -200), from: "overworld",
            dimensionTypes: types, destinationBorder: border) == Block(x: 60, y: 64, z: -21))
        #expect(NetherPortal.destination(of: Block(x: 1, y: 64, z: 1), from: "overworld",
            dimensionTypes: types, destinationBorder: border) == Block(x: 40, y: 64, z: -1))
        #expect(try Data(contentsOf: borderFile) == bytes)

        // Invalid higher-priority scale preserves build facts without inventing the jar's scale.
        try Fixtures.write(Array(definition("0").utf8), to: folderType)
        let invalid = try world.dimensionTypes(assets: assets)
        #expect(invalid[NetherPortal.overworld]?.height == 256)
        #expect(invalid[NetherPortal.overworld]?.coordinateScale == nil)
        #expect(NetherPortal.destination(of: Block(x: 100, y: 64, z: 0), from: "overworld",
            dimensionTypes: invalid, destinationBorder: border) == nil)
    }

    @Test func invalidScaleDoesNotDiscardOtherDimensionFacts() throws {
        for value in [0.0, -1, .infinity, .nan, 30_000_001, 0.000001] {
            let type = try #require(DimensionType(PortalFixtures.definition(scale: value)))
            #expect(type.coordinateScale == nil)
            #expect(type.height == 256)
        }
        for value in [Double(Float(0.00001)), 0.5, 1, 30_000_000] {
            #expect(DimensionType(PortalFixtures.definition(scale: value))?.coordinateScale == value)
        }
    }

    @Test func linksExcludeBorderExteriorAndKeepUnknownReturnSeparate() {
        let source = NetherPortal(dimension: "overworld", blocks: [Block(x: 0, y: 64, z: 0)])
        let outside = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: 0, y: 64, z: 0)])
        let inside = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: 1, y: 64, z: 1)])
        var border = PortalFixtures.border
        border.centerX = 10.25; border.centerZ = 10.25; border.size = 20
        let borders = [NetherPortal.nether: border]
        #expect(source.link(into: [outside, inside], dimensionTypes: PortalFixtures.types, borders: borders)
                == .portal(inside, block: inside.entry))
        #expect(source.roundTrip(into: [inside], returningThrough: [source],
                dimensionTypes: PortalFixtures.types, borders: borders) == .returnUnknown(target: inside, block: inside.entry))
        #expect(source.link(into: [inside], dimensionTypes: PortalFixtures.types, borders: [:]) == nil)
        #expect(source.link(into: [inside], dimensionTypes: [:], borders: borders) == nil)
        border.size = .nan
        #expect(source.link(into: [inside], dimensionTypes: PortalFixtures.types,
                borders: [NetherPortal.nether: border]) == nil)
        let empty = NetherPortal(dimension: NetherPortal.overworld, blocks: [])
        #expect(empty.link(into: [inside], dimensionTypes: PortalFixtures.types, borders: borders) == nil)
    }

    @Test func customDimensionsTravelToNetherAndReturnViaOverworld() {
        var types = PortalFixtures.types
        types["example:sky"] = DimensionType(PortalFixtures.definition(scale: 4))
        let source = NetherPortal(dimension: "example:sky", blocks: [Block(x: 100, y: 64, z: 0)])
        let target = NetherPortal(dimension: NetherPortal.nether, blocks: [Block(x: 50, y: 64, z: 0)])
        let returning = NetherPortal(dimension: NetherPortal.overworld, blocks: [Block(x: 400, y: 64, z: 0)])
        #expect(NetherPortal.targetDimension(from: "the_end") == NetherPortal.nether)
        #expect(NetherPortal.targetDimension(from: "Invalid ID") == nil)
        #expect(source.roundTrip(into: [target], returningThrough: [returning], dimensionTypes: types,
            borders: PortalFixtures.borders) == .oneWay(target: target, block: target.entry,
                returning: .portal(returning, block: returning.entry)))
    }

    @Test func tinyAndInvertedSavedBordersUseTheGamesClampOrder() {
        var border = PortalFixtures.border
        border.centerX = 0.000005; border.centerZ = 0.000005; border.size = 0.000001
        #expect(NetherPortal.destination(of: Block(x: -1, y: 64, z: 1), from: "overworld",
            dimensionTypes: PortalFixtures.types, destinationBorder: border) == Block(x: 0, y: 64, z: -1))
        border.centerX = 0; border.centerZ = 0
        for size in [0.0, -1.0] {
            border.size = size
            #expect(NetherPortal.destination(of: Block(x: -1, y: 64, z: 1), from: "overworld",
                dimensionTypes: PortalFixtures.types, destinationBorder: border) == Block(x: 0, y: 64, z: -1))
        }
    }
}
