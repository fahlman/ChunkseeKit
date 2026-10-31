import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Property dependencies proven by observed state results, including explicit unknown values. */
record BlockStateValues<Value>(List<String> properties, Map<List<String>, Value> values) {
    static <Value> BlockStateValues<Value> reduce(List<String> properties, Map<List<String>, Value> observations) {
        var names = new ArrayList<>(properties);
        Map<List<String>, Value> values = observations;
        // Drop a property only when all remaining combinations still have one result.
        // Callers represent unknown answers with a value, not null, so they participate equally.
        for (int index = names.size() - 1; index >= 0; index--) {
            var projected = new LinkedHashMap<List<String>, Value>();
            boolean independent = true;
            for (var entry : values.entrySet()) {
                var key = new ArrayList<>(entry.getKey());
                key.remove(index);
                var previous = projected.putIfAbsent(key, entry.getValue());
                if (previous != null && !previous.equals(entry.getValue())) { independent = false; break; }
            }
            if (independent) { names.remove(index); values = projected; }
        }
        return new BlockStateValues<>(names, values);
    }
}
