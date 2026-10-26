import com.google.gson.*;
import com.mojang.datafixers.*;
import com.mojang.serialization.*;
import java.lang.classfile.ClassFile;
import java.lang.classfile.constantpool.StringEntry;
import java.lang.reflect.Modifier;
import java.util.*;
import java.util.function.Function;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.*;
import net.minecraft.util.datafix.schemas.NamespacedSchema;

/** Saved attribute/enchantment identity rewrites, independent of registry membership. */
final class ExtractEffectRenames {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var attributes = new JsonArray(); var enchantments = new JsonArray(); var records = new JsonArray();
        for (Object value : (List<?>) field(DataFixers.getDataFixer(), "globalList")) {
            var fix = (DataFix) value;
            boolean legacy = fix instanceof AttributesRenameLegacy;
            boolean attribute = legacy || fix instanceof AttributesRenameFix;
            if (!attribute && !(fix instanceof RenameEnchantmentsFix)) continue;
            int version = DataFixUtils.getVersion(fix.getVersionKey());
            require(fix.getVersionKey() == DataFixUtils.makeKey(version), "Unexpected effect rename subversion");
            var row = new JsonObject(); row.addProperty("version", version);
            row.addProperty("source", fix.getClass().getName()); row.addProperty("name", (String) field(fix, "name"));
            var changes = new JsonObject(); var prefixes = new JsonArray(); var inputs = new TreeSet<String>();
            if (attribute) {
                var rename = (Function<String, String>) field(fix, "renames");
                if (fix instanceof AttributeIdPrefixFix) {
                    for (String prefix : (List<String>) field(fix, "PREFIXES")) {
                        String before = NamespacedSchema.ensureNamespaced(prefix), suffix = "chunksee_probe";
                        String after = rename.apply(before + suffix);
                        require(after.endsWith(suffix) && !after.equals(before + suffix), "Attribute prefix format changed");
                        var pair = new JsonObject(); pair.addProperty("from", before);
                        pair.addProperty("to", after.substring(0, after.length() - suffix.length())); prefixes.add(pair);
                        for (String name : List.of(before + suffix, prefix + suffix, ":" + prefix + suffix,
                                "example:" + prefix + suffix, before + "max_health", before + "nameplate_distance")) inputs.add(name);
                    }
                } else {
                    inputs.addAll(constants(DataFixers.class)); inputs.addAll(constants(fix.getClass()));
                    for (var capture : rename.getClass().getDeclaredFields()) {
                        if (Modifier.isStatic(capture.getModifiers())) continue;
                        capture.setAccessible(true); Object captured = capture.get(rename);
                        if (captured instanceof String name) inputs.add(name);
                        else if (captured instanceof Map<?, ?> map) for (Object key : map.keySet()) inputs.add((String) key);
                        else throw new IllegalStateException("Unsupported attribute rename capture " + captured.getClass());
                    }
                    for (String name : new ArrayList<>(inputs)) {
                        if (name.startsWith("minecraft:")) {
                            inputs.add(name.substring("minecraft:".length()));
                            inputs.add(name.substring("minecraft".length()));
                        }
                    }
                    for (String before : inputs) {
                        String after = rename.apply(before);
                        if (!before.equals(after)) changes.addProperty(before, after);
                    }
                    require(!changes.isEmpty(), "No attribute aliases extracted");
                    inputs = new TreeSet<>(changes.keySet());
                    for (String name : List.of("example:unchanged", "unchanged", "Invalid Name")) {
                        require(rename.apply(name).equals(name), "Unbounded attribute rename requires an adapter");
                    }
                }
                for (String input : inputs) {
                    for (int saved : new int[] {version - 1, version, currentVersion}) {
                        var player = new JsonObject(); var values = new JsonArray(); var item = new JsonObject();
                        item.addProperty(legacy ? "Name" : "id", input); item.addProperty(legacy ? "Base" : "base", 9.5);
                        values.add(item); player.add(legacy ? "Attributes" : "attributes", values);
                        records.add(record("attributePlayer", References.PLAYER, player, saved, currentVersion));
                        records.add(record("attributeItem", References.ITEM_STACK,
                            attributeItem(input, legacy, !legacy && (boolean) field(fix, "oldDataComponentFormat")), saved, currentVersion));
                    }
                }
                row.add("prefixes", prefixes); row.add("changes", changes); attributes.add(row);
            } else {
                var map = (Map<String, String>) field(fix, "renames");
                for (var entry : map.entrySet().stream().sorted(Map.Entry.comparingByKey()).toList()) {
                    changes.addProperty(entry.getKey(), entry.getValue());
                    inputs.add(entry.getKey());
                    if (entry.getKey().startsWith("minecraft:")) inputs.add(entry.getKey().substring("minecraft:".length()));
                }
                require(!changes.isEmpty(), "No enchantment aliases extracted");
                for (String input : inputs) {
                    for (int saved : new int[] {version - 1, version, currentVersion}) {
                        for (String listName : List.of("Enchantments", "StoredEnchantments")) {
                            var stack = new JsonObject(); stack.addProperty("id", "minecraft:enchanted_book"); stack.addProperty("Count", 1);
                            var tag = new JsonObject(); var list = new JsonArray(); var enchant = new JsonObject();
                            enchant.addProperty("id", input); enchant.addProperty("lvl", 2); list.add(enchant);
                            tag.add(listName, list); stack.add("tag", tag);
                            records.add(record("enchantmentItem", References.ITEM_STACK, stack, saved, currentVersion));
                        }
                    }
                }
                row.addProperty("kind", "enchantment"); row.add("changes", changes); enchantments.add(row);
            }
        }
        var result = new JsonObject(); result.add("attributes", attributes); result.add("enchantments", enchantments);
        result.add("records", records); return result;
    }

    private static JsonObject attributeItem(String name, boolean legacy, boolean wrapped) {
        var item = new JsonObject(); item.addProperty("id", "minecraft:stick"); item.addProperty(legacy ? "Count" : "count", 1);
        var modifier = new JsonObject(); modifier.addProperty(legacy ? "AttributeName" : "type", name);
        modifier.addProperty(legacy ? "Amount" : "amount", 0.5); modifier.addProperty(legacy ? "Slot" : "slot", "head");
        var list = new JsonArray(); list.add(modifier); var fields = new JsonObject();
        if (legacy) {
            modifier.addProperty("Name", "Chunksee proof"); modifier.addProperty("Operation", 0);
            modifier.add("UUID", JsonParser.parseString("[1,2,3,4]"));
            fields.add("AttributeModifiers", list); item.add("tag", fields);
        } else {
            modifier.addProperty("id", "example:proof"); modifier.addProperty("operation", "add_value");
            if (wrapped) { var wrapper = new JsonObject(); wrapper.add("modifiers", list); fields.add("minecraft:attribute_modifiers", wrapper); }
            else fields.add("minecraft:attribute_modifiers", list);
            item.add("components", fields);
        }
        return item;
    }

    private static JsonObject record(String kind, DSL.TypeReference reference, JsonObject input, int version, int currentVersion) {
        input.addProperty("DataVersion", version);
        var output = DataFixers.getDataFixer().update(reference, new Dynamic<>(JsonOps.INSTANCE, input), version, currentVersion).getValue();
        var record = new JsonObject(); record.addProperty("kind", kind); record.addProperty("version", version);
        record.add("input", input); record.add("output", output); return record;
    }

    private static Set<String> constants(Class<?> type) throws Exception {
        var result = new TreeSet<String>();
        try (var stream = type.getResourceAsStream(type.getSimpleName() + ".class")) {
            for (var entry : ClassFile.of().parse(stream.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry string) result.add(string.stringValue());
            }
        }
        return result;
    }

    private static Object field(Object value, String name) throws Exception {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            try { var field = type.getDeclaredField(name); field.setAccessible(true); return field.get(value); }
            catch (NoSuchFieldException inherited) { }
        }
        throw new IllegalStateException("Missing game field " + name);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
