import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.lang.reflect.Modifier;
import java.lang.reflect.ParameterizedType;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.IdentityHashMap;
import java.util.TreeMap;
import net.minecraft.SharedConstants;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;

/** Extract facts from the official registry and its declared entity classes, without a world. */
public final class ExtractEntityTypes {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected output JSON path");
        SharedConstants.tryDetectVersion();
        Bootstrap.bootStrap();
        var classes = new IdentityHashMap<EntityType<?>, Class<?>>();
        // 26.2 moved the registered constants into EntityTypes; 26.1 keeps them in EntityType.
        Class<?> declarations;
        try { declarations = Class.forName("net.minecraft.world.entity.EntityTypes"); }
        catch (ClassNotFoundException olderLayout) { declarations = EntityType.class; }
        for (var field : declarations.getDeclaredFields()) {
            if (!Modifier.isStatic(field.getModifiers()) || field.getType() != EntityType.class) continue;
            if (!(field.getGenericType() instanceof ParameterizedType generic)
                || !(generic.getActualTypeArguments()[0] instanceof Class<?> entityClass)
                || !Entity.class.isAssignableFrom(entityClass)
                || (!Mob.class.isAssignableFrom(entityClass) && entityClass.isAssignableFrom(Mob.class))) {
                throw new IllegalStateException("Unresolved entity class: " + field);
            }
            var type = (EntityType<?>) field.get(null);
            if (classes.put(type, entityClass) != null) {
                throw new IllegalStateException("Aliased entity type: " + field);
            }
        }
        var entries = new TreeMap<String, JsonObject>();
        for (var type : BuiltInRegistries.ENTITY_TYPE) {
            var entityClass = classes.remove(type);
            if (entityClass == null) throw new IllegalStateException("Unmapped registered entity: " + type);
            var entry = new JsonObject();
            entry.addProperty("class", entityClass.getName());
            entry.addProperty("mob", Mob.class.isAssignableFrom(entityClass));
            var parents = new JsonArray();
            for (var parent = entityClass; parent != null; parent = parent.getSuperclass()) {
                parents.add(parent.getName());
            }
            entry.add("ancestry", parents);
            entries.put(BuiltInRegistries.ENTITY_TYPE.getKey(type).toString(), entry);
        }
        if (!classes.isEmpty()) throw new IllegalStateException("Unregistered entity declarations");
        Files.writeString(Path.of(args[0]), new GsonBuilder().setPrettyPrinting().create().toJson(entries) + "\n");
        System.out.println("ENTITY_TYPES " + entries.size() + ", MOBS "
            + entries.values().stream().filter(e -> e.get("mob").getAsBoolean()).count());
    }
}
