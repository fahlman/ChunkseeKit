import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.SpawnEggItem;

/** Uses the game's entity-data lookup after item prototype components have been bound. */
final class ExtractSpawnEggs {
    static JsonObject extract() {
        var eggs = new TreeMap<String, String>();
        for (var entity : BuiltInRegistries.ENTITY_TYPE) {
            var found = SpawnEggItem.byId(entity);
            if (found.isEmpty()) continue;
            var item = found.get().value();
            if (!(item instanceof SpawnEggItem)) {
                throw new IllegalStateException("SpawnEggItem.byId returned another item class: " + item.getClass().getName());
            }
            eggs.put(BuiltInRegistries.ENTITY_TYPE.getKey(entity).toString(), BuiltInRegistries.ITEM.getKey(item).toString());
        }
        if (eggs.isEmpty()) throw new IllegalStateException("No spawn-egg relationships found");
        var result = new JsonObject();
        eggs.forEach(result::addProperty);
        return result;
    }
}
