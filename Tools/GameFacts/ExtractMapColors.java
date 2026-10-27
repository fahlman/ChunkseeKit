import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import net.minecraft.world.level.material.MapColor;

/** Palette facts and independent packed-byte colors from the game's own methods. */
final class ExtractMapColors {
    static JsonObject extract() {
        var colors = new JsonArray();
        for (int id = 0; id < 64; id++) {
            var color = MapColor.byId(id);
            if (color == MapColor.NONE) {
                colors.add(JsonNull.INSTANCE);
            } else {
                if (color.id != id || (color.col & 0xff000000) != 0) {
                    throw new IllegalStateException("Unsupported map base color: " + id);
                }
                colors.add(color.col);
            }
        }
        int[] modifiers = new int[4];
        boolean[] seen = new boolean[4];
        for (var brightness : MapColor.Brightness.values()) {
            int id = brightness.id;
            if (id < 0 || id >= modifiers.length || seen[id]
                    || brightness.modifier < 0 || brightness.modifier > 255
                    || MapColor.Brightness.byId(id) != brightness) {
                throw new IllegalStateException("Unsupported map brightness: " + brightness);
            }
            modifiers[id] = brightness.modifier;
            seen[id] = true;
        }
        var brightness = new JsonArray();
        for (int id = 0; id < modifiers.length; id++) {
            if (!seen[id]) throw new IllegalStateException("Missing map brightness: " + id);
            brightness.add(modifiers[id]);
        }
        var proofs = new JsonArray();
        for (int id = 0; id <= 255; id++) {
            int actual = MapColor.getColorFromPackedId(id);
            if (actual != MapColor.getColorFromPackedId((byte) id)) {
                throw new IllegalStateException("Map color depends on byte signedness: " + id);
            }
            var color = MapColor.byId(id / 4);
            if (color != MapColor.NONE
                    && Byte.toUnsignedInt(color.getPackedId(MapColor.Brightness.byId(id % 4))) != id) {
                throw new IllegalStateException("Unsupported packed map color: " + id);
            }
            proofs.add(Integer.toUnsignedLong(actual));
        }
        var result = new JsonObject();
        result.add("baseColors", colors);
        result.add("brightness", brightness);
        result.add("argb", proofs);
        return result;
    }
}
