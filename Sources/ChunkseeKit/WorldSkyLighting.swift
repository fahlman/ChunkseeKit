import Foundation

extension World {
    /// Composes each readable 26.3 dimension's base lighting and resolved timeline tracks at
    /// their own named saved clock times. No simulation, weather/spatial layers or final range
    /// clamping is applied. Missing/unsupported inputs omit that dimension; read errors propagate.
    ///
    /// Enabled folder/ZIP definitions and timeline tags use normal pack priority and a matching
    /// supplied jar. Tags compose low-to-high, preserve first occurrence and honor replace and
    /// optional references. Direct timeline lists retain duplicates. Malformed/cyclic selections
    /// remain unavailable, including invalid optional selections; no partial-registry recovery.
    /// Fixed-time and default-clock metadata never override a timeline's own clock. Unrelated
    /// tracks require no clock. A dimension with no timelines needs no resource or clock read.
    ///
    /// Query bounds: 64 enabled packs, 64 tag levels, 4,096 entries/members per tag or direct list,
    /// 16 MiB per resource, 64 MiB of selected resource payloads and 65,536 reference/member steps.
    /// Resources and clocks are shared within this read; no mutable cache or world writes persist.
    public func savedSkyLighting(assets: GameAssets?) throws -> [String: SkyLighting] {
        try Task.checkCancellation()
        guard WorldTimelineReader<LightingTimeline>.allowsQuery(in: self) else { return [:] }
        let types = try dimensionTypes(assets: assets)
        var reader: WorldTimelineReader<LightingTimeline>?
        var clocks: [String: Int]?
        var result: [String: SkyLighting] = [:]
        for id in types.keys.sorted() {
            try Task.checkCancellation()
            guard let type = types[id], let time = type.time, let base = type.baseSkyLighting else { continue }
            if time.timelines == .list([]) { result[id] = base; continue }
            if reader == nil {
                reader = try WorldTimelineReader(world: self, assets: assets)
            }
            guard let timelines = try reader?.read(time.timelines) else { continue }
            var value: SkyLighting? = base
            for timeline in timelines where timeline.hasLightingTracks {
                if clocks == nil { clocks = try clockTimes() }
                guard let ticks = clocks?[timeline.clockID], let current = value else { value = nil; break }
                value = timeline.applying(at: Int64(ticks), to: current)
            }
            result[id] = value
        }
        return result
    }
}
