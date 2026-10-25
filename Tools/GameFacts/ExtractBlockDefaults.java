import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Actual registered default states; model files do not designate their default selector. */
final class ExtractBlockDefaults {
    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }

    static JsonObject extract() {
        var blocks = new TreeMap<String, JsonObject>();
        for (var block : BuiltInRegistries.BLOCK) {
            var state = block.defaultBlockState();
            var values = new TreeMap<String, String>();
            for (var property : state.getProperties()) values.put(property.getName(), valueName(state, property));
            var properties = new JsonObject();
            values.forEach(properties::addProperty);
            var entry = new JsonObject();
            entry.addProperty("class", block.getClass().getName());
            entry.add("properties", properties);
            blocks.put(BuiltInRegistries.BLOCK.getKey(block).toString(), entry);
        }
        var result = new JsonObject();
        blocks.forEach(result::add);
        return result;
    }
}
