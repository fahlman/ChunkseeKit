import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct InterpretationVersionTests {
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    @Test func persistentIdentityOwnsNestedDictionaryOrderingAndFormatting() throws {
        let original = ["z": ["path": "example/a", "name": "Café"], "a": ["d": "4", "c": "3"]]
        let reordered = ["a": ["c": "3", "d": "4"], "z": ["name": "Café", "path": "example/a"]]
        #expect(try InterpretationKey.identity(of: original) == InterpretationKey.identity(of: reordered))
        #expect(try InterpretationKey.identity(of: original)
            == "009788e0156d2ded8379f546db8cc78fa9bafd38dd93d5c8f65466b534df9b33")
        #expect(try InterpretationKey.identity(of: [1.25, -2.5])
            == "6bf41ffa52c6edc6600452cd4f3ce54983f8b48cbc9761f8c15debf2d97e562b")
    }

    @Test func nonfiniteNumbersHaveStableDistinctIdentities() throws {
        let values: [Double] = [.infinity, -.infinity, .nan]
        let keys = try values.map { try InterpretationKey.identity(of: $0) }
        #expect(Set(keys).count == values.count)
        #expect(try InterpretationKey.identity(of: Float.infinity) == keys[0])
        #expect(try InterpretationKey.identity(of: -Float.infinity) == keys[1])
        #expect(try InterpretationKey.identity(of: Float.nan) == keys[2])
        for (index, spelling) in ["Infinity", "-Infinity", "NaN"].enumerated() {
            #expect(try InterpretationKey.identity(of: spelling) != keys[index])
        }
        #expect(try InterpretationKey.identity(of: Double(bitPattern: 0x7ff8_0000_0000_0001)) == keys[2])
    }

    @Test func canonicalFormIsAPropertyListWithDistinctTypedValues() throws {
        let bytes = try InterpretationKey.canonicalData(for: ["b": [2, 1], "a": [3, 4]])
        #expect(bytes.starts(with: Data("bplist00".utf8)))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let decoded = try PropertyListSerialization.propertyList(from: bytes, format: &format)
        #expect(format == .binary && decoded is [Any])
        let nilValue: String? = nil
        let identities = try [
            InterpretationKey.identity(of: nilValue), InterpretationKey.identity(of: "$null"),
            InterpretationKey.identity(of: ""), InterpretationKey.identity(of: [String]()),
            InterpretationKey.identity(of: [String: String]()), InterpretationKey.identity(of: false),
            InterpretationKey.identity(of: 0), InterpretationKey.identity(of: "0"),
            InterpretationKey.identity(of: UInt64.max), InterpretationKey.identity(of: Int64.max),
        ]
        #expect(Set(identities).count == identities.count)
        #expect(try InterpretationKey.identity(of: [nilValue]) != InterpretationKey.identity(of: ["$null"]))
        #expect(try InterpretationKey.identity(of: [1, 2]) != InterpretationKey.identity(of: [2, 1]))
        #expect(try InterpretationKey.identity(of: ["a": 1]) != InterpretationKey.identity(of: ["a": 2]))
        #expect(try InterpretationKey.identity(of: 0.0) == InterpretationKey.identity(of: -0.0))
        #expect(try InterpretationKey.identity(of: Int64(42)) == InterpretationKey.identity(of: UInt8(42)))
    }

    @Test func explicitlyNestedContainersAndSuperEncodersKeepTheirValues() throws {
        struct Nested: Encodable {
            enum Key: String, CodingKey { case groups, payload }
            let number: Int
            func encode(to encoder: any Encoder) throws {
                var root = encoder.container(keyedBy: Key.self)
                var groups = root.nestedUnkeyedContainer(forKey: .groups)
                var entry = groups.nestedContainer(keyedBy: Key.self)
                try entry.encode(number, forKey: .payload)
                try "base".encode(to: root.superEncoder())
                var nested = groups.nestedUnkeyedContainer()
                try nested.encodeNil()
                try Data([1, 2, 3]).encode(to: nested.superEncoder())
            }
        }
        #expect(try InterpretationKey.identity(of: Nested(number: 1)) == InterpretationKey.identity(of: Nested(number: 1)))
        #expect(try InterpretationKey.identity(of: Nested(number: 1)) != InterpretationKey.identity(of: Nested(number: 2)))
    }

    @Test func encodingFailuresStillPropagateWithoutAFallbackIdentity() throws {
        struct Invalid: Encodable {
            enum Failure: Error { case rejected }
            func encode(to encoder: any Encoder) throws { throw Failure.rejected }
        }
        #expect(throws: Invalid.Failure.self) { try InterpretationKey.identity(of: Invalid()) }
    }

    @Test func persistentIdentityAcrossFreshProcesses() throws {
        let outputKey = "CHUNKSEE_IDENTITY_PROBE_OUTPUT"
        let orderKey = "CHUNKSEE_IDENTITY_PROBE_REVERSED"
        if let output = ProcessInfo.processInfo.environment[outputKey] {
            struct Input: Encodable {
                let nested: [String: [String: Double?]]
                let options: RegionScanOptions
            }
            let reversed = ProcessInfo.processInfo.environment[orderKey] == "1"
            let keys = reversed ? ["z", "a"] : ["a", "z"]
            var nested: [String: [String: Double?]] = [:]
            for key in keys {
                var values: [String: Double?] = [:]
                for name in keys { values[name] = .some(name == "a" ? 1.25 : nil) }
                nested[key] = values
            }
            let options = RegionScanOptions(blockIDs: Set(keys), biomeIDs: Set(keys), structurePieceIDs: Set(keys))
            let identity = try InterpretationKey.identity(of: Input(nested: nested, options: options))
            try PropertyListEncoder().encode([identity]).write(to: URL(fileURLWithPath: output))
            return
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var identities: [String] = []
        for order in 0..<2 {
            let output = root.appendingPathComponent("identity-\(order).plist")
            let process = Process(), pipe = Pipe()
            // SwiftPM can load a test bundle through a helper rather than execute the bundle.
            // Preserve its loader arguments and replace only the filter when re-entering this case.
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            var arguments: [String] = [], index = 1
            while index < CommandLine.arguments.count {
                let argument = CommandLine.arguments[index]
                if argument == "--filter" { index += 2; continue }
                if !argument.hasPrefix("--filter=") { arguments.append(argument) }
                index += 1
            }
            process.arguments = arguments + ["--filter", "persistentIdentityAcrossFreshProcesses"]
            var environment = ProcessInfo.processInfo.environment
            environment[outputKey] = output.path; environment[orderKey] = String(order)
            process.environment = environment
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let log = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "\(String(decoding: log, as: UTF8.self))")
            try #require(FileManager.default.fileExists(atPath: output.path),
                "No identity from \(process.executableURL?.path ?? "") \(process.arguments ?? []): \(String(decoding: log, as: UTF8.self))")
            let value = try PropertyListDecoder().decode([String].self, from: Data(contentsOf: output))
            identities.append(try #require(value.first))
        }
        #expect(identities.count == 2 && identities[0] == identities[1])
    }

    @Test func publishedContractsSurviveReopeningAndRemainDistinct() throws {
        let versions = [Chunk.interpretationVersion, MonsterSpawnLight.interpretationVersion,
                        GameAssets.interpretationVersion, RegionFacts.interpretationVersion]
        let stored = try encoded(versions)
        let reopened = try JSONDecoder().decode([InterpretationVersion].self, from: stored)
        #expect(reopened == versions)
        #expect(try encoded(reopened) == stored)
        #expect(Set(reopened).count == 4)
        for version in reopened {
            #expect(version.generatedFacts.count == 64)
            #expect(version.generatedFacts.allSatisfy { "0123456789abcdef".contains($0) })
        }
    }

    @Test func regionArchiveIdentityIsIndependentOfSetInsertionOrder() throws {
        var first = RegionFacts(dimension: "example:world", region: .init(x: 0, z: 0),
                                options: .init(blockIDs: Set(["example:a", "example:b"])))
        first.paletteBlockIDs = Set(["example:a", "example:b", "example:c"])
        var reordered = RegionFacts(dimension: "example:world", region: .init(x: 0, z: 0),
                                    options: .init(blockIDs: Set(["example:b", "example:a"])))
        reordered.paletteBlockIDs = Set(["example:c", "example:b", "example:a"])
        #expect(try InterpretationKey.identity(of: first) == InterpretationKey.identity(of: reordered))
        reordered.paletteBlockIDs.insert("example:d")
        #expect(try InterpretationKey.identity(of: first) != InterpretationKey.identity(of: reordered))
    }

    @Test func regionArchiveRejectsChangedReaderGeneratedFactsAndDependency() throws {
        let facts = RegionFacts(dimension: "example:world", region: .init(x: 2, z: -3), options: .init())
        let bytes = try encoded(facts)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let current = try #require(original["version"] as? [String: Any])
        var changedRevision = current
        changedRevision["revision"] = RegionFacts.interpretationVersion.revision + 1
        var changedFacts = current
        changedFacts["generatedFacts"] = String(repeating: "0", count: 64)
        var changedDependency = current
        var dependencies = try #require(current["dependencies"] as? [[String: Any]])
        #expect(!dependencies.isEmpty)
        dependencies[0]["revision"] = Chunk.interpretationVersion.revision + 1
        changedDependency["dependencies"] = dependencies
        for stale in [changedRevision, changedFacts, changedDependency] {
            var archive = original
            archive["version"] = stale
            let data = try JSONSerialization.data(withJSONObject: archive)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: data) }
        }
        let reopened = try JSONDecoder().decode(RegionFacts.self, from: bytes)
        #expect(reopened.dimension == "example:world" && reopened.region == .init(x: 2, z: -3))
        #expect(reopened.inhabitedTimes == facts.inhabitedTimes)
        #expect(try encoded(reopened) == bytes)
    }

    @Test func wholeLightRulesDistinguishChangedMeaningAndReuseEqualReads() throws {
        func rule(_ threshold: Int32) throws -> MonsterSpawnLight {
            let type = try #require(DimensionType(.compound([
                "min_y": .int(0), "height": .int(256), "logical_height": .int(256),
                "has_ceiling": .byte(0), "has_skylight": .byte(0),
                "monster_spawn_block_light_limit": .int(15), "monster_spawn_light_level": .int(threshold),
            ])))
            return try #require(MonsterSpawnLight(type: type, skyLightLevel: nil))
        }
        let original = try rule(7), same = try rule(7), changed = try rule(6)
        let cache = [original: "cached light"]
        #expect(cache[same] == "cached light" && cache[changed] == nil)
        #expect(try InterpretationKey.identity(of: original) == InterpretationKey.identity(of: same))
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        let position = BlockPosition(blockX: 0, blockY: 0, blockZ: 0)
        #expect(original.canPass(blockLight: 7, skyLight: nil, at: position) == true)
        #expect(changed.canPass(blockLight: 7, skyLight: nil, at: position) == false)
    }

    @Test func wholeBiomeDefinitionsRetainUnknownModifiersAndChangedColors() throws {
        let source = #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1193046,"grass_color_modifier":"example:future"}}"#
        let original = try #require(BiomeDefinition(json: Data(source.utf8)))
        let same = try #require(BiomeDefinition(json: Data(source.utf8)))
        let changed = try #require(BiomeDefinition(json: Data(source.replacingOccurrences(of: "1193046", with: "1193047").utf8)))
        let cache = [original: "cached color"]
        #expect(cache[same] == "cached color" && cache[changed] == nil)
        #expect(try InterpretationKey.identity(of: original) == InterpretationKey.identity(of: same))
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        #expect(original.grassColorModifier == .unknown("example:future"))
        #expect(String(decoding: try encoded(original), as: UTF8.self).contains("example:future"))
    }

    @Test func savedMapContentChangesWithoutChangingItsItemID() throws {
        let original = try #require(MapItem(id: 4, nbt: .compound([
            "colors": .byteArray(Array(repeating: 0, count: MapItem.size * MapItem.size)),
        ])))
        var changed = original
        changed.colors[0] = 4
        let cache = [original: "cached image"]
        #expect(cache[original] == "cached image" && cache[changed] == nil)
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        #expect(original.id == changed.id && original.isBlank && !changed.isBlank)
        changed = original
        changed.banners = [.init(x: 1, y: 2, z: 3, color: "red", name: "Camp")]
        #expect(cache[changed] == nil)
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
    }

    @Test func completeScanOptionsHaveStableUnorderedInputs() throws {
        let original = RegionScanOptions(blockIDs: Set(["example:a", "example:b"]),
            biomeIDs: Set(["example:dry", "example:wet"]), structurePieceIDs: Set(["example:door", "example:room"]),
            biomeSampleY: 20, height: 384)
        let reordered = RegionScanOptions(blockIDs: Set(["example:b", "example:a"]),
            biomeIDs: Set(["example:wet", "example:dry"]), structurePieceIDs: Set(["example:room", "example:door"]),
            biomeSampleY: 20, height: 384)
        #expect(original == reordered)
        #expect(try InterpretationKey.identity(of: original) == InterpretationKey.identity(of: reordered))
        var changed = original
        changed.biomeSampleY = 21
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        changed = original
        changed.height = 256
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        #expect(try InterpretationKey.identity(of: RegionScanOptions(blockIDs: nil))
            != InterpretationKey.identity(of: RegionScanOptions(blockIDs: [])))
        #expect(try InterpretationKey.identity(of: RegionScanOptions(biomeIDs: nil))
            != InterpretationKey.identity(of: RegionScanOptions(biomeIDs: [])))
        #expect(try InterpretationKey.identity(of: RegionScanOptions(structurePieceIDs: nil))
            != InterpretationKey.identity(of: RegionScanOptions(structurePieceIDs: [])))
        changed = original
        changed.biomeIDs = ["example:dry"]
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
        changed = original
        changed.structurePieceIDs = ["example:door"]
        #expect(try InterpretationKey.identity(of: original) != InterpretationKey.identity(of: changed))
    }
}
