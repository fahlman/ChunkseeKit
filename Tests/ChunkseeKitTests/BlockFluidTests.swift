import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct BlockFluidTests {
    private func tag(_ values: [String] = ["water", "flowing_water"]) throws -> GameTag {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["values": values]), as: UTF8.self)
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"unfamiliar","world_version":1}"#),
            .init(path: "data/minecraft/tags/fluid/water.json", text: json)
        ]))))
        return try #require(try assets.tag("water", in: "fluid"))
    }

    @Test func waterPlantsAndOmittedWaterloggedDefaultsUseTheGameState() throws {
        let water = try tag()
        for id in ["water", "bubble_column", "kelp", "kelp_plant", "seagrass", "tall_seagrass",
                   "tube_coral", "brain_coral_fan", "fire_coral_wall_fan", "conduit", "sea_pickle"] {
            #expect(BlockState(id).containsFluid(in: water) == true, "\(id)")
        }
        for id in ["stone", "oak_stairs", "oak_slab", "oak_leaves", "lava", "air"] {
            #expect(BlockState(id).containsFluid(in: water) == false, "\(id)")
        }
        for level in 0...15 {
            #expect(BlockState("water", properties: ["level": String(level)]).containsFluid(in: water) == true)
        }
    }

    @Test func savedWaterloggingOverridesDefaultsWithoutHidingIndependentFacts() throws {
        let water = try tag()
        #expect(BlockState("oak_stairs", properties: ["waterlogged": "true"]).containsFluid(in: water) == true)
        #expect(BlockState("conduit", properties: ["waterlogged": "false"]).containsFluid(in: water) == false)
        #expect(BlockState("oak_stairs", properties: ["waterlogged": "invalid"]).containsFluid(in: water) == nil)
        #expect(BlockState("oak_stairs", properties: ["waterlogged": "invalid"]).hasSolidUpperFace == false)
        let unknownHalf = BlockState("oak_stairs", properties: ["half": "invalid", "waterlogged": "true"])
        #expect(unknownHalf.containsFluid(in: water) == true && unknownHalf.hasSolidUpperFace == nil)
        #expect(BlockState("kelp", properties: ["age": "invalid"]).containsFluid(in: water) == true)
        #expect(BlockState("stone", properties: ["waterlogged": "true"]).containsFluid(in: water) == false)
    }

    @Test func solidUpperFacesUseSupportShapesRatherThanWaterOrTextureOpacity() throws {
        let water = try tag()
        for half in ["bottom", "top"] {
            let stair = BlockState("oak_stairs", properties: ["half": half, "waterlogged": "true"])
            #expect(stair.containsFluid(in: water) == true)
            #expect(stair.hasSolidUpperFace == (half == "top"))
        }
        for type in ["bottom", "top", "double"] {
            #expect(BlockState("oak_slab", properties: ["type": type]).hasSolidUpperFace == (type != "bottom"))
        }
        #expect(BlockState("stone").hasSolidUpperFace == true)
        #expect(BlockState("glass").hasSolidUpperFace == true)
        #expect(BlockState("water").hasSolidUpperFace == false)
        #expect(BlockState("tube_coral").hasSolidUpperFace == false)
        // These support shapes need a block entity or world context, absent from a saved state.
        #expect(BlockState("shulker_box").hasSolidUpperFace == nil)
        #expect(BlockState("moving_piston").hasSolidUpperFace == nil)
        #expect(BlockState("shulker_box").containsFluid(in: nil) == false)
    }

    @Test func runtimeTagsDecideMembershipAndMissingFactsStayUnknown() throws {
        let ordinary = try tag(), changed = try tag(["lava", "flowing_lava"]), empty = try tag([])
        #expect(BlockState("water").containsFluid(in: ordinary) == true)
        #expect(BlockState("water").containsFluid(in: changed) == false)
        #expect(BlockState("lava").containsFluid(in: changed) == true)
        #expect(BlockState("water").containsFluid(in: empty) == false)
        #expect(BlockState("water").containsFluid(in: nil) == nil)
        #expect(BlockState("stone").containsFluid(in: nil) == false)
        #expect(BlockState("water", properties: ["level": "16"]).containsFluid(in: ordinary) == nil)
        for id in ["pack:unfamiliar", "minecraft:unfamiliar"] {
            let state = BlockState(id, properties: ["waterlogged": "true"])
            #expect(state.containsFluid(in: ordinary) == nil && state.hasSolidUpperFace == nil)
        }
        for id in ["water", ":water", "minecraft:water"] {
            #expect(BlockState(id).containsFluid(in: ordinary) == true)
        }
    }
}
