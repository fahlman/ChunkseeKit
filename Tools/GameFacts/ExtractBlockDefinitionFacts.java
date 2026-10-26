import com.google.gson.JsonArray;
import java.util.Map;
import java.util.TreeSet;
import net.minecraft.client.resources.model.BlockStateDefinitions;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;

/** Rendering-only definitions, never an inventory of registered blocks. */
final class ExtractBlockDefinitionFacts {
    static JsonArray extract() throws Exception {
        var field = BlockStateDefinitions.class.getDeclaredField("STATIC_DEFINITIONS");
        field.setAccessible(true);
        var definitions = (Map<?, ?>) field.get(null);
        var mapper = BlockStateDefinitions.definitionLocationToBlockStateMapper();
        var ids = new TreeSet<String>();
        for (var entry : definitions.entrySet()) {
            if (!(entry.getKey() instanceof Identifier id)) {
                throw new IllegalStateException("Unexpected static definition identifier");
            }
            // The mapper installs registered blocks after the synthetic definitions, so
            // a future real block with the same ID supersedes the rendering-only entry.
            if (BuiltInRegistries.BLOCK.containsKey(id)) continue;
            if (mapper.apply(id) != entry.getValue()) {
                throw new IllegalStateException("Static definition mapper changed: " + id);
            }
            ids.add(id.toString());
        }
        var result = new JsonArray();
        ids.forEach(result::add);
        return result;
    }
}
