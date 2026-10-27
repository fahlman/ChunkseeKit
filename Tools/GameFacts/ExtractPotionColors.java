import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.TreeMap;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.effect.MobEffect;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.item.alchemy.Potion;
import net.minecraft.world.item.alchemy.PotionContents;

/** Built-in color/ingredient defaults, independently checked through PotionContents.getColorOr. */
final class ExtractPotionColors {
    private static final int PROOF_DEFAULT_COLOR = 0x385dc6;

    static JsonObject extract() {
        var effects = new TreeMap<String, MobEffect>();
        for (var effect : BuiltInRegistries.MOB_EFFECT) {
            effects.put(BuiltInRegistries.MOB_EFFECT.getKey(effect).toString(), effect);
        }
        var potions = new TreeMap<String, Potion>();
        for (var potion : BuiltInRegistries.POTION) {
            potions.put(BuiltInRegistries.POTION.getKey(potion).toString(), potion);
        }
        if (effects.size() < 2 || potions.isEmpty()) throw new IllegalStateException("No potion color facts");
        var colors = new JsonObject();
        effects.forEach((id, effect) -> colors.addProperty(id, effect.getColor() & 0xffffff));
        var recipes = new JsonObject();
        var proofs = new JsonArray();
        var first = effects.firstEntry().getValue();
        potions.forEach((id, potion) -> {
            var ingredients = new JsonArray();
            for (var effect : potion.getEffects()) {
                // PotionContents.getColorOptional ignores invisible ingredients completely.
                if (!effect.isVisible()) continue;
                if (effect.getAmplifier() < 0 || effect.getAmplifier() > 255) {
                    throw new IllegalStateException("Unsupported potion amplifier: " + id);
                }
                var ingredient = new JsonObject();
                ingredient.addProperty("id", BuiltInRegistries.MOB_EFFECT.getKey(effect.getEffect().value()).toString());
                ingredient.addProperty("amplifier", effect.getAmplifier());
                ingredients.add(ingredient);
            }
            if (ingredients.size() > 4096) throw new IllegalStateException("Potion exceeds reader effect budget: " + id);
            recipes.add(id, ingredients);
            proofs.add(proof(id, potion, List.of()));
            proofs.add(proof(id, potion, List.of(instance(first, 1, true))));
        });
        var ordered = new ArrayList<>(effects.values());
        for (int index = 0; index < ordered.size(); index++) {
            var effect = ordered.get(index);
            var next = ordered.get((index + 1) % ordered.size());
            proofs.add(proof(null, null, List.of(instance(effect, 0, true))));
            proofs.add(proof(null, null, List.of(instance(effect, 1, true), instance(next, 3, true))));
            proofs.add(proof(null, null, List.of(instance(effect, 255, false), instance(next, 0, true))));
        }
        var result = new JsonObject();
        result.add("effects", colors);
        result.add("recipes", recipes);
        result.addProperty("proofDefaultColor", PROOF_DEFAULT_COLOR);
        result.add("proofs", proofs);
        return result;
    }

    private static MobEffectInstance instance(MobEffect effect, int amplifier, boolean visible) {
        return new MobEffectInstance(Holder.direct(effect), 0, amplifier, false, visible);
    }

    private static JsonObject proof(String id, Potion potion, List<MobEffectInstance> effects) {
        var contents = new PotionContents(Optional.ofNullable(potion).map(Holder::direct),
            Optional.empty(), effects, Optional.empty());
        var result = new JsonObject();
        result.addProperty("potion", id);
        var custom = new JsonArray();
        for (var effect : effects) {
            var input = new JsonObject();
            input.addProperty("id", BuiltInRegistries.MOB_EFFECT.getKey(effect.getEffect().value()).toString());
            input.addProperty("amplifier", effect.getAmplifier());
            input.addProperty("visible", effect.isVisible());
            custom.add(input);
        }
        result.add("effects", custom);
        result.addProperty("color", contents.getColorOr(PROOF_DEFAULT_COLOR) & 0xffffff);
        return result;
    }
}
