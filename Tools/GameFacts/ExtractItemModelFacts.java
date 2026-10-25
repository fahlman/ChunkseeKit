import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.TreeMap;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.world.item.CrossbowItem;
import net.minecraft.world.item.Items;

/** Only prototype facts needed by saved item-model selectors; item definitions remain resources. */
final class ExtractItemModelFacts {
    static JsonObject extract() {
        // Modern prototypes are deferred until their referenced registries exist. This builds
        // the game's vanilla lookup and binds code initializers; it does not create a world.
        for (var pending : BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(VanillaRegistries.createWorldLookup())) {
            pending.apply();
        }
        var result = new JsonObject();
        var entries = new TreeMap<String, JsonObject>();
        for (var item : BuiltInRegistries.ITEM) {
            var components = item.components();
            var entry = new JsonObject();
            var types = new JsonArray();
            components.keySet().stream().map(type -> BuiltInRegistries.DATA_COMPONENT_TYPE.getKey(type).toString())
                .sorted().forEach(types::add);
            entry.add("components", types);
            var state = components.get(DataComponents.BLOCK_STATE);
            var properties = new JsonObject();
            if (state != null) new TreeMap<>(state.properties()).forEach(properties::addProperty);
            entry.add("blockState", properties);
            var projectiles = components.get(DataComponents.CHARGED_PROJECTILES);
            var charge = projectiles == null || projectiles.isEmpty() ? CrossbowItem.ChargeType.NONE
                : projectiles.contains(Items.FIREWORK_ROCKET) ? CrossbowItem.ChargeType.ROCKET : CrossbowItem.ChargeType.ARROW;
            entry.addProperty("charge", charge.getSerializedName());
            entries.put(BuiltInRegistries.ITEM.getKey(item).toString(), entry);
        }
        var prototypes = new JsonObject();
        entries.forEach(prototypes::add);
        result.add("prototypes", prototypes);
        result.addProperty("rocketItem", BuiltInRegistries.ITEM.getKey(Items.FIREWORK_ROCKET).toString());
        var charges = new JsonObject();
        for (var charge : CrossbowItem.ChargeType.values()) charges.addProperty(charge.name(), charge.getSerializedName());
        result.add("chargeNames", charges);
        return result;
    }
}
