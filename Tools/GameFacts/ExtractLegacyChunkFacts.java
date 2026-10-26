import com.google.gson.*;
import com.mojang.datafixers.*;
import com.mojang.serialization.*;
import java.lang.classfile.ClassFile;
import java.lang.classfile.constantpool.StringEntry;
import java.util.*;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.*;

/** Historical chunk format facts and independent complete-game upgrade records. */
final class ExtractLegacyChunkFacts {
    private static Object field(Object object, Class<?> type, String name) throws Exception {
        var field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(object);
    }

    private static List<DataFix> fixes() throws Exception {
        var fixer = DataFixers.getDataFixer();
        var field = fixer.getClass().getDeclaredField("globalList");
        field.setAccessible(true);
        return ((List<?>) field.get(fixer)).stream().map(DataFix.class::cast).toList();
    }

    private static int version(Class<?> type) throws Exception {
        var matches = fixes().stream().filter(type::isInstance).toList();
        if (matches.size() != 1) throw new IllegalStateException("Ambiguous chunk fix: " + type);
        int key = matches.getFirst().getVersionKey();
        int version = DataFixUtils.getVersion(key);
        if (key != DataFixUtils.makeKey(version)) throw new IllegalStateException("Chunk fix subversion: " + type);
        return version;
    }

    private static Set<String> literals(Class<?> type) throws Exception {
        var strings = new TreeSet<String>();
        try (var source = type.getResourceAsStream(type.getSimpleName() + ".class")) {
            for (var entry : ClassFile.of().parse(source.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry string) strings.add(string.stringValue());
            }
        }
        return strings;
    }

    static JsonObject extract(int currentVersion) throws Exception {
        var result = new JsonObject();
        var boundaries = new JsonObject();
        for (var type : List.of(HeightmapRenamingFix.class, ChunkStatusFix.class,
                ChunkStatusFix2.class, ChunkBiomeFix.class, BitStorageAlignFix.class,
                ChunkHeightAndBiomeFix.class, ChunkRenamesFix.class)) {
            boundaries.addProperty(type.getSimpleName(), version(type));
        }
        result.add("boundaries", boundaries);
        var lightResets = new JsonArray();
        for (var fix : fixes()) {
            if (fix instanceof ChunkDeleteLightFix) {
                int key = fix.getVersionKey();
                int reset = DataFixUtils.getVersion(key);
                if (key != DataFixUtils.makeKey(reset)) throw new IllegalStateException("Light reset subversion");
                lightResets.add(reset);
            }
        }
        if (lightResets.isEmpty()) throw new IllegalStateException("No chunk light resets");
        result.add("lightResets", lightResets);
        var geometry = new JsonObject();
        for (String name : List.of("OLD_SECTION_COUNT", "NEW_SECTION_COUNT", "NEW_MIN_SECTION_Y",
                "HEIGHTMAP_BITS", "BIOME_CONTAINER_SIZE", "BIOME_CONTAINER_LAYER_SIZE")) {
            geometry.addProperty(name, (Integer) field(null, ChunkHeightAndBiomeFix.class, name));
        }
        result.add("geometry", geometry);
        var biomes = new JsonObject();
        var names = (Map<?, ?>) field(null, ChunkHeightAndBiomeFix.class, "BIOMES_BY_ID");
        for (var entry : names.entrySet()) biomes.addProperty(entry.getKey().toString(), (String) entry.getValue());
        result.add("biomes", biomes);
        result.addProperty("defaultBiome", (String) field(null, ChunkHeightAndBiomeFix.class, "DEFAULT_BIOME"));

        // Read the format's default state from actual output, rather than copying its name.
        int layoutVersion = version(ChunkHeightAndBiomeFix.class);
        var empty = chunk(layoutVersion - 1, "full", 0, 1, true, 0);
        empty.getAsJsonObject("Level").add("Sections", new JsonArray());
        var upgradedEmpty = update(empty, layoutVersion - 1, currentVersion);
        result.addProperty("emptyBlock", upgradedEmpty.getAsJsonArray("sections").get(0)
            .getAsJsonObject().getAsJsonObject("block_states").getAsJsonArray("palette").get(0)
            .getAsJsonObject().get("id").getAsString());

        var statusSteps = new JsonArray();
        for (var type : List.of(ChunkStatusFix.class, ChunkStatusFix2.class)) {
            int boundary = version(type);
            var candidates = literals(type);
            if (type == ChunkStatusFix2.class) {
                var mapping = (Map<?, ?>) field(null, type, "RENAMES_AND_DOWNGRADES");
                mapping.keySet().forEach(key -> candidates.add((String) key));
            }
            String unknown = "chunksee:unknown_status";
            String fallback = update(chunk(boundary - 1, unknown, 0, 1, false, 256),
                boundary - 1, boundary).getAsJsonObject("Level").get("Status").getAsString();
            var aliases = new JsonObject();
            for (String input : candidates) {
                if (!input.matches("[a-z0-9_:.-]+")) continue;
                String output = update(chunk(boundary - 1, input, 0, 1, false, 256),
                    boundary - 1, boundary).getAsJsonObject("Level").get("Status").getAsString();
                if (!output.equals(input) && (!output.equals(fallback) || fallback.equals(unknown))) {
                    aliases.addProperty(input, output);
                }
            }
            var step = new JsonObject();
            step.addProperty("version", boundary); step.addProperty("source", type.getName());
            step.add("aliases", aliases);
            if (!fallback.equals(unknown)) step.addProperty("fallback", fallback);
            statusSteps.add(step);
        }
        result.add("statusSteps", statusSteps);

        var heightmaps = new JsonObject();
        var fix = fixes().stream().filter(HeightmapRenamingFix.class::isInstance).findFirst().orElseThrow();
        var method = HeightmapRenamingFix.class.getDeclaredMethod("fix", Dynamic.class);
        method.setAccessible(true);
        for (String name : literals(HeightmapRenamingFix.class)) {
            if (!name.matches("[A-Z_]+")) continue;
            var level = new JsonObject(); var heights = new JsonObject();
            heights.add(name, new JsonArray()); level.add("Heightmaps", heights);
            var output = ((Dynamic<?>) method.invoke(fix, new Dynamic<>(JsonOps.INSTANCE, level)))
                .convert(JsonOps.INSTANCE).getValue().getAsJsonObject().getAsJsonObject("Heightmaps");
            if (!output.keySet().equals(Set.of(name))) {
                var destinations = new JsonArray(); new TreeSet<>(output.keySet()).forEach(destinations::add);
                heightmaps.add(name, destinations);
            }
        }
        result.add("heightmapNames", heightmaps);
        result.add("records", records(currentVersion));
        if (biomes.isEmpty() || heightmaps.isEmpty()) throw new IllegalStateException("Missing legacy chunk facts");
        return result;
    }

    private static JsonObject update(JsonObject input, int before, int after) {
        return DataFixers.getDataFixer().update(References.CHUNK,
            new Dynamic<>(JsonOps.INSTANCE, input), before, after).getValue().getAsJsonObject();
    }

    private static JsonArray records(int currentVersion) throws Exception {
        var result = new JsonArray();
        int alignment = version(BitStorageAlignFix.class);
        for (int saved : new int[] {version(ChunkToProtochunkFix.class), version(ChunkStatusFix.class) - 1,
                version(ChunkStatusFix2.class) - 1, version(ChunkBiomeFix.class) - 1,
                alignment - 1, alignment, version(ChunkHeightAndBiomeFix.class) - 1}) {
            String status = saved < version(ChunkStatusFix.class) ? "postprocessed"
                : saved < version(ChunkStatusFix2.class) ? "fullchunk" : "full";
            int biomeCount = saved < version(ChunkBiomeFix.class) ? 256 : 1024;
            for (int paletteCount : new int[] {1, 2, 17, 33, 65, 129}) {
                var input = chunk(saved, status, 4, paletteCount, saved >= alignment, biomeCount);
                addRecord(result, "palette-" + paletteCount, input, saved, currentVersion);
            }
        }
        int saved = version(ChunkHeightAndBiomeFix.class) - 1;
        for (int size : new int[] {0, 7, 1024}) {
            var input = chunk(saved, "full", 4, 1, true, size);
            if (size == 1024) {
                var values = input.getAsJsonObject("Level").getAsJsonArray("Biomes");
                for (int i = 0; i < values.size(); i++) values.set(i, new JsonPrimitive(i - 512));
            }
            addRecord(result, "numeric-biomes-" + size, input, saved, currentVersion);
        }
        var light = chunk(saved, "full", 4, 1, true, 1024);
        light.getAsJsonObject("Level").addProperty("isLightOn", true);
        var bytes = new JsonArray(); for (int i = 0; i < 2048; i++) bytes.add(i % 128);
        light.getAsJsonObject("Level").getAsJsonArray("Sections").get(0).getAsJsonObject().add("BlockLight", bytes);
        light.getAsJsonObject("Level").getAsJsonArray("Sections").get(0).getAsJsonObject().add("SkyLight", bytes.deepCopy());
        addRecord(result, "invalidated-light", light, saved, currentVersion);
        return result;
    }

    private static void addRecord(JsonArray records, String name, JsonObject input, int saved, int current) {
        var record = new JsonObject(); record.addProperty("name", name); record.addProperty("version", saved);
        record.add("input", input); record.add("output", update(input, saved, current)); records.add(record);
    }

    private static JsonArray packed(int count, int bits, boolean aligned, int paletteCount, boolean heightmap) {
        int perWord = 64 / bits;
        var words = new long[aligned ? (count + perWord - 1) / perWord : (count * bits + 63) / 64];
        for (int index = 0; index < count; index++) {
            int value = heightmap ? 80 + index % 16 : index % paletteCount;
            int word = aligned ? index / perWord : index * bits / 64;
            int shift = aligned ? index % perWord * bits : index * bits % 64;
            words[word] |= (long) value << shift;
            if (!aligned && shift + bits > 64) words[word + 1] |= (long) value >>> (64 - shift);
        }
        var result = new JsonArray(); for (long word : words) result.add(word); return result;
    }

    private static JsonObject chunk(int saved, String status, int sectionY, int paletteCount,
            boolean aligned, int biomeCount) {
        var root = new JsonObject(); root.addProperty("DataVersion", saved);
        var level = new JsonObject(); root.add("Level", level);
        level.addProperty("xPos", 2); level.addProperty("zPos", -3); level.addProperty("Status", status);
        level.addProperty("LastUpdate", 678); level.addProperty("InhabitedTime", 345);
        var sections = new JsonArray(); var section = new JsonObject(); section.addProperty("Y", sectionY);
        var palette = new JsonArray();
        for (int i = 0; i < paletteCount; i++) {
            var state = new JsonObject(); state.addProperty("Name", i == 0 ? "minecraft:grass" : "example:block_" + i);
            palette.add(state);
        }
        section.add("Palette", palette);
        int bits = Math.max(4, 32 - Integer.numberOfLeadingZeros(paletteCount - 1));
        section.add("BlockStates", packed(4096, bits, aligned, paletteCount, false));
        sections.add(section); level.add("Sections", sections);
        var biomes = new JsonArray(); for (int i = 0; i < biomeCount; i++) biomes.add(1 + i % 3);
        if (biomeCount > 0) level.add("Biomes", biomes);
        var heights = new JsonObject(); heights.add("WORLD_SURFACE", packed(256, 9, aligned, 1, true));
        level.add("Heightmaps", heights);
        level.add("Entities", JsonParser.parseString("[{\"id\":\"minecraft:cow\",\"Pos\":[32.5,70,-47.5],\"Health\":8.0,\"CanPickUpLoot\":false,\"PersistenceRequired\":false,\"LeftHanded\":false,\"UUID\":[1,2,3,4]}]"));
        level.add("TileEntities", JsonParser.parseString("[{\"id\":\"minecraft:chest\",\"x\":32,\"y\":70,\"z\":-47,\"Items\":[{\"id\":\"minecraft:grass\",\"Count\":2,\"Slot\":0}]}]"));
        return root;
    }
}
