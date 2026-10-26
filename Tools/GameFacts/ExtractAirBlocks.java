import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.TreeMap;
import java.util.function.Predicate;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.world.level.levelgen.Heightmap;

/** Heightmap uses the block's code flag, independently of membership in the air tag. */
final class ExtractAirBlocks {
    static JsonObject extract() throws ReflectiveOperationException {
        var field = Heightmap.class.getDeclaredField("NOT_AIR");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        var surfacePredicate = (Predicate<BlockState>) field.get(null);
        var flags = new TreeMap<String, Boolean>();
        var samples = new JsonArray();
        var gson = new Gson();
        for (var block : BuiltInRegistries.BLOCK) {
            String id = BuiltInRegistries.BLOCK.getKey(block).toString();
            boolean air = block.defaultBlockState().isAir();
            for (var state : block.getStateDefinition().getPossibleStates()) {
                if (state.isAir() != air) throw new IllegalStateException("State-dependent air flag: " + id);
                if (surfacePredicate.test(state) == air) throw new IllegalStateException("Changed surface-air predicate: " + id);
                var sample = new JsonObject();
                sample.addProperty("id", id);
                var properties = new TreeMap<String, String>();
                for (var property : state.getProperties()) properties.put(property.getName(), valueName(state, property));
                sample.add("properties", gson.toJsonTree(properties));
                sample.addProperty("isAir", air);
                sample.addProperty("surfaceCandidate", surfacePredicate.test(state));
                samples.add(sample);
            }
            flags.put(id, air);
        }
        var result = new JsonObject();
        result.addProperty("source", "BlockBehaviour.Properties.isAir -> BlockState.isAir; Heightmap.NOT_AIR");
        result.add("flags", gson.toJsonTree(flags));
        result.add("samples", samples);
        return result;
    }

    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }
}
