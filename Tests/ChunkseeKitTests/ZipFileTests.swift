import Darwin
import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct ZipFileTests {
    private let texturePath = "assets/minecraft/textures/item/test.png"

    private func version(_ name: String = "before") -> TestZIP.Entry {
        .init(path: "version.json", text: "{\"id\":\"\(name)\",\"world_version\":5023}")
    }

    private func archive(_ texture: Data, version name: String = "before") throws -> Data {
        Data(try TestZIP.zip([version(name), .init(path: texturePath, text: "", data: texture, compressed: true)]))
    }

    @Test func fileAndMemoryUseTheSameDirectoryAndPayloadValidation() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        let bytes = Data((0..<180_000).map { UInt8(truncatingIfNeeded: $0) })
        // Long names, a full trailing comment and payloads crossing pages exercise metadata
        // reads on both sides of the local-header/central-directory boundary.
        let longName = String(repeating: "a", count: 65_535)
        let entries: [TestZIP.Entry] = [
            version(), .init(path: "stored", text: "", data: bytes),
            .init(path: "signed", text: "", data: bytes, compressed: true, flags: 8),
            .init(path: "unsigned", text: "", data: bytes, compressed: true, flags: 8, descriptorSignature: false),
            .init(path: longName, text: "long"),
            .init(path: "bad-crc", text: "broken", compressed: true, wrongCRC: true),
            .init(path: "link", text: "target", mode: 0o120777)
        ]
        let data = Data(try TestZIP.zip(entries, comment: [UInt8](repeating: 65, count: 65_535)))
        try data.write(to: url)
        let file = try #require(try ZipResources(contentsOf: url))
        let memory = try #require(ZipResources(data: data))
        for entry in entries {
            #expect(file.contains(entry.path))
            #expect(file.read(entry.path) == memory.read(entry.path))
        }
        #expect(file.read("stored") == bytes && file.read("signed") == bytes && file.read("unsigned") == bytes)
        #expect(file.read(longName) == Data("long".utf8))
        #expect(file.read("bad-crc") == nil && file.read("link") == nil)
        #expect(!file.contains("absent") && file.read("absent") == nil)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test(arguments: ["truncate", "rewrite", "append"])
    func changedFilesStopReadingAndNeverPermitFallback(_ change: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        let original = try archive(Data("texture".utf8))
        try original.write(to: url)
        let reader = try #require(try GameAssets(contentsOf: url))
        let resources = try #require(try ZipResources(contentsOf: url))
        #expect(reader.texture("item/test") == Data("texture".utf8))
        #expect(!resources.contains("missing"))
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        switch change {
        case "truncate": try writer.truncate(atOffset: 12)
        case "append":
            try writer.seekToEnd()
            try writer.write(contentsOf: Data([0]))
        default:
            let replacement = try archive(Data("texture".utf8), version: "after!")
            #expect(replacement.count == original.count)
            try writer.write(contentsOf: replacement)
        }
        #expect(reader.texture("item/test") == nil)
        #expect(resources.read("version.json") == nil)
        // A changed higher-priority pack may have added this resource. Its old absence
        // must not silently expose a lower-priority definition.
        #expect(resources.contains("missing"))
    }

    @Test func replacingThePathNeverMixesVersionsAndResources() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        let oldTexture = Data("old texture".utf8), newTexture = Data("new texture".utf8)
        try archive(oldTexture).write(to: url)
        let old = try #require(try GameAssets(contentsOf: url))
        try archive(newTexture, version: "after!").write(to: url, options: .atomic)
        let new = try #require(try GameAssets(contentsOf: url))
        #expect(old.version.id == "before" && new.version.id == "after!")
        #expect(new.texture("item/test") == newTexture)
        // An unchanged opened inode still describes the old archive. If replacement also
        // changed that inode's metadata, it is unavailable instead; it never reads the new file.
        let retained = old.texture("item/test")
        #expect(retained == nil || retained == oldTexture)
    }

    @Test func copiedReadersSupportConcurrentIndependentReads() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        let textures = (0..<4).map { Data(repeating: UInt8($0 + 1), count: 128 * 1024 + $0) }
        let entries = textures.enumerated().map { index, data in
            TestZIP.Entry(path: "assets/minecraft/textures/item/\(index).png", text: "", data: data,
                          compressed: index.isMultiple(of: 2))
        }
        try Data(TestZIP.zip([version()] + entries)).write(to: url)
        var original = try GameAssets(contentsOf: url)
        let copy = try #require(original)
        original = nil
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<24 {
                let selected = index % textures.count
                group.addTask {
                    (0..<3).allSatisfy { _ in copy.texture("item/\(selected)") == textures[selected] }
                }
            }
            for await valid in group { #expect(valid) }
        }
    }

    @Test func lastReaderClosesItsFileDescriptor() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        try archive(Data("texture".utf8)).write(to: url)
        #expect(try openDescriptors(for: url).isEmpty)
        func readWithCopies() throws {
            var original = try GameAssets(contentsOf: url)
            let copy = try #require(original)
            original = nil
            try withExtendedLifetime(copy) {
                #expect(copy.texture("item/test") == Data("texture".utf8))
                let descriptors = try openDescriptors(for: url)
                #expect(descriptors.count == 1)
            }
        }
        try readWithCopies()
        #expect(try openDescriptors(for: url).isEmpty)
    }

    @Test func incompleteDirectoriesAndUnsupportedFilesFailSafely() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets.jar")
        let bytes = try archive(Data("texture".utf8))
        for length in [0, 21, 29, bytes.count - 1] {
            try bytes.prefix(length).write(to: url)
            #expect(try ZipResources(contentsOf: url) == nil)
            #expect(try openDescriptors(for: url).isEmpty)
        }
        let unsupported = try TestZIP.zip([version(), .init(path: "encrypted", text: "", flags: 1)])
        try Data(unsupported).write(to: url)
        #expect(try ZipResources(contentsOf: url) == nil)
        #expect(throws: (any Error).self) { try GameAssets(contentsOf: root) }
        let fifo = root.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: (any Error).self) { try GameAssets(contentsOf: fifo) }
        #expect(throws: (any Error).self) { try GameAssets(contentsOf: root.appendingPathComponent("missing.jar")) }
    }

    /// Match the unique fixture's file identity: Foundation and fcntl spell /private/var differently.
    /// Other suites may open unrelated descriptors while this test runs.
    private func openDescriptors(for url: URL) throws -> [Int32] {
        var target = stat()
        guard lstat(url.path, &target) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap { name in
            guard let descriptor = Int32(name) else { return nil }
            var value = stat()
            guard fstat(descriptor, &value) == 0 else { return nil }
            return value.st_dev == target.st_dev && value.st_ino == target.st_ino ? descriptor : nil
        }
    }
}
