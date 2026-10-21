import Foundation
import Testing
import ChunkseeKit

@Suite struct DimensionDescriptionTests {
    @Test func recognizedDimensionsDoNotAcquireAnUnknownDescription() throws {
        let cases: [(NBT, String)] = [
            (.byte(-1), "minecraft:the_nether"), (.short(0), "minecraft:overworld"),
            (.int(1), "minecraft:the_end"), (.long(-1), "minecraft:the_nether"),
            (.string("overworld"), "minecraft:overworld"),
            (.string(":the_end"), "minecraft:the_end"),
            (.string("example:deep/caves"), "example:deep/caves"),
            (.string(""), "minecraft:"),
        ]
        for (tag, expected) in cases {
            let (player, map) = try read(tag)
            #expect(player.position?.dimension == expected)
            #expect(map.dimension == expected)
            #expect(player.unrecognizedDimension == nil && map.unrecognizedDimension == nil)
        }
    }

    @Test func unknownDimensionsHaveTheSameDescriptionInBothReaders() throws {
        let cases: [(NBT, String)] = [
            (.byte(21), "21"), (.short(-12), "-12"), (.int(31), "31"),
            (.long(.min), "-9223372036854775808"),
            (.string("Invalid Dimension"), "Invalid Dimension"),
            (.string("example:invalid:path"), "example:invalid:path"),
            (.float(0), "?"), (.double(1), "?"),
            (.compound(["id": .string("minecraft:overworld")]), "?"),
            (.list([.string("minecraft:the_nether")]), "?"),
            (.byteArray([0]), "?"), (.intArray([1]), "?"), (.longArray([-1]), "?"),
        ]
        for (tag, expected) in cases {
            let (player, map) = try read(tag)
            #expect(player.position == nil && map.dimension == nil)
            #expect(player.unrecognizedDimension == expected)
            #expect(map.unrecognizedDimension == expected)
        }
    }

    @Test func missingDimensionDoesNotInventAValue() throws {
        let (player, map) = try read(nil)
        #expect(player.position == nil && map.dimension == nil)
        #expect(player.unrecognizedDimension == nil && map.unrecognizedDimension == nil)
    }

    private func read(_ dimension: NBT?) throws -> (PlayerInfo, MapItem) {
        var playerFields: [String: NBT] = ["Pos": .list([.double(1), .double(64), .double(-1)])]
        playerFields["Dimension"] = dimension
        var mapFields: [String: NBT] = ["colors": .byteArray([Int8](repeating: 0, count: 128 * 128))]
        mapFields["dimension"] = dimension
        let player = PlayerInfo(uuid: UUID(), nbt: .compound(playerFields))
        let map = try #require(MapItem(id: 7, nbt: .compound(["data": .compound(mapFields)])))
        return (player, map)
    }
}
