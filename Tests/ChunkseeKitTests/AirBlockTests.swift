import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct AirBlockTests {
    @Test func generatedFlagsDistinguishKnownAirKnownNonAirAndUnknownCode() {
        for id in ["air", ":cave_air", "minecraft:void_air"] { #expect(BlockState(id).isAir == true) }
        for id in ["stone", "minecraft:water", "short_grass"] { #expect(BlockState(id).isAir == false) }
        for id in ["example:air", "minecraft:unfamiliar", "invalid name"] { #expect(BlockState(id).isAir == nil) }
        #expect(BlockState("air", properties: ["unfamiliar": "value"]).isAir == true)
    }

    @Test func airTagOverridesDoNotChangeTheHeightmapCodeFlag() throws {
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"unfamiliar","world_version":1}"#),
            .init(path: "data/minecraft/tags/block/air.json", text: #"{"replace":true,"values":["minecraft:stone"]}"#)
        ]))))
        let tag = try #require(try assets.tag("air", in: "block"))
        #expect(tag.members.map(\.id) == ["minecraft:stone"])
        #expect(BlockState("stone").isAir == false)
        #expect(BlockState("air").isAir == true)
    }
}
