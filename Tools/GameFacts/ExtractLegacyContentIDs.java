import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.datafixers.DataFix;
import com.mojang.datafixers.DataFixUtils;
import com.mojang.serialization.Dynamic;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import net.minecraft.nbt.*;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.BannerPatternFormatFix;
import net.minecraft.util.datafix.fixes.MobEffectIdFix;
import net.minecraft.util.datafix.fixes.References;

/** Historical identities come from the fixers, never today's registry order. */
final class ExtractLegacyContentIDs {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var effects = new TreeMap<>((Map<Integer, String>) field(MobEffectIdFix.class, "ID_MAP"));
        var patterns = new TreeMap<>((Map<String, String>) field(BannerPatternFormatFix.class, "PATTERN_ID_MAP"));
        if (effects.isEmpty() || effects.firstKey() < 0 || effects.lastKey() > 65535 || patterns.isEmpty()) {
            throw new IllegalStateException("Unsupported legacy content ID maps");
        }
        int effectsBefore = previousVersion(MobEffectIdFix.class);
        int patternsBefore = previousVersion(BannerPatternFormatFix.class);
        var effectMap = new JsonObject();
        var patternMap = new JsonObject();
        var effectProofs = new JsonArray();
        var patternProofs = new JsonArray();
        for (var entry : effects.entrySet()) {
            effectMap.addProperty(entry.getKey().toString(), entry.getValue());
            var proof = effectProof(".int(" + entry.getKey() + ")", IntTag.valueOf(entry.getKey()),
                effectsBefore, currentVersion);
            if (!proof.get("id").getAsString().equals(entry.getValue())) {
                throw new IllegalStateException("Effect identity changed after its numeric fixer");
            }
            effectProofs.add(proof);
        }
        for (var sample : List.of(
                new NumericInput(".byte(-1)", ByteTag.valueOf((byte) -1)),
                new NumericInput(".byte(1)", ByteTag.valueOf((byte) 1)),
                new NumericInput(".short(2)", ShortTag.valueOf((short) 2)),
                new NumericInput(".int(0)", IntTag.valueOf(0)),
                new NumericInput(".int(" + (effects.lastKey() + 1) + ")", IntTag.valueOf(effects.lastKey() + 1)),
                new NumericInput(".int(.min)", IntTag.valueOf(Integer.MIN_VALUE)),
                new NumericInput(".int(.max)", IntTag.valueOf(Integer.MAX_VALUE)),
                new NumericInput(".long(4294967297)", LongTag.valueOf(4294967297L)),
                new NumericInput(".long(.min)", LongTag.valueOf(Long.MIN_VALUE)),
                new NumericInput(".long(.max)", LongTag.valueOf(Long.MAX_VALUE)),
                new NumericInput(".float(1.75)", FloatTag.valueOf(1.75f)),
                new NumericInput(".double(2.75)", DoubleTag.valueOf(2.75)),
                new NumericInput(".double(-0.75)", DoubleTag.valueOf(-0.75)),
                new NumericInput(".float(-1.75)", FloatTag.valueOf(-1.75f)),
                new NumericInput(".double(2147483648)", DoubleTag.valueOf(2147483648.0)),
                new NumericInput(".double(-2147483649)", DoubleTag.valueOf(-2147483649.0)),
                new NumericInput(".float(.nan)", FloatTag.valueOf(Float.NaN)),
                new NumericInput(".double(.nan)", DoubleTag.valueOf(Double.NaN)),
                new NumericInput(".float(.infinity)", FloatTag.valueOf(Float.POSITIVE_INFINITY)),
                new NumericInput(".double(-.infinity)", DoubleTag.valueOf(Double.NEGATIVE_INFINITY)),
                new NumericInput(".string(\"1\")", StringTag.valueOf("1")),
                new NumericInput(".compound([:])", new CompoundTag()),
                new NumericInput(".list([])", new ListTag()),
                new NumericInput(".intArray([1])", new IntArrayTag(new int[] {1})))) {
            effectProofs.add(effectProof(sample.swift(), sample.tag(), effectsBefore, currentVersion));
        }
        patterns.forEach(patternMap::addProperty);
        var inputs = new TreeSet<>(patterns.keySet());
        inputs.addAll(List.of("pack:custom", "unmapped_short", "minecraft:flower"));
        for (String input : inputs) {
            var layer = new CompoundTag(); layer.putString("Pattern", input); layer.putInt("Color", 14);
            var layers = new ListTag(); layers.add(layer);
            var banner = new CompoundTag(); banner.putString("id", "minecraft:banner"); banner.put("Patterns", layers);
            var output = DataFixers.getDataFixer().update(References.BLOCK_ENTITY,
                new Dynamic<>(NbtOps.INSTANCE, banner), patternsBefore, currentVersion);
            String actual = output.get("patterns").asStream().findFirst()
                .flatMap(value -> value.get("pattern").asString().result()).orElseThrow();
            if (!actual.equals(patterns.getOrDefault(input, input))) {
                throw new IllegalStateException("Banner identity changed after its short-ID fixer");
            }
            var proof = new JsonObject(); proof.addProperty("before", input); proof.addProperty("id", actual);
            proof.addProperty("inputNBT", banner.toString()); proof.addProperty("outputNBT", output.getValue().toString());
            patternProofs.add(proof);
        }
        var result = new JsonObject(); result.add("effects", effectMap); result.add("patterns", patternMap);
        result.addProperty("effectsBefore", effectsBefore); result.addProperty("patternsBefore", patternsBefore);
        result.add("effectProofs", effectProofs); result.add("patternProofs", patternProofs);
        return result;
    }

    private record NumericInput(String swift, Tag tag) { }

    private static JsonObject effectProof(String swift, Tag tag, int before, int currentVersion) {
        var effect = new CompoundTag(); effect.put("Id", tag); effect.putInt("Amplifier", 2); effect.putInt("Duration", 200);
        var effects = new ListTag(); effects.add(effect);
        var player = new CompoundTag(); player.put("ActiveEffects", effects);
        var output = DataFixers.getDataFixer().update(References.PLAYER,
            new Dynamic<>(NbtOps.INSTANCE, player), before, currentVersion);
        String id = output.get("active_effects").asStream().findFirst()
            .flatMap(value -> value.get("id").asString().result()).orElse(null);
        var proof = new JsonObject(); proof.addProperty("tag", swift); proof.addProperty("id", id);
        proof.addProperty("inputNBT", player.toString()); proof.addProperty("outputNBT", output.getValue().toString());
        return proof;
    }

    private static Object field(Class<?> type, String name) throws Exception {
        var field = type.getDeclaredField(name); field.setAccessible(true); return field.get(null);
    }

    private static int previousVersion(Class<? extends DataFix> type) throws Exception {
        var fixer = DataFixers.getDataFixer();
        var field = fixer.getClass().getDeclaredField("globalList"); field.setAccessible(true);
        var fixes = ((List<?>) field.get(fixer)).stream().filter(type::isInstance).toList();
        if (fixes.size() != 1) throw new IllegalStateException("Ambiguous legacy content fixer: " + type);
        int key = ((DataFix) fixes.getFirst()).getVersionKey();
        int version = DataFixUtils.getVersion(key);
        // A whole version earlier also precedes fixes registered at a subversion.
        // These values choose proof inputs only; the runtime uses the saved field format.
        return version - 1;
    }
}
