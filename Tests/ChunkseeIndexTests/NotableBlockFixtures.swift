import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

enum NotableBlockFixtures {
    static func tag(_ id: String, _ values: [Any], replace: Bool = false) throws -> TestZIP.Entry {
        let identifier = try #require(Identifier(id))
        let data = try JSONSerialization.data(withJSONObject: ["values": values, "replace": replace])
        return .init(path: "data/\(identifier.namespace)/tags/block/\(identifier.path).json",
                     text: String(decoding: data, as: UTF8.self))
    }

    static func assets(_ entries: [TestZIP.Entry]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":1}"#)
        ] + entries))))
    }

    static func catalog() throws -> NotableBlock.Catalog {
        let jar = try assets([
            tag("diamond_ores", ["diamond_ore", "deepslate_diamond_ore"]),
            tag("emerald_ores", ["emerald_ore", "deepslate_emerald_ore"]),
            tag("gold_ores", ["gold_ore", "deepslate_gold_ore", "nether_gold_ore"]),
            tag("lapis_ores", ["lapis_ore", "deepslate_lapis_ore"])
        ])
        var tags: [String: GameTag] = [:]
        for id in NotableBlock.tagIDs { tags[id] = try jar.tag(id, in: "block") }
        return NotableBlock.Catalog(tags: tags)
    }
}
