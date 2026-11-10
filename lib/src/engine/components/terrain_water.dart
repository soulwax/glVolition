part of '../../engine.dart';

/// Procedural island/heightfield terrain component wrapping pixeldart's
/// [TerrainGenerator] (E5-3).
final class TerrainComponent extends Component {
  final TerrainGenerator generator;
  final double roughness;
  final double metallic;
  final int biomeTextureSize;

  MeshData? _meshData;
  MeshHandle? _mesh;
  TextureHandle? _biomeTex;
  MaterialHandle? _material;
  SceneNode? _leaf;

  TerrainComponent(
    this.generator, {
    this.roughness = 0.92,
    this.metallic = 0.0,
    this.biomeTextureSize = 256,
  });

  MeshData get meshData => _meshData ??= generator.generateMesh();

  double sampleHeight(double x, double z) => generator.sampleHeight(x, z);
  Vec3 sampleNormal(double x, double z) => generator.sampleNormal(x, z);
  double sampleSlope(double x, double z) => generator.sampleSlope(x, z);

  @override
  void _onEnableInternal() {
    if (_leaf == null) {
      final g = engine.graphics;
      final data = meshData;
      _mesh = g.createMesh(data, debugLabel: '${gameObject.name}#terrain');
      final pixels = generator.generateBiomeTexture(
        width: biomeTextureSize,
        height: biomeTextureSize,
      );
      _biomeTex = g.createTexture(
        width: biomeTextureSize,
        height: biomeTextureSize,
        pixels: pixels,
        hasMips: true,
        minFilter: GpuTextureFilter.linearMipmapLinear,
        magFilter: GpuTextureFilter.linear,
        wrap: GpuTextureWrap.repeat,
        debugLabel: '${gameObject.name}#biome',
      );
      _material = g.createMaterial(
        MaterialDefinition(
          key: '${gameObject.name}#terrain_mat',
          albedoTexture: _biomeTex,
          roughness: roughness,
          metallic: metallic,
        ),
      );
      _leaf = gameObject.node.add(
        name: '${gameObject.name}#terrain_node',
        mesh: _mesh,
        meshData: data,
        bounds: data.bounds,
        material: _material,
      );
    }
    _leaf?.visible = true;
  }

  @override
  void _onDisableInternal() => _leaf?.visible = false;

  @override
  void _onDestroyInternal() {
    _leaf?.removeFromParent();
    _leaf = null;
  }
}

/// CPU-deformed Gerstner wave surface component wrapping [WaterSurfaceMesh]
/// and [GerstnerWaveEvaluator] (E5-3).
final class WaterSurfaceComponent extends Behaviour {
  final WaterSurfaceMesh surface;
  GerstnerWaveEvaluator waves;
  final MaterialDefinition materialDefinition;

  MeshHandle? _mesh;
  MaterialHandle? _material;
  SceneNode? _leaf;

  WaterSurfaceComponent({
    required this.surface,
    required this.waves,
    this.materialDefinition = const MaterialDefinition(
      key: 'ocean',
      tintR: 0.05,
      tintG: 0.22,
      tintB: 0.36,
      roughness: 0.1,
      metallic: 0.35,
      clearcoatStrength: 0.9,
      clearcoatRoughness: 0.06,
    ),
  });

  @override
  void _onEnableInternal() {
    scene._waters.add(this);
    if (_leaf == null) {
      final g = engine.graphics;
      _mesh = g.createMesh(surface.mesh, debugLabel: '${gameObject.name}#water');
      _material = g.createMaterial(materialDefinition);
      _leaf = gameObject.node.add(
        name: '${gameObject.name}#water_node',
        mesh: _mesh,
        meshData: surface.mesh,
        bounds: surface.mesh.bounds,
        material: _material,
        receivesShadow: true,
      );
    }
    _leaf?.visible = true;
  }

  @override
  void _onDisableInternal() {
    scene._waters.remove(this);
    _leaf?.visible = false;
  }

  @override
  void update() {
    surface.updateWaves(time.time, waves);
  }

  @override
  void _onDestroyInternal() {
    _leaf?.removeFromParent();
    _leaf = null;
  }
}

/// Four-probe buoyant hull behaviour wrapping [BuoyantVesselBody] over the
/// scene's active [WaterSurfaceComponent] (or an explicit [waveEvaluator]) (E5-3).
final class BuoyantBody extends Behaviour {
  final BuoyantVesselBody vessel;
  GerstnerWaveEvaluator? waveEvaluator;

  BuoyantBody({
    double width = 1.8,
    double length = 3.2,
    double mass = 1.0,
    double linearDamping = 4.5,
    double angularDamping = 6.0,
    double rightingStiffness = 14.0,
    double yaw = 0.0,
    this.waveEvaluator,
  }) : vessel = BuoyantVesselBody(
          position: Vec3.zero,
          width: width,
          length: length,
          mass: mass,
          linearDamping: linearDamping,
          angularDamping: angularDamping,
          rightingStiffness: rightingStiffness,
          yaw: yaw,
        );

  double get yaw => vessel.yaw;
  set yaw(double value) => vessel.yaw = value;

  double get roll => vessel.roll;
  double get pitch => vessel.pitch;

  @override
  void update() {
    final waves = waveEvaluator ?? scene._waters.lastOrNull?.waves;
    if (waves == null) return;
    final pos = transform.localPosition;
    vessel.position = Vec3(pos.x, vessel.position.y, pos.z);
    final next = vessel.update(time.deltaTime, time.time, waves);
    transform
      ..localPosition = next.translation
      ..localRotation = next.rotation;
  }
}
