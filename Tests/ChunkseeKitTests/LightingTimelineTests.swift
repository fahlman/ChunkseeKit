import ChunkseeKitTestSupport
import Foundation
import ChunkseeKit
import Testing

@Suite struct LightingTimelineTests {
    private let sun = "minecraft:visual/sun_angle"
    private let moon = "minecraft:visual/moon_angle"
    private let factor = "minecraft:visual/sky_light_factor"
    private let color = "minecraft:visual/sky_light_color"
    private let phase = "minecraft:visual/moon_phase"
    private var base: SkyLighting {
        SkyLighting(sunAngle: 17, moonAngle: 23, skyLightFactor: 0.8,
                    skyLightColor: SIMD3(0.25, 0.5, 0.75), moonPhase: .fullMoon)!
    }

    @Test(arguments: [1, 5023, Int(Int32.max)])
    func jarQueryPreservesClockIdentityAndMissingAttributes(version: Int) throws {
        let reader = try assets(["clock": ":custom", "tracks": [sun: track([(10, 90)])]], version: version)
        let timeline = try #require(reader.lightingTimeline("test:sky"))
        #expect(timeline.clockID == "minecraft:custom" && timeline.periodTicks == nil)
        let value = try #require(timeline.applying(at: .min, to: base))
        #expect(value.sunAngle == 90 && value.moonAngle == base.moonAngle)
        #expect(value.skyLightFactor == base.skyLightFactor && value.skyLightColor == base.skyLightColor)
        #expect(value.moonPhase == base.moonPhase)
        #expect(reader.lightingTimeline("test:missing") == nil)
        #expect(reader.lightingTimeline("test:../sky") == nil)
        #expect(try assets(["clock": "overworld"], version: version).lightingTimeline("test:sky")?.clockID == "minecraft:overworld")
    }

    @Test func cyclicSegmentsPreserveJumpsAndWrapNegativeAndExtremeTicks() throws {
        let timeline = try #require(try read([sun: track([(6000, 360), (6000, 0)]),
                                         moon: track([(6000, 540), (6000, 180)])], period: 24000))
        #expect(timeline.periodTicks == 24000)
        for (tick, angle): (Int64, Float) in [(0, 270), (5999, 359.985), (6000, 0),
                                            (6001, 0.015), (12000, 90), (23999, 269.985),
                                            (24000, 270), (-1, 269.985), (-18000, 0)] {
            let value = try #require(timeline.applying(at: tick, to: base))
            #expect(abs(value.sunAngle - angle) < 0.0001)
            #expect(abs(value.moonAngle - angle - 180) < 0.0001)
        }
        for tick in [Int64.min, Int64.max] {
            let remainder = tick % 24000
            let wrapped = remainder < 0 ? remainder + 24000 : remainder
            #expect(timeline.applying(at: tick, to: base) == timeline.applying(at: wrapped, to: base))
        }
    }

    @Test func nonperiodicAndConstantTracksHoldTheirEnds() throws {
        let linear = try #require(try read([sun: track([(10, 100), (20, 200)])]))
        let constant = try #require(try read([sun: track([(10, 100), (20, 200)], ease: "constant")]))
        for tick: Int64 in [.min, 0, 10] { #expect(linear.applying(at: tick, to: base)?.sunAngle == 100) }
        #expect(linear.applying(at: 15, to: base)?.sunAngle == 150)
        #expect(constant.applying(at: 19, to: base)?.sunAngle == 100)
        for tick: Int64 in [20, 21, .max] { #expect(linear.applying(at: tick, to: base)?.sunAngle == 200) }
        #expect(constant.applying(at: 20, to: base)?.sunAngle == 200)
    }

    @Test func cubicBezierAndDiscreteValuesUseTheSameEasedSegment() throws {
        let ease: [String: Any] = ["cubic_bezier": [0.5, 0, 0.5, 1]]
        let curve = try #require(try read([sun: track([(0, 0), (100, 200)], ease: ease)]))
        #expect(curve.applying(at: 50, to: base)?.sunAngle == 100)
        #expect((curve.applying(at: 25, to: base)?.sunAngle ?? 200) < 50)
        #expect((curve.applying(at: 75, to: base)?.sunAngle ?? 0) > 150)
        // A valid overshooting curve can cross the discrete interpolation threshold early.
        let overshoot = try #require(try read([phase: track([(0, "full_moon"), (100, "new_moon")],
                                                      ease: ["cubic_bezier": [0.5, 2, 0.5, 2]])]))
        #expect(overshoot.applying(at: 50, to: base)?.moonPhase == .newMoon)
        let flatX = try #require(try read([sun: track([(0, 0), (100000, 100)],
                                                ease: ["cubic_bezier": [1, 0, 0, 1]])]))
        for tick: Int64 in [1, 49999, 50000, 50001, 99999] {
            #expect(flatX.applying(at: tick, to: base) != nil)
        }
    }

    @Test func scalarModifiersComposeWithoutPrematureClamping() throws {
        let expected: [(String, Float)] = [("override", 2), ("add", 19), ("subtract", 15),
                                           ("multiply", 34), ("minimum", 2), ("maximum", 17)]
        for (modifier, result) in expected {
            let value = try #require(try read([sun: track([(0, 2)], modifier: modifier)]))
            #expect(value.applying(at: 0, to: base)?.sunAngle == result)
        }
        #expect(try read([factor: track([(0, 2)])]) == nil) // Override uses the attribute's unit range.
        let multiply = try #require(try read([factor: track([(0, 2)], modifier: "multiply")]))
        #expect(multiply.applying(at: 0, to: base)?.skyLightFactor == 1.6)
        let first = try #require(multiply.applying(at: 0, to: base))
        let half = try #require(try read([factor: track([(0, 0.5)], modifier: "multiply")]))
        #expect(half.applying(at: 0, to: first)?.skyLightFactor == base.skyLightFactor)
    }

    @Test func rgbChannelsKeepPrecisionAndUseColorSpecificModifiers() throws {
        let exact = try #require(try read([color: track([(0, [0.12345, -0.25, 1.5])])]))
        #expect(exact.applying(at: 0, to: base)?.skyLightColor == SIMD3(0.12345, -0.25, 1.5))
        let fade = try #require(try read([color: track([(0, [0.12345, 0.5, 1]), (10, [0.23456, 1, 0])])]))
        let mixed = try #require(fade.applying(at: 5, to: base))
        #expect(abs(mixed.skyLightColor.x - 0.179005) < 0.000001)
        #expect(mixed.skyLightColor.y == 0.75 && mixed.skyLightColor.z == 0.5)
        for value: Any in ["#123456", 0x123456, -15584170] {
            let packed = try #require(try read([color: track([(0, value)])]))
            #expect(packed.applying(at: 0, to: base)?.skyLightColor == SIMD3<Float>(18, 52, 86) / 255)
        }
        let add = try #require(try read([color: track([(0, [1, -1, 0.5])], modifier: "add")]))
        #expect(add.applying(at: 0, to: base)?.skyLightColor == SIMD3(1, -0.5, 1))
        let subtract = try #require(try read([color: track([(0, [1, -1, 0.5])], modifier: "subtract")]))
        #expect(subtract.applying(at: 0, to: base)?.skyLightColor == SIMD3(0, 1.5, 0.25))
        let multiply = try #require(try read([color: track([(0, [1, 2, 0.5])], modifier: "multiply")]))
        #expect(multiply.applying(at: 0, to: base)?.skyLightColor == SIMD3(0.25, 1, 0.375))
    }

    @Test func moonPhasesStepAtTheirSavedBoundaries() throws {
        let phases = SkyLighting.MoonPhase.allCases
        let frames: [(Int, Any)] = phases.enumerated().map { ($0.offset * 24000, $0.element.rawValue) }
        let timeline = try #require(try read([phase: track(frames)], period: 192000))
        for (index, expected) in phases.enumerated() {
            for offset in [0, 1, 23999] {
                #expect(timeline.applying(at: Int64(index * 24000 + offset), to: base)?.moonPhase == expected)
            }
        }
        #expect(timeline.applying(at: -1, to: base)?.moonPhase == .waxingGibbous)
        #expect(timeline.applying(at: 192000, to: base)?.moonPhase == .fullMoon)
    }

    @Test func malformedOrUnsupportedRelevantDataNeverBecomesAPartialSample() throws {
        let invalid: [Any] = [NSNull(), [], 1,
            track([]), track([(2, 1), (1, 2)]), track([(-1, 0)]), track([(Int(Int32.max) + 1, 0)]),
            track([(1, true)]), track([(0, "1")]), track([(0, 1e100)]),
            track([(0, 1)], modifier: "alpha_blend"), track([(0, 1)], modifier: "unknown"),
            track([(0, 1)], ease: "in_bounce"), track([(0, 1)], ease: [:]),
            track([(0, 1)], ease: ["cubic_bezier": [-0.01, 0, 1, 1]]),
            track([(0, 1)], ease: ["cubic_bezier": [0, 0, 1.01, 1]]),
            track([(0, 1)], ease: ["cubic_bezier": [0, 0, 1]])]
        for value in invalid { #expect(try read([sun: track([(0, 17)]), moon: value]) == nil) }
        #expect(try read([color: track([(0, [1, 1])])]) == nil)
        #expect(try read([color: track([(0, "#ffffffff")])]) == nil)
        #expect(try read([color: track([(0, 0)], modifier: "minimum")]) == nil)
        #expect(try read([phase: track([(0, "unknown")])]) == nil)
        #expect(try read([phase: track([(0, "full_moon")], modifier: "add")]) == nil)
        #expect(try read([sun: track([(0, 1)]), "visual/sun_angle": track([(0, 2)])]) == nil)
    }

    @Test func absentAndNullDefaultsAreDistinctFromMalformedFields() throws {
        for fields: [String: Any] in [[:], ["period_ticks": NSNull(), "tracks": NSNull()]] {
            var root: [String: Any] = ["clock": "test:sky"]; root.merge(fields) { _, new in new }
            let timeline = try #require(try assets(root).lightingTimeline("test:sky"))
            #expect(timeline.applying(at: 100, to: base) == base && timeline.periodTicks == nil)
        }
        let defaults = try #require(try read([sun: track([(0, 0), (10, 10)], modifier: NSNull(), ease: NSNull())]))
        #expect(defaults.applying(at: 5, to: base)?.sunAngle == 5)
        for fields: [String: Any] in [["period_ticks": 0], ["period_ticks": -1], ["period_ticks": true],
                                     ["period_ticks": 0.9], ["tracks": []], ["clock": NSNull()],
                                     ["clock": "Invalid Clock"], ["clock": [:]]] {
            var root: [String: Any] = ["clock": "test:sky"]; root.merge(fields) { _, new in new }
            #expect(try assets(root).lightingTimeline("test:sky") == nil)
        }
        // A lighting projection does not attempt to evaluate gameplay tracks or time markers.
        let projection = try #require(try read(["custom:unrelated": "uninterpreted", sun: track([(0, 90)])]))
        #expect(projection.applying(at: 0, to: base)?.sunAngle == 90)
    }

    @Test func duplicateValidationPreservesTheGamesDiscontinuities() throws {
        #expect(try read([sun: track([(1, 1), (1, 2)])]) != nil)
        #expect(try read([sun: track([(1, 1), (1, 2), (1, 3)])]) == nil)
        // 26.3's repeat counter starts at the last keyframe and resets at each new tick.
        let triple = try #require(try read([sun: track([(0, 0), (1, 1), (1, 2), (1, 3), (2, 4)])]))
        #expect(triple.applying(at: 1, to: base)?.sunAngle == 3)
        #expect(try read([sun: track([(0, 0), (1, 1), (1, 2), (1, 3), (1, 4)])]) == nil)
        #expect(try read([sun: track([(0, 1), (10, 2)])], period: 10) != nil)
        #expect(try read([sun: track([(0, 1), (11, 2)])], period: 10) == nil)
    }

    @Test func inputAndArithmeticBoundsFailWithoutTrapping() throws {
        #expect(SkyLighting(sunAngle: .nan, moonAngle: 0, skyLightFactor: 1,
                            skyLightColor: SIMD3(repeating: 1), moonPhase: .fullMoon) == nil)
        #expect(SkyLighting(sunAngle: 0, moonAngle: 0, skyLightFactor: 1,
                            skyLightColor: SIMD3(1, .infinity, 1), moonPhase: .fullMoon) == nil)
        let overflow = try #require(try read([sun: track([(0, Double(Float.greatestFiniteMagnitude))], modifier: "multiply")]))
        #expect(overflow.applying(at: 0, to: base) == nil)
        #expect(try read([sun: track([(1, 0), (2, 1)])], period: Int(Int32.max)) == nil)
        let large = try #require(try read([sun: track([(0, 0), (Int(Int32.max), 1)])]))
        #expect(large.applying(at: .max, to: base)?.sunAngle == 1)
        let frames = (0..<4096).map { ($0, 1 as Any) }
        #expect(try read([sun: track(frames)]) != nil)
        #expect(try read([sun: track(frames), moon: track([(0, 1)])]) == nil)
        let many = Dictionary(uniqueKeysWithValues: (0..<257).map { ("custom:track\($0)", "unused" as Any) })
        #expect(try read(many) == nil)
    }

    @Test func immutableSamplerCanBeReusedAcrossConcurrentConsumers() async throws {
        let timeline = try #require(try read([sun: track([(0, 0), (100, 100)])], period: 100))
        let base = base
        let values = await withTaskGroup(of: Float?.self) { group in
            for _ in 0..<20 { group.addTask { timeline.applying(at: 42, to: base)?.sunAngle } }
            var result: [Float?] = []
            for await value in group { result.append(value) }
            return result
        }
        #expect(values.count == 20 && values.allSatisfy { $0 == 42 })
        #expect(timeline.applying(at: 0, to: base)?.sunAngle == 0)
    }

    private func track(_ frames: [(Int, Any)], modifier: Any? = nil, ease: Any? = nil) -> [String: Any] {
        var value: [String: Any] = ["keyframes": frames.map { ["ticks": $0.0, "value": $0.1] }]
        value["modifier"] = modifier; value["ease"] = ease
        return value
    }

    private func read(_ tracks: [String: Any], period: Int? = nil) throws -> LightingTimeline? {
        var root: [String: Any] = ["clock": "custom:solar", "tracks": tracks]
        root["period_ticks"] = period
        return try assets(root).lightingTimeline("test:sky")
    }

    private func assets(_ root: [String: Any], version: Int = 5023) throws -> GameAssets {
        let json = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let zip = try TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"synthetic\",\"world_version\":\(version)}"),
            .init(path: "data/test/timeline/sky.json", text: "", data: json)
        ])
        return try #require(GameAssets(data: Data(zip)))
    }
}
