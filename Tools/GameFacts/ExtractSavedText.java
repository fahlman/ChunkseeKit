import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.datafixers.DSL;
import com.mojang.datafixers.DataFix;
import com.mojang.datafixers.DataFixUtils;
import com.mojang.serialization.Dynamic;
import com.mojang.serialization.JsonOps;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.lang.classfile.ClassFile;
import java.lang.classfile.Instruction;
import java.lang.classfile.constantpool.StringEntry;
import java.lang.classfile.instruction.ConstantInstruction;
import java.lang.classfile.instruction.InvokeInstruction;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtIo;
import net.minecraft.nbt.NbtOps;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.util.datafix.DataFixers;
import net.minecraft.util.datafix.fixes.References;
import net.minecraft.util.datafix.fixes.UnflattenTextComponentFix;
import net.minecraft.util.datafix.fixes.EntityCustomNameToComponentFix;
import net.minecraft.util.datafix.fixes.BlockEntityCustomNameToComponentFix;
import net.minecraft.util.datafix.fixes.ItemCustomNameToComponentFix;
import net.minecraft.util.datafix.fixes.ItemLoreFix;
import net.minecraft.util.datafix.fixes.SignTextStrictJsonFix;
import net.minecraft.util.datafix.fixes.WrittenBookPagesStrictJsonFix;
import net.minecraft.util.datafix.fixes.BlockPosFormatAndRenamesFix;
import net.minecraft.world.level.storage.SavedDataStorage;

/** Saved-text format boundaries and actual native-NBT fixer outputs, never game content. */
final class ExtractSavedText {
    static JsonObject extract(int currentVersion) throws Exception {
        int boundary = boundary(UnflattenTextComponentFix.class);
        var facts = new JsonObject();
        facts.addProperty("source", "UnflattenTextComponentFix.makeRule / unflattenJson");
        facts.addProperty("boundary", boundary);
        int savedDataDefaultVersion = savedDataDefaultVersion();
        facts.addProperty("savedDataDefaultVersion", savedDataDefaultVersion);
        var encodings = new JsonObject();
        for (var entry : List.of(
                new Encoding("entityName", EntityCustomNameToComponentFix.class),
                new Encoding("blockEntityName", BlockEntityCustomNameToComponentFix.class),
                new Encoding("itemName", ItemCustomNameToComponentFix.class),
                new Encoding("lore", ItemLoreFix.class),
                new Encoding("sign", SignTextStrictJsonFix.class),
                new Encoding("book", WrittenBookPagesStrictJsonFix.class),
                new Encoding("mapBannerFields", BlockPosFormatAndRenamesFix.class))) {
            var row = new JsonObject();
            row.addProperty("source", entry.type().getSimpleName());
            row.addProperty("boundary", boundary(entry.type()));
            encodings.add(entry.name(), row);
        }
        facts.add("encodings", encodings);
        var entities = new JsonArray();
        var entityFix = EntityCustomNameToComponentFix.class.getDeclaredMethod(
            "fixCustomName", com.mojang.serialization.DynamicOps.class, String.class, String.class);
        entityFix.setAccessible(true);
        for (var id : identifiers(EntityCustomNameToComponentFix.class)) {
            String probe = "\"saved text\"";
            var output = (Dynamic<?>) entityFix.invoke(null, NbtOps.INSTANCE, probe, id);
            if (output.asString().result().orElseThrow().equals(probe)) entities.add(id);
            else throw new IllegalStateException("Unclassified custom-name exception: " + id);
        }
        if (entities.isEmpty()) throw new IllegalStateException("Entity name exception code changed");
        facts.add("jsonEntityNames", entities);
        var nameable = BlockEntityCustomNameToComponentFix.class.getDeclaredField("NAMEABLE_BLOCK_ENTITIES");
        nameable.setAccessible(true);
        if (!(nameable.get(null) instanceof Set<?> savedNames)) throw new IllegalStateException("Nameable field is not a set");
        var names = new TreeSet<String>();
        for (var raw : savedNames) {
            if (!(raw instanceof String id) || !id.matches("[a-z0-9_.-]+:[a-z0-9_./-]+")) {
                throw new IllegalStateException("Invalid historical name format identity");
            }
            names.add(id);
        }
        var blockEntities = new JsonArray();
        for (var id : names) blockEntities.add(id);
        if (blockEntities.isEmpty()) throw new IllegalStateException("Historical block-entity name formats unavailable");
        facts.add("plainBlockEntityNames", blockEntities);
        var books = identifiers(WrittenBookPagesStrictJsonFix.class);
        if (books.size() != 1) throw new IllegalStateException("Written-book format identity changed");
        facts.addProperty("writtenBookID", books.first());
        var samples = new JsonArray();
        for (var input : List.of(
                "\"Sword\"", "[1]", "{}", "true", "1", "null", "{broken",
                "{\"text\":\"[1]\",\"extra\":[\"\\\"Sword\\\"\",{\"text\":\"{}\"}]}",
                "{\"translate\":\"test.number\",\"with\":[9007199254740993]}",
                "{\"translate\":\"test.number\",\"with\":[1,128,32768,2147483648,1.5,0.1,1e100]}",
                "{\"translate\":\"test.arguments\",\"with\":[true,false]}",
                "{\"translate\":\"test.arguments\",\"with\":[true,false,null]}",
                "[1,true,\"A\",{\"text\":\"B\"}]",
                "{\"text\":\"A\",\"extra\":[1,true,\"B\",{\"text\":\"C\"}]}",
                "{\"text\":\"A\",\"extra\":[1,true,null,\"B\"]}",
                "[[\"A\",1],{\"text\":\"B\",\"extra\":[[\"C\",1]]}]",
                "{\"selector\":\"@s\",\"separator\":[1,\"A\"]}",
                "{\"translate\":\"test.args\",\"with\":[\"[1]\",\"\\\"Sword\\\"\",{\"text\":\"{}\"}]}",
                "{translate:'test.args';with:[1;2]}", "{text=>Sword}",
                "/* before */ {text: /* value */ 'Sword'} // after", "# before\n{text:'Sword'}",
                "[\"A\",]", "{\"text\":\"A\",}", ")]}'\n{text:'Sword'}", "\"A\" \"B\"",
                "{'text':'line\\nquote\\\' and \\\"'}", "{text:'\\uD83D\\uDE00'}",
                "{text:'literal line\nbreak'}", "{text:'bad\\q'}",
                "{text:TRUE}", "{text:01}", "{text:NaN}",
                "{translate:'test.number',with:[1844674407370955161601]}")) {
            sample(samples, "text", References.TEXT_COMPONENT, StringTag.valueOf(input), boundary - 1, boundary);
            sample(samples, "text", References.TEXT_COMPONENT, StringTag.valueOf(input), boundary, currentVersion);
        }
        record(samples, "item", References.ITEM_STACK, """
            {id:'minecraft:stone',count:1,components:{
              'minecraft:custom_name':'"Sword"','minecraft:item_name':'{"text":"[1]"}',
              'minecraft:lore':['"First"','{"text":"[1]"}'],
              'minecraft:custom_data':{CustomName:'"Sword"',pages:['"Sword"']}}}
            """, boundary, currentVersion);
        record(samples, "item", References.ITEM_STACK, """
            {id:'minecraft:written_book',count:1,components:{'minecraft:written_book_content':{
              title:{raw:'"Sword"',filtered:'{"text":"[1]"}'},author:'Synthetic fixture',
              pages:['"Sword"',{raw:'{"text":"[1]"}',filtered:'"Filtered"'}]}}}
            """, boundary, currentVersion);
        record(samples, "item", References.ITEM_STACK, """
            {id:'minecraft:shulker_box',count:1,components:{'minecraft:container':[{slot:0,item:{
              id:'minecraft:bundle',count:1,components:{'minecraft:custom_name':'{"text":"[1]"}',
              'minecraft:bundle_contents':[{id:'minecraft:stone',count:1,components:{'minecraft:custom_name':'"Sword"'}}]}}}]}}
            """, boundary, currentVersion);
        record(samples, "entity", References.ENTITY_TREE, """
            {id:'minecraft:pig',CustomName:'"Sword"',Passengers:[{id:'minecraft:parrot',CustomName:'{"text":"[1]"}'}],
             custom:{CustomName:'"Sword"'}}
            """, boundary, currentVersion);
        record(samples, "blockEntity", References.BLOCK_ENTITY, """
            {id:'minecraft:sign',x:0,y:64,z:0,
             front_text:{messages:['"Sword"','{"text":"[1]"}','""','"Last"'],
                         filtered_messages:['"Filtered"','{"text":"[1]"}','""','"Last"']},
             back_text:{messages:['{"text":"[1]"}','"Sword"','""','"Last"']},
             custom:{messages:['"Sword"']}}
            """, boundary, currentVersion);
        record(samples, "blockEntity", References.BLOCK_ENTITY, """
            {id:'minecraft:chest',x:0,y:64,z:0,CustomName:'"Sword"',
             Items:[{id:'minecraft:stone',count:1,Slot:0,components:{'minecraft:custom_name':'"Sword"'}}]}
            """, boundary, currentVersion);
        record(samples, "player", References.PLAYER, """
            {Inventory:[{id:'minecraft:stone',count:1,Slot:0,components:{'minecraft:custom_name':'"Sword"'}}],
             EnderItems:[{id:'minecraft:stone',count:1,Slot:0,components:{'minecraft:custom_name':'"Sword"'}}],
             ShoulderEntityLeft:{id:'minecraft:parrot',CustomName:'{"text":"[1]"}',Pos:[0,64,0],
               CanPickUpLoot:false,PersistenceRequired:false,LeftHanded:false}}
            """, boundary, currentVersion);
        // SavedDataStorage upgrades the complete root before handing its data payload to
        // MapItemSavedData. Paired banner spellings distinguish which declared field reaches
        // the text fixer; unrelated custom fields must remain opaque.
        for (String name : List.of("Name", "name", "both")) {
            String positionAndColor = name.equals("Name")
                ? "Pos:{X:0,Y:64,Z:0},Color:'white'," : "pos:[0,64,0],color:'white',";
            String nameFields = name.equals("both") ? "Name:'\"Upper\"',name:'\"Lower\"'" : name + ":'\"Sword\"'";
            String input = "{data:{dimension:'minecraft:overworld',banners:[{" + positionAndColor + nameFields + "}],"
                + "custom:{Name:'\"Sword\"',name:'\"Sword\"'}}}";
            var record = (CompoundTag) JsonOps.INSTANCE.convertTo(NbtOps.INSTANCE, JsonParser.parseString(input));
            if (!name.equals("Name")) {
                // The current map codec writes BlockPos as an int array. JsonOps.createList
                // would give this synthetic input a different physical NBT representation.
                var data = (CompoundTag) record.get("data");
                var banner = (CompoundTag) ((net.minecraft.nbt.ListTag) data.get("banners")).get(0);
                banner.putIntArray("pos", new int[] {0, 64, 0});
            }
            int fieldBoundary = boundary(BlockPosFormatAndRenamesFix.class);
            for (int version : new int[] {fieldBoundary - 1, fieldBoundary, boundary - 1, boundary, savedDataDefaultVersion}) {
                sample(samples, "map", References.SAVED_DATA_MAP_DATA, record, version, currentVersion);
            }
        }
        legacyRecord(samples, "item", References.ITEM_STACK,
            "{id:'minecraft:stone',Count:1,tag:{display:{Name:'\"Sword\"'}}}",
            boundary(ItemCustomNameToComponentFix.class), currentVersion);
        legacyRecord(samples, "item", References.ITEM_STACK,
            "{id:'minecraft:stone',Count:1,tag:{display:{Lore:['\"Sword\"','[1]','\"123\"']}}}",
            boundary(ItemLoreFix.class), currentVersion);
        legacyRecord(samples, "entity", References.ENTITY_TREE,
            "{id:'minecraft:pig',CustomName:'\"Sword\"'}",
            boundary(EntityCustomNameToComponentFix.class), currentVersion);
        legacyRecord(samples, "blockEntity", References.BLOCK_ENTITY,
            "{id:'minecraft:chest',x:0,y:64,z:0,CustomName:'\"Sword\"'}",
            boundary(BlockEntityCustomNameToComponentFix.class), currentVersion);
        legacyRecord(samples, "blockEntity", References.BLOCK_ENTITY,
            "{id:'Sign',x:0,y:64,z:0,Text1:'\"123\"',Text2:'\"Sword\"',Text3:'null',Text4:'[1]'}",
            boundary(SignTextStrictJsonFix.class), currentVersion);
        legacyRecord(samples, "item", References.ITEM_STACK,
            "{id:'minecraft:written_book',Count:1,tag:{title:'\"Sword\"',author:'Fixture',pages:['\"123\"','\"Sword\"','null','[1]']}}",
            boundary(WrittenBookPagesStrictJsonFix.class), currentVersion);
        // An unframed number is plain text only before these fixes. Reusing it at the
        // boundary instead creates a numeric component that the later schema rejects.
        beforeRecord(samples, "item", References.ITEM_STACK,
            "{id:'minecraft:stone',Count:1,tag:{display:{Lore:['123']}}}",
            boundary(ItemLoreFix.class), currentVersion);
        beforeRecord(samples, "blockEntity", References.BLOCK_ENTITY,
            "{id:'Sign',x:0,y:64,z:0,Text1:'123',Text2:'',Text3:'',Text4:''}",
            boundary(SignTextStrictJsonFix.class), currentVersion);
        beforeRecord(samples, "item", References.ITEM_STACK,
            "{id:'minecraft:written_book',Count:1,tag:{title:'Fixture',author:'Fixture',pages:['123']}}",
            boundary(WrittenBookPagesStrictJsonFix.class), currentVersion);
        facts.add("proofs", samples);
        return facts;
    }

    private record Encoding(String name, Class<?> type) {}

    private static int savedDataDefaultVersion() throws Exception {
        try (var stream = SavedDataStorage.class.getResourceAsStream("SavedDataStorage.class")) {
            var methods = ClassFile.of().parse(stream.readAllBytes()).methods().stream()
                .filter(method -> method.methodName().equalsString("readTagFromDisk")).toList();
            if (methods.size() != 1) throw new IllegalStateException("Saved-data reader changed");
            var instructions = methods.getFirst().code().orElseThrow().elementStream()
                .filter(entry -> entry instanceof Instruction).map(entry -> (Instruction) entry).toList();
            Integer found = null;
            for (int index = 1; index < instructions.size(); index++) {
                if (instructions.get(index) instanceof InvokeInstruction call
                        && call.owner().asInternalName().equals("net/minecraft/nbt/NbtUtils")
                        && call.name().equalsString("getDataVersion")) {
                    if (found != null || !(instructions.get(index - 1) instanceof ConstantInstruction constant)
                            || !(constant.constantValue() instanceof Integer value)) {
                        throw new IllegalStateException("Saved-data version fallback changed");
                    }
                    found = value;
                }
            }
            if (found == null) throw new IllegalStateException("Saved-data version fallback unavailable");
            return found;
        }
    }

    private static TreeSet<String> identifiers(Class<?> type) throws Exception {
        var result = new TreeSet<String>();
        try (var stream = type.getResourceAsStream(type.getSimpleName() + ".class")) {
            for (var entry : ClassFile.of().parse(stream.readAllBytes()).constantPool()) {
                if (entry instanceof StringEntry text && text.stringValue().matches("[a-z0-9_.-]+:[a-z0-9_./-]+")) {
                    result.add(text.stringValue());
                }
            }
        }
        return result;
    }

    private static int boundary(Class<?> type) throws Exception {
        var matches = ((List<?>) ExtractGameFacts.field(DataFixers.getDataFixer(), "globalList"))
            .stream().filter(type::isInstance).toList();
        if (matches.size() != 1) throw new IllegalStateException("Ambiguous text fixer: " + type.getName());
        int key = ((DataFix) matches.getFirst()).getVersionKey();
        int version = DataFixUtils.getVersion(key);
        return version + (key == DataFixUtils.makeKey(version) ? 0 : 1);
    }

    private static void record(JsonArray rows, String kind, DSL.TypeReference type, String json,
                               int boundary, int currentVersion) throws Exception {
        var input = JsonOps.INSTANCE.convertTo(NbtOps.INSTANCE, JsonParser.parseString(json));
        sample(rows, kind, type, input, boundary - 1, boundary);
        sample(rows, kind, type, input, boundary, currentVersion);
    }

    private static void legacyRecord(JsonArray rows, String kind, DSL.TypeReference type, String json,
                                     int boundary, int currentVersion) throws Exception {
        var input = JsonOps.INSTANCE.convertTo(NbtOps.INSTANCE, JsonParser.parseString(json));
        sample(rows, kind, type, input, boundary - 1, currentVersion);
        sample(rows, kind, type, input, boundary, currentVersion);
    }

    private static void beforeRecord(JsonArray rows, String kind, DSL.TypeReference type, String json,
                                     int boundary, int currentVersion) throws Exception {
        var input = JsonOps.INSTANCE.convertTo(NbtOps.INSTANCE, JsonParser.parseString(json));
        sample(rows, kind, type, input, boundary - 1, currentVersion);
    }

    private static void sample(JsonArray rows, String kind, DSL.TypeReference type, Tag input,
                               int from, int to) throws Exception {
        var row = new JsonObject();
        row.addProperty("kind", kind);
        row.addProperty("version", from);
        row.addProperty("targetVersion", to);
        row.addProperty("input", encoded(input));
        try {
            var output = DataFixers.getDataFixer().update(type,
                new Dynamic<Tag>(NbtOps.INSTANCE, input.copy()), from, to).getValue();
            row.addProperty("output", encoded(output));
        } catch (net.minecraft.ReportedException error) {
            if (!kind.equals("text") || !(error.getCause() instanceof IllegalStateException)) throw error;
            // Util.readTypedOrThrow wraps an invalid root component's output-schema error.
            // Keep that actual rejection, while allowing unrelated extraction failures to stop.
            row.addProperty("error", error.getClass().getName() + ": " + error.getMessage()
                + "; " + error.getCause().getMessage());
        }
        rows.add(row);
    }

    private static String encoded(Tag value) throws Exception {
        var root = new CompoundTag();
        root.put("value", value);
        var bytes = new ByteArrayOutputStream();
        NbtIo.write(root, new DataOutputStream(bytes));
        return Base64.getEncoder().encodeToString(bytes.toByteArray());
    }
}
