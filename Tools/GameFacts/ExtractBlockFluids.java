import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import java.lang.reflect.Proxy;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Fluid identity is block code; membership in a water/lava tag remains runtime data. */
final class ExtractBlockFluids {
    private static final Gson GSON = new Gson();

    static JsonObject extract() {
        var blocks = new JsonObject();
        var samples = new JsonArray();
        int statesChecked = 0, unknownFaces = 0;
        BlockGetter unavailableWorld = (BlockGetter) Proxy.newProxyInstance(BlockGetter.class.getClassLoader(),
            new Class<?>[] {BlockGetter.class}, (proxy, method, arguments) -> { throw new NeedsWorldData(); });
        for (var block : BuiltInRegistries.BLOCK) {
            String id = BuiltInRegistries.BLOCK.getKey(block).toString();
            var properties = block.getStateDefinition().getProperties().stream()
                .sorted(Comparator.comparing(Property::getName)).toList();
            var fluids = new Values(properties);
            var upperFaces = new Values(properties);
            for (var state : block.getStateDefinition().getPossibleStates()) {
                var fluid = state.getFluidState();
                // Empty has no contained fluid. The sentinel never escapes the generated owner.
                String fluidID = fluid.isEmpty() ? "" : BuiltInRegistries.FLUID.getKey(fluid.getType()).toString();
                JsonElement upperFace;
                try { upperFace = new JsonPrimitive(state.isFaceSturdy(unavailableWorld, BlockPos.ZERO, Direction.UP)); }
                catch (NeedsWorldData error) { upperFace = JsonNull.INSTANCE; unknownFaces++; }
                var fluidValue = new JsonPrimitive(fluidID);
                fluids.add(state, fluidValue);
                upperFaces.add(state, upperFace);
                var sample = new JsonObject();
                sample.addProperty("id", id);
                var saved = new TreeMap<String, String>();
                for (var property : properties) saved.put(property.getName(), valueName(state, property));
                sample.add("properties", GSON.toJsonTree(saved));
                sample.addProperty("fluid", fluidID);
                sample.add("solidUpperFace", upperFace);
                samples.add(sample);
                statesChecked++;
            }
            var entry = new JsonObject();
            entry.addProperty("source", block.getClass().getName() + " via BlockState.getFluidState / isFaceSturdy(UP)");
            entry.add("fluid", fluids.finish());
            entry.add("solidUpperFace", upperFaces.finish());
            blocks.add(id, entry);
        }
        var result = new JsonObject();
        result.add("blocks", blocks);
        result.add("samples", samples);
        result.addProperty("statesChecked", statesChecked);
        result.addProperty("worldDependentUpperFaces", unknownFaces);
        return result;
    }

    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }

    private static final class NeedsWorldData extends RuntimeException {}

    private static final class Values {
        final List<Property<?>> properties;
        final Map<List<String>, JsonElement> observations = new LinkedHashMap<>();
        Values(List<Property<?>> properties) { this.properties = properties; }
        void add(BlockState state, JsonElement result) {
            var key = properties.stream().map(p -> valueName(state, p)).toList();
            if (observations.putIfAbsent(key, result) != null) throw new IllegalStateException("Duplicate block state");
        }
        JsonObject finish() {
            var reduced = BlockStateValues.reduce(properties.stream().map(Property::getName).toList(), observations);
            var result = new JsonObject();
            result.add("properties", GSON.toJsonTree(reduced.properties()));
            var entries = new JsonArray();
            reduced.values().entrySet().stream().sorted(Comparator.comparing(e -> GSON.toJson(e.getKey()))).forEach(entry -> {
                var value = new JsonObject();
                value.add("values", GSON.toJsonTree(entry.getKey()));
                value.add("result", entry.getValue());
                entries.add(value);
            });
            result.add("values", entries);
            return result;
        }
    }
}
