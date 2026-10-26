import com.google.gson.JsonObject;
import java.lang.classfile.ClassFile;
import java.lang.classfile.Instruction;
import java.lang.classfile.Opcode;
import java.lang.classfile.instruction.ConstantInstruction;
import java.lang.classfile.instruction.FieldInstruction;
import java.lang.classfile.instruction.InvokeInstruction;
import java.util.List;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.NetherPortalBlock;
import net.minecraft.world.level.border.WorldBorder;
import net.minecraft.world.level.dimension.DimensionType;
import net.minecraft.world.level.portal.PortalForcer;

/** Code-format adapters only; dimension scales and saved borders are runtime data. */
final class ExtractPortalFacts {
    static JsonObject extract() throws Exception {
        var facts = new JsonObject();
        var travel = instructions(NetherPortalBlock.class, "getPortalDestination", null);
        // Verified ternary: source.dimension == special ? other : special. Refuse a changed
        // instruction shape rather than silently extracting unrelated dimension constants.
        var prefix = List.of(Opcode.ALOAD_1, Opcode.INVOKEVIRTUAL, Opcode.GETSTATIC,
            Opcode.IF_ACMPNE, Opcode.GETSTATIC, Opcode.GOTO, Opcode.GETSTATIC, Opcode.ASTORE);
        require(travel.subList(0, prefix.size()).stream().map(Instruction::opcode).toList().equals(prefix));
        var special = (FieldInstruction) travel.get(2);
        var other = (FieldInstruction) travel.get(4);
        var fallback = (FieldInstruction) travel.get(6);
        require(special.name().equalsString(fallback.name().stringValue()));
        facts.addProperty("specialDimension", dimension(special));
        facts.addProperty("otherDimension", dimension(other));

        facts.addProperty("specialSearchRadius", integerField(PortalForcer.class, "NETHER_PORTAL_RADIUS"));
        facts.addProperty("otherSearchRadius", integerField(PortalForcer.class, "OVERWORLD_PORTAL_RADIUS"));
        var search = instructions(PortalForcer.class, "findClosestPortalPosition", null);
        var radii = search.stream().filter(i -> i instanceof ConstantInstruction)
            .map(i -> ((ConstantInstruction) i).constantValue()).limit(2).toList();
        require(radii.equals(List.of(facts.get("specialSearchRadius").getAsInt(), facts.get("otherSearchRadius").getAsInt())));

        var codec = instructions(DimensionType.class, "lambda$createDirectCodec$0", null);
        boolean found = false;
        for (int i = 3; i < codec.size(); i++) {
            if (codec.get(i) instanceof ConstantInstruction value && value.constantValue().equals("coordinate_scale")) {
                require(!found && codec.get(i - 1) instanceof InvokeInstruction call && call.name().equalsString("doubleRange"));
                facts.addProperty("minimumScale", number(codec.get(i - 3)));
                facts.addProperty("maximumScale", number(codec.get(i - 2)));
                found = true;
            }
        }
        require(found);
        var border = new WorldBorder();
        var limit = WorldBorder.class.getDeclaredField("absoluteMaxSize"); limit.setAccessible(true);
        facts.addProperty("absoluteBorderLimit", limit.getInt(border));
        var clamp = instructions(WorldBorder.class, "clampVec3ToBound", "(DDD)Lnet/minecraft/world/phys/Vec3;");
        var margins = clamp.stream().filter(i -> i instanceof ConstantInstruction)
            .map(ExtractPortalFacts::number).distinct().toList();
        require(margins.size() == 1 && margins.getFirst() > 0);
        facts.addProperty("borderInset", margins.getFirst());
        var defaults = WorldBorder.Settings.DEFAULT;
        facts.addProperty("defaultBorderSize", defaults.size());
        return facts;
    }

    private static String dimension(FieldInstruction field) throws Exception {
        require(field.owner().asInternalName().equals("net/minecraft/world/level/Level"));
        return ((ResourceKey<?>) Level.class.getField(field.name().stringValue()).get(null)).identifier().toString();
    }

    private static int integerField(Class<?> type, String name) throws Exception {
        var field = type.getDeclaredField(name); field.setAccessible(true); return field.getInt(null);
    }

    private static double number(Instruction instruction) {
        return ((Number) ((ConstantInstruction) instruction).constantValue()).doubleValue();
    }

    private static List<Instruction> instructions(Class<?> type, String name, String descriptor) throws Exception {
        try (var stream = type.getResourceAsStream("/" + type.getName().replace('.', '/') + ".class")) {
            var methods = ClassFile.of().parse(stream.readAllBytes()).methods().stream()
                .filter(m -> m.methodName().equalsString(name) && (descriptor == null || m.methodType().equalsString(descriptor))).toList();
            require(methods.size() == 1);
            return methods.getFirst().code().orElseThrow().elementStream()
                .filter(e -> e instanceof Instruction).map(e -> (Instruction) e).toList();
        }
    }

    private static void require(boolean condition) {
        if (!condition) throw new IllegalStateException("Portal code format changed; inspect the game's implementation");
    }
}
