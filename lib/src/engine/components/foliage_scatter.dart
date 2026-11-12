part of '../../engine.dart';

/// Procedural foliage scattering, distance cluster LOD culling & harmonic wind sway component (`voxfoliage`) (E63-2).
final class FoliageScatterComponent extends Behaviour {
  int seed;
  double originX;
  double originZ;
  double areaWidth;
  double areaDepth;
  double clusterCellSize;
  double lodFullDistance;
  double lodMidDistance;
  double maxDrawDistance;
  double windSpeed;
  double gustStrength;
  Vec3 windDirection;
  bool animateWind;
  bool scatterOnStart;

  MeshData? foliageMeshData;
  MaterialDefinition? foliageMaterialDefinition;

  final List<foliage.FoliageSpeciesDef> speciesList = [];
  final List<foliage.FoliageInstance> allInstances = [];
  foliage.FoliageClusterGrid? _clusterGrid;
  foliage.WindSwayInstanceBuffer? _windBuffer;
  foliage.FoliageVisibleBatch? lastVisibleBatch;
  InstancedMeshRenderer? _renderer;

  FoliageScatterComponent({
    this.seed = 2026,
    this.originX = -32.0,
    this.originZ = -32.0,
    this.areaWidth = 64.0,
    this.areaDepth = 64.0,
    this.clusterCellSize = 16.0,
    this.lodFullDistance = 24.0,
    this.lodMidDistance = 52.0,
    this.maxDrawDistance = 96.0,
    this.windSpeed = 3.5,
    this.gustStrength = 0.35,
    this.windDirection = const Vec3(1.0, 0.0, 0.35),
    this.animateWind = true,
    this.scatterOnStart = false,
    this.foliageMeshData,
    this.foliageMaterialDefinition,
  });

  static final spec = ComponentSpec<FoliageScatterComponent>(
    'FoliageScatterComponent',
    FoliageScatterComponent.new,
    [
      Field.integer('seed', (f) => f.seed, (f, v) => f.seed = v),
      Field.number('originX', (f) => f.originX, (f, v) => f.originX = v),
      Field.number('originZ', (f) => f.originZ, (f, v) => f.originZ = v),
      Field.number('areaWidth', (f) => f.areaWidth, (f, v) => f.areaWidth = v),
      Field.number('areaDepth', (f) => f.areaDepth, (f, v) => f.areaDepth = v),
      Field.number('clusterCellSize', (f) => f.clusterCellSize, (f, v) => f.clusterCellSize = v),
      Field.number('lodFullDistance', (f) => f.lodFullDistance, (f, v) => f.lodFullDistance = v),
      Field.number('lodMidDistance', (f) => f.lodMidDistance, (f, v) => f.lodMidDistance = v),
      Field.number('maxDrawDistance', (f) => f.maxDrawDistance, (f, v) => f.maxDrawDistance = v),
      Field.number('windSpeed', (f) => f.windSpeed, (f, v) => f.windSpeed = v),
      Field.number('gustStrength', (f) => f.gustStrength, (f, v) => f.gustStrength = v),
      Field.vec3('windDirection', (f) => f.windDirection, (f, v) => f.windDirection = v),
      Field.boolean('animateWind', (f) => f.animateWind, (f, v) => f.animateWind = v),
    ],
  );

  foliage.FoliageClusterGrid _ensureGrid() =>
      _clusterGrid ??= foliage.FoliageClusterGrid(cellSize: math.max(1.0, clusterCellSize));

  foliage.WindSwayInstanceBuffer _ensureWindBuffer() {
    final wb = _windBuffer ??= foliage.WindSwayInstanceBuffer(
      windSpeed: windSpeed,
      gustStrength: gustStrength,
      windDirection: foliage.FoliageVec2(windDirection.x, windDirection.z),
    );
    wb.windSpeed = windSpeed;
    wb.gustStrength = gustStrength;
    wb.windDirection = foliage.FoliageVec2(windDirection.x, windDirection.z).normalized;
    return wb;
  }

  int get totalScatteredCount => allInstances.length;
  int get visibleCount => lastVisibleBatch?.visibleInstances.length ?? 0;
  int get activeClusterCount => lastVisibleBatch?.activeClusterCount ?? 0;
  int get totalClusterCount => _ensureGrid().clusterCount;
  List<foliage.FoliageSwayPose> get lastSwayPoses => _ensureWindBuffer().poses;
  InstancedMeshRenderer? get instancedRenderer => _renderer;

  void addSpecies(foliage.FoliageSpeciesDef species) {
    speciesList.add(species);
  }

  void clearFoliage() {
    allInstances.clear();
    _ensureGrid().rebuild(const []);
    lastVisibleBatch = null;
    _renderer?.clearInstances();
  }

  /// Generates Poisson-disk foliage instances across `[originX, originX + areaWidth) x [originZ, originZ + areaDepth)`
  /// sampling heights from [heightSampler] or an attached/scene [TerrainComponent].
  int scatter({
    double Function(double x, double z)? heightSampler,
    double Function(double x, double z)? slopeDegreesSampler,
    double Function(double x, double z)? densityMaskSampler,
    bool Function(double x, double z)? exclusionPredicate,
    int maxSamplesPerSpecies = 4000,
    Vec3? cameraPosition,
  }) {
    if (speciesList.isEmpty) {
      speciesList.add(
        const foliage.FoliageSpeciesDef(
          id: 'default_pine',
          name: 'Default Pine',
          minSpacing: 3.5,
          minScale: 0.85,
          maxScale: 1.35,
          maxSlopeDegrees: 32.0,
        ),
      );
    }

    TerrainComponent? sceneTerrain;
    if (heightSampler == null && isAttached) {
      final terrains = scene.findObjectsOfType<TerrainComponent>();
      if (terrains.isNotEmpty) sceneTerrain = terrains.first;
    }

    double sampleY(double x, double z) {
      if (heightSampler != null) return heightSampler(x, z);
      if (sceneTerrain != null) return sceneTerrain.sampleHeight(x, z);
      return 0.0;
    }

    double sampleSlope(double x, double z) {
      if (slopeDegreesSampler != null) return slopeDegreesSampler(x, z);
      if (sceneTerrain != null) return sceneTerrain.sampleSlope(x, z);
      const eps = 0.5;
      final dx = (sampleY(x + eps, z) - sampleY(x - eps, z)) / (2.0 * eps);
      final dz = (sampleY(x, z + eps) - sampleY(x, z - eps)) / (2.0 * eps);
      return math.atan(math.sqrt(dx * dx + dz * dz)) * 180.0 / math.pi;
    }

    final scatterer = foliage.FoliageBiomeScatterer(
      originX: originX,
      originZ: originZ,
      width: areaWidth,
      depth: areaDepth,
    );

    allInstances.clear();
    for (var sIdx = 0; sIdx < speciesList.length; sIdx++) {
      final sp = speciesList[sIdx];
      final generated = scatterer.scatter(
        species: sp,
        heightSampler: sampleY,
        slopeDegreesSampler: sampleSlope,
        densityMaskSampler: densityMaskSampler,
        exclusionPredicate: exclusionPredicate,
        seed: seed + sIdx * 997,
        maxSamples: maxSamplesPerSpecies,
      );
      allInstances.addAll(generated);
    }

    _clusterGrid = foliage.FoliageClusterGrid(cellSize: math.max(1.0, clusterCellSize))
      ..rebuild(allInstances);

    _ensureRenderer();
    updateVisibility(cameraPosition: cameraPosition, dt: 0.0);
    return allInstances.length;
  }

  void _ensureRenderer() {
    if (!isAttached) return;
    _renderer ??= gameObject.getComponent<InstancedMeshRenderer>();
    if (_renderer == null) {
      final mesh = foliageMeshData ??
          Primitives.cone(radius: 0.45, height: 1.5, radialSegments: 8);
      final mat = foliageMaterialDefinition ??
          MaterialDefinition.dielectric(
            key: '${gameObject.name}#foliageMat',
            color: const LinearColor(0.18, 0.48, 0.2),
          );
      _renderer = gameObject.addComponent(
        InstancedMeshRenderer(
          meshData: mesh,
          materialDefinition: mat,
          castsShadow: true,
        ),
      );
    }
  }

  /// Culls spatial foliage clusters against [cameraPosition] and evaluates wind bend poses.
  foliage.FoliageVisibleBatch updateVisibility({
    Vec3? cameraPosition,
    double dt = 0.0,
  }) {
    final camPos = cameraPosition ??
        (isAttached ? scene.findObjectOfType<Camera>()?.transform.position : null) ??
        Vec3.zero;
    final batch = _ensureGrid().queryVisible(
      foliage.FoliageVec3(camPos.x, camPos.y, camPos.z),
      lodFullDistance: lodFullDistance,
      lodMidDistance: lodMidDistance,
      maxDrawDistance: maxDrawDistance,
    );
    lastVisibleBatch = batch;

    final wb = _ensureWindBuffer();
    if (animateWind && dt > 0.0) {
      wb.advance(dt);
    }
    final poses = wb.evaluate(batch.visibleInstances);

    final renderer = _renderer;
    if (renderer != null) {
      final transforms = <Transform>[];
      for (final pose in poses) {
        final inst = pose.instance;
        final rot = Quat.axisAngle(Vec3.unitY, pose.animatedYawRadians) *
            Quat.axisAngle(Vec3.unitX, pose.bendXRadians) *
            Quat.axisAngle(Vec3.unitZ, pose.bendZRadians);
        transforms.add(
          Transform(
            translation: Vec3(inst.position.x, inst.position.y + inst.scale * 0.65, inst.position.z),
            rotation: rot,
            scale: inst.scale,
          ),
        );
      }
      renderer.setTransforms(transforms);
    }
    return batch;
  }

  @override
  void start() {
    if (scatterOnStart && allInstances.isEmpty) {
      scatter();
    }
  }

  @override
  void update() {
    if (allInstances.isEmpty) return;
    updateVisibility(dt: time.deltaTime);
  }
}

/// Persistent UI interaction state for [FoliageInspectorUI.render].
final class FoliageInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` foliage density, LOD culling & wind sway inspector (E63-2).
final class FoliageInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    FoliageInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    FoliageScatterComponent foliageComp, {
    FoliageInspectorUiState? state,
    String title = 'Foliage & Wind Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? FoliageInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Visible / Total',
      '${foliageComp.visibleCount} / ${foliageComp.totalScatteredCount}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Active Clusters',
      '${foliageComp.activeClusterCount} / ${foliageComp.totalClusterCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Wind / Gust',
      '${foliageComp.windSpeed.toStringAsFixed(1)} m/s (${foliageComp.gustStrength.toStringAsFixed(2)})',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'LOD Full / Max',
      '${foliageComp.lodFullDistance.toStringAsFixed(0)}m / ${foliageComp.maxDrawDistance.toStringAsFixed(0)}m',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final rescatterRect = VoxRect(x + pad, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'fol_scatter', 'Rescatter', rescatterRect)) {
      foliageComp.seed++;
      foliageComp.scatter();
    }

    final gustRect = VoxRect(rescatterRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'fol_gust', 'Gust +2', gustRect)) {
      foliageComp.windSpeed = math.min(20.0, foliageComp.windSpeed + 2.0);
      foliageComp.updateVisibility(dt: 0.05);
    }

    final calmRect = VoxRect(gustRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'fol_calm', 'Calm', calmRect)) {
      foliageComp.windSpeed = 0.0;
      foliageComp.updateVisibility(dt: 0.05);
    }

    ui.endWindow();
  }
}
