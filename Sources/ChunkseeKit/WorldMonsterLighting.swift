import Foundation

extension World {
    /// Ordinary monster light eligibility for a clear-night planning overlay, verified for
    /// 26.3 definitions. Each sky-lit dimension uses its selected timelines' first declared
    /// minecraft:midnight on one clock. All gameplay light tracks must use that clock and period;
    /// missing/ambiguous markers, other relevant clocks and unsupported definitions omit it.
    /// Static sky levels need no marker; dimensions without sky light need no sky projection.
    /// This does not use saved clock time, apply weather, predict later nights or test complete
    /// spawnability. The existing visual lighting projection remains independent.
    ///
    /// Enabled pack priority, timeline tags, direct-list duplicates and read limits are shared
    /// with savedSkyLighting. Per-query resources only; no chunks, persistent cache or world writes.
    public func nightMonsterLighting(assets: GameAssets?) throws -> [String: MonsterSpawnLight] {
        try Task.checkCancellation()
        guard level.enabledDataPacks.count <= 64 else { return [:] }
        let types = try dimensionTypes(assets: assets)
        var reader: WorldTimelineReader<MonsterLightTimeline>?
        var result: [String: MonsterSpawnLight] = [:]
        for id in types.keys.sorted() {
            try Task.checkCancellation()
            guard let type = types[id], let time = type.time else { continue }
            if !time.hasSkylight {
                result[id] = MonsterSpawnLight(type: type, skyLightLevel: nil)
                continue
            }
            guard let base = type.baseSkyLightLevel else { continue }
            if time.timelines == .list([]) {
                result[id] = MonsterSpawnLight(type: type, skyLightLevel: base)
                continue
            }
            if reader == nil {
                let vanilla: WorldResourcePack = if let assets, Int(assets.version.dataVersion) == SaveVersion.java26_3 {
                    .zip(assets.resources)
                } else { .unavailable }
                reader = try WorldTimelineReader(packs: WorldResourcePack.load(enabled: level.enabledDataPacks, in: url, vanilla: vanilla))
            }
            guard let timelines = try reader?.read(time.timelines),
                  let value = MonsterLightTimeline.nightLevel(timelines, base: base) else { continue }
            result[id] = MonsterSpawnLight(type: type, skyLightLevel: value)
        }
        return result
    }
}
