import com.google.gson.JsonObject;
import com.google.gson.JsonArray;
import java.util.TreeMap;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.EntityTypes;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.TamableAnimal;
import net.minecraft.world.entity.ai.attributes.AttributeMap;
import net.minecraft.world.entity.ai.attributes.Attribute;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.attributes.DefaultAttributes;
import net.minecraft.world.entity.ai.attributes.RangedAttribute;
import net.minecraft.world.entity.animal.wolf.Wolf;
import net.minecraft.world.entity.monster.cubemob.AbstractCubeMob;
import net.minecraft.world.entity.monster.cubemob.Slime;
import net.minecraft.world.entity.monster.cubemob.SulfurCube;
import sun.misc.Unsafe;

/** Registry bases are code defaults; entity-specific loading rules are separate facts. */
final class ExtractHealthDefaults {
    @SuppressWarnings("unchecked")
    static JsonObject extract(JsonObject entityTypes) throws Exception {
        for (var entry : entityTypes.entrySet()) {
            var type = Class.forName(entry.getValue().getAsJsonObject().get("class").getAsString());
            if (AbstractCubeMob.class.isAssignableFrom(type)) {
                var owner = methodOwner(type, "setCubeMobHealth", int.class);
                if (owner != AbstractCubeMob.class && owner != SulfurCube.class) {
                    throw new IllegalStateException("Unsupported cube health method: " + owner);
                }
            }
            if (TamableAnimal.class.isAssignableFrom(type)) {
                var owner = methodOwner(type, "applyTamingSideEffects");
                if (owner != TamableAnimal.class && owner != Wolf.class) {
                    throw new IllegalStateException("Unsupported taming health method: " + owner);
                }
            }
        }
        var defaults = new TreeMap<String, Double>();
        var proofs = new TreeMap<String, Float>();
        for (var type : BuiltInRegistries.ENTITY_TYPE) {
            if (!DefaultAttributes.hasSupplier(type)) continue;
            var supplier = DefaultAttributes.getSupplier((EntityType<? extends LivingEntity>) type);
            if (!supplier.hasAttribute(Attributes.MAX_HEALTH)) continue;
            String id = BuiltInRegistries.ENTITY_TYPE.getKey(type).toString();
            double base = supplier.getBaseValue(Attributes.MAX_HEALTH);
            // LivingEntity.getMaxHealth reads AttributeMap.getValue and converts to Float.
            float actual = (float) new AttributeMap(supplier).getValue(Attributes.MAX_HEALTH);
            if (!Double.isFinite(base) || !Float.isFinite(actual)) {
                throw new IllegalStateException("Nonfinite maximum-health default: " + id);
            }
            defaults.put(id, base);
            proofs.put(id, actual);
        }
        String player = BuiltInRegistries.ENTITY_TYPE.getKey(EntityTypes.PLAYER).toString();
        if (!defaults.containsKey(player)) throw new IllegalStateException("Missing player health default");
        if (!(Attributes.MAX_HEALTH.value() instanceof RangedAttribute bounds)) {
            throw new IllegalStateException("Maximum health is no longer a ranged attribute");
        }
        var result = new JsonObject();
        result.addProperty("player", player);
        result.addProperty("minimum", bounds.getMinValue());
        result.addProperty("maximum", bounds.getMaxValue());
        var values = new JsonObject();
        defaults.forEach(values::addProperty);
        result.add("bases", values);
        var expected = new JsonObject();
        proofs.forEach(expected::addProperty);
        result.add("attributeValues", expected);
        result.addProperty("minimumCubeSize", AbstractCubeMob.MIN_SIZE);
        result.addProperty("maximumCubeSize", AbstractCubeMob.MAX_SIZE);
        if (AbstractCubeMob.MIN_SIZE < 1 || AbstractCubeMob.MAX_SIZE > 4096) {
            throw new IllegalStateException("Unsupported cube size range");
        }
        var rules = new JsonArray();
        var wolf = allocate(UntamedWolfProbe.class);
        probeAttributes = new AttributeMap(DefaultAttributes.getSupplier(EntityTypes.WOLF));
        probeAttributes.getInstance(Attributes.MAX_HEALTH).setBaseValue(37);
        wolf.apply();
        var reset = new JsonObject();
        reset.addProperty("class", Wolf.class.getName());
        reset.addProperty("kind", "untamedReset");
        reset.addProperty("base", probeAttributes.getInstance(Attributes.MAX_HEALTH).getBaseValue());
        reset.addProperty("actual", (float) probeAttributes.getValue(Attributes.MAX_HEALTH));
        rules.add(reset);
        var slime = allocate(SlimeProbe.class);
        rules.add(sizeRule(AbstractCubeMob.class, EntityTypes.SLIME, slime::apply));
        var sulfur = allocate(SulfurCubeProbe.class);
        rules.add(sizeRule(SulfurCube.class, EntityTypes.SULFUR_CUBE, sulfur::apply));
        result.add("loadingRules", rules);
        probeAttributes = null;
        return result;
    }

    private static JsonObject sizeRule(Class<?> owner, EntityType<? extends LivingEntity> type,
                                      java.util.function.IntConsumer apply) {
        var result = new JsonObject();
        result.addProperty("class", owner.getName());
        result.addProperty("kind", "cubeSize");
        var bases = new JsonArray();
        var values = new JsonArray();
        for (int size = AbstractCubeMob.MIN_SIZE; size <= AbstractCubeMob.MAX_SIZE; size++) {
            probeAttributes = new AttributeMap(DefaultAttributes.getSupplier(type));
            probeAttributes.getInstance(Attributes.MAX_HEALTH).setBaseValue(37);
            apply.accept(size);
            bases.add(probeAttributes.getInstance(Attributes.MAX_HEALTH).getBaseValue());
            values.add((float) probeAttributes.getValue(Attributes.MAX_HEALTH));
        }
        result.add("bases", bases);
        result.add("actual", values);
        return result;
    }

    private static Class<?> methodOwner(Class<?> type, String name, Class<?>... parameters) throws Exception {
        for (var owner = type; owner != null; owner = owner.getSuperclass()) {
            try { return owner.getDeclaredMethod(name, parameters).getDeclaringClass(); }
            catch (NoSuchMethodException inherited) { }
        }
        throw new NoSuchMethodException(type.getName() + "." + name);
    }

    // These three methods only need an attribute map and, for wolves, the tame flag.
    // Constructing an entity requires a live Level. Tool-only receivers bypass construction
    // and supply those dependencies, so extraction executes the game's actual health methods
    // without creating a world. Keep this boundary under source review when the game changes.
    // No entity is loaded, ticked, spawned or persisted. This state is used serially by extract.
    private static AttributeMap probeAttributes;

    private static <T> T allocate(Class<T> type) throws Exception {
        var field = Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        return type.cast(((Unsafe) field.get(null)).allocateInstance(type));
    }

    private static final class UntamedWolfProbe extends Wolf {
        private UntamedWolfProbe() { super(EntityTypes.WOLF, null); }
        @Override public boolean isTame() { return false; }
        @Override public AttributeInstance getAttribute(Holder<Attribute> attribute) { return probeAttributes.getInstance(attribute); }
        void apply() { super.applyTamingSideEffects(); }
    }

    private static final class SlimeProbe extends Slime {
        private SlimeProbe() { super(EntityTypes.SLIME, null); }
        @Override public AttributeInstance getAttribute(Holder<Attribute> attribute) { return probeAttributes.getInstance(attribute); }
        void apply(int size) { super.setCubeMobHealth(size); }
    }

    private static final class SulfurCubeProbe extends SulfurCube {
        private SulfurCubeProbe() { super(EntityTypes.SULFUR_CUBE, null); }
        @Override public AttributeInstance getAttribute(Holder<Attribute> attribute) { return probeAttributes.getInstance(attribute); }
        void apply(int size) { super.setCubeMobHealth(size); }
    }
}
