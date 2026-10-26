import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.datafixers.DataFix;
import com.mojang.datafixers.DataFixUtils;
import com.mojang.serialization.Dynamic;
import com.mojang.serialization.JsonOps;
import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.TreeMap;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.References;
import net.minecraft.world.entity.animal.panda.Panda;
import net.minecraft.world.item.DyeColor;

/** Code-only game facts. Registry ancestry comes from the existing verification tool. */
public final class ExtractGameFacts {
    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("Expected facts/entity-class paths and current data version");
        ExtractEntityTypes.main(new String[] {args[1]});
        var facts = new JsonObject();
        var dyes = new JsonArray();
        for (var color : DyeColor.values()) {
            var entry = new JsonObject();
            entry.addProperty("id", color.getId());
            entry.addProperty("name", color.getSerializedName());
            entry.addProperty("textureRGB", color.getTextureDiffuseColor() & 0xffffff);
            dyes.add(entry);
        }
        facts.add("dyes", dyes);
        var variants = new JsonObject();
        for (var name : List.of(
                "net.minecraft.world.entity.animal.axolotl.Axolotl$Variant",
                "net.minecraft.world.entity.animal.parrot.Parrot$Variant",
                "net.minecraft.world.entity.animal.equine.Llama$Variant",
                "net.minecraft.world.entity.animal.equine.Variant",
                "net.minecraft.world.entity.animal.equine.Markings")) {
            variants.add(name, enumValues(name, "getId"));
        }
        variants.add("net.minecraft.world.entity.animal.rabbit.Rabbit$Variant",
            enumValues("net.minecraft.world.entity.animal.rabbit.Rabbit$Variant", "id"));
        variants.add("net.minecraft.world.entity.animal.fish.TropicalFish$Pattern",
            enumValues("net.minecraft.world.entity.animal.fish.TropicalFish$Pattern", "getPackedId"));
        facts.add("variants", variants);
        var shapes = new JsonObject();
        for (var shape : Class.forName("net.minecraft.world.entity.animal.fish.TropicalFish$Base").getEnumConstants()) {
            shapes.addProperty(field(shape, "id").toString(), ((Enum<?>) shape).name().toLowerCase(Locale.ROOT));
        }
        facts.add("fishBodyShapes", shapes);
        var genes = new JsonObject();
        for (var gene : Panda.Gene.values()) genes.addProperty(gene.getSerializedName(), gene.isRecessive());
        facts.add("pandaRecessiveGenes", genes);
        facts.addProperty("pandaNormalVariant", Panda.Gene.NORMAL.getSerializedName());
        facts.add("legacyCatTypes", legacyCatTypes(Integer.parseInt(args[2])));
        facts.add("enchantmentEffects", ExtractEnchantmentEffects.extract());
        facts.add("itemModels", ExtractItemModelFacts.extract());
        facts.add("blockDefaults", ExtractBlockDefaults.extract());
        facts.add("blockModelSeeds", ExtractBlockModelSeeds.extract());
        facts.add("blockTints", ExtractBlockTints.extract());
        facts.add("spawnEggs", ExtractSpawnEggs.extract());
        facts.add("equipment", ExtractEquipmentFacts.extract());
        Files.writeString(Path.of(args[0]), new GsonBuilder().setPrettyPrinting().create().toJson(facts) + "\n");
    }

    private static JsonObject enumValues(String name, String idMethod) throws Exception {
        var type = Class.forName(name);
        if (!type.isEnum()) throw new IllegalStateException("Expected enum: " + name);
        var values = new TreeMap<Integer, String>();
        for (var value : type.getEnumConstants()) {
            int id = (int) type.getMethod(idMethod).invoke(value);
            String key;
            try { key = (String) type.getMethod("getSerializedName").invoke(value); }
            catch (NoSuchMethodException symbolicOnly) {
                // Horse markings have code symbols, not serialized names or a data registry.
                if (!name.equals("net.minecraft.world.entity.animal.equine.Markings")) throw symbolicOnly;
                key = ((Enum<?>) value).name().toLowerCase(Locale.ROOT);
            }
            if (values.put(id, key) != null) throw new IllegalStateException("Duplicate enum ID: " + name);
        }
        var result = new JsonObject();
        for (var entry : values.entrySet()) result.addProperty(entry.getKey().toString(), entry.getValue());
        return result;
    }

    private static JsonObject legacyCatTypes(int currentVersion) throws Exception {
        JsonObject result = null;
        // The fixer retains the actual old integer-to-ID map. Inspect its captured map instead
        // of copying names or inferring the old order from today's registry order.
        for (var fix : (List<?>) field(DataFixers.getDataFixer(), "globalList")) {
            if (!fix.getClass().getName().equals("net.minecraft.util.datafix.fixes.EntityVariantFix")
                    || !field(fix, "fieldName").equals("CatType")) continue;
            if (result != null) throw new IllegalStateException("Multiple CatType fixers");
            Object conversion = field(fix, "idConversions");
            for (var captured : conversion.getClass().getDeclaredFields()) {
                captured.setAccessible(true);
                if (!(captured.get(conversion) instanceof Int2ObjectMap<?> map)) continue;
                if (result != null) throw new IllegalStateException("Ambiguous CatType conversion map");
                var ordered = new TreeMap<Integer, String>();
                for (var entry : map.int2ObjectEntrySet()) {
                    if (!(entry.getValue() instanceof String value)) throw new IllegalStateException("Non-string cat ID");
                    ordered.put(entry.getIntKey(), value);
                }
                result = new JsonObject();
                for (var entry : ordered.entrySet()) {
                    var saved = new JsonObject();
                    saved.addProperty("id", (String) field(fix, "entityName"));
                    saved.addProperty("CatType", entry.getKey());
                    // Later fixers can rename an early conversion's ID (for example a breed).
                    // Let the game apply the complete chain rather than copying those aliases.
                    var upgraded = DataFixers.getDataFixer().update(References.ENTITY,
                        new Dynamic<>(JsonOps.INSTANCE, saved),
                        DataFixUtils.getVersion(((DataFix) fix).getVersionKey()) - 1, currentVersion);
                    String identifier = upgraded.get("variant").asString().result().orElseThrow();
                    result.addProperty(entry.getKey().toString(), identifier);
                }
            }
        }
        if (result == null || result.size() == 0) throw new IllegalStateException("CatType mapping unavailable");
        return result;
    }

    private static Object field(Object object, String name) throws Exception {
        for (Class<?> type = object.getClass(); type != null; type = type.getSuperclass()) {
            try {
                Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(object);
            } catch (NoSuchFieldException inherited) { }
        }
        throw new NoSuchFieldException(object.getClass().getName() + "." + name);
    }
}
