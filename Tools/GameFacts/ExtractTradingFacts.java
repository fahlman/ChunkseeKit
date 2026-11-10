import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.mojang.serialization.DataResult;
import java.util.TreeMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtOps;
import net.minecraft.world.entity.monster.zombie.ZombieVillager;
import net.minecraft.world.entity.npc.villager.Villager;
import net.minecraft.world.entity.npc.villager.VillagerData;
import net.minecraft.world.level.storage.ValueInput;

/** Villager reader defaults and profession links live in code; trade contents remain runtime data. */
final class ExtractTradingFacts {
    static JsonObject extract(JsonObject entityTypes) throws Exception {
        var professions = new TreeMap<String, TreeMap<Integer, String>>();
        for (var profession : BuiltInRegistries.VILLAGER_PROFESSION) {
            var levels = new TreeMap<Integer, String>();
            for (var entry : profession.tradeSetsByLevel().int2ObjectEntrySet()) {
                var actual = profession.getTrades(entry.getIntKey());
                if (!entry.getValue().equals(actual)) throw new IllegalStateException("Changed profession lookup");
                levels.put(entry.getIntKey(), actual.identifier().toString());
            }
            professions.put(BuiltInRegistries.VILLAGER_PROFESSION.getKey(profession).toString(), levels);
        }
        if (professions.isEmpty()) throw new IllegalStateException("No profession code facts");
        var result = new JsonObject();
        result.addProperty("source", "BuiltInRegistries.VILLAGER_PROFESSION -> VillagerProfession.tradeSetsByLevel / getTrades; Villager.updateTrades; Villager.createDefaultVillagerData; VillagerData.CODEC; Villager/ZombieVillager.readAdditionalSaveData");
        int minimumLevel = new VillagerData(null, null, Integer.MIN_VALUE).level();
        for (int input : new int[] {Integer.MIN_VALUE, -1, 0, 1, 2, 5, 6, Integer.MAX_VALUE}) {
            if (new VillagerData(null, null, input).level() != Math.max(minimumLevel, input)) {
                throw new IllegalStateException("Changed VillagerData level normalization");
            }
        }
        result.addProperty("minimumLevel", minimumLevel);
        result.add("professions", new Gson().toJsonTree(professions));
        var defaults = Villager.createDefaultVillagerData();
        String defaultProfession = BuiltInRegistries.VILLAGER_PROFESSION.getKey(defaults.profession().value()).toString();
        String defaultType = BuiltInRegistries.VILLAGER_TYPE.getKey(defaults.type().value()).toString();
        if (!professions.containsKey(defaultProfession) || defaults.level() < minimumLevel) {
            throw new IllegalStateException("Unresolved villager defaults");
        }
        var empty = VillagerData.CODEC.parse(NbtOps.INSTANCE, new CompoundTag()).result().orElseThrow();
        requireSameDefaults(defaults, empty);
        var invalidLevel = new CompoundTag();
        invalidLevel.putString("level", "not a number");
        var parsed = VillagerData.CODEC.parse(NbtOps.INSTANCE, invalidLevel);
        if (!(parsed instanceof DataResult.Error<VillagerData> error)) {
            throw new IllegalStateException("Changed VillagerData invalid-level codec result");
        }
        requireSameDefaults(defaults, error.partialValue().orElseThrow());
        result.addProperty("defaultProfession", defaultProfession);
        result.addProperty("defaultType", defaultType);
        result.addProperty("defaultLevel", defaults.level());

        // The existing entity-class extraction establishes the reader association. A new
        // override needs its own source proof; a familiar superclass is not enough.
        var readers = new TreeMap<String, String>();
        for (var entry : entityTypes.entrySet()) {
            var type = Class.forName(entry.getValue().getAsJsonObject().get("class").getAsString());
            Class<?> expected;
            String reader;
            if (Villager.class.isAssignableFrom(type)) {
                expected = Villager.class;
                reader = "villager";
            } else if (ZombieVillager.class.isAssignableFrom(type)) {
                expected = ZombieVillager.class;
                reader = "zombieVillager";
            } else {
                continue;
            }
            // The outer fallback also depends on constructor initialization. An inherited
            // reader alone does not prove a newly introduced subclass has the same defaults.
            if (type != expected || readerOwner(type) != expected) {
                throw new IllegalStateException("Unverified villager reader: " + type.getName());
            }
            readers.put(entry.getKey(), reader);
        }
        if (!readers.containsValue("villager") || !readers.containsValue("zombieVillager")) {
            throw new IllegalStateException("Missing villager reader associations");
        }
        result.add("dataReaders", new Gson().toJsonTree(readers));
        return result;
    }

    private static Class<?> readerOwner(Class<?> type) throws NoSuchMethodException {
        for (var owner = type; owner != null; owner = owner.getSuperclass()) {
            try {
                owner.getDeclaredMethod("readAdditionalSaveData", ValueInput.class);
                return owner;
            } catch (NoSuchMethodException inherited) { }
        }
        throw new NoSuchMethodException(type.getName() + ".readAdditionalSaveData");
    }

    private static void requireSameDefaults(VillagerData expected, VillagerData actual) {
        if (actual.level() != expected.level()
                || !actual.profession().unwrapKey().equals(expected.profession().unwrapKey())
                || !actual.type().unwrapKey().equals(expected.type().unwrapKey())) {
            throw new IllegalStateException("VillagerData codec and entity defaults differ");
        }
    }
}
