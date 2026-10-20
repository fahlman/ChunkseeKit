import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct UUIDTests {
    private let id = UUID(uuidString: "81234567-89AB-CDEF-FEDC-BA9876543210")!

    private var forms: [NBT] {
        [.intArray([Int32(bitPattern: 0x81234567), Int32(bitPattern: 0x89abcdef),
                    Int32(bitPattern: 0xfedcba98), 0x76543210]),
         .string(id.uuidString.lowercased()),
         .compound(["UUIDMost": .long(Int64(bitPattern: 0x8123456789abcdef)),
                    "UUIDLeast": .long(Int64(bitPattern: 0xfedcba9876543210))])]
    }

    private var entities: [NBT] {
        forms.map { form in form.compound == nil ? .compound(["UUID": form]) : form }
    }

    @Test func allSavedFormsHaveOneIdentityAndMalformedValuesStayUnknown() throws {
        for form in forms + entities {
            #expect(form.uuid == id)
            #expect(try NBT.read(NBT.compound(["value": form]).serialized()).value["value"]?.uuid == id)
        }
        for invalid in [NBT.string("not-a-uuid"), .intArray([1, 2, 3]), .intArray([1, 2, 3, 4, 5]),
                        .compound(["UUIDMost": .long(1)]), .compound(["UUIDLeast": .long(2)]),
                        .compound(["UUIDMost": .double(1), "UUIDLeast": .long(2)]),
                        .compound(["Owner": .string(id.uuidString)])] {
            #expect(invalid.uuid == nil)
        }
    }

    @Test func embeddedSingleplayerFormsIdentifyAndLoadTheSameSavedPlayer() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for entity in entities {
            var player = try #require(entity.compound)
            player["Health"] = .float(17)
            player["Dimension"] = .int(0)
            try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
                "LevelName": .string("Legacy player"), "Player": .compound(player),
            ])]), to: root.appendingPathComponent("level.dat"))
            let world = try World(contentsOf: root)
            #expect(world.level.singleplayerUUID == id)
            #expect(world.players().map(\.uuid) == [id])
            #expect(try world.playerData(id)?["Health"]?.double == 17)
            #expect(try world.playerData(UUID()) == nil)
        }
        // A modern world-level reference also identifies a valid embedded fallback record.
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "singleplayer_uuid": Fixtures.uuidInts(id), "Player": .compound(["Health": .float(13)]),
        ])]), to: root.appendingPathComponent("level.dat"))
        let world = try World(contentsOf: root)
        #expect(world.players().map(\.uuid) == [id])
        #expect(try world.playerData(id)?["Health"]?.double == 13)
        // A UUID-shaped payload is not itself an embedded player record.
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "singleplayer_uuid": Fixtures.uuidInts(id), "Player": Fixtures.uuidInts(id),
        ])]), to: root.appendingPathComponent("level.dat"))
        let malformed = try World(contentsOf: root)
        #expect(malformed.players().isEmpty)
        #expect(try malformed.playerData(id) == nil)
    }

    @Test func petOwnersAndIdentitiesUseTheSameReader() throws {
        for identity in entities {
            for owner in forms.prefix(2) {
                var entity = try #require(identity.compound)
                entity.merge(["id": .string("minecraft:wolf"), "Health": .float(8),
                              "Pos": .list([.double(1), .double(64), .double(-1)]), "Owner": owner]) { _, new in new }
                let pet = try #require(Creature(.compound(entity)))
                #expect(pet.uuid == id && pet.owner == id)
            }
        }
    }

    @Test func equippedModifierReplacesSavedIdentityAcrossAllUUIDForms() throws {
        for saved in entities {
            for worn in entities {
                var permanent = try #require(saved.compound)
                permanent.merge(["Amount": .double(4), "Operation": .int(0)]) { _, new in new }
                var equipped = try #require(worn.compound)
                equipped.merge(["AttributeName": .string("generic.maxHealth"), "Amount": .double(10),
                                "Operation": .int(0), "Slot": .string("head")]) { _, new in new }
                let player = PlayerInfo(uuid: id, nbt: .compound([
                    "Attributes": .list([.compound(["Name": .string("generic.maxHealth"), "Base": .double(20),
                                                    "Modifiers": .list([.compound(permanent)])])]),
                    "Inventory": .list([.compound(["id": .string("minecraft:iron_helmet"), "Count": .byte(1),
                                                  "Slot": .byte(103), "tag": .compound([
                                                    "AttributeModifiers": .list([.compound(equipped)])])])]),
                ]))
                #expect(player.maxHealth == 30) // The equipment replaces +4 with +10, rather than adding both.
            }
        }
    }
}
