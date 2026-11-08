import Foundation
import Testing
import ChunkseeKitTestSupport
@testable import ChunkseeKit

@Suite struct AssetJSONNumberTests {
    // Actual StrictJsonParser/JsonOps/Codec.INT, intRange(1,255), and Codec.FLOAT outputs.
    // Frozen official jar/runtime hashes and raw results: game-json-integers-evidence/strict-probe-2.
    @Test func originalDecimalNumbersMatchGameCoercionAndDefinitionRanges() throws {
        let cases: [(json: String, integer: Int?, level: Int?, floatBits: UInt32?)] = [
            ("0", 0, nil, 0),
            ("1", 1, 1, 1065353216),
            ("1.0", 1, 1, 1065353216),
            ("1.5", 1, 1, 1069547520),
            ("-1.5", -1, nil, 3217031168),
            ("255.9", 255, 255, 1132455526),
            ("256", 256, nil, 1132462080),
            ("2147483647.9", 2147483647, nil, 1325400064),
            ("2147483648", -2147483648, nil, 1325400064),
            ("2147483648.5", -2147483648, nil, 1325400064),
            ("-2147483649", 2147483647, nil, 3472883712),
            ("4294967295", -1, nil, 1333788672),
            ("4294967296", 0, nil, 1333788672),
            ("4294967297", 1, 1, 1333788672),
            ("1e10", 1410065408, nil, 1343554297),
            ("1e100", 0, nil, 2139095040),
            ("1e300", 0, nil, 2139095040),
            ("1e-10", 0, nil, 786163455),
            ("99999999999999999999999999999999999999999", -1, nil, 2139095040),
            ("9223372036854775807", -1, nil, 1593835520),
            ("9223372036854775808", 0, nil, 1593835520),
            ("\"1\"", nil, nil, nil),
            ("true", nil, nil, nil),
            ("false", nil, nil, nil),
            ("null", nil, nil, nil),
            ("[]", nil, nil, nil),
            ("{}", nil, nil, nil),
            ("-0.9", 0, nil, 3211159142),
            ("4294967297.9", 1, 1, 1333788672),
            ("-4294967297.9", -1, nil, 3481272320),
            ("1000000000000000000.01", -1486618624, nil, 1566444395),
            ("0.1", 0, nil, 1036831949),
            ("1.00000005960464477539062500001", 1, 1, 1065353217),
            ("1.00000005960464477539062499999", 1, 1, 1065353216),
            ("3.4028235e38", -2147483648, nil, 2139095039),
        ]
        var entries = [TestZIP.Entry(path: "version.json", text: #"{"id":"fixture","world_version":999999}"#)]
        for (index, fixture) in cases.enumerated() {
            let value = try AssetJSON.value(from: Data(fixture.json.utf8))
            #expect((try? AssetJSON.integer(value)) == fixture.integer, "\(fixture.json)")
            let expectedFloat = fixture.floatBits.map(Float.init(bitPattern:)).flatMap { $0.isFinite ? $0.bitPattern : nil }
            #expect((try? AssetJSON.number(value))?.bitPattern == expectedFloat, "\(fixture.json)")
            #expect((try? AssetJSON.float(value))?.bitPattern == fixture.floatBits, "\(fixture.json)")
            let json = "{\"max_level\":" + fixture.json + ",\"slots\":[\"head\"],\"effects\":{}}"
            let definition = try #require(EnchantmentDefinition(data: Data(json.utf8)))
            #expect(definition.maximumLevel == fixture.level, "\(fixture.json)")
            #expect(definition.slots == ["head"] && definition.hasMaximumHealthModifier == false)
            entries.append(.init(path: "data/test/enchantment/number_\(index).json", text: json))
        }
        let assets = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        let definitions = try assets.enchantmentDefinitions()
        #expect(definitions.count == cases.count)
        for (index, fixture) in cases.enumerated() {
            #expect(definitions["test:number_\(index)"]?.maximumLevel == fixture.level)
        }
    }

    @Test func publicResourceReadersShareIntegerCoercionWithoutLosingFloatsOrBooleans() throws {
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: #"{"id":"fixture","world_version":999999}"#),
            .init(path: "assets/test/blockstates/sample.json", text: #"{"variants":{"":[{"model":"test:block/sample","weight":4294967297.9,"y":90.9,"uvlock":true}]}}"#),
            .init(path: "assets/test/models/block/sample.json", text: "{}"),
            .init(path: "data/test/timeline/day.json", text: #"{"clock":"test:clock","period_ticks":4294967297.9}"#),
            .init(path: "data/test/worldgen/biome/sample.json", text: #"{"temperature":1.00000005960464477539062500001,"downfall":0.5,"effects":{"water_color":4294967297.9},"attributes":{"minecraft:gameplay/natural_mob_spawns":{"spawns_by_category":{"monster":[{"type":"test:visible","weight":4294967297.9},{"type":"test:zero","weight":-0.9},{"type":"test:invalid","weight":2147483648}]}}}}"#),
        ]
        let assets = try #require(GameAssets(data: Data(TestZIP.zip(entries))))
        let block = try #require(assets.blockModel(for: BlockState("test:sample")))
        let alternative = try #require(block.parts.first?.alternatives.first)
        #expect(alternative.weight == 1 && alternative.rotation.y == 90 && alternative.uvLock)
        #expect(assets.timelineTiming("test:day")?.periodTicks == 1)
        let biome = try #require(assets.biomeDefinition("test:sample"))
        #expect(biome.temperature.bitPattern == 1065353217 && biome.downfall == 0.5 && biome.waterColor == 1)
        let spawns = try #require(assets.biomeSpawnSettings("test:sample", base: nil))
        #expect(spawns.contains("test:visible", in: "monster") == true)
        #expect(spawns.contains("test:zero", in: "monster") == false)
        #expect(spawns.contains("test:invalid", in: "monster") == nil)
    }
}
