import com.google.gson.JsonObject;
import com.mojang.serialization.Dynamic;
import com.mojang.serialization.JsonOps;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.util.datafix.fixes.SaddleEquipmentSlotFix;
import net.minecraft.world.item.Items;

/** Item identities supplied by old saved attachment flags rather than saved item stacks. */
final class ExtractEquipmentFacts {
    static JsonObject extract() throws Exception {
        var saved = new JsonObject();
        saved.addProperty("Saddle", true);
        var fix = SaddleEquipmentSlotFix.class.getDeclaredMethod("fixEntityWithSaddleFlag", Dynamic.class);
        fix.setAccessible(true);
        var upgraded = (Dynamic<?>) fix.invoke(null, new Dynamic<>(JsonOps.INSTANCE, saved));
        var saddle = upgraded.get("saddle");
        var fields = saddle.asMapOpt().result().orElseThrow();
        if (fields.count() != 2) throw new IllegalStateException("New saddle item fields require inspection");
        var result = new JsonObject();
        result.addProperty("legacySaddleItem", saddle.get("id").asString().result().orElseThrow());
        result.addProperty("legacySaddleCount", saddle.get("count").asInt(0));
        // AbstractChestedHorse.mobInteract tests Items.CHEST before setting ChestedHorse.
        result.addProperty("attachedChestItem", BuiltInRegistries.ITEM.getKey(Items.CHEST).toString());
        return result;
    }
}
