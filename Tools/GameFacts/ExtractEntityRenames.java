import com.google.gson.*;
import com.mojang.datafixers.*;
import com.mojang.serialization.*;
import java.util.*;
import java.util.function.Function;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.*;

/** Namespaced record identities only. Earlier type splits belong with the old entity formats. */
final class ExtractEntityRenames {
    @SuppressWarnings("unchecked")
    static JsonObject extract(int currentVersion) throws Exception {
        var fixer = DataFixers.getDataFixer();
        var schemaVersions = new TreeSet<Integer>();
        schemaVersions.add(-1);
        for (Object value : ((Map<?, ?>) field(fixer, "schemas")).keySet()) {
            int key = (Integer) value, version = DataFixUtils.getVersion(key);
            schemaVersions.add(version + (key == DataFixUtils.makeKey(version) ? 0 : 1));
        }
        var steps = new JsonArray();
        var proofs = new JsonArray();
        var introductions = new JsonObject();
        introductions.add("entity", new JsonObject());
        introductions.add("blockEntity", new JsonObject());
        var renameMethod = SimplestEntityRenameFix.class.getDeclaredMethod("rename", String.class);
        renameMethod.setAccessible(true);
        for (Object value : (List<?>) field(fixer, "globalList")) {
            var fix = (DataFix) value;
            boolean entity = fix instanceof SimplestEntityRenameFix;
            if (!entity && !(fix instanceof BlockEntityRenameFix)) continue;
            String kind = entity ? "entity" : "blockEntity";
            var reference = entity ? References.ENTITY : References.BLOCK_ENTITY;
            int version = DataFixUtils.getVersion(fix.getVersionKey());
            require(fix.getVersionKey() == DataFixUtils.makeKey(version), "Unexpected entity rename subversion");
            var schema = fixer.getSchema(DataFixUtils.makeKey(version - 1));
            var changes = new JsonObject();
            for (Object key : new TreeSet<>(schema.findChoiceType(reference).types().keySet())) {
                String before = key.toString();
                if (!before.matches("[a-z0-9_.-]+:[a-z0-9_./-]+")) continue;
                String after = entity ? (String) renameMethod.invoke(fix, before)
                    : ((Function<String, String>) field(fix, "nameChangeLookup")).apply(before);
                if (before.equals(after)) continue;
                require(after.matches("[a-z0-9_.-]+:[a-z0-9_./-]+"), "Malformed entity rename result");
                var input = new JsonObject(); input.addProperty("id", before);
                String boundaryResult = fixer.update(reference, new Dynamic<>(JsonOps.INSTANCE, input),
                    version - 1, version).get("id").asString().result().orElseThrow();
                require(after.equals(boundaryResult), "Entity rename disagrees at " + version + ": " + before);
                int introduced = schemaVersions.stream().filter(saved -> saved < version
                    && fixer.getSchema(DataFixUtils.makeKey(saved)).findChoiceType(reference).types().containsKey(before))
                    .findFirst().orElseThrow();
                introductions.getAsJsonObject(kind).addProperty(before, introduced);
                changes.addProperty(before, after);
                // Check every schema interval, not just the rename boundary. An ID unknown to
                // the input schema is left untouched by DFU; that is rename applicability,
                // never a record-admission list in the reader.
                var versions = new TreeSet<>(schemaVersions);
                versions.add(version - 1); versions.add(currentVersion); versions.add(introduced - 1);
                for (int saved : versions) {
                    if (saved > currentVersion) continue;
                    String expected = fixer.update(reference, new Dynamic<>(JsonOps.INSTANCE, input), saved, currentVersion)
                        .get("id").asString().result().orElseThrow();
                    var proof = new JsonObject(); proof.addProperty("kind", kind);
                    proof.addProperty("version", saved); proof.addProperty("input", before);
                    proof.addProperty("expected", expected); proofs.add(proof);
                }
            }
            // The pre-namespace TippedArrow rule is part of the later old-entity-format slice.
            if (changes.isEmpty()) {
                require(fix instanceof EntityTippedArrowFix, "Entity rename has no extracted changes: " + fix.getClass());
                continue;
            }
            var step = new JsonObject(); step.addProperty("kind", kind); step.addProperty("version", version);
            step.addProperty("source", fix.getClass().getName()); step.addProperty("name", (String) field(fix, "name"));
            step.add("changes", changes); steps.add(step);
        }
        require(!steps.isEmpty(), "No entity rename steps");
        var result = new JsonObject(); result.add("steps", steps); result.add("proofs", proofs);
        result.add("introductions", introductions);
        return result;
    }

    private static Object field(Object value, String name) throws Exception {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            try { var field = type.getDeclaredField(name); field.setAccessible(true); return field.get(value); }
            catch (NoSuchFieldException inherited) { }
        }
        throw new IllegalStateException("Missing game field " + name);
    }

    static JsonArray records(int currentVersion) {
        String mob = """
            {"id":"minecraft:zombie_pigman","Pos":[1.0,64.0,2.0],"UUID":[1,2,3,4],
             "CanPickUpLoot":false,"PersistenceRequired":true,"LeftHanded":false}
            """;
        String passenger = mob.replace("[1,2,3,4]", "[5,6,7,8]");
        var parent = JsonParser.parseString(mob).getAsJsonObject();
        var passengers = new JsonArray(); passengers.add(JsonParser.parseString(passenger));
        parent.add("Passengers", passengers);
        String spawner = """
            {"id":"minecraft:mob_spawner","x":0,"y":64,"z":0,"SpawnData":{"id":"minecraft:zombie_pigman"},
             "SpawnPotentials":[{"Entity":{"id":"minecraft:zombie_pigman"},"Weight":1}]}
            """;
        String item = """
            {"id":"minecraft:pig_spawn_egg","Count":1,"tag":{"EntityTag":{"id":"minecraft:zombie_pigman"}}}
            """;
        var records = new JsonArray();
        var inputs = Map.of("entityNames", parent.toString(), "entityItem", item,
            "entityPlayer", "{\"ShoulderEntityLeft\":" + mob + ",\"RootVehicle\":{\"Entity\":" + parent + "}}",
            "spawnerNames", spawner,
            "beehiveNames", "{\"id\":\"minecraft:beehive\",\"x\":0,\"y\":64,\"z\":0,\"Bees\":[{\"EntityData\":" + mob + "}]}",
            "blockEntityNames", "{\"id\":\"minecraft:suspicious_sand\",\"x\":0,\"y\":64,\"z\":0,\"LootTable\":\"example:loot\"}");
        for (var entry : inputs.entrySet().stream().sorted(Map.Entry.comparingByKey()).toList()) {
            var reference = switch (entry.getKey()) {
                case "entityNames" -> References.ENTITY_TREE;
                case "entityPlayer" -> References.PLAYER;
                case "entityItem" -> References.ITEM_STACK;
                default -> References.BLOCK_ENTITY;
            };
            int version = entry.getKey().equals("blockEntityNames") ? 3437 : 2508;
            var input = JsonParser.parseString(entry.getValue()).getAsJsonObject();
            input.addProperty("DataVersion", version);
            var output = DataFixers.getDataFixer().update(reference, new Dynamic<>(JsonOps.INSTANCE, input),
                version, currentVersion).getValue();
            var record = new JsonObject(); record.addProperty("kind", entry.getKey()); record.addProperty("version", version);
            record.add("input", input); record.add("output", output); records.add(record);
        }
        return records;
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
