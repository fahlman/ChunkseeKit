import com.google.gson.Gson;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.levelgen.LegacyRandomSource;
import net.minecraft.util.Mth;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Extract seed-method formats, checking their offsets against every registered state. */
final class ExtractBlockModelSeeds {
    private static final List<BlockPos> POSITIONS = List.of(BlockPos.ZERO, new BlockPos(17, -63, -31),
        new BlockPos(Integer.MAX_VALUE, Integer.MIN_VALUE, Integer.MAX_VALUE),
        new BlockPos(Integer.MIN_VALUE, Integer.MAX_VALUE, Integer.MIN_VALUE));

    static JsonObject extract() throws Exception {
        var bed = new TreeMap<String, Map<String, List<Integer>>>();
        var tall = new TreeMap<String, List<Integer>>();
        List<Integer> ordinary = null;
        var blocks = new TreeMap<String, Object>();
        var samples = new ArrayList<Object>();
        var sources = new TreeSet<String>();
        int statesChecked = 0;
        for (var block : BuiltInRegistries.BLOCK) {
            var id = BuiltInRegistries.BLOCK.getKey(block);
            String source = seedSource(block.getClass());
            // These adapters name code formats, never block IDs. A new implementation needs
            // inspection; a matching picture selector cannot establish its seed behavior.
            String family = switch (source) {
                case "net.minecraft.world.level.block.state.BlockBehaviour.getSeed" -> "ordinary";
                case "net.minecraft.world.level.block.AbstractBedBlock.getSeed" -> "bed";
                case "net.minecraft.world.level.block.DoorBlock.getSeed",
                     "net.minecraft.world.level.block.DoublePlantBlock.getSeed" -> "doubleBlock";
                default -> throw new IllegalStateException("Unmapped seed method: " + source);
            };
            sources.add(source);
            int count = 0;
            for (var state : block.getStateDefinition().getPossibleStates()) {
                var properties = properties(state);
                var offset = offset(state);
                switch (family) {
                    case "bed" -> put(bed.computeIfAbsent(required(properties, "part"), key -> new TreeMap<>()),
                        required(properties, "facing"), offset);
                    case "doubleBlock" -> put(tall, required(properties, "half"), offset);
                    default -> {
                        if (ordinary != null && !ordinary.equals(offset)) throw new IllegalStateException("Unclassified seed rule: " + id);
                        ordinary = offset;
                    }
                }
                // Keep public-check vectors for all special states and each ordinary default.
                if (!family.equals("ordinary") || state == block.defaultBlockState()) {
                    var direct = new ArrayList<Integer>();
                    var multipart = new ArrayList<Integer>();
                    for (var position : POSITIONS) {
                        long seed = state.getSeed(position);
                        direct.add(choice(new LegacyRandomSource(seed)));
                        multipart.add(choice(new LegacyRandomSource(new LegacyRandomSource(seed).nextLong())));
                    }
                    samples.add(new TreeMap<String, Object>(Map.of("id", id.toString(), "properties", properties, "family", family,
                        "direct", direct, "multipart", multipart)));
                }
                count++;
            }
            statesChecked += count;
            blocks.put(id.toString(), new TreeMap<String, Object>(Map.of("format", family, "seedMethod", source, "statesChecked", count)));
        }
        if (ordinary == null || bed.isEmpty() || tall.isEmpty()) throw new IllegalStateException("Missing seed formats");
        var result = new JsonObject();
        var gson = new Gson();
        result.add("ordinaryOffset", gson.toJsonTree(ordinary));
        result.add("bedOffsets", gson.toJsonTree(bed));
        result.add("doubleBlockOffsets", gson.toJsonTree(tall));
        result.add("sources", gson.toJsonTree(sources));
        result.add("blocks", gson.toJsonTree(blocks));
        result.addProperty("statesChecked", statesChecked);
        result.add("positions", gson.toJsonTree(POSITIONS.stream().map(p -> List.of(p.getX(), p.getY(), p.getZ())).toList()));
        result.add("samples", gson.toJsonTree(samples));
        return result;
    }

    private static int choice(LegacyRandomSource random) {
        int value = random.nextInt(11); // Synthetic alternatives have weights 1, 3, 7.
        return value < 1 ? 0 : value < 4 ? 1 : 2;
    }

    private static List<Integer> offset(BlockState state) {
        List<Integer> result = null;
        for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
            boolean matches = true;
            for (var position : POSITIONS) {
                if (state.getSeed(position) != Mth.getSeed(position.getX() + x, position.getY() + y, position.getZ() + z)) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                if (result != null) throw new IllegalStateException("Ambiguous seed offset: " + state);
                result = List.of(x, y, z);
            }
        }
        if (result == null) throw new IllegalStateException("Unsupported seed algorithm: " + state);
        return result;
    }

    private static void put(Map<String, List<Integer>> values, String key, List<Integer> offset) {
        var previous = values.putIfAbsent(key, offset);
        if (previous != null && !previous.equals(offset)) throw new IllegalStateException("State-dependent seed format: " + key);
    }

    private static String required(Map<String, String> properties, String key) {
        String value = properties.get(key);
        if (value == null) throw new IllegalStateException("Missing seed property: " + key);
        return value;
    }

    private static String seedSource(Class<?> type) throws Exception {
        for (Class<?> current = type; current != null; current = current.getSuperclass()) {
            try {
                current.getDeclaredMethod("getSeed", BlockState.class, BlockPos.class);
                return current.getName() + ".getSeed";
            } catch (NoSuchMethodException inherited) { }
        }
        throw new IllegalStateException("Missing getSeed implementation: " + type.getName());
    }

    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }

    private static Map<String, String> properties(BlockState state) {
        var values = new TreeMap<String, String>();
        for (var property : state.getProperties()) values.put(property.getName(), valueName(state, property));
        return values;
    }

}
