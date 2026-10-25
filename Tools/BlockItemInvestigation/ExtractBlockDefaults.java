import com.google.gson.GsonBuilder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.TreeMap;
import net.minecraft.SharedConstants;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.level.block.state.properties.Property;

/** Investigation oracle: actual registered default states, without opening a world. */
public final class ExtractBlockDefaults {
    @SuppressWarnings({"rawtypes", "unchecked"})
    private static String name(Property property, Comparable value) {
        return property.getName(value);
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected output JSON path");
        SharedConstants.tryDetectVersion();
        Bootstrap.bootStrap();
        var blocks = new TreeMap<String, TreeMap<String, String>>();
        for (var block : BuiltInRegistries.BLOCK) {
            var properties = new TreeMap<String, String>();
            for (var entry : block.defaultBlockState().getValues().entrySet()) {
                properties.put(entry.getKey().getName(), name(entry.getKey(), entry.getValue()));
            }
            blocks.put(BuiltInRegistries.BLOCK.getKey(block).toString(), properties);
        }
        Files.writeString(Path.of(args[0]), new GsonBuilder().setPrettyPrinting().create().toJson(blocks) + "\n");
        System.out.println("BLOCKS " + blocks.size() + ", PROPERTY_BEARING "
            + blocks.values().stream().filter(p -> !p.isEmpty()).count());
    }
}
