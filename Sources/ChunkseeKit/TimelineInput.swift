import Foundation

/// Shared header and track bounds for independent projections of one timeline resource.
struct TimelineInput {
    let clockID: String
    let periodTicks: Int?
    let tracks: [String: Any]
    let markers: Any?

    init(json: Data) throws {
        guard json.count <= ZipResources.maximumResourceSize else { throw InvalidLighting.data }
        let root = try AssetJSON.object(from: json)
        guard let clock = root["clock"] as? String, let id = Identifier(clock) else { throw InvalidLighting.data }
        clockID = id.description
        if let raw = root["period_ticks"], !(raw is NSNull) {
            let period = try AssetJSON.integer(raw)
            guard period > 0 else { throw InvalidLighting.data }
            periodTicks = period
        } else { periodTicks = nil }
        if let raw = root["tracks"], !(raw is NSNull) { tracks = try AssetJSON.object(raw) }
        else { tracks = [:] }
        markers = root["time_markers"]
    }

    static func sampleTime(_ ticks: Int64, period: Int?) -> Int64 {
        guard let period else { return ticks }
        let remainder = ticks % Int64(period)
        return remainder < 0 ? remainder + Int64(period) : remainder
    }
}

protocol WorldTimelineProjection {
    init?(json: Data)
}
