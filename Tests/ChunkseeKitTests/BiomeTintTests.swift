import ChunkseeKitTestSupport
import Foundation
import ChunkseeKit
import Testing

@Suite struct BiomeTintTests {
    private func biome(temperature: Float = 0.8, downfall: Float = 0.4, effects: String = "") throws -> BiomeDefinition {
        let json = #"{"temperature":\#(temperature),"downfall":\#(downfall),"effects":{"water_color":1193046\#(effects)}}"#
        let bytes = try TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":5023}"#),
            .init(path: "data/test/worldgen/biome/example.json", text: json)
        ])
        return try #require(GameAssets(data: Data(bytes))?.biomeDefinition("test:example"))
    }

    @Test func climateSamplesTheSamePixelAsItemsAndClampsBiomeClimate() throws {
        let cases: [(Float, Float, SIMD2<Int>)] = [
            (0.8, 0.4, SIMD2(50, 173)), (0.5, 1, SIMD2(127, 127)),
            (-50, 7, SIMD2(255, 255)), (2, 0.5, SIMD2(0, 127)), (2, -3, SIMD2(0, 255))
        ]
        for (temperature, downfall, expected) in cases {
            let value = try biome(temperature: temperature, downfall: downfall)
            for (source, texture) in [(BiomeColor.grass, "grass"), (.foliage, "foliage"), (.dryFoliage, "dry_foliage")] {
                var calls = 0
                let result = value.color(source, x: -12, z: 34) { id, pixel in
                    calls += 1
                    #expect(id.description == "minecraft:colormap/" + texture)
                    #expect(pixel == expected)
                    return 0xabcdef
                }
                #expect(result == 0xabcdef && calls == 1)
            }
        }
    }

    @Test func overridesAndWaterDoNotNeedColormapPixels() throws {
        let value = try biome(effects: #", "grass_color":11259375,"foliage_color":1122867,"dry_foliage_color":4478310"#)
        for (source, expected) in [(BiomeColor.grass, UInt32(0xabcdef)), (.foliage, 0x112233), (.dryFoliage, 0x445566), (.water, 0x123456)] {
            #expect(value.color(source, x: 0, z: 0) { _, _ in
                Issue.record("An explicit color must not decode a colormap")
                return nil
            } == expected)
        }
        let missing = try biome()
        #expect(missing.color(.grass, x: 0, z: 0) { _, _ in nil } == nil)
        #expect(missing.color(.foliage, x: 0, z: 0) { _, _ in nil } == nil)
        #expect(missing.color(.dryFoliage, x: 0, z: 0) { _, _ in nil } == nil)
        #expect(missing.color(.water, x: 0, z: 0) { _, _ in nil } == 0x123456)
    }

    @Test func darkForestModifiesOnlyGrassIncludingAnOverride() throws {
        let value = try biome(effects: #", "grass_color_modifier":"dark_forest""#)
        #expect(value.color(.grass, x: 20, z: -40) { _, _ in 0xabcdef } == 0x69807c)
        #expect(value.color(.foliage, x: 20, z: -40) { _, _ in 0xabcdef } == 0xabcdef)
        #expect(value.color(.grass, x: 20, z: -40) { _, _ in nil } == nil)
        let override = try biome(effects: #", "grass_color_modifier":"dark_forest","grass_color":11259375"#)
        #expect(override.color(.grass, x: 20, z: -40) { _, _ in nil } == 0x69807c)
    }

    @Test func swampMatchesOfficialPositionsAndReplacesAnyBaseColor() throws {
        let value = try biome(effects: #", "grass_color_modifier":"swamp","grass_color":16777215"#)
        // Independently captured from 26.3 GrassColorModifier.SWAMP, not from this implementation.
        let positions: [(Int32, Int32, UInt32)] = [
            (0, 0, 0x6a7039), (1, 1, 0x6a7039), (-1, -1, 0x6a7039),
            (-100, -100, 0x4c763c), (45, 56, 0x4c763c), (-76, 32, 0x4c763c),
            (.min, .max, 0x6a7039)
        ]
        for (x, z, expected) in positions {
            #expect(value.color(.grass, x: x, z: z) { _, _ in nil } == expected)
        }
        #expect(value.color(.foliage, x: 45, z: 56) { _, _ in 0xabcdef } == 0xabcdef)
    }

    @Test func positionDependencyMatchesResolvedColorsForEverySourceAndModifier() throws {
        let cases: [(String, Set<BiomeColor>)] = [
            ("", []),
            (#", "grass_color_modifier":"none""#, []),
            (#", "grass_color_modifier":"dark_forest""#, []),
            (#", "grass_color_modifier":"swamp""#, [.grass]),
            (#", "grass_color":16777215"#, []),
            (#", "grass_color_modifier":"dark_forest","grass_color":16777215"#, []),
            (#", "grass_color_modifier":"swamp","grass_color":16777215"#, [.grass])
        ]
        for (effects, varyingSources) in cases {
            let value = try biome(effects: effects)
            for source in BiomeColor.allCases {
                #expect(value.colorDependsOnPosition(source) == varyingSources.contains(source))
                // These positions have different swamp colors in the official 26.3 probe.
                let first = try #require(value.color(source, x: 0, z: 0) { _, _ in 0xabcdef })
                let second = try #require(value.color(source, x: 45, z: 56) { _, _ in 0xabcdef })
                #expect((first != second) == varyingSources.contains(source))
            }
        }
    }

    @Test func registeredPlantSourcesKeepFixedAndBiomeColorsDistinct() {
        func tint(_ id: String, _ index: Int = 0) -> BlockTint? {
            BlockState(id).tintSource(at: index)
        }
        for id in ["grass_block", "short_grass", "fern", "potted_fern", "bush", "sugar_cane"] {
            #expect(tint(id) == .biome(.grass, yOffset: 0))
        }
        for id in ["oak_leaves", "jungle_leaves", "acacia_leaves", "dark_oak_leaves", "mangrove_leaves", "vine"] {
            #expect(tint(id) == .biome(.foliage, yOffset: 0))
        }
        #expect(tint("spruce_leaves") == .constant(0x619961))
        #expect(tint("birch_leaves") == .constant(0x80a755))
        #expect(tint("lily_pad") == .constant(0x208030))
        #expect(tint("leaf_litter") == .biome(.dryFoliage, yOffset: 0))
        #expect(tint("water_cauldron") == .biome(.water, yOffset: 0))
        // Fluid water is colored separately; these block sources affect only terrain particles.
        #expect(tint("water") == .constant(0xffffff))
        #expect(tint("bubble_column") == .constant(0xffffff))
        for id in ["pink_petals", "wildflowers"] {
            #expect(tint(id, 0) == .constant(0xffffff))
            #expect(tint(id, 1) == .biome(.grass, yOffset: 0))
            #expect(tint(id, 2) == .constant(0xffffff))
        }
    }

    @Test func tallPlantsUseTheLowerHalfBiomeAndVerifiedCompactDefault() {
        for id in ["large_fern", "tall_grass"] {
            #expect(BlockState(id).tintSource(at: 0) == .biome(.grass, yOffset: 0))
            #expect(BlockState(id, properties: ["half": "upper"]).tintSource(at: 0) == .biome(.grass, yOffset: -1))
            #expect(BlockState(id, properties: ["half": "sideways"]).tintSource(at: 0) == nil)
        }
    }

    @Test func stateDrivenColorsKeepAgeAndPowerAndRejectMalformedValues() {
        #expect(BlockState("redstone_wire").tintSource(at: 0) == .constant(0x4c0000))
        #expect(BlockState("redstone_wire", properties: ["power": "15"]).tintSource(at: 0) == .constant(0xff3200))
        for id in ["melon_stem", "pumpkin_stem"] {
            #expect(BlockState(id).tintSource(at: 0) == .constant(0x00ff00))
            #expect(BlockState(id, properties: ["age": "7"]).tintSource(at: 0) == .constant(0xe0c71c))
        }
        for id in ["attached_melon_stem", "attached_pumpkin_stem"] {
            #expect(BlockState(id).tintSource(at: 0) == .constant(0xe0c71c))
        }
        for raw in ["-1", "16", "01", "0.0", "NaN", "999999999999999999999999"] {
            #expect(BlockState("redstone_wire", properties: ["power": raw]).tintSource(at: 0) == nil)
            #expect(BlockState("melon_stem", properties: ["age": raw]).tintSource(at: 0) == nil)
        }
    }

    @Test func missingRegisteredSourcesLeaveTheTextureUntinted() {
        for id in ["cherry_leaves", "pale_oak_leaves", "bamboo", "bamboo_sapling", "stonecutter",
                   "lava_cauldron", "powder_snow_cauldron", "stone"] {
            for index in [0, 1, Int.max] {
                #expect(BlockState(id).tintSource(at: index) == .constant(0xffffff))
            }
        }
        for id in ["oak_leaves", "redstone_wire", "tall_grass"] {
            #expect(BlockState(id).tintSource(at: 1) == .constant(0xffffff))
        }
    }

    @Test func unrelatedMalformedPropertiesDoNotHideKnownTints() {
        #expect(BlockState("grass_block", properties: ["snowy": "invalid"]).tintSource(at: 0) == .biome(.grass, yOffset: 0))
        #expect(BlockState("redstone_wire", properties: ["north": "invalid", "power": "15"]).tintSource(at: 0) == .constant(0xff3200))
        #expect(BlockState("redstone_wire", properties: ["power": "invalid"]).tintSource(at: 1) == .constant(0xffffff))
        #expect(BlockState("cherry_leaves", properties: ["distance": "invalid"]).tintSource(at: 0) == .constant(0xffffff))
    }

    @Test func unknownCodeFactsAndInvalidIndexesStayUnavailable() {
        for id in ["example:oak_leaves", "example:grass_block", "example:cherry_leaves",
                   "minecraft:no_registered_source", "invalid ID"] {
            #expect(BlockState(id).tintSource(at: 0) == nil)
        }
        for index in [-1, Int.min] {
            #expect(BlockState("oak_leaves").tintSource(at: index) == nil)
            #expect(BlockState("cherry_leaves").tintSource(at: index) == nil)
        }
    }
}
