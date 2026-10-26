import com.google.gson.Gson;
import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;

/** Professions name their trade-set keys in code; trade contents remain runtime data. */
final class ExtractTradingFacts {
    static JsonObject extract() {
        var professions = new TreeMap<String, TreeMap<Integer, String>>();
        for (var profession : BuiltInRegistries.VILLAGER_PROFESSION) {
            var levels = new TreeMap<Integer, String>();
            for (var entry : profession.tradeSetsByLevel().int2ObjectEntrySet()) {
                var actual = profession.getTrades(entry.getIntKey());
                if (!entry.getValue().equals(actual)) throw new IllegalStateException("Changed profession lookup");
                levels.put(entry.getIntKey(), actual.identifier().toString());
            }
            professions.put(BuiltInRegistries.VILLAGER_PROFESSION.getKey(profession).toString(), levels);
        }
        if (professions.isEmpty()) throw new IllegalStateException("No profession code facts");
        var result = new JsonObject();
        result.addProperty("source", "BuiltInRegistries.VILLAGER_PROFESSION -> VillagerProfession.tradeSetsByLevel / getTrades; Villager.updateTrades");
        result.add("professions", new Gson().toJsonTree(professions));
        return result;
    }
}
