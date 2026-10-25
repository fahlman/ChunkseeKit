import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct NBTWriterTests {
    @Test func containerOrderEmptyListTypesAndModifiedUTF8KeepTheirBytes() {
        let value = NBT.compound([
            "z": .byte(-1),
            "a": .list([.compound(["k": .string("é\u{0}🌍")]), .compound([:])]),
            "empty": .list(.short, [])
        ])
        let expected: [UInt8] = [
            10, 0, 1, 114, // Compound named r.
            9, 0, 1, 97, 10, 0, 0, 0, 2, // a: two compounds.
            8, 0, 1, 107, 0, 10, 0xc3, 0xa9, 0xc0, 0x80, 0xed, 0xa0, 0xbc, 0xed, 0xbc, 0x8d,
            0, 0, // End both list elements.
            9, 0, 5, 101, 109, 112, 116, 121, 2, 0, 0, 0, 0, // empty: short list.
            1, 0, 1, 122, 255, 0 // z and root end.
        ]
        #expect(value.serialized(rootName: "r") == expected)
    }

    @Test func deeplyNestedCompoundsSerializeBeyondTheReadersIndependentLimit() {
        for depth in [200, 511, 512, 600] {
            var value = NBT.compound(["answer": .int(42)])
            for _ in 0..<depth { value = .compound(["child": value]) }
            let childHeader: [UInt8] = [10, 0, 5] + Array("child".utf8)
            let answer: [UInt8] = [3, 0, 6] + Array("answer".utf8) + [0, 0, 0, 42, 0]
            let expected = [UInt8]([10, 0, 0]) + Array(repeating: childHeader, count: depth).flatMap { $0 }
                + answer + Array(repeating: 0, count: depth)
            #expect(value.serialized() == expected)
        }
    }

    @Test func twoHundredPassengerPairsCanBeWrittenAndReadOnATestWorker() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let position = NBT.list([.double(1), .double(64), .double(-2)])
        var entity = NBT.compound(["id": .string("minecraft:cat"), "Pos": position])
        for _ in 0..<200 {
            entity = .compound(["id": .string("minecraft:boat"), "Pos": position, "Passengers": .list([entity])])
        }
        let chunk = NBT.compound(["DataVersion": .int(5023), "Entities": .list([entity])])
        let file = root.appendingPathComponent("passengers.dat")
        try Fixtures.writeGzippedNBT(chunk, to: file)
        let decoded = try NBT.read(contentsOf: file)
        #expect(decoded["DataVersion"]?.int == 5023)
        var current = try #require(decoded["Entities"]?.list?.first)
        for _ in 0..<200 {
            #expect(current["id"]?.string == "minecraft:boat")
            #expect(current["Pos"] == position)
            current = try #require(current["Passengers"]?.list?.first)
        }
        #expect(current["id"]?.string == "minecraft:cat")
        #expect(current["Pos"] == position)
        #expect(current["Passengers"] == nil)
    }
}
