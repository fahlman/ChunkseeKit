import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.serialization.Codec;
import com.mojang.serialization.JsonOps;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.util.random.Weighted;
import net.minecraft.world.attribute.EnvironmentAttributes;

/** Only registered defaults; biome and dimension spawn contents remain runtime resources. */
final class ExtractMobSpawnFacts {
    static JsonObject extract() {
        var result = new JsonObject();
        var missingWeight = Weighted.codec(Codec.STRING.fieldOf("id"))
            .parse(JsonOps.INSTANCE, JsonParser.parseString("{\"id\":\"probe\"}")).result();
        if (missingWeight.isPresent()) result.addProperty("defaultWeight", missingWeight.get().weight());
        result.addProperty("requiresWeight", missingWeight.isEmpty());
        var defaults = EnvironmentAttributes.NATURAL_MOB_SPAWNS.defaultValue();
        var categories = new TreeMap<String, JsonArray>();
        for (var category : defaults.definedCategories()) {
            var entries = new JsonArray();
            for (var weighted : defaults.getMobsToSpawn(category).unwrap()) {
                var entry = new JsonObject();
                entry.addProperty("type", BuiltInRegistries.ENTITY_TYPE.getKey(weighted.value().type()).toString());
                entry.addProperty("weight", weighted.weight());
                entries.add(entry);
            }
            categories.put(category.getName(), entries);
        }
        var values = new JsonObject(); categories.forEach(values::add);
        result.add("defaultCandidates", values);
        return result;
    }
}
