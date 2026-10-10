import Foundation
import Testing
@testable import MCWorldKit

@Suite struct UserCacheTests {
    @Test func parsesEntriesAndSkipsMalformedOnes() throws {
        let json = """
        [{"uuid":"52dfb519-de9c-47e6-bc6c-bb053cc423e7","name":"fahlman","expiresOn":"2026-11-09 21:40:44 -0500"},
         {"uuid":"not-a-uuid","name":"x","expiresOn":"2026-11-09 21:40:44 -0500"},
         {"uuid":"06d119da-bc79-410f-8f7b-062ce442a86d","name":"","expiresOn":"2026-11-09 21:40:44 -0500"},
         {"uuid":"8688ec2e-834a-4b2e-9499-0a2387b8780d","name":"someone"}]
        """
        let entries = try UserCache.parse(Data(json.utf8))
        #expect(entries.map(\.name) == ["fahlman", "someone"])
        #expect(entries[0].uuid == UUID(uuidString: "52DFB519-DE9C-47E6-BC6C-BB053CC423E7"))
        #expect(entries[0].expires == Date(timeIntervalSince1970: 1_794_278_444))  // 2026-11-10 02:40:44 UTC
        #expect(entries[1].expires == nil)
        #expect(throws: UserCache.ReadError.notAUserCache) { try UserCache.parse(Data("{}".utf8)) }
    }

    @Test func mergesCachesUnderAFolderPreferringTheNewest() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let uuid = "06d119da-bc79-410f-8f7b-062ce442a86d"
        func cache(_ path: String, _ name: String, _ expires: String) throws {
            try Fixtures.write(Array(#"[{"uuid":"\#(uuid)","name":"\#(name)","expiresOn":"\#(expires)"}]"#.utf8),
                               to: root.appendingPathComponent(path))
        }
        try cache("vanilla/release/usercache.json", "OldName", "2025-07-01 00:00:00 +0000")
        try cache("vanilla/snapshot/usercache.json", "NewName", "2026-09-01 00:00:00 +0000")
        try cache("vanilla/release/saves/World/usercache.json", "Ignored", "2027-01-01 00:00:00 +0000")  // saves aren't searched
        let names = UserCache.names(under: root)
        #expect(names[UUID(uuidString: uuid)!]?.name == "NewName")
        #expect(UserCache.names(under: root, depth: 1).isEmpty)  // the caches are two levels down
    }
}
