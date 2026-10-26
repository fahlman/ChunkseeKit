import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.client.color.block.BlockColors;
import net.minecraft.client.color.block.BlockTintSource;
import net.minecraft.client.renderer.BiomeColors;
import net.minecraft.client.renderer.block.BlockAndTintGetter;
import net.minecraft.client.renderer.block.ModelBlockRenderer;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Actual in-world tint methods. The proxy records biome queries without creating a world. */
final class ExtractBlockTints {
    private static final Gson GSON = new Gson();

    static JsonObject extract() throws ReflectiveOperationException {
        var colors = BlockColors.createDefault();
        var missingTint = ModelBlockRenderer.class.getDeclaredMethod("computeTintColor", BlockAndTintGetter.class,
            BlockState.class, BlockPos.class, int.class);
        missingTint.setAccessible(true);
        var firstProbe = new WorldProbe(0x102030);
        var secondProbe = new WorldProbe(0xabcdef);
        var blocks = new TreeMap<String, JsonArray>();
        var samples = new JsonArray();
        JsonObject missingSource = null;
        int statesChecked = 0;
        for (var block : BuiltInRegistries.BLOCK) {
            String id = BuiltInRegistries.BLOCK.getKey(block).toString();
            var sources = colors.getTintSources(block.defaultBlockState());
            var builders = new ArrayList<SourceBuilder>();
            for (var source : sources) builders.add(new SourceBuilder(source));
            for (var state : block.getStateDefinition().getPossibleStates()) {
                if (!sources.equals(colors.getTintSources(state))) throw new IllegalStateException("State-dependent source registration: " + id);
                for (int index = 0; index < sources.size(); index++) {
                    var source = sources.get(index);
                    var tint = firstProbe.read(source, state);
                    if (!tint.equals(secondProbe.read(source, state))) throw new IllegalStateException("Unsupported biome-color transformation: " + id);
                    if (builders.get(index).add(state, tint)) samples.add(sample(id, state, index, tint));
                }
                statesChecked++;
            }
            var fallback = new JsonObject();
            int missingRGB = (int) missingTint.invoke(new ModelBlockRenderer(false, false, colors), firstProbe.world,
                block.defaultBlockState(), firstProbe.origin, Integer.MAX_VALUE);
            fallback.addProperty("rgb", missingRGB & 0xffffff);
            if (missingSource != null && !missingSource.equals(fallback)) throw new IllegalStateException("Inconsistent missing-source behavior");
            missingSource = fallback;
            samples.add(sample(id, block.defaultBlockState(), sources.size(), fallback));
            var entries = new JsonArray();
            for (var builder : builders) entries.add(builder.finish());
            blocks.put(id, entries);
        }
        var result = new JsonObject();
        var registrations = new JsonObject();
        blocks.forEach(registrations::add);
        result.add("blocks", registrations);
        result.add("missingSource", missingSource);
        result.addProperty("statesChecked", statesChecked);
        result.add("samples", samples);
        return result;
    }

    private static JsonObject sample(String id, BlockState state, int index, JsonObject tint) {
        var result = new JsonObject();
        result.addProperty("id", id);
        result.addProperty("index", index);
        var values = new TreeMap<String, String>();
        for (var property : state.getProperties()) values.put(property.getName(), valueName(state, property));
        result.add("properties", GSON.toJsonTree(values));
        result.add("tint", tint);
        return result;
    }

    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }

    private static final class SourceBuilder {
        final BlockTintSource source;
        final List<Property<?>> properties;
        final Map<List<String>, JsonObject> observations = new LinkedHashMap<>();
        SourceBuilder(BlockTintSource source) {
            this.source = source;
            properties = source.relevantProperties().stream().sorted(Comparator.comparing(Property::getName)).toList();
        }
        boolean add(BlockState state, JsonObject tint) {
            var key = properties.stream().map(p -> valueName(state, p)).toList();
            var previous = observations.putIfAbsent(key, tint);
            if (previous != null && !previous.equals(tint)) throw new IllegalStateException("Undeclared color-driving property: " + state);
            return previous == null;
        }
        JsonObject finish() {
            var names = new ArrayList<>(properties.stream().map(Property::getName).toList());
            Map<List<String>, JsonObject> values = observations;
            // relevantProperties can include particle-only inputs. Retain only dependencies
            // of colorInWorld, so an unrelated malformed property cannot hide a known tint.
            for (int index = names.size() - 1; index >= 0; index--) {
                var projected = new LinkedHashMap<List<String>, JsonObject>();
                boolean independent = true;
                for (var entry : values.entrySet()) {
                    var key = new ArrayList<>(entry.getKey());
                    key.remove(index);
                    var previous = projected.putIfAbsent(key, entry.getValue());
                    if (previous != null && !previous.equals(entry.getValue())) { independent = false; break; }
                }
                if (independent) { names.remove(index); values = projected; }
            }
            var result = new JsonObject();
            // JVM hidden lambda suffixes contain process-specific identities, not provenance.
            String implementation = source.getClass().getName();
            int lambda = implementation.indexOf("$$Lambda");
            if (lambda >= 0) implementation = implementation.substring(0, lambda) + ".lambda";
            result.addProperty("source", "BlockColors.createDefault -> " + implementation + ".colorInWorld");
            result.add("properties", GSON.toJsonTree(names));
            var entries = new JsonArray();
            values.entrySet().stream().sorted(Comparator.comparing(e -> GSON.toJson(e.getKey()))).forEach(entry -> {
                var value = new JsonObject();
                value.add("values", GSON.toJsonTree(entry.getKey()));
                value.add("tint", entry.getValue());
                entries.add(value);
            });
            result.add("values", entries);
            return result;
        }
    }

    private static final class WorldProbe {
        final int marker;
        final BlockPos origin = new BlockPos(37, 64, -21);
        final BlockAndTintGetter world;
        int queries, yOffset;
        String biome;
        WorldProbe(int marker) {
            this.marker = marker;
            world = (BlockAndTintGetter) Proxy.newProxyInstance(BlockAndTintGetter.class.getClassLoader(),
                new Class<?>[] {BlockAndTintGetter.class}, (proxy, method, arguments) -> {
                    if (!method.getName().equals("getBlockTint")) throw new IllegalStateException("Unsupported world query: " + method);
                    var position = (BlockPos) arguments[0];
                    if (position.getX() != origin.getX() || position.getZ() != origin.getZ())
                        throw new IllegalStateException("Unsupported horizontal biome offset");
                    Object resolver = arguments[1];
                    if (resolver == BiomeColors.GRASS_COLOR_RESOLVER) biome = "grass";
                    else if (resolver == BiomeColors.FOLIAGE_COLOR_RESOLVER) biome = "foliage";
                    else if (resolver == BiomeColors.DRY_FOLIAGE_COLOR_RESOLVER) biome = "dryFoliage";
                    else if (resolver == BiomeColors.WATER_COLOR_RESOLVER) biome = "water";
                    else throw new IllegalStateException("Unknown biome color resolver");
                    queries++;
                    yOffset = position.getY() - origin.getY();
                    return marker;
                });
        }
        JsonObject read(BlockTintSource source, BlockState state) {
            queries = 0;
            biome = null;
            yOffset = 0;
            int rgb = source.colorInWorld(state, world, origin) & 0xffffff;
            var result = new JsonObject();
            if (queries == 0) result.addProperty("rgb", rgb);
            else {
                if (queries != 1 || rgb != marker) throw new IllegalStateException("Unsupported biome tint operation");
                result.addProperty("biome", biome);
                result.addProperty("yOffset", yOffset);
            }
            return result;
        }
    }
}
