import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Items;

/** Block.asItem owns inventory identity, including wall/standing registrations. */
final class ExtractBlockItems {
    static JsonObject extract() {
        var items = new TreeMap<String, String>();
        for (var block : BuiltInRegistries.BLOCK) {
            var item = block.asItem();
            if (item != Item.byBlock(block)) {
                throw new IllegalStateException("Block.asItem differs from Item.byBlock: " + BuiltInRegistries.BLOCK.getKey(block));
            }
            // AIR is the lookup's no-item result, not a picture for this block.
            if (item == Items.AIR) continue;
            var key = BuiltInRegistries.ITEM.getKey(item);
            if (key == null) throw new IllegalStateException("Unregistered block item");
            items.put(BuiltInRegistries.BLOCK.getKey(block).toString(), key.toString());
        }
        if (items.isEmpty()) throw new IllegalStateException("No block-item relationships found");
        var result = new JsonObject();
        items.forEach(result::addProperty);
        return result;
    }
}
