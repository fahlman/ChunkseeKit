import ChunkseeKit
import Testing

@Suite struct BlockEntityRenderingTests {
    @Test func emptyResourceModelsCanHaveCodeRenderers() {
        for id in ["chest", ":oak_wall_sign", "white_banner", "player_head", "shulker_box"] {
            #expect(BlockState(id).hasBlockEntityRenderer == true)
        }
        for id in ["air", "barrier", "light", "structure_void", "stone", "torch", "short_grass"] {
            #expect(BlockState(id).hasBlockEntityRenderer == false)
        }
        // Having a block entity alone does not imply a renderer registration.
        #expect(BlockState("barrel").hasBlockEntityRenderer == false)
        // Beds now supply their geometry through resource models instead of a code renderer.
        #expect(BlockState("red_bed").hasBlockEntityRenderer == false)
    }

    @Test func registrationIsIndependentOfSavedPropertiesAndUnknownCodeStaysUnknown() {
        #expect(BlockState("chest", properties: ["facing": "south", "type": "left"]).hasBlockEntityRenderer == true)
        #expect(BlockState("chest", properties: ["unfamiliar": "value"]).hasBlockEntityRenderer == true)
        for id in ["example:chest", "minecraft:unfamiliar", "invalid name"] {
            #expect(BlockState(id).hasBlockEntityRenderer == nil)
        }
    }
}
