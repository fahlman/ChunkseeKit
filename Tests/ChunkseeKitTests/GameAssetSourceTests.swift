import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct GameAssetSourceTests {
    private let texture = Data("original texture".utf8)
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func archive(_ texture: Data) throws -> Data {
        Data(try TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"test","world_version":5023}"#),
            .init(path: "assets/minecraft/textures/item/test.png", text: "", data: texture)
        ]))
    }

    @Test func unchangedPathAndOpenedReaderShareOneIdentity() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("game.jar")
        let bytes = try archive(texture)
        try bytes.write(to: url)
        let discovered = try GameAssets.SourceIdentity(contentsOf: url)
        let reader = try #require(try GameAssets(contentsOf: url))
        let opened = try #require(reader.sourceIdentity)
        #expect(opened == discovered)
        #expect(opened.byteCount == bytes.count)
        #expect(opened.cacheKey == discovered.cacheKey)
        #expect(Set([opened, discovered]).count == 1)
        #expect(reader.isUnchanged)
        #expect(reader.texture("item/test") == texture)
        #expect(try GameAssets.SourceIdentity(contentsOf: url) == opened)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func restoringTheSameFileCannotReuseAnInvalidatedReader() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("game.jar"), away = root.appendingPathComponent("away.jar")
        let bytes = try archive(texture)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let old = try #require(try GameAssets(contentsOf: url))
        let original = try #require(old.sourceIdentity)
        let originalDate = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        try FileManager.default.moveItem(at: url, to: away)
        #expect(throws: (any Error).self) { try GameAssets.SourceIdentity(contentsOf: url) }
        try FileManager.default.moveItem(at: away, to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == originalDate)
        let restored = try GameAssets.SourceIdentity(contentsOf: url)
        #expect(restored.byteCount == original.byteCount)
        #expect(restored != original && restored.cacheKey != original.cacheKey)
        // Holding the old reader is deliberate: a weak client cache must reject this handle.
        #expect(!old.isUnchanged && old.texture("item/test") == nil)
        #expect(old.sourceIdentity == original)
        let fresh = try #require(try GameAssets(contentsOf: url))
        #expect(fresh.sourceIdentity == restored && fresh.isUnchanged)
        #expect(fresh.texture("item/test") == texture)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func sameSizeAndDateReplacementHasADifferentIdentity() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("game.jar")
        let bytes = try archive(texture), replacement = try archive(Data("replaced texture".utf8))
        #expect(bytes.count == replacement.count)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let old = try #require(try GameAssets(contentsOf: url))
        let original = try #require(old.sourceIdentity)
        try replacement.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let current = try GameAssets.SourceIdentity(contentsOf: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == date)
        #expect(current.byteCount == original.byteCount && current != original)
        #expect(current.cacheKey != original.cacheKey)
        let fresh = try #require(try GameAssets(contentsOf: url))
        #expect(fresh.sourceIdentity == current && fresh.isUnchanged)
        #expect(fresh.texture("item/test") == Data("replaced texture".utf8))
        #expect(old.sourceIdentity == original)
        #expect(old.texture("item/test") == (old.isUnchanged ? texture : nil))
    }

    @Test(arguments: ["rewrite", "truncate", "permissions"])
    func changedFileValidityMatchesResourceReads(_ change: String) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("game.jar")
        try archive(texture).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date, .posixPermissions: 0o600],
                                             ofItemAtPath: url.path)
        let reader = try #require(try GameAssets(contentsOf: url))
        let original = try #require(reader.sourceIdentity)
        if change == "permissions" {
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        } else {
            let writer = try FileHandle(forWritingTo: url)
            defer { try? writer.close() }
            if change == "truncate" { try writer.truncate(atOffset: 1) }
            else { try writer.write(contentsOf: archive(Data("replaced texture".utf8))) }
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let current = try GameAssets.SourceIdentity(contentsOf: url)
        #expect(current != original && current.cacheKey != original.cacheKey)
        #expect(!reader.isUnchanged && reader.texture("item/test") == nil)
        #expect(reader.sourceIdentity == original)
    }

    @Test func retargetedSymlinkRequiresPathIdentityEvenIfOpenedFileIsUnchanged() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.jar"), second = root.appendingPathComponent("second.jar")
        let link = root.appendingPathComponent("selected.jar")
        try archive(texture).write(to: first)
        try archive(Data("replaced texture".utf8)).write(to: second)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let reader = try #require(try GameAssets(contentsOf: link))
        #expect(try GameAssets.SourceIdentity(contentsOf: link) == reader.sourceIdentity)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        #expect(reader.isUnchanged && reader.texture("item/test") == texture)
        #expect(try GameAssets.SourceIdentity(contentsOf: link) != reader.sourceIdentity)
        let current = try #require(try GameAssets(contentsOf: link))
        #expect(try GameAssets.SourceIdentity(contentsOf: link) == current.sourceIdentity)
        #expect(current.texture("item/test") == Data("replaced texture".utf8))
    }

    @Test func metadataIdentityDoesNotValidateArchiveContents() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty.jar")
        try Data().write(to: empty)
        #expect(try GameAssets.SourceIdentity(contentsOf: empty).byteCount == 0)
        #expect(try GameAssets(contentsOf: empty) == nil)
        for url in [root, root.appendingPathComponent("missing.jar"),
                    URL(string: "https://example.com/game.jar")!, URL(fileURLWithPath: "/bad\0path")] {
            #expect(throws: (any Error).self) { try GameAssets.SourceIdentity(contentsOf: url) }
        }
    }

    @Test func dataBackedReaderHasNoFileIdentityAndStaysUnchanged() throws {
        var bytes = try archive(texture)
        let reader = try #require(GameAssets(data: bytes))
        bytes[0] = 0
        #expect(reader.sourceIdentity == nil && reader.isUnchanged)
        #expect(reader.texture("item/test") == texture)
    }
}
