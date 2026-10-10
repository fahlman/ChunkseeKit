import Foundation

/// A point of interest from a dimension's `poi/` region files: beds, villager workstations, bells,
/// Nether portal blocks, lodestones, bee nests and so on.
public struct PointOfInterest: Sendable, Equatable, Codable {
    /// Type id, e.g. `minecraft:home` (a bed), `minecraft:nether_portal`, `minecraft:meeting` (a bell).
    public var type: String
    public var x: Int
    public var y: Int
    public var z: Int
    /// How many more villagers (or other users) can claim it; a bed with 0 is already claimed.
    public var freeTickets: Int

    public init(type: String, x: Int, y: Int, z: Int, freeTickets: Int) {
        self.type = type
        self.x = x
        self.y = y
        self.z = z
        self.freeTickets = freeTickets
    }

    /// The records in one `poi` chunk: `{Sections: {"<y>": {Valid, Records: [{type, pos, free_tickets}]}}}`.
    /// Sections the game marked invalid (being rebuilt) are skipped.
    public static func records(inChunk nbt: NBT) -> [PointOfInterest] {
        guard let sections = nbt["Sections"]?.compound else { return [] }
        return sections.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }.flatMap { _, section -> [PointOfInterest] in
            guard section["Valid"]?.bool ?? true else { return [] }
            return (section["Records"]?.list ?? []).compactMap { record in
                guard let type = record["type"]?.string, let pos = record["pos"]?.intArray, pos.count == 3 else { return nil }
                return PointOfInterest(type: type, x: Int(pos[0]), y: Int(pos[1]), z: Int(pos[2]),
                                       freeTickets: record["free_tickets"]?.int ?? 0)
            }
        }
    }
}

extension Dimension {
    /// Points of interest in one region (see `regionFiles(.pointsOfInterest)`), or none if the
    /// dimension has no `poi` file for it. Chunks that can't be read are skipped.
    public func pointsOfInterest(regionX: Int, regionZ: Int) throws -> [PointOfInterest] {
        try chunks(.pointsOfInterest, regionX: regionX, regionZ: regionZ).flatMap { PointOfInterest.records(inChunk: $0.nbt) }
    }
}
