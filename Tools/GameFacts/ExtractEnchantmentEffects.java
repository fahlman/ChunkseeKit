import com.google.gson.JsonObject;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.core.component.DataComponentType;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.enchantment.EnchantmentEffectComponents;

/** Codec associations, not enchantment membership. Enchantment contents stay in data packs. */
final class ExtractEnchantmentEffects {
    static JsonObject extract() throws Exception {
        var result = new JsonObject();
        var components = new TreeMap<String, JsonObject>();
        for (var field : EnchantmentEffectComponents.class.getFields()) {
            if (field.getType() != DataComponentType.class) continue;
            var type = (DataComponentType<?>) field.get(null);
            String shape = field.getGenericType().getTypeName();
            String format;
            if (shape.contains("EnchantmentAttributeEffect")) format = "attributes";
            else if (shape.contains("EnchantmentLocationBasedEffect") || shape.contains("EnchantmentEntityEffect")) format = "conditionalEffects";
            else if (shape.contains("EnchantmentValueEffect")) format = shape.contains("java.util.List") ? "conditionalValues" : "value";
            else if (shape.contains("DamageImmunity")) format = "conditionalValues";
            else if (shape.contains("CrossbowItem$ChargingSounds")) format = "sounds";
            else if (shape.contains("SoundEvent")) format = shape.contains("java.util.List") ? "soundList" : "sound";
            else if (shape.contains("net.minecraft.util.Unit")) format = "unit";
            else throw new IllegalStateException("Unknown enchantment component format: " + field);
            var entry = new JsonObject();
            entry.addProperty("format", format);
            entry.addProperty("source", field.getDeclaringClass().getName() + "." + field.getName() + ": " + shape);
            components.put(BuiltInRegistries.ENCHANTMENT_EFFECT_COMPONENT_TYPE.getKey(type).toString(), entry);
        }
        if (components.size() != BuiltInRegistries.ENCHANTMENT_EFFECT_COMPONENT_TYPE.size()) {
            throw new IllegalStateException("Unmapped enchantment component");
        }
        var componentJSON = new JsonObject();
        components.forEach(componentJSON::add);
        result.add("components", componentJSON);

        // These adapters describe effect formats/behavior, not registered IDs. The classes'
        // apply/onChangedBlock methods establish whether they add unsaved attribute modifiers.
        // Mob effects use permanent attribute modifiers, already retained in the entity save.
        var formats = Map.ofEntries(
            Map.entry("AllOf$EntityEffects", "allOf"),
            Map.entry("AllOf$LocationBasedEffects", "allOf"),
            Map.entry("EnchantmentAttributeEffect", "attribute"),
            Map.entry("RunFunction", "unavailable"),
            Map.entry("ApplyMobEffect", "noAttribute"),
            Map.entry("ChangeItemDamage", "noAttribute"),
            Map.entry("DamageEntity", "noAttribute"),
            Map.entry("ExplodeEffect", "noAttribute"),
            Map.entry("Ignite", "noAttribute"),
            Map.entry("ApplyEntityImpulse", "noAttribute"),
            Map.entry("ApplyExhaustion", "noAttribute"),
            Map.entry("PlaySoundEffect", "noAttribute"),
            Map.entry("ReplaceBlock", "noAttribute"),
            Map.entry("ReplaceDisk", "noAttribute"),
            Map.entry("SetBlockProperties", "noAttribute"),
            Map.entry("SpawnParticlesEffect", "noAttribute"),
            Map.entry("SummonEntityEffect", "noAttribute"));
        var effects = new TreeMap<String, JsonObject>();
        for (var entry : new TreeMap<>(formats).entrySet()) {
            var type = Class.forName("net.minecraft.world.item.enchantment.effects." + entry.getKey());
            var codec = type.getField(entry.getKey().equals("EnchantmentAttributeEffect") ? "MAP_CODEC" : "CODEC").get(null);
            for (var registry : java.util.List.of(BuiltInRegistries.ENCHANTMENT_ENTITY_EFFECT_TYPE,
                                                  BuiltInRegistries.ENCHANTMENT_LOCATION_BASED_EFFECT_TYPE)) {
                for (var key : registry.keySet()) {
                    if (registry.getValue(key) != codec) continue;
                    var known = effects.get(key.toString());
                    if (known != null) {
                        if (!known.get("format").getAsString().equals(entry.getValue())) throw new IllegalStateException("Conflicting effect formats");
                        String sources = known.get("source").getAsString();
                        if (!java.util.Arrays.asList(sources.split(", ")).contains(type.getName())) {
                            known.addProperty("source", sources + ", " + type.getName());
                        }
                    } else {
                        var value = new JsonObject();
                        value.addProperty("format", entry.getValue());
                        value.addProperty("source", type.getName());
                        effects.put(key.toString(), value);
                    }
                }
            }
        }
        var allKeys = new java.util.HashSet<>(BuiltInRegistries.ENCHANTMENT_ENTITY_EFFECT_TYPE.keySet());
        allKeys.addAll(BuiltInRegistries.ENCHANTMENT_LOCATION_BASED_EFFECT_TYPE.keySet());
        if (effects.size() != allKeys.size()) throw new IllegalStateException("Unmapped enchantment effect format");
        var effectJSON = new JsonObject();
        effects.forEach(effectJSON::add);
        result.add("effects", effectJSON);
        return result;
    }
}
