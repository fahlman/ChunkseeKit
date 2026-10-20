import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct SavedDateTests {
    private struct Sample: Sendable {
        var text: String
        var epoch: TimeInterval?
        var expected: Date? { epoch.map { Date(timeIntervalSince1970: $0) } }
    }
    private static let samples = [
        Sample(text: "1970-01-01 00:00:00 +0000", epoch: 0),
        Sample(text: "1970-01-01 01:30:00 +0130", epoch: 0),
        Sample(text: "1969-12-31 19:00:00 -0500", epoch: 0),
        Sample(text: "1970-01-01 14:00:00 +1400", epoch: 0),
        Sample(text: "2024-02-29 12:34:56 +0545", epoch: 1_709_189_396),
        Sample(text: "2026-11-09 21:40:44 -0500", epoch: 1_794_278_444),
        Sample(text: "not a date", epoch: nil),
        Sample(text: "", epoch: nil),
    ]
    private static let uuid = "00000000-0000-4000-8000-000000000001"
    private struct Parsed: Sendable {
        var expiry: Date?
        var criterion: Date?
        var completion: Date?
        var entryCount: Int
        var criteriaCount: Int
    }

    private static func read(_ sample: Sample) throws -> Parsed {
        let cache: [[String: String]] = [
            ["uuid": uuid, "name": "Fixture", "expiresOn": sample.text],
            ["uuid": "00000000-0000-4000-8000-000000000002", "name": "No expiry"],
        ]
        let advancements: [String: Any] = [
            "minecraft:story/fixture": ["criteria": ["sample": sample.text, "control": "1969-12-31 23:59:00 +0000"], "done": true],
            "DataVersion": 5023,
        ]
        let entries = try UserCache.parse(JSONSerialization.data(withJSONObject: cache))
        let progress = try #require(AdvancementProgress.list(json: JSONSerialization.data(withJSONObject: advancements)).first)
        return Parsed(expiry: entries.first?.expires, criterion: progress.criteria["sample"], completion: progress.completed,
                      entryCount: entries.count, criteriaCount: progress.criteria.count)
    }

    @Test(arguments: samples)
    private func bothPublicReadersPreserveDatesOffsetsAndMalformedValues(_ sample: Sample) throws {
        let parsed = try Self.read(sample)
        #expect(parsed.expiry == sample.expected && parsed.criterion == sample.expected)
        #expect(parsed.entryCount == 2)
        #expect(parsed.criteriaCount == (sample.epoch == nil ? 1 : 2))
        #expect(parsed.completion == (sample.expected ?? Date(timeIntervalSince1970: -60)))
    }

    @Test func concurrentPublicReadersDoNotContaminateEachOthersDates() async throws {
        let count = Self.samples.count * 4
        var received: Set<Int> = []
        try await withThrowingTaskGroup(of: (Int, Parsed).self) { group in
            for index in 0..<count {
                let sample = Self.samples[index % Self.samples.count]
                group.addTask { (index, try Self.read(sample)) }
            }
            for try await (index, parsed) in group {
                let sample = Self.samples[index % Self.samples.count]
                #expect(parsed.expiry == sample.expected && parsed.criterion == sample.expected)
                #expect(parsed.entryCount == 2 && parsed.criteriaCount == (sample.epoch == nil ? 1 : 2))
                received.insert(index)
            }
        }
        #expect(received.count == count)
    }

    @Test func cacheSelectionStillUsesTheInstantRatherThanTheTimestampText() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for (folder, name, date) in [("a", "Earlier", "1970-01-01 01:00:00 +0200"),
                                     ("b", "Later", "1970-01-01 00:00:00 +0000"),
                                     ("c", "Unknown date", "invalid")] {
            let data = try JSONSerialization.data(withJSONObject: [["uuid": Self.uuid, "name": name, "expiresOn": date]])
            try Fixtures.write(Array(data), to: root.appendingPathComponent(folder + "/usercache.json"))
        }
        let entries = UserCache.names(under: root, depth: 1)
        let newest = try #require(entries[UUID(uuidString: Self.uuid)!])
        #expect(entries.count == 1 && newest.name == "Later")
        #expect(newest.expires == Date(timeIntervalSince1970: 0))
    }
}
