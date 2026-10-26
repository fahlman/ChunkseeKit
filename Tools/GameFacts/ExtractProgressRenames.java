import com.google.gson.*;
import com.mojang.datafixers.*;
import com.mojang.serialization.*;
import java.lang.classfile.ClassFile;
import java.lang.classfile.constantpool.StringEntry;
import java.lang.reflect.Modifier;
import java.util.*;
import java.util.function.Function;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.*;

/** Player progress identities, without a recipe/advancement/statistic inventory. */
final class ExtractProgressRenames {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var steps = new JsonArray(); var records = new JsonArray();
        var candidates = constants(DataFixers.class);
        for (Object value : (List<?>) field(DataFixers.getDataFixer(), "globalList")) {
            var fix = (DataFix) value;
            String kind; Function<String, String> rename;
            var inputs = new TreeSet<>(candidates);
            if (fix instanceof StatsRenameFix) {
                kind = "stat";
                var changes = (Map<String, String>) field(fix, "renames");
                inputs.addAll(changes.keySet()); rename = name -> changes.getOrDefault(name, name);
            } else if (fix instanceof AdvancementsRenameFix) {
                kind = "advancement"; rename = (Function<String, String>) field(fix, "renamer");
            } else if (fix instanceof NamespacedTypeRenameFix && field(fix, "type").equals(References.RECIPE)) {
                kind = "recipe"; rename = (Function<String, String>) field(fix, "renamer");
            } else continue;
            inputs.addAll(constants(fix.getClass()));
            if (!kind.equals("stat")) {
                for (var capture : rename.getClass().getDeclaredFields()) {
                    if (Modifier.isStatic(capture.getModifiers())) continue;
                    capture.setAccessible(true); var captured = capture.get(rename);
                    if (captured instanceof String name) inputs.add(name);
                    else if (captured instanceof Map<?, ?> map) for (Object key : map.keySet()) inputs.add((String) key);
                    else throw new IllegalStateException("Unsupported progress rename capture " + captured.getClass());
                }
            }
            var names = new TreeSet<String>();
            for (String name : inputs) {
                if (name.matches("[a-z0-9_.-]+:[a-z0-9_./-]+") && !rename.apply(name).equals(name)) names.add(name);
            }
            require(!names.isEmpty(), "No progress aliases extracted: " + field(fix, "name"));
            int version = DataFixUtils.getVersion(fix.getVersionKey());
            require(fix.getVersionKey() == DataFixUtils.makeKey(version), "Unexpected progress rename subversion");
            var changes = new JsonObject();
            for (String name : names) {
                var spellings = new TreeSet<String>(); spellings.add(name);
                if (name.startsWith("minecraft:")) {
                    spellings.add(name.substring("minecraft:".length()));
                    spellings.add(name.substring("minecraft".length()));
                }
                for (String spelling : spellings) {
                    // Advancement keys are literal strings: some fixes normalize a namespace,
                    // while AdvancementsFix's switch does not. Retain the actual function's domain.
                    if (spelling.equals(name) || kind.equals("advancement")) {
                        String after = rename.apply(spelling);
                        if (!after.equals(spelling)) changes.addProperty(spelling, after);
                    }
                    for (int saved : new int[] {version - 1, version, currentVersion}) {
                        records.add(record(kind, spelling, saved, currentVersion));
                    }
                }
            }
            for (String name : List.of("example:unchanged", "unchanged", "Invalid Name")) {
                require(rename.apply(name).equals(name), "Unbounded progress rename requires an adapter");
            }
            var row = new JsonObject(); row.addProperty("kind", kind); row.addProperty("version", version);
            row.addProperty("source", fix.getClass().getName()); row.addProperty("name", (String) field(fix, "name"));
            row.add("changes", changes); steps.add(row);
        }
        var result = new JsonObject(); result.add("steps", steps); result.add("records", records); return result;
    }

    private static JsonObject record(String kind, String name, int version, int currentVersion) {
        var input = new JsonObject(); input.addProperty("DataVersion", version);
        DSL.TypeReference reference;
        if (kind.equals("stat")) {
            reference = References.STATS; var stats = new JsonObject(); var custom = new JsonObject();
            custom.addProperty(name, 17); stats.add("minecraft:custom", custom); input.add("stats", stats);
        } else if (kind.equals("advancement")) {
            reference = References.ADVANCEMENTS;
            input.add(name, JsonParser.parseString("{\"criteria\":{\"proof\":\"2020-01-01 00:00:00 +0000\"},\"done\":true}"));
        } else {
            reference = References.PLAYER; var book = new JsonObject(); var recipes = new JsonArray(); recipes.add(name);
            book.add("recipes", recipes); book.add("toBeDisplayed", recipes.deepCopy()); input.add("recipeBook", book);
        }
        var output = DataFixers.getDataFixer().update(reference, new Dynamic<>(JsonOps.INSTANCE, input), version, currentVersion).getValue();
        var record = new JsonObject(); record.addProperty("kind", kind + "Progress"); record.addProperty("version", version);
        record.add("input", input); record.add("output", output); return record;
    }

    private static Set<String> constants(Class<?> type) throws Exception {
        var result = new TreeSet<String>();
        try (var stream = type.getResourceAsStream(type.getSimpleName() + ".class")) {
            for (var entry : ClassFile.of().parse(stream.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry string) result.add(string.stringValue());
            }
        }
        return result;
    }

    private static Object field(Object value, String name) throws Exception {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            try { var field = type.getDeclaredField(name); field.setAccessible(true); return field.get(value); }
            catch (NoSuchFieldException inherited) { }
        }
        throw new IllegalStateException("Missing game field " + name);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
