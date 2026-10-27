import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.lighting.BlockLightSectionStorage;

/** The value returned for an absent layer is an engine fact, not a save-version rule. */
final class ExtractLightStorage {
    static JsonObject extract() {
        var storage = new EmptyBlockStorage();
        int absent = storage.read(BlockPos.ZERO);
        if (absent < 0 || absent > 15) throw new IllegalStateException("Unsupported absent block light");
        var samples = new JsonArray();
        for (var point : new BlockPos[] {
                BlockPos.ZERO, new BlockPos(15, 15, 15), new BlockPos(-1, -1, -1),
                new BlockPos(-16, -64, 31), new BlockPos(32, 319, -17),
                new BlockPos(-30_000_000, -2048, 30_000_000),
                new BlockPos(30_000_000, 2047, -30_000_000) }) {
            int actual = storage.read(point);
            if (actual != absent) throw new IllegalStateException("Absent block light depends on position");
            var sample = new JsonObject();
            sample.addProperty("x", point.getX());
            sample.addProperty("y", point.getY());
            sample.addProperty("z", point.getZ());
            sample.addProperty("value", actual);
            samples.add(sample);
        }
        var result = new JsonObject();
        result.addProperty("absentBlockLight", absent);
        result.add("samples", samples);
        return result;
    }

    // Construction creates empty storage maps. This read uses only the visible map;
    // it neither calls the chunk source nor schedules propagation or world operations.
    private static final class EmptyBlockStorage extends BlockLightSectionStorage {
        EmptyBlockStorage() { super(null); }
        int read(BlockPos point) { return super.getLightValue(point.asLong()); }
    }
}
