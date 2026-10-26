import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.lang.reflect.Field;
import java.util.Map;
import net.minecraft.client.color.ColorLerper;
import net.minecraft.client.model.geom.EntityModelSet;
import net.minecraft.client.model.geom.LayerDefinitions;
import net.minecraft.client.renderer.entity.AxolotlRenderer;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.state.AxolotlRenderState;
import net.minecraft.client.renderer.entity.state.SheepRenderState;
import net.minecraft.resources.Identifier;
import net.minecraft.world.entity.animal.axolotl.Axolotl;
import net.minecraft.world.entity.animal.sheep.Sheep;
import net.minecraft.world.item.DyeColor;

/** Saved-color sources, checked through the actual render-state/texture selection methods. */
final class ExtractCreatureColors {
    static JsonArray extract() throws Exception {
        var result = new JsonArray();
        var colors = new JsonObject();
        var colorProofs = new JsonObject();
        for (var dye : DyeColor.values()) {
            String key = "minecraft:" + dye.getSerializedName();
            int rgb = ColorLerper.Type.SHEEP.getColor(dye) & 0xffffff;
            colors.addProperty(key, rgb);
            var state = new SheepRenderState();
            state.woolColor = dye;
            state.isJebSheep = false; // A saved dye, not a live color-animation frame.
            int actual = state.getWoolColor() & 0xffffff;
            if (actual != rgb) throw new IllegalStateException("Sheep renderer color differs: " + key);
            colorProofs.addProperty(key, actual);
        }
        result.add(entry(Sheep.class.getName(), "tint", colors, colorProofs));

        // The model set supplies real vanilla geometry. No world, client, window or GPU is created;
        // services unused by construction and getTextureLocation remain absent.
        var models = new EntityModelSet(LayerDefinitions.createRoots());
        var context = new EntityRendererProvider.Context(null, null, null, null, null, models, null, null, null, null, null);
        var renderer = new AxolotlRenderer(context);
        var byType = (Map<?, ?>) field(AxolotlRenderer.class, "TEXTURE_BY_TYPE");
        if (byType.size() != Axolotl.Variant.values().length) throw new IllegalStateException("Incomplete axolotl textures");
        var textures = new JsonObject();
        var textureProofs = new JsonObject();
        for (var variant : Axolotl.Variant.values()) {
            String key = "minecraft:" + variant.getSerializedName();
            var texture = (Identifier) field(byType.get(variant), "adult");
            textures.addProperty(key, textureID(texture));
            var state = new AxolotlRenderState();
            state.variant = variant;
            state.isBaby = false;
            var actual = renderer.getTextureLocation(state);
            if (!actual.equals(texture)) throw new IllegalStateException("Axolotl renderer texture differs: " + key);
            textureProofs.addProperty(key, textureID(actual));
        }
        result.add(entry(Axolotl.class.getName(), "texture", textures, textureProofs));
        return result;
    }

    private static JsonObject entry(String entityClass, String kind, JsonObject values, JsonObject proofs) {
        var result = new JsonObject();
        result.addProperty("entityClass", entityClass);
        result.addProperty("kind", kind);
        result.add("values", values);
        result.add("proofs", proofs);
        return result;
    }

    private static String textureID(Identifier texture) {
        String path = texture.getPath();
        if (!path.startsWith("textures/") || !path.endsWith(".png")) throw new IllegalStateException("Unexpected texture: " + texture);
        return texture.getNamespace() + ":" + path.substring("textures/".length(), path.length() - ".png".length());
    }

    private static Object field(Object object, String name) throws ReflectiveOperationException {
        Class<?> type = object instanceof Class<?> c ? c : object.getClass();
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(object instanceof Class<?> ? null : object);
    }
}
