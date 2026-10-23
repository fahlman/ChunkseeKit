import CZlib
import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct ZipResourceTests {
    private let metadata = "{\"pack\":{\"min_format\":121,\"max_format\":121,\"description\":\"Fixture\"}}"
    private let path = "data/minecraft/dimension_type/overworld.json"
    private let custom = "{\"min_y\":0,\"height\":128,\"logical_height\":64,\"has_ceiling\":true}"

    private typealias Entry = TestZIP.Entry
    private func zip(_ entries: [Entry], comment: [UInt8] = []) throws -> [UInt8] {
        try TestZIP.zip(entries, comment: comment)
    }

    private func world(at root: URL, pack: [UInt8], reference: String = "overworld",
                       packs: [String] = ["vanilla", "file/Test.zip"], noise: String = "overworld") throws -> World {
        try Fixtures.write(pack, to: root.appendingPathComponent("datapacks/Test.zip"))
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("ZIP Resources"), "DataVersion": .int(5023),
            "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))]),
            "WorldGenSettings": .compound(["dimensions": .compound([
                "example:mine": .compound(["type": .string(reference), "generator": .compound([
                    "type": .string("minecraft:noise"), "settings": .string(noise)
                ])])
            ])])
        ])]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    @Test(arguments: [false, true], [UInt16(0), 8])
    func storedAndDeflatedOverridesResolveWithoutWriting(compressed: Bool, flags: UInt16) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata, compressed: compressed, flags: flags),
                             Entry(path: path, text: custom, compressed: compressed, flags: flags)])
        let world = try world(at: root, pack: bytes)
        #expect(try world.dimensionTypes()["example:mine"]?.buildRange == 0...127)
        #expect(try Array(Data(contentsOf: root.appendingPathComponent("datapacks/Test.zip"))) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("datapacks").path) == ["Test.zip"])
    }

    @Test func aCompleteZIPWithoutTheResourcePermitsVanillaAndKeepsPackPriority() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: "data/example/function/a.mcfunction", text: "say test")])
        let world = try world(at: root, pack: plain)
        #expect(try world.dimensionTypes()["example:mine"]?.buildRange == -64...319)
        let override = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom)])
        let lower = try self.world(at: root, pack: override, packs: ["file/Test.zip", "vanilla"])
        #expect(try lower.dimensionTypes()["example:mine"]?.buildRange == -64...319)
    }

    @Test func invalidPresentOverridesNeverExposeLowerDefinitions() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = [Entry(path: path, text: "{}"), Entry(path: path, text: custom, wrongCRC: true),
                       Entry(path: path, text: custom, flags: 1),
                       Entry(path: path, text: custom, savedSize: UInt32(ZipResources.maximumResourceSize + 1)),
                       Entry(path: path, text: custom, mode: 0o120777)]
        for item in invalid {
            let world = try world(at: root, pack: zip([Entry(path: "pack.mcmeta", text: metadata), item]))
            #expect(try world.dimensionTypes().isEmpty)
        }
    }

    @Test func duplicatePathsAndBrokenDirectoriesCannotProveAnOverrideAbsent() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let duplicate = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom), Entry(path: path, text: "{}")])
        #expect(try world(at: root, pack: duplicate).dimensionTypes().isEmpty)
        var broken = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom)])
        let centralSignature: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
        let starts = (0..<broken.count - 4).filter { Array(broken[$0..<$0 + 4]) == centralSignature }
        let last = try #require(starts.last)
        broken[last] = 0
        #expect(try world(at: root, pack: broken).dimensionTypes().isEmpty)
        #expect(try world(at: root, pack: Array(broken.dropLast(10))).dimensionTypes().isEmpty)
    }

    @Test(arguments: ["{}", "{\"pack\":{},\"overlays\":{\"entries\":[]}}", "{\"pack\":{},\"filter\":{\"block\":[]}}"])
    func unsupportedMetadataStillBlocksFallback(text: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try world(at: root, pack: zip([Entry(path: "pack.mcmeta", text: text)])).dimensionTypes().isEmpty)
    }

    @Test func pathLookupsDoNotNormalizeDotSegmentsOrFollowArchiveSymlinks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata),
                             Entry(path: "data/example/dimension_type/../escape.json", text: custom)])
        #expect(try world(at: root, pack: bytes, reference: "example:../escape").dimensionTypes().isEmpty)
        let outside = root.appendingPathComponent("outside.zip")
        try Fixtures.write(bytes, to: outside)
        let alias = root.appendingPathComponent("datapacks/Alias.zip")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        #expect(try world(at: root, pack: bytes, packs: ["vanilla", "file/Alias.zip"]).dimensionTypes().isEmpty)
    }

    @Test func unreadResourcesAreNotDecompressed() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom),
                             Entry(path: "data/example/worldgen/noise_settings/broken.json", text: "{}", compressed: true, wrongCRC: true)])
        let world = try world(at: root, pack: bytes, noise: "example:broken")
        #expect(try world.dimensionTypes()["example:mine"]?.buildRange == 0...127)
        let settings = try #require(try world.dimensionSettings()["example:mine"])
        #expect(settings.type?.buildRange == 0...127)
        #expect(settings.noiseGeneration == nil)
    }

    @Test func noiseAndTypeUseTheSameZIPResolverAndPriority() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom),
                             Entry(path: "data/example/worldgen/noise_settings/custom.json",
                                   text: "{\"noise\":{\"min_y\":16,\"height\":64},\"sea_level\":45}", compressed: true)])
        let world = try world(at: root, pack: bytes, noise: "example:custom")
        let settings = try #require(try world.dimensionSettings()["example:mine"])
        let type = try #require(settings.type)
        #expect(type.buildRange == 0...127)
        #expect(settings.noiseGeneration?.range == 16..<80)
        #expect(settings.noiseGeneration?.seaLevel == 45)
        #expect(settings.noiseGeneration?.surfaceRuleRange(in: type) == 16..<80)
    }

    @Test(arguments: [false, true])
    func descriptorsWithoutSignaturesAndArchiveCommentsAreReadable(compressed: Bool) throws {
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata, compressed: compressed, flags: 8, descriptorSignature: false),
                             Entry(path: path, text: custom, compressed: compressed, flags: 0x0808, descriptorSignature: false)],
                            comment: Array("A comment containing PK\u{5}\u{6}, not another record".utf8))
        let resources = try #require(ZipResources(data: Data(bytes)))
        #expect(resources.read(path) == Data(custom.utf8))
        #expect(resources.read("pack.mcmeta") == Data(metadata.utf8))
    }

    @Test func lookupUsesExactUTF8NamesAndDoesNotTreatDirectoriesAsResources() throws {
        let composed = "data/example/é.json", decomposed = "data/example/e\u{301}.json"
        let bytes = try zip([Entry(path: composed, text: "one", flags: 0x0800),
                             Entry(path: decomposed, text: "two", flags: 0x0800),
                             Entry(path: "folder/", text: "", mode: 0o040755)])
        let resources = try #require(ZipResources(data: Data(bytes)))
        #expect(resources.read(composed) == Data("one".utf8))
        #expect(resources.read(decomposed) == Data("two".utf8))
        #expect(!resources.contains("Data/example/é.json"))
        #expect(resources.contains("folder/"))
        #expect(resources.read("folder/") == nil)
    }

    @Test func malformedDirectoryAndLocalHeadersCannotEstablishAbsence() throws {
        let bytes = try zip([Entry(path: "pack.mcmeta", text: metadata), Entry(path: path, text: custom)])
        let central = try #require(offsets(of: [0x50, 0x4b, 0x01, 0x02], in: bytes).first)
        let end = bytes.count - 22
        let wordChanges: [(Int, UInt16)] = [(end + 4, 1), (end + 6, 1), (end + 8, 1),
                                           (end + 8, 0), (end + 10, 0), (end + 10, .max),
                                           (central + 28, .max), (central + 30, .max), (central + 32, .max),
                                           (central + 34, 1), (central + 6, 45),
                                           (6, 1), (8, 8), (26, .max), (28, .max)]
        for (offset, value) in wordChanges {
            var changed = bytes
            replace(value, at: offset, in: &changed)
            #expect(ZipResources(data: Data(changed)) == nil)
        }
        for offset in [end + 12, end + 16, central + 20, central + 24, central + 42, 14, 18, 22] {
            var changed = bytes
            replace(UInt32.max, at: offset, in: &changed)
            #expect(ZipResources(data: Data(changed)) == nil)
        }
        var wrongName = bytes
        wrongName[30] = UInt8(ascii: "P")
        #expect(ZipResources(data: Data(wrongName)) == nil)
        for length in 0..<bytes.count {
            #expect(ZipResources(data: Data(bytes.prefix(length))) == nil)
        }
    }

    @Test func unsupportedFlagsMethodsAndExtrasKeepThePackUnavailable() throws {
        for flags in [UInt16(1), 0x40, 0x2000, 0x10] {
            #expect(ZipResources(data: Data(try zip([Entry(path: "pack.mcmeta", text: metadata, flags: flags)]))) == nil)
        }
        let extras: [[UInt8]] = [[1, 0, 8, 0] + Array(repeating: 0, count: 8), [0xfe, 0xca, 255, 255], [0]]
        for extra in extras {
            #expect(ZipResources(data: Data(try zip([Entry(path: "pack.mcmeta", text: metadata, extra: extra)]))) == nil)
        }
        var bytes = try zip([Entry(path: "pack.mcmeta", text: metadata)])
        let central = try #require(offsets(of: [0x50, 0x4b, 0x01, 0x02], in: bytes).first)
        replace(UInt16(12), at: 8, in: &bytes)
        replace(UInt16(12), at: central + 10, in: &bytes)
        #expect(ZipResources(data: Data(bytes)) == nil)
    }

    @Test func truncatedTrailingAndOversizedDeflateNeverReturnPartialResources() throws {
        let raw = Array(try Compression.deflate(Array(custom.utf8)).dropFirst(2).dropLast(4))
        let entries = [Entry(path: path, text: custom, compressed: true, payloadOverride: Array(raw.dropLast())),
                       Entry(path: path, text: custom, compressed: true, payloadOverride: raw + [0]),
                       Entry(path: path, text: custom, compressed: true, payloadOverride: [255, 255, 255]),
                       Entry(path: path, text: custom, compressed: true, savedSize: UInt32(custom.utf8.count - 1)),
                       Entry(path: path, text: custom, compressed: true, savedSize: UInt32(custom.utf8.count + 1)),
                       Entry(path: path, text: String(repeating: "x", count: 65_536), compressed: true, savedSize: 10)]
        for entry in entries {
            let resources = try #require(ZipResources(data: Data(try zip([entry]))))
            #expect(resources.contains(path))
            #expect(resources.read(path) == nil)
        }
        for compressed in [false, true] {
            let empty = try #require(ZipResources(data: Data(try zip([Entry(path: path, text: "", compressed: compressed)]))))
            #expect(empty.read(path) == Data())
        }
    }

    @Test func resourceLimitIncludesExactBoundaryAndRejectsBadDescriptors() throws {
        let text = String(repeating: "x", count: ZipResources.maximumResourceSize)
        let resources = try #require(ZipResources(data: Data(try zip([Entry(path: path, text: text, compressed: true)]))))
        #expect(resources.read(path)?.count == ZipResources.maximumResourceSize)
        let oversized = try #require(ZipResources(data: Data(try zip([
            Entry(path: path, text: text, compressed: true, savedSize: UInt32(ZipResources.maximumResourceSize + 1))
        ]))))
        #expect(oversized.read(path) == nil)
        var bytes = try zip([Entry(path: path, text: custom, compressed: true, flags: 8)])
        let descriptor = try #require(offsets(of: [0x50, 0x4b, 0x07, 0x08], in: bytes).first)
        bytes[descriptor + 4] ^= 1
        #expect(ZipResources(data: Data(bytes)) == nil)
    }

    @Test func overlappingLocalEntriesAndAmbiguousEndRecordsAreUnavailable() throws {
        var bytes = try zip([Entry(path: "a", text: "one"), Entry(path: "b", text: "two")])
        let central = try #require(offsets(of: [0x50, 0x4b, 0x01, 0x02], in: bytes).first)
        // The first stored payload now claims the following local record as part of its body.
        let length = UInt32(central - 31)
        for offset in [18, 22, central + 20, central + 24] { replace(length, at: offset, in: &bytes) }
        #expect(ZipResources(data: Data(bytes)) == nil)
        var fake = [UInt8](repeating: 0, count: 22)
        replace(UInt32(0x06054b50), at: 0, in: &fake)
        let ambiguous = try zip([Entry(path: path, text: custom)], comment: fake)
        #expect(ZipResources(data: Data(ambiguous)) == nil)
    }

    private func replace<T: FixedWidthInteger>(_ value: T, at offset: Int, in bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<offset + $0.count, with: $0) }
    }

    private func offsets(of signature: [UInt8], in bytes: [UInt8]) -> [Int] {
        (0...bytes.count - signature.count).filter { bytes[$0..<$0 + signature.count].elementsEqual(signature) }
    }
}
