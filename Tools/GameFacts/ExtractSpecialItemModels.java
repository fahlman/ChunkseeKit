import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.vertex.PoseStack;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.geom.EntityModelSet;
import net.minecraft.client.model.geom.LayerDefinitions;
import net.minecraft.client.model.geom.ModelLayerLocation;
import net.minecraft.client.model.geom.ModelLayers;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.object.banner.BannerFlagModel;
import net.minecraft.client.model.object.banner.BannerModel;
import net.minecraft.client.model.object.chest.ChestModel;
import net.minecraft.client.model.object.equipment.ShieldModel;
import net.minecraft.client.model.object.skull.SkullModelBase;
import net.minecraft.client.model.object.statue.CopperGolemStatueModel;
import net.minecraft.client.renderer.FaceInfo;
import net.minecraft.client.renderer.Sheets;
import net.minecraft.client.renderer.blockentity.ConduitRenderer;
import net.minecraft.client.renderer.blockentity.SkullBlockRenderer;
import net.minecraft.client.renderer.special.CopperGolemStatueSpecialRenderer;
import net.minecraft.client.resources.DefaultPlayerSkin;
import net.minecraft.core.Direction;
import net.minecraft.resources.Identifier;
import net.minecraft.util.Unit;
import net.minecraft.world.level.block.BannerBlock;
import net.minecraft.world.level.block.CopperGolemStatueBlock;
import net.minecraft.world.level.block.SkullBlock;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import org.joml.Vector3fc;

/** Baked model polygons and actual static inventory poses; no copied geometry or skin inventory. */
final class ExtractSpecialItemModels {
    private static final Gson GSON = new Gson();
    private final Map<ModelLayerLocation, LayerDefinition> layers = LayerDefinitions.createRoots();
    private final RecordingModelSet models = new RecordingModelSet(layers);
    private final Map<String, JsonObject> results = new TreeMap<>();
    private final Map<String, String> textures = new TreeMap<>();

    static JsonObject extract() throws Exception { return new ExtractSpecialItemModels().read(); }

    private JsonObject read() throws Exception {
        var chest = new ChestModel(models.bakeLayer(ModelLayers.CHEST));
        chest.setupAnim(0f);
        add("chest", chest.root(), ModelLayers.CHEST, "primary", "ChestModel.setupAnim(0)");
        add("shield", new ShieldModel(models.bakeLayer(ModelLayers.SHIELD)).root(), ModelLayers.SHIELD,
            "primary", "ShieldModel");
        add("conduit", models.bakeLayer(ModelLayers.CONDUIT_SHELL), ModelLayers.CONDUIT_SHELL,
            "primary", "ConduitSpecialRenderer / ConduitRenderer.createShellLayer");
        textures.put("conduit", ConduitRenderer.SHELL_TEXTURE.texture().toString());
        textures.put("decorated_pot", Sheets.DECORATED_POT_BASE.texture().toString());

        // The box renderer has its own animation model; the entity's shulker model differs.
        var boxClass = Class.forName("net.minecraft.client.renderer.blockentity.ShulkerBoxRenderer$ShulkerBoxModel");
        var constructor = boxClass.getDeclaredConstructor(ModelPart.class);
        constructor.setAccessible(true);
        var shulker = (Model<?>) constructor.newInstance(models.bakeLayer(ModelLayers.SHULKER_BOX));
        var animate = boxClass.getDeclaredMethod("setupAnim", Float.class);
        animate.setAccessible(true);
        animate.invoke(shulker, 0f);
        add("shulker_box", shulker.root(), ModelLayers.SHULKER_BOX, "primary", "ShulkerBoxRenderer.ShulkerBoxModel.setupAnim(0)");

        for (var attachment : BannerBlock.AttachmentType.values()) {
            boolean ground = attachment == BannerBlock.AttachmentType.GROUND;
            var bodyLayer = ground ? ModelLayers.STANDING_BANNER : ModelLayers.WALL_BANNER;
            var flagLayer = ground ? ModelLayers.STANDING_BANNER_FLAG : ModelLayers.WALL_BANNER_FLAG;
            var body = new BannerModel(models.bakeLayer(bodyLayer));
            var flag = new BannerFlagModel(models.bakeLayer(flagLayer));
            flag.setupAnim(0f);
            String key = "banner/" + attachment.getSerializedName();
            add(key, body.root(), bodyLayer, "plain", "BannerRenderer / BannerModel");
            add(key, flag.root(), flagLayer, "primary", "BannerFlagModel.setupAnim(0)");
        }

        var skinByType = (Map<?, ?>) field(SkullBlockRenderer.class, "SKIN_BY_TYPE");
        for (var type : SkullBlock.Types.values()) {
            models.requested.clear();
            var head = SkullBlockRenderer.createModel(models, type);
            if (head == null || models.requested.size() != 1) throw new IllegalStateException("Unknown skull model: " + type);
            head.setupAnim(new SkullModelBase.State());
            String key = type == SkullBlock.Types.PLAYER ? "player_head" : "head/" + type.getSerializedName();
            add(key, head.root(), models.requested.getFirst(), "primary", "SkullBlockRenderer.createModel / " + head.getClass().getName() + ".setupAnim(0)");
            var texture = type == SkullBlock.Types.PLAYER ? DefaultPlayerSkin.getDefaultTexture() : (Identifier) skinByType.get(type);
            if (texture == null) throw new IllegalStateException("Missing skull texture: " + type);
            textures.put(key, imageTexture(texture));
        }

        var statueLayer = CopperGolemStatueSpecialRenderer.Unbaked.class.getDeclaredMethod("getModel", CopperGolemStatueBlock.Pose.class);
        statueLayer.setAccessible(true);
        for (var pose : CopperGolemStatueBlock.Pose.values()) {
            var layer = (ModelLayerLocation) statueLayer.invoke(null, pose);
            var model = new CopperGolemStatueModel(models.bakeLayer(layer));
            model.setupAnim(Unit.INSTANCE);
            add("copper_golem_statue/" + pose.getSerializedName(), model.root(), layer, "primary",
                "CopperGolemStatueSpecialRenderer.Unbaked.getModel / CopperGolemStatueModel.setupAnim");
        }
        add("decorated_pot", models.bakeLayer(ModelLayers.DECORATED_POT_BASE), ModelLayers.DECORATED_POT_BASE,
            "primary", "DecoratedPotRenderer.createBaseLayer");
        add("decorated_pot", models.bakeLayer(ModelLayers.DECORATED_POT_SIDES), ModelLayers.DECORATED_POT_SIDES,
            "pot-side", "DecoratedPotRenderer.createSidesLayer");

        var corners = new JsonObject();
        for (var direction : Direction.values()) {
            var values = new JsonArray();
            for (int index = 0; index < 4; index++) {
                values.add(vector(FaceInfo.fromFacing(direction).getVertexInfo(index).select(new Vector3f(0), new Vector3f(1))));
            }
            corners.add(direction.getSerializedName(), values);
        }
        var result = new JsonObject();
        result.add("models", GSON.toJsonTree(results));
        result.add("textures", GSON.toJsonTree(textures));
        result.add("faceCorners", corners);
        return result;
    }

    private void add(String key, ModelPart part, ModelLayerLocation layer, String material, String source) throws Exception {
        var definition = layers.get(layer);
        var skin = field(definition, "material");
        int width = (int) field(skin, "xTexSize"), height = (int) field(skin, "yTexSize");
        var result = results.computeIfAbsent(key, ignored -> {
            var value = new JsonObject(); value.add("parts", new JsonArray()); return value;
        });
        walk(part, new PoseStack(), "", result.getAsJsonArray("parts"), width, height, material, source, 1f);
    }

    private void walk(ModelPart part, PoseStack poses, String path, JsonArray output,
                      int width, int height, String material, String source, float parentScale) throws Exception {
        if (!part.visible) return;
        poses.pushPose();
        part.translateAndRotate(poses);
        var matrix = new Matrix4f(poses.last().pose());
        if (part.xScale != part.yScale || part.yScale != part.zScale || part.xScale <= 0)
            throw new IllegalStateException("Unrepresentable model-part scale: " + path);
        float inheritedScale = parentScale * part.xScale;
        var scale = new Vector3f(inheritedScale);
        var angles = matrix.getUnnormalizedRotation(new Quaternionf()).getEulerAnglesZYX(new Vector3f());
        int index = 0;
        for (var raw : (List<?>) field(part, "cubes")) {
            if (part.skipDraw) break;
            var cube = (ModelPart.Cube) raw;
            var result = new JsonObject();
            result.addProperty("source", source);
            result.addProperty("part", path + "/" + index++);
            String role = material;
            if (material.equals("pot-side")) {
                role = path.substring(path.lastIndexOf('/') + 1);
                if (!List.of("front", "back", "left", "right").contains(role)) throw new IllegalStateException("Unknown pot side: " + role);
            }
            result.addProperty("material", role);
            result.add("skinSize", GSON.toJsonTree(new int[] {width, height}));
            result.add("matrix", GSON.toJsonTree(matrix.get(new float[16])));
            result.add("scale", vector(scale));
            result.add("angles", vector(angles));
            var polygons = new JsonArray();
            for (var polygon : (ModelPart.Polygon[]) field(cube, "polygons")) {
                var face = new JsonObject();
                face.add("normal", vector(polygon.normal()));
                var vertices = new JsonArray();
                for (var vertex : polygon.vertices()) {
                    var value = new JsonObject();
                    var point = new Vector3f(vertex.x(), vertex.y(), vertex.z());
                    value.add("local", vector(point));
                    value.add("posed", vector(matrix.transformPosition(new Vector3f(point).mul(1f / 16)).mul(16)));
                    value.add("uv", GSON.toJsonTree(new float[] {vertex.u(), vertex.v()}));
                    vertices.add(value);
                }
                face.add("vertices", vertices);
                polygons.add(face);
            }
            result.add("polygons", polygons);
            output.add(result);
        }
        var children = new TreeMap<String, ModelPart>();
        for (var entry : ((Map<?, ?>) field(part, "children")).entrySet()) children.put((String) entry.getKey(), (ModelPart) entry.getValue());
        for (var entry : children.entrySet()) walk(entry.getValue(), poses, path + "/" + entry.getKey(), output,
            width, height, material, source, inheritedScale);
        poses.popPose();
    }

    private static JsonArray vector(Vector3fc value) {
        return GSON.toJsonTree(new float[] {value.x(), value.y(), value.z()}).getAsJsonArray();
    }
    private static String imageTexture(Identifier image) {
        String path = image.getPath();
        if (!path.startsWith("textures/") || !path.endsWith(".png")) throw new IllegalStateException("Unknown image path: " + image);
        return image.getNamespace() + ":" + path.substring("textures/".length(), path.length() - ".png".length());
    }
    private static Object field(Object object, String name) throws ReflectiveOperationException {
        Class<?> type = object instanceof Class<?> c ? c : object.getClass();
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(object instanceof Class<?> ? null : object);
    }
    private static final class RecordingModelSet extends EntityModelSet {
        final List<ModelLayerLocation> requested = new ArrayList<>();
        RecordingModelSet(Map<ModelLayerLocation, LayerDefinition> layers) { super(layers); }
        @Override public ModelPart bakeLayer(ModelLayerLocation layer) { requested.add(layer); return super.bakeLayer(layer); }
    }
}
