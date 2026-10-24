/// A view of saved values plus verified registry defaults, without changing the saved state.
/// Resolve the block once per model read; all its predicates and seed rules share this lookup.
struct BlockProperties {
    let id: Identifier?
    private let saved: [String: String]
    private let defaults: [String: String]

    init(_ state: BlockState, gameDataVersion: Int32) {
        id = Identifier(state.id)
        saved = state.properties
        if gameDataVersion == SaveVersion.java26_3, let id, id.namespace == "minecraft" {
            defaults = BlockPropertyDefaults.values[id.path] ?? [:]
        } else { defaults = [:] }
    }

    subscript(_ name: String) -> String? { saved[name] ?? defaults[name] }
}

/// Mechanically extracted from the 26.3/5023 registered default states (Kit #195).
/// Client jar SHA-256: 4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d.
/// Exact names only: 884 property-bearing blocks share 114 immutable property dictionaries.
/// Empty dictionaries need no entry. These facts do not validate explicit property domains.
private enum BlockPropertyDefaults {
    static let values: [String: [String: String]] = {
        var result = [String: [String: String]]()
        func add(_ names: String, _ properties: [String: String]) {
            for name in names.split(whereSeparator: \.isWhitespace) { result[String(name)] = properties }
        }
        add("""
        acacia_button bamboo_button birch_button cherry_button crimson_button dark_oak_button
        jungle_button lever mangrove_button oak_button pale_oak_button polished_blackstone_button
        poplar_button spruce_button stone_button warped_button
        """, ["face": "wall", "facing": "north", "powered": "false"])
        add("""
        acacia_door bamboo_door birch_door cherry_door copper_door crimson_door dark_oak_door
        exposed_copper_door iron_door jungle_door mangrove_door oak_door oxidized_copper_door
        pale_oak_door poplar_door spruce_door warped_door waxed_copper_door waxed_exposed_copper_door
        waxed_oxidized_copper_door waxed_weathered_copper_door weathered_copper_door
        """, ["facing": "north", "half": "lower", "hinge": "left", "open": "false", "powered": "false"])
        add("""
        acacia_fence bamboo_fence birch_fence black_stained_glass_pane blue_stained_glass_pane
        brown_stained_glass_pane cherry_fence copper_bars crimson_fence cyan_stained_glass_pane
        dark_oak_fence exposed_copper_bars glass_pane gray_stained_glass_pane green_stained_glass_pane
        iron_bars jungle_fence light_blue_stained_glass_pane light_gray_stained_glass_pane
        lime_stained_glass_pane magenta_stained_glass_pane mangrove_fence nether_brick_fence oak_fence
        orange_stained_glass_pane oxidized_copper_bars pale_oak_fence pink_stained_glass_pane
        poplar_fence purple_stained_glass_pane red_stained_glass_pane spruce_fence warped_fence
        waxed_copper_bars waxed_exposed_copper_bars waxed_oxidized_copper_bars
        waxed_weathered_copper_bars weathered_copper_bars white_stained_glass_pane
        yellow_stained_glass_pane
        """, ["east": "false", "north": "false", "south": "false", "waterlogged": "false", "west": "false"])
        add("""
        acacia_fence_gate bamboo_fence_gate birch_fence_gate cherry_fence_gate crimson_fence_gate
        dark_oak_fence_gate jungle_fence_gate mangrove_fence_gate oak_fence_gate pale_oak_fence_gate
        poplar_fence_gate spruce_fence_gate warped_fence_gate
        """, ["facing": "north", "in_wall": "false", "open": "false", "powered": "false"])
        add("""
        acacia_hanging_sign bamboo_hanging_sign birch_hanging_sign cherry_hanging_sign
        crimson_hanging_sign dark_oak_hanging_sign jungle_hanging_sign mangrove_hanging_sign
        oak_hanging_sign pale_oak_hanging_sign poplar_hanging_sign spruce_hanging_sign
        warped_hanging_sign
        """, ["attached": "false", "rotation": "8", "waterlogged": "false"])
        add("""
        acacia_leaves azalea_leaves birch_leaves cherry_leaves dark_oak_leaves flowering_azalea_leaves
        jungle_leaves mangrove_leaves oak_leaves orange_poplar_leaves pale_oak_leaves red_poplar_leaves
        spruce_leaves yellow_poplar_leaves
        """, ["distance": "7", "persistent": "false", "waterlogged": "false"])
        add("""
        acacia_log acacia_wood bamboo_block basalt birch_log birch_wood bone_block cherry_log
        cherry_wood crimson_hyphae crimson_stem dark_oak_log dark_oak_wood deepslate hay_block
        infested_deepslate jungle_log jungle_wood mangrove_log mangrove_wood muddy_mangrove_roots
        oak_log oak_wood ochre_froglight pale_oak_log pale_oak_wood pearlescent_froglight
        polished_basalt poplar_log poplar_wood purpur_pillar quartz_pillar spruce_log spruce_wood
        stripped_acacia_log stripped_acacia_wood stripped_bamboo_block stripped_birch_log
        stripped_birch_wood stripped_cherry_log stripped_cherry_wood stripped_crimson_hyphae
        stripped_crimson_stem stripped_dark_oak_log stripped_dark_oak_wood stripped_jungle_log
        stripped_jungle_wood stripped_mangrove_log stripped_mangrove_wood stripped_oak_log
        stripped_oak_wood stripped_pale_oak_log stripped_pale_oak_wood stripped_poplar_log
        stripped_poplar_wood stripped_spruce_log stripped_spruce_wood stripped_warped_hyphae
        stripped_warped_stem verdant_froglight warped_hyphae warped_stem
        """, ["axis": "y"])
        add("""
        acacia_pressure_plate bamboo_pressure_plate birch_pressure_plate cherry_pressure_plate
        crimson_pressure_plate dark_oak_pressure_plate jungle_pressure_plate mangrove_pressure_plate
        oak_pressure_plate pale_oak_pressure_plate polished_blackstone_pressure_plate
        poplar_pressure_plate spruce_pressure_plate stone_pressure_plate warped_pressure_plate
        """, ["powered": "false"])
        add("""
        acacia_sapling birch_sapling cherry_sapling dark_oak_sapling jungle_sapling oak_sapling
        pale_oak_sapling poplar_sapling spruce_sapling
        """, ["stage": "0"])
        add("""
        acacia_shelf bamboo_shelf birch_shelf cherry_shelf crimson_shelf dark_oak_shelf jungle_shelf
        mangrove_shelf oak_shelf pale_oak_shelf poplar_shelf spruce_shelf warped_shelf
        """, ["facing": "north", "powered": "false", "side_chain": "unconnected", "waterlogged": "false"])
        add("""
        acacia_sign bamboo_sign birch_sign cherry_sign crimson_sign dark_oak_sign jungle_sign
        mangrove_sign oak_sign pale_oak_sign poplar_sign spruce_sign warped_sign
        """, ["rotation": "8", "waterlogged": "false"])
        add("""
        acacia_slab andesite_slab bamboo_mosaic_slab bamboo_slab birch_slab black_concrete_slab
        black_wool_slab blackstone_slab blue_concrete_slab blue_wool_slab brick_slab brown_concrete_slab
        brown_wool_slab cherry_slab cinnabar_brick_slab cinnabar_slab cobbled_deepslate_slab
        cobblestone_slab crimson_slab cut_copper_slab cut_red_sandstone_slab cut_sandstone_slab
        cyan_concrete_slab cyan_wool_slab dark_oak_slab dark_prismarine_slab deepslate_brick_slab
        deepslate_tile_slab diorite_slab end_stone_brick_slab exposed_cut_copper_slab granite_slab
        gray_concrete_slab gray_wool_slab green_concrete_slab green_wool_slab jungle_slab
        light_blue_concrete_slab light_blue_wool_slab light_gray_concrete_slab light_gray_wool_slab
        lime_concrete_slab lime_wool_slab magenta_concrete_slab magenta_wool_slab mangrove_slab
        mossy_cobblestone_slab mossy_stone_brick_slab mud_brick_slab nether_brick_slab oak_slab
        orange_concrete_slab orange_wool_slab oxidized_cut_copper_slab pale_oak_slab petrified_oak_slab
        pink_concrete_slab pink_wool_slab polished_andesite_slab polished_blackstone_brick_slab
        polished_blackstone_slab polished_cinnabar_slab polished_deepslate_slab polished_diorite_slab
        polished_granite_slab polished_sulfur_slab polished_tuff_slab poplar_slab prismarine_brick_slab
        prismarine_slab purple_concrete_slab purple_wool_slab purpur_slab quartz_slab red_concrete_slab
        red_nether_brick_slab red_sandstone_slab red_wool_slab resin_brick_slab sandstone_slab
        smooth_quartz_slab smooth_red_sandstone_slab smooth_sandstone_slab smooth_stone_slab spruce_slab
        stone_brick_slab stone_slab sulfur_brick_slab sulfur_slab tuff_brick_slab tuff_slab warped_slab
        waxed_cut_copper_slab waxed_exposed_cut_copper_slab waxed_oxidized_cut_copper_slab
        waxed_weathered_cut_copper_slab weathered_cut_copper_slab white_concrete_slab white_wool_slab
        yellow_concrete_slab yellow_wool_slab
        """, ["type": "bottom", "waterlogged": "false"])
        add("""
        acacia_stairs andesite_stairs bamboo_mosaic_stairs bamboo_stairs birch_stairs
        black_concrete_stairs black_wool_stairs blackstone_stairs blue_concrete_stairs blue_wool_stairs
        brick_stairs brown_concrete_stairs brown_wool_stairs cherry_stairs cinnabar_brick_stairs
        cinnabar_stairs cobbled_deepslate_stairs cobblestone_stairs crimson_stairs cut_copper_stairs
        cyan_concrete_stairs cyan_wool_stairs dark_oak_stairs dark_prismarine_stairs
        deepslate_brick_stairs deepslate_tile_stairs diorite_stairs end_stone_brick_stairs
        exposed_cut_copper_stairs granite_stairs gray_concrete_stairs gray_wool_stairs
        green_concrete_stairs green_wool_stairs jungle_stairs light_blue_concrete_stairs
        light_blue_wool_stairs light_gray_concrete_stairs light_gray_wool_stairs lime_concrete_stairs
        lime_wool_stairs magenta_concrete_stairs magenta_wool_stairs mangrove_stairs
        mossy_cobblestone_stairs mossy_stone_brick_stairs mud_brick_stairs nether_brick_stairs
        oak_stairs orange_concrete_stairs orange_wool_stairs oxidized_cut_copper_stairs pale_oak_stairs
        pink_concrete_stairs pink_wool_stairs polished_andesite_stairs polished_blackstone_brick_stairs
        polished_blackstone_stairs polished_cinnabar_stairs polished_deepslate_stairs
        polished_diorite_stairs polished_granite_stairs polished_sulfur_stairs polished_tuff_stairs
        poplar_stairs prismarine_brick_stairs prismarine_stairs purple_concrete_stairs
        purple_wool_stairs purpur_stairs quartz_stairs red_concrete_stairs red_nether_brick_stairs
        red_sandstone_stairs red_wool_stairs resin_brick_stairs sandstone_stairs smooth_quartz_stairs
        smooth_red_sandstone_stairs smooth_sandstone_stairs spruce_stairs stone_brick_stairs
        stone_stairs sulfur_brick_stairs sulfur_stairs tuff_brick_stairs tuff_stairs warped_stairs
        waxed_cut_copper_stairs waxed_exposed_cut_copper_stairs waxed_oxidized_cut_copper_stairs
        waxed_weathered_cut_copper_stairs weathered_cut_copper_stairs white_concrete_stairs
        white_wool_stairs yellow_concrete_stairs yellow_wool_stairs
        """, ["facing": "north", "half": "bottom", "shape": "straight", "waterlogged": "false"])
        add("""
        acacia_trapdoor bamboo_trapdoor birch_trapdoor cherry_trapdoor copper_trapdoor crimson_trapdoor
        dark_oak_trapdoor exposed_copper_trapdoor iron_trapdoor jungle_trapdoor mangrove_trapdoor
        oak_trapdoor oxidized_copper_trapdoor pale_oak_trapdoor poplar_trapdoor spruce_trapdoor
        warped_trapdoor waxed_copper_trapdoor waxed_exposed_copper_trapdoor
        waxed_oxidized_copper_trapdoor waxed_weathered_copper_trapdoor weathered_copper_trapdoor
        """, ["facing": "north", "half": "bottom", "open": "false", "powered": "false", "waterlogged": "false"])
        add("""
        acacia_wall_hanging_sign acacia_wall_sign bamboo_wall_hanging_sign bamboo_wall_sign
        big_dripleaf_stem birch_wall_hanging_sign birch_wall_sign cherry_wall_hanging_sign
        cherry_wall_sign crimson_wall_hanging_sign crimson_wall_sign dark_oak_wall_hanging_sign
        dark_oak_wall_sign ender_chest jungle_wall_hanging_sign jungle_wall_sign ladder
        mangrove_wall_hanging_sign mangrove_wall_sign oak_wall_hanging_sign oak_wall_sign
        pale_oak_wall_hanging_sign pale_oak_wall_sign poplar_wall_hanging_sign poplar_wall_sign
        spruce_wall_hanging_sign spruce_wall_sign warped_wall_hanging_sign warped_wall_sign
        """, ["facing": "north", "waterlogged": "false"])
        add("""
        activator_rail detector_rail powered_rail
        """, ["powered": "false", "shape": "north_south", "waterlogged": "false"])
        add("""
        amethyst_cluster large_amethyst_bud medium_amethyst_bud small_amethyst_bud
        """, ["facing": "up", "waterlogged": "false"])
        add("""
        andesite_wall blackstone_wall brick_wall cinnabar_brick_wall cinnabar_wall
        cobbled_deepslate_wall cobblestone_wall deepslate_brick_wall deepslate_tile_wall diorite_wall
        end_stone_brick_wall granite_wall mossy_cobblestone_wall mossy_stone_brick_wall mud_brick_wall
        nether_brick_wall polished_blackstone_brick_wall polished_blackstone_wall polished_cinnabar_wall
        polished_deepslate_wall polished_sulfur_wall polished_tuff_wall prismarine_wall
        red_nether_brick_wall red_sandstone_wall resin_brick_wall sandstone_wall stone_brick_wall
        sulfur_brick_wall sulfur_wall tuff_brick_wall tuff_wall
        """, ["east": "none", "north": "none", "south": "none", "up": "true", "waterlogged": "false", "west": "none"])
        add("""
        anvil attached_melon_stem attached_pumpkin_stem black_glazed_terracotta black_wall_banner
        blue_glazed_terracotta blue_wall_banner brown_glazed_terracotta brown_wall_banner carved_pumpkin
        chipped_anvil copper_wall_torch cyan_glazed_terracotta cyan_wall_banner damaged_anvil
        gray_glazed_terracotta gray_wall_banner green_glazed_terracotta green_wall_banner jack_o_lantern
        light_blue_glazed_terracotta light_blue_wall_banner light_gray_glazed_terracotta
        light_gray_wall_banner lime_glazed_terracotta lime_wall_banner loom magenta_glazed_terracotta
        magenta_wall_banner orange_glazed_terracotta orange_wall_banner pink_glazed_terracotta
        pink_wall_banner purple_glazed_terracotta purple_wall_banner red_glazed_terracotta
        red_wall_banner soul_wall_torch stonecutter wall_torch white_glazed_terracotta white_wall_banner
        yellow_glazed_terracotta yellow_wall_banner
        """, ["facing": "north"])
        add("""
        bamboo
        """, ["age": "0", "leaves": "none", "stage": "0"])
        add("""
        barrel
        """, ["facing": "north", "open": "false"])
        add("""
        barrier copper_grate exposed_copper_grate hanging_roots heavy_core mangrove_roots
        oxidized_copper_grate waxed_copper_grate waxed_exposed_copper_grate waxed_oxidized_copper_grate
        waxed_weathered_copper_grate weathered_copper_grate
        """, ["waterlogged": "false"])
        add("""
        bee_nest beehive
        """, ["facing": "north", "honey_level": "0"])
        add("""
        beetroots cactus carrots chorus_flower frosted_ice kelp melon_stem nether_wart potatoes
        pumpkin_stem sugar_cane sweet_berry_bush torchflower_crop twisting_vines weeping_vines wheat
        """, ["age": "0"])
        add("""
        bell
        """, ["attachment": "floor", "facing": "north", "powered": "false"])
        add("""
        big_dripleaf
        """, ["facing": "north", "tilt": "none", "waterlogged": "false"])
        add("""
        black_banner blue_banner brown_banner cyan_banner gray_banner green_banner light_blue_banner
        light_gray_banner lime_banner magenta_banner orange_banner pink_banner purple_banner red_banner
        white_banner yellow_banner
        """, ["rotation": "8"])
        add("""
        black_bed blue_bed brown_bed cyan_bed gray_bed green_bed light_blue_bed light_gray_bed lime_bed
        magenta_bed orange_bed pink_bed purple_bed red_bed straw_bed white_bed yellow_bed
        """, ["facing": "north", "occupied": "false", "part": "foot"])
        add("""
        black_candle blue_candle brown_candle candle cyan_candle gray_candle green_candle
        light_blue_candle light_gray_candle lime_candle magenta_candle orange_candle pink_candle
        purple_candle red_candle white_candle yellow_candle
        """, ["candles": "1", "lit": "false", "waterlogged": "false"])
        add("""
        black_candle_cake blue_candle_cake brown_candle_cake candle_cake cyan_candle_cake
        deepslate_redstone_ore gray_candle_cake green_candle_cake light_blue_candle_cake
        light_gray_candle_cake lime_candle_cake magenta_candle_cake orange_candle_cake pink_candle_cake
        purple_candle_cake red_candle_cake redstone_lamp redstone_ore white_candle_cake
        yellow_candle_cake
        """, ["lit": "false"])
        add("""
        black_shulker_box blue_shulker_box brown_shulker_box cyan_shulker_box end_rod gray_shulker_box
        green_shulker_box light_blue_shulker_box light_gray_shulker_box lime_shulker_box
        magenta_shulker_box orange_shulker_box pink_shulker_box purple_shulker_box red_shulker_box
        shulker_box white_shulker_box yellow_shulker_box
        """, ["facing": "up"])
        add("""
        blast_furnace furnace smoker
        """, ["facing": "north", "lit": "false"])
        add("""
        brain_coral brain_coral_fan bubble_coral bubble_coral_fan conduit dead_brain_coral
        dead_brain_coral_fan dead_bubble_coral dead_bubble_coral_fan dead_fire_coral dead_fire_coral_fan
        dead_horn_coral dead_horn_coral_fan dead_tube_coral dead_tube_coral_fan fire_coral
        fire_coral_fan horn_coral horn_coral_fan tube_coral tube_coral_fan
        """, ["waterlogged": "true"])
        add("""
        brain_coral_wall_fan bubble_coral_wall_fan dead_brain_coral_wall_fan dead_bubble_coral_wall_fan
        dead_fire_coral_wall_fan dead_horn_coral_wall_fan dead_tube_coral_wall_fan fire_coral_wall_fan
        horn_coral_wall_fan tube_coral_wall_fan
        """, ["facing": "north", "waterlogged": "true"])
        add("""
        brewing_stand
        """, ["has_bottle_0": "false", "has_bottle_1": "false", "has_bottle_2": "false"])
        add("""
        brown_mushroom_block mushroom_stem red_mushroom_block
        """, ["down": "true", "east": "true", "north": "true", "south": "true", "up": "true", "west": "true"])
        add("""
        bubble_column
        """, ["drag": "true"])
        add("""
        cake
        """, ["bites": "0"])
        add("""
        calibrated_sculk_sensor
        """, ["facing": "north", "power": "0", "sculk_sensor_phase": "inactive", "waterlogged": "false"])
        add("""
        campfire soul_campfire
        """, ["facing": "north", "lit": "true", "signal_fire": "false", "waterlogged": "false"])
        add("""
        cave_vines
        """, ["age": "0", "berries": "false"])
        add("""
        cave_vines_plant
        """, ["berries": "false"])
        add("""
        chain_command_block command_block repeating_command_block
        """, ["conditional": "false", "facing": "north"])
        add("""
        chest copper_chest exposed_copper_chest oxidized_copper_chest trapped_chest waxed_copper_chest
        waxed_exposed_copper_chest waxed_oxidized_copper_chest waxed_weathered_copper_chest
        weathered_copper_chest
        """, ["facing": "north", "type": "single", "waterlogged": "false"])
        add("""
        chiseled_bookshelf
        """, ["facing": "north", "slot_0_occupied": "false", "slot_1_occupied": "false", "slot_2_occupied": "false", "slot_3_occupied": "false", "slot_4_occupied": "false", "slot_5_occupied": "false"])
        add("""
        chorus_plant
        """, ["down": "false", "east": "false", "north": "false", "south": "false", "up": "false", "west": "false"])
        add("""
        cocoa shelf_mushroom
        """, ["age": "0", "facing": "north"])
        add("""
        comparator
        """, ["facing": "north", "mode": "compare", "powered": "false"])
        add("""
        composter lava water
        """, ["level": "0"])
        add("""
        copper_bulb exposed_copper_bulb oxidized_copper_bulb waxed_copper_bulb waxed_exposed_copper_bulb
        waxed_oxidized_copper_bulb waxed_weathered_copper_bulb weathered_copper_bulb
        """, ["lit": "false", "powered": "false"])
        add("""
        copper_chain exposed_copper_chain iron_chain oxidized_copper_chain waxed_copper_chain
        waxed_exposed_copper_chain waxed_oxidized_copper_chain waxed_weathered_copper_chain
        weathered_copper_chain
        """, ["axis": "y", "waterlogged": "false"])
        add("""
        copper_golem_statue exposed_copper_golem_statue oxidized_copper_golem_statue
        waxed_copper_golem_statue waxed_exposed_copper_golem_statue waxed_oxidized_copper_golem_statue
        waxed_weathered_copper_golem_statue weathered_copper_golem_statue
        """, ["copper_golem_pose": "standing", "facing": "north", "waterlogged": "false"])
        add("""
        copper_lantern exposed_copper_lantern lantern oxidized_copper_lantern soul_lantern
        waxed_copper_lantern waxed_exposed_copper_lantern waxed_oxidized_copper_lantern
        waxed_weathered_copper_lantern weathered_copper_lantern
        """, ["hanging": "false", "waterlogged": "false"])
        add("""
        crafter
        """, ["crafting": "false", "orientation": "north_up", "triggered": "false"])
        add("""
        creaking_heart
        """, ["axis": "y", "creaking_heart_state": "uprooted", "natural": "false"])
        add("""
        creeper_head dragon_head piglin_head player_head skeleton_skull wither_skeleton_skull
        zombie_head
        """, ["powered": "false", "rotation": "0"])
        add("""
        creeper_wall_head dragon_wall_head piglin_wall_head player_wall_head skeleton_wall_skull
        wither_skeleton_wall_skull zombie_wall_head
        """, ["facing": "north", "powered": "false"])
        add("""
        daylight_detector
        """, ["inverted": "false", "power": "0"])
        add("""
        decorated_pot
        """, ["cracked": "false", "facing": "north", "waterlogged": "false"])
        add("""
        dispenser dropper
        """, ["facing": "north", "triggered": "false"])
        add("""
        dried_ghast
        """, ["facing": "north", "hydration": "0", "waterlogged": "false"])
        add("""
        end_portal_frame
        """, ["eye": "false", "facing": "north"])
        add("""
        exposed_lightning_rod lightning_rod oxidized_lightning_rod waxed_exposed_lightning_rod
        waxed_lightning_rod waxed_oxidized_lightning_rod waxed_weathered_lightning_rod
        weathered_lightning_rod
        """, ["facing": "up", "powered": "false", "waterlogged": "false"])
        add("""
        farmland
        """, ["moisture": "0"])
        add("""
        fire
        """, ["age": "0", "east": "false", "north": "false", "south": "false", "up": "false", "west": "false"])
        add("""
        glow_lichen resin_clump sculk_vein
        """, ["down": "false", "east": "false", "north": "false", "south": "false", "up": "false", "waterlogged": "false", "west": "false"])
        add("""
        grass_block mycelium podzol
        """, ["snowy": "false"])
        add("""
        grindstone
        """, ["face": "wall", "facing": "north"])
        add("""
        heavy_weighted_pressure_plate light_weighted_pressure_plate target
        """, ["power": "0"])
        add("""
        hopper
        """, ["enabled": "true", "facing": "down"])
        add("""
        jigsaw
        """, ["orientation": "north_up"])
        add("""
        jukebox
        """, ["has_record": "false"])
        add("""
        large_fern lilac peony pitcher_plant rose_bush sunflower tall_grass tall_seagrass
        """, ["half": "lower"])
        add("""
        leaf_litter
        """, ["facing": "north", "segment_amount": "1"])
        add("""
        lectern
        """, ["facing": "north", "has_book": "false", "powered": "false"])
        add("""
        light
        """, ["level": "15", "waterlogged": "false"])
        add("""
        mangrove_propagule
        """, ["age": "0", "hanging": "false", "stage": "0", "waterlogged": "false"])
        add("""
        moving_piston
        """, ["facing": "north", "type": "normal"])
        add("""
        nether_portal
        """, ["axis": "x"])
        add("""
        note_block
        """, ["instrument": "harp", "note": "0", "powered": "false"])
        add("""
        observer
        """, ["facing": "south", "powered": "false"])
        add("""
        pale_hanging_moss
        """, ["tip": "true"])
        add("""
        pale_moss_carpet
        """, ["bottom": "true", "east": "none", "north": "none", "south": "none", "west": "none"])
        add("""
        pink_petals wildflowers
        """, ["facing": "north", "flower_amount": "1"])
        add("""
        piston sticky_piston
        """, ["extended": "false", "facing": "north"])
        add("""
        piston_head
        """, ["facing": "north", "short": "false", "type": "normal"])
        add("""
        pitcher_crop
        """, ["age": "0", "half": "lower"])
        add("""
        pointed_dripstone sulfur_spike
        """, ["thickness": "tip", "vertical_direction": "up", "waterlogged": "false"])
        add("""
        potent_sulfur
        """, ["potent_sulfur_state": "dry"])
        add("""
        powder_snow_cauldron water_cauldron
        """, ["level": "1"])
        add("""
        rail
        """, ["shape": "north_south", "waterlogged": "false"])
        add("""
        redstone_torch
        """, ["lit": "true"])
        add("""
        redstone_wall_torch
        """, ["facing": "north", "lit": "true"])
        add("""
        redstone_wire
        """, ["east": "none", "north": "none", "power": "0", "south": "none", "west": "none"])
        add("""
        repeater
        """, ["delay": "1", "facing": "north", "locked": "false", "powered": "false"])
        add("""
        respawn_anchor
        """, ["charges": "0"])
        add("""
        scaffolding
        """, ["bottom": "false", "distance": "7", "waterlogged": "false"])
        add("""
        sculk_catalyst
        """, ["bloom": "false"])
        add("""
        sculk_sensor
        """, ["power": "0", "sculk_sensor_phase": "inactive", "waterlogged": "false"])
        add("""
        sculk_shrieker
        """, ["can_summon": "false", "shrieking": "false", "waterlogged": "false"])
        add("""
        sea_pickle
        """, ["pickles": "1", "waterlogged": "true"])
        add("""
        small_dripleaf
        """, ["facing": "north", "half": "lower", "waterlogged": "false"])
        add("""
        sniffer_egg
        """, ["hatch": "0"])
        add("""
        snow
        """, ["layers": "1"])
        add("""
        structure_block
        """, ["mode": "load"])
        add("""
        suspicious_gravel suspicious_sand
        """, ["dusted": "0"])
        add("""
        test_block
        """, ["mode": "start"])
        add("""
        tnt
        """, ["unstable": "false"])
        add("""
        trial_spawner
        """, ["ominous": "false", "trial_spawner_state": "inactive"])
        add("""
        tripwire
        """, ["attached": "false", "disarmed": "false", "east": "false", "north": "false", "powered": "false", "south": "false", "west": "false"])
        add("""
        tripwire_hook
        """, ["attached": "false", "facing": "north", "powered": "false"])
        add("""
        turtle_egg
        """, ["eggs": "1", "hatch": "0"])
        add("""
        vault
        """, ["facing": "north", "ominous": "false", "vault_state": "inactive"])
        add("""
        vine
        """, ["east": "false", "north": "false", "south": "false", "up": "false", "west": "false"])
        return result
    }()
}
