import Foundation
import ChunkseeKit
import Testing

@Suite struct AssetBlockSelectionTests {
    private let choices = #"[{"model":"block/a","weight":1},{"model":"block/b","weight":3,"y":90},{"model":"block/c","weight":7,"uvlock":true}]"#
    // These vectors come from 26.3 BlockState.getSeed and actual WeightedVariants/MultiPartModel
    // collectParts calls, including 32-bit boundary positions. No game assets are checked in.
    private let positions: [BlockPosition] = [
        .init(blockX: 0, blockY: 0, blockZ: 0), .init(blockX: 1, blockY: 64, blockZ: 1),
        .init(blockX: -1, blockY: 64, blockZ: -1), .init(blockX: 175, blockY: 63, blockZ: -16),
        .init(blockX: -1162, blockY: 62, blockZ: -1082),
        .init(blockX: 30_000_000, blockY: 319, blockZ: -30_000_000),
        .init(blockX: -30_000_000, blockY: -64, blockZ: 30_000_000),
        .init(blockX: Int(Int32.min), blockY: Int(Int32.min), blockZ: Int(Int32.min)),
        .init(blockX: Int(Int32.max), blockY: Int(Int32.max), blockZ: Int(Int32.max)),
        .init(blockX: Int(Int32.min), blockY: 0, blockZ: Int(Int32.max)),
        .init(blockX: 0, blockY: Int(Int32.min), blockZ: 0),
        .init(blockX: 0, blockY: Int(Int32.max), blockZ: 0),
        .init(blockX: 782, blockY: 72, blockZ: -999), .init(blockX: -427, blockY: 255, blockZ: 13),
        .init(blockX: 512, blockY: -64, blockZ: 511), .init(blockX: 24, blockY: 0, blockZ: 48)
    ]

    private func model(_ definition: String, state: BlockState = .init("minecraft:stone"),
                       version: Int = 5023) throws -> AssetBlock {
        let id = try #require(Identifier(state.id))
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}"),
            .init(path: "assets/\(id.namespace)/blockstates/\(id.path).json", text: definition)
        ] + ["a", "b", "c"].map { .init(path: "assets/minecraft/models/block/\($0).json", text: "{}") }
        let assets = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        return try #require(assets.blockModel(for: state))
    }

    private func names(_ model: AssetBlock, at position: BlockPosition) throws -> [String] {
        try #require(model.selectedAlternatives(at: position)).map(\.modelID.path)
    }

    @Test func directWeightedChoicesMatchOfficialPositionVectorsAndRetainGeometry() throws {
        let model = try model("{\"variants\":{\"\":\(choices)}}")
        let expected = ["a", "c", "c", "b", "b", "c", "c", "c", "b", "b", "b", "b", "c", "c", "b", "b"]
        for (position, name) in zip(positions, expected) {
            let selected = try #require(model.selectedAlternatives(at: position))
            #expect(selected.count == 1)
            #expect(selected[0].modelID.path == "block/\(name)")
            #expect(selected[0] == model.parts[0].alternatives.first { $0.modelID.path == "block/\(name)" })
            #expect(model.selectedAlternatives(at: position) == selected)
        }
        #expect(model.parts[0].alternatives.map(\.weight) == [1, 3, 7])
    }

    @Test func multipartUsesItsOwnSeedAndResetsItForEveryPart() throws {
        let one = try model("{\"multipart\":[{\"apply\":\(choices)}]}")
        let many = try model("{\"multipart\":[{\"apply\":\(choices)},{\"apply\":{\"model\":\"block/a\"}},{\"apply\":\(choices)}]}")
        let expected = ["b", "b", "b", "a", "c", "c", "b", "a", "c", "c", "b", "c", "b", "c", "c", "c"]
        for (position, name) in zip(positions, expected) {
            #expect(try names(one, at: position) == ["block/\(name)"])
            #expect(try names(many, at: position) == ["block/\(name)", "block/a", "block/\(name)"])
        }
    }

    @Test func largeWeightsUseJavaRejectionAndSingletonsRemainDeterministic() throws {
        let weighted = try model(#"{"variants":{"":[{"model":"block/a","weight":536870912},{"model":"block/b","weight":536870913}]}}"#)
        let expected = ["a", "b", "b", "a", "a", "a", "a", "a", "b", "a", "b", "b", "a", "a", "a", "a"]
        let single = try model(#"{"variants":{"":[{"model":"block/a","weight":2147483647}]}}"#)
        for (position, name) in zip(positions, expected) {
            #expect(try names(weighted, at: position) == ["block/\(name)"])
            #expect(try names(single, at: position) == ["block/a"])
        }
    }

    @Test func bedHalvesShareTheHeadPositionIncludingWrappedCoordinates() throws {
        let definition = "{\"variants\":{\"\":\(choices)}}"
        for id in ["red_bed", "straw_bed"] {
            for (facing, dx, dz) in [("north", 0, -1), ("south", 0, 1), ("east", 1, 0), ("west", -1, 0)] {
                let foot = try model(definition, state: .init("minecraft:\(id)", properties: ["part": "foot", "facing": facing]))
                let head = try model(definition, state: .init("minecraft:\(id)", properties: ["part": "head", "facing": facing]))
                let ordinary = try model(definition)
                for position in positions {
                    let normalized = BlockPosition(blockX: Int(Int32(position.x) &+ Int32(dx)), blockY: position.y,
                                                   blockZ: Int(Int32(position.z) &+ Int32(dz)))
                    #expect(try names(foot, at: position) == names(head, at: normalized))
                    #expect(try names(head, at: normalized) == names(ordinary, at: normalized))
                }
            }
        }
    }

    @Test func doorsAndDoublePlantsShareTheLowerPositionIncludingWrappedY() throws {
        let definition = "{\"variants\":{\"\":\(choices)}}"
        for id in ["oak_door", "waxed_oxidized_copper_door", "sunflower", "pitcher_crop", "small_dripleaf"] {
            let upper = try model(definition, state: .init("minecraft:\(id)", properties: ["half": "upper"]))
            let lower = try model(definition, state: .init("minecraft:\(id)", properties: ["half": "lower"]))
            let ordinary = try model(definition)
            for position in positions {
                let normalized = BlockPosition(blockX: position.x, blockY: Int(Int32(position.y) &- 1), blockZ: position.z)
                #expect(try names(upper, at: position) == names(lower, at: normalized))
                #expect(try names(lower, at: normalized) == names(ordinary, at: normalized))
            }
        }
    }

    @Test func unknownRulesAndRequiredPropertiesStayUnavailableWithoutLosingOverviewParts() throws {
        let definition = "{\"variants\":{\"\":\(choices)}}"
        for state in [BlockState("example:stone"), .init("minecraft:unknown"),
                      .init("minecraft:fake_door", properties: ["half": "upper"]),
                      .init("minecraft:red_bed"), .init("minecraft:red_bed", properties: ["part": "foot"]),
                      .init("minecraft:red_bed", properties: ["part": "foot", "facing": "up"]),
                      .init("minecraft:oak_door"), .init("minecraft:sunflower", properties: ["half": "sideways"])] {
            let resolved = try model(definition, state: state)
            #expect(resolved.parts.first?.alternatives.count == 3)
            #expect(resolved.selectedAlternatives(at: positions[0]) == nil)
        }
        for version in [4903, 5024] {
            let resolved = try model(definition, version: version)
            #expect(resolved.parts.first?.alternatives.count == 3)
            #expect(resolved.selectedAlternatives(at: positions[0]) == nil)
        }
        #expect(try names(model(definition, state: .init("stone")), at: positions[0]) == ["block/a"])
    }

    @Test func unrepresentableCoordinatesDoNotNarrowAndExplicitVariantsKeepPrecedence() throws {
        let resolved = try model("{\"variants\":{\"\":\(choices)},\"multipart\":[{\"apply\":\(choices)}]}")
        #expect(try names(resolved, at: positions[0]) == ["block/a"])
        for value in [Int.min, Int.max, Int(Int32.min) - 1, Int(Int32.max) + 1] {
            for position in [BlockPosition(blockX: value, blockY: 0, blockZ: 0),
                             .init(blockX: 0, blockY: value, blockZ: 0), .init(blockX: 0, blockY: 0, blockZ: value)] {
                #expect(resolved.selectedAlternatives(at: position) == nil)
            }
        }
        let empty = try model(#"{"multipart":[{"when":{"OR":[]},"apply":{"model":"missing"}}]}"#)
        #expect(try names(empty, at: positions[0]).isEmpty)
    }
}
