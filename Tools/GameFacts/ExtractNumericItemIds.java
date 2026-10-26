import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.datafixers.DataFix;
import com.mojang.datafixers.DataFixUtils;
import com.mojang.serialization.Dynamic;
import com.mojang.serialization.JsonOps;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.ItemIdFix;
import net.minecraft.util.datafix.fixes.References;

/** The numeric item codec step only. Later field-sensitive item fixes have separate adapters. */
final class ExtractNumericItemIds {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var fixer = DataFixers.getDataFixer();
        var fixes = fixer.getClass().getDeclaredField("globalList"); fixes.setAccessible(true);
        var steps = ((List<?>) fixes.get(fixer)).stream().filter(ItemIdFix.class::isInstance).toList();
        require(steps.size() == 1, "Ambiguous numeric item codec step");
        int key = ((DataFix) steps.getFirst()).getVersionKey();
        int boundary = DataFixUtils.getVersion(key);
        require(key == DataFixUtils.makeKey(boundary), "Unexpected numeric item codec subversion");
        var field = ItemIdFix.class.getDeclaredField("ITEM_NAMES"); field.setAccessible(true);
        var map = new TreeMap<>((Map<Integer, String>) field.get(null));
        require(!map.isEmpty(), "No numeric item meanings");
        var mappings = new JsonObject();
        for (var entry : map.entrySet()) {
            require(entry.getValue().equals(ItemIdFix.getItem(entry.getKey())), "Numeric item mapping disagrees");
            mappings.addProperty(entry.getKey().toString(), entry.getValue());
        }
        String fallback = ItemIdFix.getItem(Integer.MIN_VALUE);
        var inputs = new java.util.TreeSet<>(map.keySet());
        for (int absent : new int[] {Integer.MIN_VALUE, -1, Integer.MAX_VALUE}) {
            require(!map.containsKey(absent) && ItemIdFix.getItem(absent).equals(fallback),
                "Numeric item fallback changed");
            inputs.add(absent);
        }
        var proofs = new JsonArray();
        for (int id : inputs) {
            for (int version : new int[] {-1, boundary - 1, boundary}) {
                var input = stack(id, 0);
                var output = fixer.update(References.ITEM_STACK, new Dynamic<>(JsonOps.INSTANCE, input),
                    version, boundary).getValue().getAsJsonObject().get("id");
                if (version < boundary) require(output.getAsString().equals(ItemIdFix.getItem(id)),
                    "Numeric item boundary proof disagrees: " + id);
                else require(output.isJsonPrimitive() && output.getAsJsonPrimitive().isNumber()
                    && output.getAsInt() == id, "Numeric item changed after its boundary");
                var proof = new JsonObject(); proof.addProperty("input", id); proof.addProperty("version", version);
                proof.add("expected", output); proofs.add(proof);
            }
        }
        var result = new JsonObject();
        result.addProperty("source", "ItemIdFix.ITEM_NAMES / getItem / makeRule");
        result.addProperty("boundary", boundary); result.addProperty("fallback", fallback);
        result.add("mappings", mappings); result.add("proofs", proofs);
        result.add("records", records(currentVersion, boundary));
        return result;
    }

    private static JsonObject stack(int id, int damage) {
        var stack = new JsonObject(); stack.addProperty("id", id); stack.addProperty("Damage", damage);
        stack.addProperty("Count", 2); return stack;
    }

    private static JsonArray records(int currentVersion, int boundary) {
        var result = new JsonArray();
        // Format fixtures cover the existing named-variant and later-alias pipeline. They do
        // not claim the separate potion/spawn-egg/banner field conversions are implemented.
        for (int id : new int[] {1, 5, 35, 351, 355, 397}) {
            for (int damage : new int[] {0, 1, 14, 16384}) {
                addRecord(result, "item", stack(id, damage), -1, currentVersion);
            }
        }
        String inventory = """
            {"Inventory":[{"id":35,"Damage":14,"Count":2,"Slot":0},
              {"id":351,"Damage":0,"Count":3,"Slot":1}],
             "EnderItems":[{"id":355,"Damage":0,"Count":1,"Slot":0}]}
            """;
        for (int version : new int[] {-1, boundary - 1}) {
            var player = JsonParser.parseString(inventory).getAsJsonObject();
            player.addProperty("DataVersion", version);
            addRecord(result, "player", player, version, currentVersion);
        }
        return result;
    }

    private static void addRecord(JsonArray result, String kind, JsonObject input, int version, int currentVersion) {
        var reference = kind.equals("player") ? References.PLAYER : References.ITEM_STACK;
        var output = DataFixers.getDataFixer().update(reference,
            new Dynamic<>(JsonOps.INSTANCE, input.deepCopy()), version, currentVersion).getValue();
        var row = new JsonObject(); row.addProperty("kind", kind); row.addProperty("version", version);
        row.add("input", input); row.add("output", output); result.add(row);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
