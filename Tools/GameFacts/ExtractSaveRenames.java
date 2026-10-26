import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import com.google.gson.JsonParser;
import com.mojang.datafixers.DSL;
import com.mojang.datafixers.DataFix;
import com.mojang.datafixers.DataFixUtils;
import com.mojang.serialization.Dynamic;
import com.mojang.serialization.JsonOps;
import java.lang.classfile.ClassFile;
import java.lang.classfile.constantpool.StringEntry;
import java.lang.reflect.Modifier;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.function.Function;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.ItemRenameFix;
import net.minecraft.util.datafix.fixes.ItemStackTheFlatteningFix;
import net.minecraft.util.datafix.fixes.BedItemColorFix;
import net.minecraft.util.datafix.fixes.LegacyBlockRenameFix;
import net.minecraft.util.datafix.fixes.NamespacedTypeRenameFix;
import net.minecraft.util.datafix.fixes.References;

/** Only rename facts; numeric flattening and save-layout conversions are separate adapters. */
final class ExtractSaveRenames {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var result = new JsonArray();
        var proofs = new JsonArray();
        var candidates = new TreeSet<String>();
        // Stateless rename lambdas keep their literal inputs in DataFixers' constant pool.
        // Captured strings/maps below supply the other finite equality-lookup inputs.
        try (var stream = DataFixers.class.getResourceAsStream("DataFixers.class")) {
            for (var entry : ClassFile.of().parse(stream.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry string) candidates.add(string.stringValue());
            }
        }
        var fixer = DataFixers.getDataFixer();
        for (var value : (List<?>) field(fixer, "globalList")) {
            var fix = (DataFix) value;
            Function<String, String> rename;
            String kind;
            DSL.TypeReference reference;
            if (fix instanceof LegacyBlockRenameFix) {
                rename = (Function<String, String>) field(fix, "val$renamer");
                kind = "block"; reference = References.BLOCK_NAME;
            } else if (fix instanceof ItemRenameFix) {
                rename = (Function<String, String>) field(fix, "val$fixItem");
                kind = "item"; reference = References.ITEM_NAME;
            } else if (fix instanceof NamespacedTypeRenameFix
                    && field(fix, "type").equals(References.BIOME)) {
                rename = (Function<String, String>) field(fix, "renamer");
                kind = "biome"; reference = References.BIOME;
            } else continue;
            int version = DataFixUtils.getVersion(fix.getVersionKey());
            require(fix.getVersionKey() == DataFixUtils.makeKey(version), "Unexpected rename subversion");
            var inputs = new TreeSet<>(candidates);
            for (var capture : rename.getClass().getDeclaredFields()) {
                if (Modifier.isStatic(capture.getModifiers())) continue;
                capture.setAccessible(true);
                var captured = capture.get(rename);
                if (captured instanceof String string) inputs.add(string);
                else if (captured instanceof Map<?, ?> map) {
                    for (var key : map.keySet()) {
                        require(key instanceof String, "Non-string rename key");
                        inputs.add((String) key);
                    }
                } else throw new IllegalStateException("Unsupported rename capture: " + captured.getClass());
            }
            var changes = new JsonObject();
            for (var before : inputs) {
                // The adapters above rename namespaced resource IDs, never arbitrary saved text.
                if (!before.matches("[a-z0-9_.-]+:[a-z0-9_./-]+")) continue;
                String after = rename.apply(before);
                if (before.equals(after)) continue;
                require(after.matches("[a-z0-9_.-]+:[a-z0-9_./-]+"), "Non-identifier rename result");
                // Run the real fix chain across this boundary as an independent check of the
                // captured function and its applicability. No game world is created or changed.
                var upgraded = fixer.update(reference, new Dynamic<>(JsonOps.INSTANCE, new JsonPrimitive(before)),
                    version - 1, version).asString().result().orElseThrow();
                require(upgraded.equals(after), "Data fixer disagrees at " + version + ": " + before);
                changes.addProperty(before, after);
                // Expected test results come from Minecraft's complete remaining fix chain,
                // not a second implementation of the generated-map composition.
                for (int savedVersion : new int[] {version - 1, version, currentVersion}) {
                    String expected;
                    if (kind.equals("item")) {
                        var stack = new JsonObject(); stack.addProperty("id", before); stack.addProperty("Count", 1);
                        expected = fixer.update(References.ITEM_STACK, new Dynamic<>(JsonOps.INSTANCE, stack),
                            savedVersion, currentVersion).get("id").asString().result().orElseThrow();
                    } else {
                        expected = fixer.update(reference, new Dynamic<>(JsonOps.INSTANCE, new JsonPrimitive(before)),
                            savedVersion, currentVersion).asString().result().orElseThrow();
                    }
                    var proof = new JsonObject();
                    proof.addProperty("kind", kind);
                    proof.addProperty("version", savedVersion);
                    proof.addProperty("input", before);
                    proof.addProperty("expected", expected);
                    proofs.add(proof);
                }
            }
            require(!changes.isEmpty(), "Rename step has no extracted inputs: " + field(fix, "name"));
            require(rename.apply("chunksee:unrelated_identifier").equals("chunksee:unrelated_identifier"),
                "Rename unexpectedly changes an unrelated namespace");
            var row = new JsonObject();
            row.addProperty("kind", kind);
            row.addProperty("version", version);
            row.addProperty("source", fix.getClass().getSuperclass().equals(DataFix.class)
                ? fix.getClass().getName() : fix.getClass().getSuperclass().getName());
            row.addProperty("name", (String) field(fix, "name"));
            row.add("changes", changes);
            result.add(row);
        }
        require(!result.isEmpty(), "No save renames found");
        var entities = ExtractEntityRenames.extract(currentVersion);
        result.addAll(entities.getAsJsonArray("steps"));
        result.asList().sort(java.util.Comparator.comparingInt(row -> row.getAsJsonObject().get("version").getAsInt()));
        proofs.addAll(entities.getAsJsonArray("proofs"));
        var facts = new JsonObject();
        facts.add("steps", result);
        facts.add("proofs", proofs);
        var records = recordProofs(currentVersion);
        records.addAll(ExtractEntityRenames.records(currentVersion));
        facts.add("records", records);
        facts.add("itemNames", legacyItemNames(currentVersion));
        facts.add("itemDamageChanges", legacyDamageChanges());
        facts.add("entityIntroductions", entities.get("introductions"));
        return facts;
    }

    private static JsonArray legacyDamageChanges() throws Exception {
        var fixer = DataFixers.getDataFixer();
        var steps = ((List<?>) field(fixer, "globalList")).stream().filter(fix -> fix instanceof BedItemColorFix).toList();
        require(steps.size() == 1, "Ambiguous historical bed-item fix");
        int key = ((DataFix) steps.getFirst()).getVersionKey();
        int version = DataFixUtils.getVersion(key);
        require(key == DataFixUtils.makeKey(version), "Unexpected item-damage subversion");
        var ids = new TreeSet<String>();
        try (var stream = BedItemColorFix.class.getResourceAsStream("BedItemColorFix.class")) {
            for (var entry : ClassFile.of().parse(stream.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry value && value.stringValue().matches("[a-z0-9_.-]+:[a-z0-9_./-]+")) ids.add(value.stringValue());
            }
        }
        require(ids.size() == 1, "Historical item-damage identity format changed");
        String id = ids.first();
        var changes = new JsonObject();
        for (int damage : new int[] {Integer.MIN_VALUE, -1, 0, 1, 16, Integer.MAX_VALUE}) {
            var stack = new JsonObject(); stack.addProperty("id", id); stack.addProperty("Count", 1); stack.addProperty("Damage", damage);
            var updated = fixer.update(References.ITEM_STACK, new Dynamic<>(JsonOps.INSTANCE, stack), version - 1, version);
            int after = updated.get("Damage").asNumber().result().orElseThrow().intValue();
            if (after != damage) { require(damage == 0, "Historical nonzero variant changed"); changes.addProperty("0", after); }
        }
        require(changes.size() == 1, "Historical default variant unavailable");
        var row = new JsonObject(); row.addProperty("id", id); row.addProperty("version", version);
        row.addProperty("source", "BedItemColorFix.makeRule"); row.add("changes", changes);
        var rows = new JsonArray(); rows.add(row); return rows;
    }

    @SuppressWarnings("unchecked")
    private static JsonObject legacyItemNames(int currentVersion) throws Exception {
        var fixer = DataFixers.getDataFixer();
        var steps = ((List<?>) field(fixer, "globalList")).stream()
            .filter(fix -> fix instanceof ItemStackTheFlatteningFix).toList();
        require(steps.size() == 1, "Ambiguous item-name flattening step");
        int key = ((DataFix) steps.getFirst()).getVersionKey();
        int version = DataFixUtils.getVersion(key);
        // DFU includes sub-version steps when the saved integer version equals their base.
        int boundary = version + (key == DataFixUtils.makeKey(version) ? 0 : 1);
        var mapField = ItemStackTheFlatteningFix.class.getDeclaredField("MAP"); mapField.setAccessible(true);
        var map = (Map<String, String>) mapField.get(null);
        var mappings = new JsonObject();
        var proofs = new JsonArray();
        for (var entry : map.entrySet().stream().sorted(Map.Entry.comparingByKey()).toList()) {
            int split = entry.getKey().lastIndexOf('.');
            String id = entry.getKey().substring(0, split);
            int damage = Integer.parseInt(entry.getKey().substring(split + 1));
            require(entry.getValue().equals(ItemStackTheFlatteningFix.updateItem(id, damage)), "Item mapping disagrees");
            if (!mappings.has(id)) mappings.add(id, new JsonObject());
            mappings.getAsJsonObject(id).addProperty(Integer.toString(damage), entry.getValue());
            for (int savedVersion : new int[] {-1, boundary - 1, boundary}) {
                var stack = new JsonObject(); stack.addProperty("id", id); stack.addProperty("Count", 1); stack.addProperty("Damage", damage);
                var updated = fixer.update(References.ITEM_STACK, new Dynamic<>(JsonOps.INSTANCE, stack), savedVersion, currentVersion);
                var proof = new JsonObject(); proof.addProperty("version", savedVersion); proof.addProperty("input", id);
                proof.addProperty("damage", damage); proof.addProperty("expected", updated.get("id").asString().result().orElseThrow());
                proofs.add(proof);
            }
        }
        for (var id : mappings.keySet()) {
            var values = mappings.getAsJsonObject(id);
            require(values.has("0"), "Missing default item identity");
            for (int absent : new int[] {Integer.MIN_VALUE, -1, Integer.MAX_VALUE}) {
                require(ItemStackTheFlatteningFix.updateItem(id, absent).equals(values.get("0").getAsString()),
                    "Item-name fallback changed");
            }
        }
        var facts = new JsonObject(); facts.addProperty("boundary", boundary);
        facts.addProperty("source", "ItemStackTheFlatteningFix.MAP / updateItem");
        facts.add("mappings", mappings); facts.add("proofs", proofs);
        return facts;
    }

    private static JsonArray recordProofs(int currentVersion) {
        // Historical-format fixtures, not runtime content inventories. Compare selected facts
        // after Minecraft's full upgrades, which also make unrelated layout/field changes.
        String stack = """
            {"id":"minecraft:shulker_box","Count":1,"tag":{"BlockEntityTag":{"Items":[
              {"id":"minecraft:grass","Count":2}, {"id":"minecraft:scute","Count":3}
            ]}}}
            """;
        String inventory = "{\"Inventory\":[" + stack + "],\"EnderItems\":[{\"id\":\"minecraft:grass\",\"Count\":4}]}";
        String entity = """
            {"id":"minecraft:zombie","Pos":[1.0,64.0,2.0],"UUID":[1,2,3,4],
             "CanPickUpLoot":false,"PersistenceRequired":true,"LeftHanded":false,
             "HandItems":[{"id":"minecraft:grass","Count":1},{}],"ArmorItems":[{},{},{},{}]}
            """;
        String chunk = """
            {"xPos":0,"zPos":0,"yPos":-4,"Status":"minecraft:full","sections":[
              {"Y":4,"block_states":{"palette":[{"Name":"minecraft:grass"}]},
               "biomes":{"palette":["minecraft:plains"]}}
             ],"block_entities":[{"id":"minecraft:chest","x":0,"y":64,"z":0,"Items":[
               {"id":"minecraft:grass","Count":2}]}]}
            """;
        var records = new JsonArray();
        for (var entry : Map.of("item", stack, "entity", entity, "player", inventory,
                "chunk", chunk, "level", "{\"LevelName\":\"Upgrade proof\",\"Player\":" + inventory + "}").entrySet().stream().sorted(Map.Entry.comparingByKey()).toList()) {
            var reference = switch (entry.getKey()) {
                case "item" -> References.ITEM_STACK;
                case "entity" -> References.ENTITY;
                case "player" -> References.PLAYER;
                case "chunk" -> References.CHUNK;
                case "level" -> References.LEVEL;
                default -> throw new IllegalStateException();
            };
            int savedVersion = 3691;
            var input = JsonParser.parseString(entry.getValue()).getAsJsonObject();
            input.addProperty("DataVersion", savedVersion);
            if (entry.getKey().equals("level")) input.getAsJsonObject("Player").addProperty("DataVersion", savedVersion);
            var updated = DataFixers.getDataFixer().update(reference, new Dynamic<>(JsonOps.INSTANCE, input),
                savedVersion, currentVersion).getValue();
            if (entry.getKey().equals("level")) {
                // LevelDat.read applies LEVEL first. LevelDatToSavedDataFileFix then passes
                // the embedded player's own DataVersion to PLAYER, not the enclosing level's.
                var player = updated.getAsJsonObject().getAsJsonObject("Player");
                int playerVersion = player.has("DataVersion") ? player.get("DataVersion").getAsInt() : -1;
                updated.getAsJsonObject().add("Player", DataFixers.getDataFixer().update(References.PLAYER,
                    new Dynamic<>(JsonOps.INSTANCE, player), playerVersion, currentVersion).getValue());
            }
            var record = new JsonObject();
            record.addProperty("kind", entry.getKey());
            record.addProperty("version", savedVersion);
            record.add("input", input);
            record.add("output", updated);
            records.add(record);
        }
        return records;
    }

    private static Object field(Object value, String name) throws Exception {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            try {
                var field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(value);
            } catch (NoSuchFieldException inherited) { }
        }
        throw new NoSuchFieldException(value.getClass().getName() + "." + name);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
