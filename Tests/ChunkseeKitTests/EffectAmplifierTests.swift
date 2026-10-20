import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct EffectAmplifierTests {
    // Expected values independently obtained from official 26.3 ExtraCodecs.UNSIGNED_BYTE/NbtOps,
    // using DFU 10.0.21. Include Number's signed-int narrowing before float-to-byte conversion.
    static let cases: [(tag: NBT, expected: Int)] = [
        (.byte(-1), 255), (.byte(-128), 128), (.byte(0), 0), (.byte(127), 127),
        (.short(256), 0), (.short(-1), 255), (.short(.min), 0), (.short(.max), 255),
        (.int(300), 44), (.int(-1), 255), (.int(.min), 0), (.int(.max), 255),
        (.long(.min), 0), (.long(.max), 255), (.long(4_294_967_597), 45),
        (.float(300.9), 44), (.float(-1.9), 255), (.float(-0.9), 0),
        (.float(.nan), 0), (.float(.infinity), 255), (.float(-.infinity), 0),
        (.double(300.9), 44), (.double(-1.9), 255), (.double(-0.9), 0),
        (.double(.nan), 0), (.double(.infinity), 255), (.double(-.infinity), 0),
        (.double(2_147_483_646.9), 254), (.double(2_147_483_647.9), 255),
        (.double(-2_147_483_648.9), 0),
    ]

    @Test func savedNumericRepresentationsMatchTheGameThroughPlayerFiles() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for legacy in [false, true] {
            let entries = Self.cases.map { pair in
                legacy
                ? NBT.compound(["Id": .byte(11), "Amplifier": pair.tag, "Duration": .int(-1)])
                : NBT.compound(["id": .string("minecraft:resistance"), "amplifier": pair.tag, "duration": .int(-1)])
            }
            let file = dir.appendingPathComponent("player.dat")
            try Fixtures.writeGzippedNBT(.compound([legacy ? "ActiveEffects" : "active_effects": .list(entries)]), to: file)
            let player = PlayerInfo(uuid: UUID(), nbt: try NBT.read(contentsOf: file))
            #expect(player.activeEffects.map(\.amplifier) == Self.cases.map(\.expected))
            #expect(player.activeEffects.map(\.level) == Self.cases.map { $0.expected + 1 })
            #expect(player.activeEffects.allSatisfy { $0.durationTicks == -1 && $0.id == "minecraft:resistance" })
        }
    }

    @Test func nonnumericValuesStayAbsentAndMissingDefaultsRemain() {
        let invalid: [NBT] = [.string("300"), .compound([:]), .list([.byte(1)]), .byteArray([1]), .intArray([1]), .longArray([1])]
        let effects = invalid.map { NBT.compound(["id": .string("minecraft:speed"), "amplifier": $0, "duration": .int(100)]) }
            + [.compound(["id": .string("minecraft:speed"), "duration": .int(100)]),
               .compound(["id": .string("minecraft:strength"), "amplifier": .int(300), "duration": .int(0)])]
        let player = PlayerInfo(uuid: UUID(), nbt: .compound(["active_effects": .list(effects)]))
        #expect(player.activeEffects == [StatusEffect(id: "minecraft:speed", amplifier: 0, durationTicks: 100)])
    }
}
