import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct SavedTextUpgradeTests {
    private func value(_ encoded: String) throws -> NBT {
        let data = try #require(Data(base64Encoded: encoded))
        let root = try NBT.read(Array(data)).value
        return try #require(root["value"])
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "text" && $0.version < GeneratedSavedText.boundary })
    func legacyConversionMatchesMinecraft(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let input = try value(sample.input)
        let actual = SavedTextUpgrade.component(input)
        if let encoded = sample.output {
            let expected = try value(encoded)
            #expect(actual == expected, "\(input)")
            #expect(TextComponent.content(actual) == TextComponent.content(expected))
        } else {
            #expect(sample.error != nil)
            #expect(TextComponent.content(actual) == nil)
        }
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "text" && $0.version >= GeneratedSavedText.boundary })
    func nativeGameFixturesRemainUnchanged(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let input = try value(sample.input)
        let output = try value(#require(sample.output))
        #expect(SavedTextUpgrade.Context(dataVersion: sample.version).component(input) == output)
        #expect(input == output)
    }

    @Test(arguments: [#""Sword""#, "[1]", "{}", #"{"text":"a literal name"}"#, "true", "1", "null"])
    func nativeStringsAreNeverReparsed(_ literal: String) {
        #expect(TextComponent.content(.string(literal)) == .literal(literal))
        #expect(TextComponent.plainText(.string(literal)) == literal)
        let nested = NBT.compound(["text": .string(literal), "extra": .list([.string(literal)])])
        #expect(TextComponent.content(nested) == .sequence([.literal(literal), .literal(literal)]))
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "item" })
    func itemNamesAndBooksMatchTheGamesUpgradedRecords(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let input = try value(sample.input)
        let output = try value(#require(sample.output))
        let actual = try #require(ItemStack(input, dataVersion: sample.version)).allItems
        let expected = try #require(ItemStack(output)).allItems
        #expect(actual.count == expected.count)
        for (read, game) in zip(actual, expected) {
            #expect(read.id == game.id && read.count == game.count)
            #expect(read.customName == game.customName)
            #expect(read.book == game.book)
        }
    }

    @Test func legacyBookKeepsMixedLiteralAndStructuredPages() throws {
        let saved = NBT.compound([
            "id": .string("minecraft:written_book"), "Count": .byte(1),
            "tag": .compound([
                "title": .string(#""Book title""#), "author": .string("Fixture"),
                "pages": .list([.string(#""First page""#), .string(#"{"text":"Second page"}"#)]),
            ]),
        ])
        let item = try #require(ItemStack(saved, dataVersion: GeneratedSavedText.bookBoundary))
        #expect(item.book == BookContent(title: #""Book title""#, author: "Fixture",
                                        pages: ["First page", "Second page"]))
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "entity" })
    func entityAndPassengerNamesMatchTheGame(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let input = try value(sample.input)
        let output = try value(#require(sample.output))
        let actual = NormalizedEntities([input], dataVersion: sample.version).records
        let expected = NormalizedEntities([output], dataVersion: sample.targetVersion).records
        #expect(actual.count == expected.count)
        for (read, game) in zip(actual, expected) {
            #expect(read.nbt["CustomName"].flatMap(TextComponent.content)
                    == game.nbt["CustomName"].flatMap(TextComponent.content))
        }
        #expect(actual.first?.nbt["custom"] == input["custom"])
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "blockEntity" })
    func signAndContainerTextMatchTheGame(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let input = try value(sample.input)
        let output = try value(#require(sample.output))
        let actual = SaveDataUpgrade.blockEntity(input, dataVersion: sample.version)
        let expected = SaveDataUpgrade.blockEntity(output, dataVersion: sample.targetVersion)
        #expect(actual["CustomName"].flatMap(TextComponent.content)
                == expected["CustomName"].flatMap(TextComponent.content))
        #expect(actual["custom"] == input["custom"])
        func signs(_ record: NBT, version: Int) -> [Sign] {
            Sign.signs(inChunk: Fixtures.chunk(x: 0, z: 0, dataVersion: version, sections: [],
                                              extra: ["block_entities": .list([record])]))
        }
        let read = signs(input, version: sample.version), game = signs(output, version: sample.targetVersion)
        // Sign identity deliberately retains its saved ID, even when the game's full fix
        // chain renamed it. Compare the text that both encodings present to the user.
        #expect(read.map(\.front) == game.map(\.front))
        if input["back_text"] != nil {
            #expect(read.map(\.back) == game.map(\.back))
        } else {
            #expect(read.allSatisfy { $0.back.allSatisfy(\.isEmpty) })
            #expect(game.allSatisfy { $0.back.allSatisfy(\.isEmpty) })
        }
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "player" })
    func playerInventoriesMatchTheGame(_ sample: GeneratedSavedTextProofs.Sample) throws {
        let uuid = UUID()
        func player(_ encoded: String, version: Int) throws -> PlayerInfo {
            let root = try value(encoded)
            var fields = try #require(root.compound)
            fields["DataVersion"] = .int(Int32(version))
            return PlayerInfo(uuid: uuid, nbt: .compound(fields))
        }
        let actual = try player(sample.input, version: sample.version)
        let expected = try player(#require(sample.output), version: sample.targetVersion)
        #expect(actual.inventory.map(\.customName) == expected.inventory.map(\.customName))
        #expect(actual.enderChest.map(\.customName) == expected.enderChest.map(\.customName))
        #expect(actual.shoulderPets.count == 1 && expected.shoulderPets.count == 1)
        #expect(actual.shoulderPets.map(\.customName) == expected.shoulderPets.map(\.customName))
    }

    @Test(arguments: GeneratedSavedTextProofs.samples.filter { $0.kind == "map" })
    func savedMapBannerNamesMatchTheGame(_ sample: GeneratedSavedTextProofs.Sample) throws {
        func map(_ encoded: String, version: Int?) throws -> MapItem {
            let root = try value(encoded)
            var fields = try #require(root.compound)
            var data = try #require(fields["data"]?.compound)
            data["colors"] = .byteArray([Int8](repeating: 0, count: MapItem.size * MapItem.size))
            fields["data"] = .compound(data)
            fields["DataVersion"] = version.map { .int(Int32($0)) }
            return try #require(MapItem(id: 1, nbt: .compound(fields)))
        }
        let actual = try map(sample.input, version: sample.version)
        let expected = try map(#require(sample.output), version: sample.targetVersion)
        #expect(!actual.banners.isEmpty && !expected.banners.isEmpty)
        #expect(actual.banners.map(\.name) == expected.banners.map(\.name))
        if sample.version == GeneratedSavedText.savedDataDefaultVersion {
            #expect(try map(sample.input, version: nil).banners.map(\.name) == expected.banners.map(\.name))
        }
    }

    @Test(arguments: [#""Sword""#, "[1]", "{}"],
          [GeneratedSavedText.boundary - 1, GeneratedSavedText.boundary, GeneratedSavedText.boundary + 1])
    func savedNamesAndSignLinesAgreeAcrossPublicReaders(_ literal: String, version: Int) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        // Historical saves quote their component strings as JSON. Native saves keep the
        // literal itself; the same visible text must survive both encodings and a later version.
        let encoded = version < GeneratedSavedText.boundary
            ? String(decoding: try JSONEncoder().encode(literal), as: UTF8.self) : literal
        let text = NBT.string(encoded)
        let opaque = NBT.compound(["CustomName": text, "pages": .list([text])])
        let book = NBT.compound([
            "id": .string("minecraft:written_book"), "count": .int(1), "Slot": .byte(0),
            "components": .compound([
                "minecraft:custom_name": text, "minecraft:custom_data": opaque,
                "minecraft:written_book_content": .compound([
                    "title": .string(literal), "author": .string("Fixture"),
                    "pages": .list([.compound(["raw": text, "filtered": text])]),
                ]),
            ]),
        ])
        let bundle = NBT.compound([
            "id": .string("minecraft:bundle"), "count": .int(1),
            "components": .compound(["minecraft:custom_name": text, "minecraft:bundle_contents": .list([book])]),
        ])
        func block(_ id: String, _ fields: [String: NBT]) -> NBT {
            .compound(["id": .string(id), "x": .int(0), "y": .int(64), "z": .int(0)]
                .merging(fields) { $1 })
        }
        let saved = Fixtures.chunk(x: 0, z: 0, dataVersion: version, sections: [], extra: [
            "block_entities": .list([
                block("minecraft:chest", ["CustomName": text, "Items": .list([bundle])]),
                block("minecraft:sign", [
                    "front_text": .compound(["messages": .list([text, .string(""), .string(""), .string("")])]),
                    "back_text": .compound(["messages": .list([text, .string(""), .string(""), .string("")])]),
                ]),
            ]),
        ])
        let position = NBT.list([.double(1), .double(64), .double(2)])
        let passenger = Fixtures.mob(["id": .string("minecraft:parrot"), "CustomName": text, "Pos": position])
        let mob = Fixtures.mob(["id": .string("minecraft:wolf"), "CustomName": text,
                                "Pos": position, "Passengers": .list([passenger])])
        let entityChunk = NBT.compound(["DataVersion": .int(Int32(version)), "Entities": .list([mob])])
        let region = RegionPosition(x: 0, z: 0)
        let terrainURL = dimension.regionURL(.terrain, at: region)
        let entityURL = dimension.regionURL(.entities, at: region)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: saved)]), to: terrainURL)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: entityChunk)]), to: entityURL)
        let originalTerrain = try Data(contentsOf: terrainURL), originalEntities = try Data(contentsOf: entityURL)

        let facts = try dimension.scan(region: region)
        let contents = try dimension.contents(regionX: 0, regionZ: 0)
        #expect(facts.signs == Sign.signs(inChunk: saved) && facts.signs == contents.signs)
        #expect(facts.signs.first?.front == [literal, "", "", ""])
        #expect(facts.signs.first?.back == [literal, "", "", ""])
        #expect(facts.containers == contents.containers)
        #expect(try dimension.containers(regionX: 0, regionZ: 0) == contents.containers)
        #expect(facts.containers.first?.customName == literal)
        let found = try #require(facts.containers.first?.items.first)
        #expect(found.customName == literal && found.contents.first?.customName == literal)
        #expect(found.contents.first?.book == BookContent(title: literal, author: "Fixture", pages: [literal]))
        #expect(found.contents.first?.components?["minecraft:custom_data"] == opaque)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == facts.creatures)
        #expect(facts.creatures.map(\.customName) == [literal, literal])
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == facts.creatures)
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0) == [mob, passenger])
        let player = PlayerInfo(uuid: UUID(), nbt: .compound([
            "DataVersion": .int(Int32(version)), "Inventory": .list([book]), "EnderItems": .list([book]),
        ]))
        #expect(player.inventory.first?.customName == literal && player.enderChest.first?.book?.pages == [literal])
        let cached = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(cached.signs == facts.signs && cached.containers == facts.containers && cached.creatures == facts.creatures)
        #expect(try Data(contentsOf: terrainURL) == originalTerrain)
        #expect(try Data(contentsOf: entityURL) == originalEntities)
    }
}
