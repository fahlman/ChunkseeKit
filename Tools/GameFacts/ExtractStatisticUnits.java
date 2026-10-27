import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.stats.Stat;
import net.minecraft.stats.StatFormatter;
import net.minecraft.stats.Stats;

/** Formatter associations are code facts; saved statistic IDs and counts remain runtime data. */
final class ExtractStatisticUnits {
    static JsonObject extract() throws Exception {
        var formatterField = Stat.class.getDeclaredField("formatter");
        formatterField.setAccessible(true);
        var statistics = Stats.CUSTOM;
        var units = new TreeMap<String, String>();
        var proofs = new TreeMap<String, JsonObject>();
        for (var identifier : BuiltInRegistries.CUSTOM_STAT) {
            if (!statistics.contains(identifier)) {
                throw new IllegalStateException("Statistic has no registered formatter: " + identifier);
            }
            var statistic = statistics.get(identifier);
            Object formatter = formatterField.get(statistic);
            String unit;
            if (formatter == StatFormatter.DEFAULT) unit = null;
            else if (formatter == StatFormatter.DISTANCE) unit = "centimeters";
            else if (formatter == StatFormatter.TIME) unit = "ticks";
            else if (formatter == StatFormatter.DIVIDE_BY_TEN) unit = "tenthsOfDamagePoint";
            else throw new IllegalStateException("Unsupported statistic formatter: " + identifier);
            String id = identifier.toString();
            if (unit != null) units.put(id, unit);
            // Public Stat.format output separately proves the scale associated with each ID.
            var proof = new JsonObject();
            for (int value : new int[] {20, 100, 155}) {
                proof.addProperty(Integer.toString(value), statistic.format(value));
            }
            proofs.put(id, proof);
        }
        if (proofs.isEmpty() || units.isEmpty()) throw new IllegalStateException("No statistic facts");
        var result = new JsonObject();
        var values = new JsonObject(); units.forEach(values::addProperty);
        var examples = new JsonObject(); proofs.forEach(examples::add);
        result.add("units", values);
        result.add("formatted", examples);
        return result;
    }
}
