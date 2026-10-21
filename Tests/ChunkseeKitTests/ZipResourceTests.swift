import CZlib
import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct ZipResourceTests {
    private let metadata = "{\"pack\":{\"min_format\":121,\"max_format\":121,\"description\":\"Fixture\"}}"
    private let path = "data/minecraft/dimension_type/overworld.json"
    private let custom = "{\"min_y\":0,\"height\":128,\"logical_height\":64,\"has_ceiling\":true}"

    /// Independent central/local header writer; the production reader uses system libarchive.
    private struct Entry {
        let path: String, text: String
        var compressed = false
        var flags: UInt16 = 0
        var wrongCRC = false
        var savedSize: UInt32?
        var mode: UInt32 = 0o100644
    }

    private func zip(_ entries: [Entry]) throws -> [UInt8] {
        var local = [UInt8](), central = [UInt8]()
        func number<T: FixedWidthInteger>(_ value: T, into bytes: inout [UInt8]) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        for entry in entries {
            let content = Array(entry.text.utf8), name = Array(entry.path.utf8)
            let payload = entry.compressed ? Array(try Compression.deflate(content).dropFirst(2).dropLast(4)) : content
            let crc = content.withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) } ^ (entry.wrongCRC ? 1 : 0)
            let size = entry.savedSize ?? UInt32(content.count)
            let descriptor = entry.flags & 8 != 0
            let offset = UInt32(local.count)
            number(UInt32(0x04034b50), into: &local); number(UInt16(20), into: &local)
            number(entry.flags, into: &local); number(UInt16(entry.compressed ? 8 : 0), into: &local)
            number(UInt32(0), into: &local); number(descriptor ? 0 : crc, into: &local)
            number(descriptor ? 0 : UInt32(payload.count), into: &local); number(descriptor ? 0 : size, into: &local)
            number(UInt16(name.count), into: &local); number(UInt16(0), into: &local)
            local += name; local += payload
            if descriptor {
                number(UInt32(0x08074b50), into: &local); number(crc, into: &local)
                number(UInt32(payload.count), into: &local); number(size, into: &local)
            }

            number(UInt32(0x02014b50), into: &central); number(UInt16(0x0314), into: &central)
            number(UInt16(20), into: &central); number(entry.flags, into: &central)
            number(UInt16(entry.compressed ? 8 : 0), into: &central); number(UInt32(0), into: &central)
            number(crc, into: &central); number(UInt32(payload.count), into: &central); number(size, into: &central)
            number(UInt16(name.count), into: &central); number(UInt16(0), into: &central)
            number(UInt16(0), into: &central); number(UInt16(0), into: &central); number(UInt16(0), into: &central)
            number(entry.mode << 16, into: &central); number(offset, into: &central); central += name
        }
        let offset = UInt32(local.count), size = UInt32(central.count)
        local += central
        number(UInt32(0x06054b50), into: &local); number(UInt16(0), into: &local); number(UInt16(0), into: &local)
        number(UInt16(entries.count), into: &local); number(UInt16(entries.count), into: &local)
        number(size, into: &local); number(offset, into: &local); number(UInt16(0), into: &local)
        return local
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
                                   text: "{\"noise\":{\"min_y\":16,\"height\":64}}", compressed: true)])
        let world = try world(at: root, pack: bytes, noise: "example:custom")
        let settings = try #require(try world.dimensionSettings()["example:mine"])
        let type = try #require(settings.type)
        #expect(type.buildRange == 0...127)
        #expect(settings.noiseGeneration?.range == 16..<80)
        #expect(settings.noiseGeneration?.surfaceRuleRange(in: type) == 16..<80)
    }
}
