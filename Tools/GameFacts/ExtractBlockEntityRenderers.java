import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderers;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.EntityBlock;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** A block entity renderer can supply geometry absent from the resource model. */
final class ExtractBlockEntityRenderers {
    static JsonObject extract() throws ReflectiveOperationException {
        var field = BlockEntityRenderers.class.getDeclaredField("PROVIDERS");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        var providers = (Map<BlockEntityType<?>, ?>) field.get(null);
        if (providers.isEmpty()) throw new IllegalStateException("No block entity renderer providers");
        var flags = new TreeMap<String, Boolean>();
        var samples = new JsonArray();
        var gson = new Gson();
        for (var block : BuiltInRegistries.BLOCK) {
            String id = BuiltInRegistries.BLOCK.getKey(block).toString();
            boolean rendered = providers.keySet().stream().anyMatch(type -> type.isValid(block.defaultBlockState()));
            for (var state : block.getStateDefinition().getPossibleStates()) {
                if (providers.keySet().stream().anyMatch(type -> type.isValid(state)) != rendered) {
                    throw new IllegalStateException("State-dependent renderer registration: " + id);
                }
                // Independently take the dispatcher path: the actual created entity supplies its type.
                boolean dispatched = false;
                String factory = "BlockState.hasBlockEntity == false";
                if (state.hasBlockEntity()) {
                    factory = "EntityBlock.newBlockEntity";
                    if (!(block instanceof EntityBlock entityBlock)) {
                        throw new IllegalStateException("Missing entity factory: " + id);
                    }
                    var entity = entityBlock.newBlockEntity(BlockPos.ZERO, state);
                    if (entity != null) {
                        dispatched = providers.containsKey(entity.getType());
                    } else {
                        // Some blocks create their entity only during a world operation. Validate
                        // their registered type factories without inventing that operation's context.
                        factory = "BlockEntityType.create (block factory returned null)";
                        boolean found = false;
                        for (var type : BuiltInRegistries.BLOCK_ENTITY_TYPE) {
                            if (!type.isValid(state)) continue;
                            var created = type.create(BlockPos.ZERO, state);
                            if (created == null || created.getType() != type) {
                                throw new IllegalStateException("Invalid registered entity factory: " + state);
                            }
                            dispatched |= providers.containsKey(created.getType());
                            found = true;
                        }
                        if (!found) throw new IllegalStateException("No registered entity type: " + state);
                    }
                }
                if (rendered != dispatched) throw new IllegalStateException("Renderer dispatch differs: " + state);
                var sample = new JsonObject();
                sample.addProperty("id", id);
                var properties = new TreeMap<String, String>();
                for (var property : state.getProperties()) properties.put(property.getName(), valueName(state, property));
                sample.add("properties", gson.toJsonTree(properties));
                sample.addProperty("hasBlockEntityRenderer", dispatched);
                sample.addProperty("factory", factory);
                samples.add(sample);
            }
            flags.put(id, rendered);
        }
        var result = new JsonObject();
        result.addProperty("source", "BlockEntityRenderers.PROVIDERS and BlockEntityType.isValid; checked through EntityBlock.newBlockEntity or BlockEntityType.create and BlockEntity.getType");
        result.add("flags", gson.toJsonTree(flags));
        result.add("samples", samples);
        return result;
    }

    private static <T extends Comparable<T>> String valueName(BlockState state, Property<T> property) {
        return property.getName(state.getValue(property));
    }
}
