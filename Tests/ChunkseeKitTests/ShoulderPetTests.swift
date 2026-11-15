import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct ShoulderPetTests {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func parrot(id: Int32, variant: Int32) -> NBT {
        Fixtures.mob([
            "id": .string("minecraft:parrot"), "UUID": .intArray([0, 0, 0, id]),
            "Owner": .string(owner.uuidString), "Health": .float(4), "Variant": .int(variant),
            "CustomName": .string("Shoulder Friend"), "Sitting": .byte(0),
            "Pos": .list([.double(-100), .double(65), .double(200)]),
        ])
    }

    @Test func bothShouldersUseTheSharedCreatureReaderAndPlayerVersion() throws {
        let left = parrot(id: 2, variant: 4), right = parrot(id: 3, variant: 1)
        let player = PlayerInfo(uuid: owner, nbt: .compound([
            "DataVersion": .int(5023), "Dimension": .string("minecraft:the_nether"),
            "Pos": .list([.double(12), .double(80), .double(-40)]),
            "ShoulderEntityLeft": left, "ShoulderEntityRight": right,
        ]))
        #expect(player.shoulderPets == [try #require(Creature(left, dataVersion: 5023)),
                                       try #require(Creature(right, dataVersion: 5023))])
        #expect(player.shoulderPets.map(\.owner) == [owner, owner])
        #expect(Set(player.shoulderPets.compactMap(\.uuid)).count == 2)
        #expect(player.shoulderPets.allSatisfy { $0.maximumHealth(enchantments: [:]) == 6 && $0.health == 4 })
        #expect(player.shoulderPets.first?.appearance?.variant == "minecraft:gray")
        #expect(player.position?.x == 12 && player.shoulderPets.first?.x == -100)
    }

    @Test func missingOrUnmappablePlayerLocationDoesNotHideShoulderPets() {
        for dimension in [NBT.int(21), .compound([:])] {
            let player = PlayerInfo(uuid: owner, nbt: .compound([
                "Dimension": dimension, "ShoulderEntityLeft": parrot(id: 2, variant: 0),
            ]))
            #expect(player.position == nil)
            #expect(player.shoulderPets.count == 1)
            #expect(player.shoulderPets.first?.maximumHealth(enchantments: [:]) == 6)
        }
    }

    @Test func emptyAndMalformedSidesDoNotHideTheOtherBird() throws {
        for invalid in [NBT.compound([:]), .string("not an entity"),
                        Fixtures.mob(["id": .string("minecraft:parrot")])] {
            for key in ["ShoulderEntityLeft", "ShoulderEntityRight"] {
                let other = key == "ShoulderEntityLeft" ? "ShoulderEntityRight" : "ShoulderEntityLeft"
                let player = PlayerInfo(uuid: owner, nbt: .compound([key: invalid, other: parrot(id: 2, variant: 0)]))
                #expect(player.shoulderPets.count == 1)
            }
        }
        #expect(PlayerInfo(uuid: owner, nbt: .compound([:])).shoulderPets.isEmpty)
    }

    @Test func everySavedMobTypeCanOccupyAShoulder() throws {
        for id in ["minecraft:wolf", "future:shoulder_companion"] {
            var fields = try #require(parrot(id: 4, variant: 0).compound)
            fields["id"] = .string(id)
            let player = PlayerInfo(uuid: owner, nbt: .compound([
                "ShoulderEntityLeft": .compound(fields), "ShoulderEntityRight": parrot(id: 2, variant: 0),
            ]))
            #expect(player.shoulderPets.map(\.id) == [id, "minecraft:parrot"])
            #expect(player.shoulderPets.first?.customName == "Shoulder Friend")
        }
    }
}
