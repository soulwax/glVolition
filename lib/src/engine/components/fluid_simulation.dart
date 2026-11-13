part of '../../engine.dart';

/// Coupled Eulerian shallow-water heightfield waves & cellular fire/smoke grid (`voxfluid`) (E67-2).
final class FluidSurfaceComponent extends Behaviour {
  int gridWidth;
  int gridDepth;
  double cellSize;
  double timeScale;
  bool paused;
  bool autoSyncTerrain;
  double waterEvaporation;
  double windX;
  double windZ;
  bool generateMesh;

  fluid.ShallowWaterGrid? _water;
  fluid.CellularFireGrid? _fire;
  bool _terrainSynced = false;
  MeshData? _waterMeshData;
  MeshHandle? _waterMeshHandle;
  MaterialHandle? _waterMaterial;

  FluidSurfaceComponent({
    this.gridWidth = 16,
    this.gridDepth = 16,
    this.cellSize = 1.0,
    this.timeScale = 1.0,
    this.paused = false,
    this.autoSyncTerrain = true,
    this.waterEvaporation = 0.0,
    this.windX = 0.0,
    this.windZ = 0.0,
    this.generateMesh = false,
  });

  static final spec = ComponentSpec<FluidSurfaceComponent>(
    'FluidSurfaceComponent',
    FluidSurfaceComponent.new,
    [
      Field.integer('gridWidth', (f) => f.gridWidth, (f, v) => f.gridWidth = v),
      Field.integer('gridDepth', (f) => f.gridDepth, (f, v) => f.gridDepth = v),
      Field.number('cellSize', (f) => f.cellSize, (f, v) => f.cellSize = v),
      Field.number('timeScale', (f) => f.timeScale, (f, v) => f.timeScale = v),
      Field.boolean('paused', (f) => f.paused, (f, v) => f.paused = v),
      Field.boolean(
        'autoSyncTerrain',
        (f) => f.autoSyncTerrain,
        (f, v) => f.autoSyncTerrain = v,
      ),
      Field.number(
        'waterEvaporation',
        (f) => f.waterEvaporation,
        (f, v) => f.waterEvaporation = v,
      ),
      Field.number('windX', (f) => f.windX, (f, v) => f.windX = v),
      Field.number('windZ', (f) => f.windZ, (f, v) => f.windZ = v),
      Field.boolean(
        'generateMesh',
        (f) => f.generateMesh,
        (f, v) => f.generateMesh = v,
      ),
    ],
  );

  fluid.ShallowWaterGrid get water {
    final w = _water ??= fluid.ShallowWaterGrid(
      math.max(2, gridWidth),
      math.max(2, gridDepth),
      cellSize: math.max(0.1, cellSize),
      evaporationRate: math.max(0.0, waterEvaporation),
    );
    w.evaporationRate = math.max(0.0, waterEvaporation);
    if (autoSyncTerrain && !_terrainSynced) {
      syncFromSceneTerrain();
    }
    return w;
  }

  fluid.CellularFireGrid get fire {
    final f = _fire ??= fluid.CellularFireGrid(
      math.max(2, gridWidth),
      math.max(2, gridDepth),
      cellSize: math.max(0.1, cellSize),
      windX: windX,
      windZ: windZ,
    )..fillFuelUniform(1.0);
    f.windX = windX;
    f.windZ = windZ;
    return f;
  }

  double get totalWaterVolume => water.totalWaterVolume;
  int get floodedCellCount => water.floodedCellCount;
  int get burningCellCount => fire.burningCellCount;
  double get totalSmoke => fire.totalSmoke;
  MeshData? get currentWaterMeshData => _waterMeshData;

  void syncFromSceneTerrain() {
    _terrainSynced = true;
    if (!isAttached) return;
    final terrains = scene.findObjectsOfType<TerrainComponent>();
    final w = _water;
    if (terrains.isEmpty || w == null) return;
    final terrain = terrains.first;
    final originX = transform.position.x - (w.width - 1) * w.cellSize * 0.5;
    final originZ = transform.position.z - (w.height - 1) * w.cellSize * 0.5;
    w.fillTerrainFromSampler(
      terrain.sampleHeight,
      originX: originX,
      originZ: originZ,
    );
  }

  void addWaterVolume(int x, int z, double cubicMeters) {
    water.addWaterVolume(x, z, cubicMeters);
    if (generateMesh) rebuildWaterMesh();
  }

  void addWaterDepth(int x, int z, double depthMeters) {
    water.addWaterDepth(x, z, depthMeters);
    if (generateMesh) rebuildWaterMesh();
  }

  void fillFireFuelUniform(double fuel, {double moisture = 0.0}) {
    fire.fillFuelUniform(fuel, moisture: moisture);
  }

  void igniteFire(int x, int z, {double heat = 2.2}) {
    fire.ignite(x, z, heat: heat);
  }

  void extinguishRadius(
    int cx,
    int cz,
    double radiusCells, {
    double waterStrength = 1.5,
  }) {
    fire.extinguishRadius(cx, cz, radiusCells, waterStrength: waterStrength);
  }

  void stepSimulation(double dt) {
    if (dt <= 0.0) return;
    final w = water;
    final f = fire;
    w.step(dt);
    f.step(dt);

    // Couple shallow water onto active fire cells: surface depth > 2cm quenches fire.
    for (var z = 0; z < f.height && z < w.height; z++) {
      for (var x = 0; x < f.width && x < w.width; x++) {
        if (w.waterDepthAt(x, z) > 0.02) {
          f.quenchCell(x, z, moistureAdd: 1.0);
        }
      }
    }

    if (generateMesh) rebuildWaterMesh();
  }

  MeshData rebuildWaterMesh() {
    final wGrid = water;
    final w = wGrid.width;
    final h = wGrid.height;
    final halfW = (w - 1) * wGrid.cellSize * 0.5;
    final halfD = (h - 1) * wGrid.cellSize * 0.5;

    const stride = 14;
    final vertices = Float32List(w * h * stride);
    final indices = <int>[];
    var minY = double.infinity;
    var maxY = -double.infinity;

    for (var iz = 0; iz < h; iz++) {
      final v = iz / math.max(1, h - 1);
      final wz = -halfD + iz * wGrid.cellSize;
      for (var ix = 0; ix < w; ix++) {
        final u = ix / math.max(1, w - 1);
        final wx = -halfW + ix * wGrid.cellSize;
        final wy = wGrid.surfaceHeightAt(ix, iz);
        if (wy < minY) minY = wy;
        if (wy > maxY) maxY = wy;

        final hL = wGrid.surfaceHeightAt(math.max(0, ix - 1), iz);
        final hR = wGrid.surfaceHeightAt(math.min(w - 1, ix + 1), iz);
        final hD = wGrid.surfaceHeightAt(ix, math.max(0, iz - 1));
        final hU = wGrid.surfaceHeightAt(ix, math.min(h - 1, iz + 1));
        final nxRaw = -(hR - hL) / (wGrid.cellSize * 2.0);
        const nyRaw = 1.0;
        final nzRaw = -(hU - hD) / (wGrid.cellSize * 2.0);
        final nLen = math.sqrt(nxRaw * nxRaw + nyRaw * nyRaw + nzRaw * nzRaw);

        final depth = wGrid.waterDepthAt(ix, iz);
        final base = (iz * w + ix) * stride;
        vertices[base + 0] = wx;
        vertices[base + 1] = wy;
        vertices[base + 2] = wz;
        vertices[base + 3] = nxRaw / nLen;
        vertices[base + 4] = nyRaw / nLen;
        vertices[base + 5] = nzRaw / nLen;
        vertices[base + 6] = 0.08;
        vertices[base + 7] = depth > 0.02 ? 0.45 : 0.15;
        vertices[base + 8] = depth > 0.02 ? 0.85 : 0.25;
        vertices[base + 9] = depth > 0.005 ? 0.88 : 0.15;
        vertices[base + 10] = 1.0;
        vertices[base + 11] = u;
        vertices[base + 12] = v;
        vertices[base + 13] = 0.0;
      }
    }

    for (var iz = 0; iz < h - 1; iz++) {
      for (var ix = 0; ix < w - 1; ix++) {
        final i00 = iz * w + ix;
        final i01 = (iz + 1) * w + ix;
        final i11 = (iz + 1) * w + (ix + 1);
        final i10 = iz * w + (ix + 1);
        indices.addAll([i00, i01, i11, i00, i11, i10]);
      }
    }

    final meshData = MeshData(
      layout: VertexLayoutDescriptor.compatibility14,
      vertices: vertices,
      indices: Uint32List.fromList(indices),
      localBounds: Aabb(
        Vec3(-halfW, minY - 0.05, -halfD),
        Vec3(halfW, maxY + 0.05, halfD),
      ),
    );
    _waterMeshData = meshData;

    if (isAttached && scene.isLoaded) {
      final graphics = engine.graphics;
      final nextMesh = graphics.createMesh(
        meshData,
        debugLabel: '${gameObject.name}#fluid_water',
      );
      _waterMaterial ??= graphics.createMaterial(
        MaterialDefinition(
          key: '${gameObject.name}#fluid_mat',
          tintR: 0.12,
          tintG: 0.55,
          tintB: 0.9,
          roughness: 0.12,
          metallic: 0.15,
        ),
      );
      final oldMesh = _waterMeshHandle;
      _waterMeshHandle = nextMesh;

      var mr = getComponent<MeshRenderer>();
      if (mr == null) {
        gameObject.addComponent(
          MeshRenderer(
            mesh: nextMesh,
            meshData: meshData,
            material: _waterMaterial,
          ),
        );
      } else {
        mr.mesh = nextMesh;
        mr.material = _waterMaterial;
        mr._leaf?.meshData = meshData;
        mr._leaf?.bounds = meshData.bounds;
      }
      if (oldMesh != null) graphics.releaseMesh(oldMesh);
    }

    return meshData;
  }

  @override
  void update() {
    if (paused) return;
    final dt = time.deltaTime * math.max(0.0, timeScale);
    if (dt > 0.0) {
      stepSimulation(dt);
    }
  }

  @override
  void onDestroy() {
    if (isAttached && scene.isLoaded && _waterMeshHandle != null) {
      engine.graphics.releaseMesh(_waterMeshHandle!);
      _waterMeshHandle = null;
    }
    _waterMaterial = null;
  }
}

/// Persistent UI interaction state for [FluidInspectorUI.render].
final class FluidInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` shallow-water & cellular fire grid monitor (E67-2).
final class FluidInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    FluidInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
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
    FluidSurfaceComponent fluidSim, {
    FluidInspectorUiState? state,
    String title = 'Fluid & Fire Grid',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? FluidInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Flooded Cells',
      '${fluidSim.floodedCellCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Water Volume',
      '${fluidSim.totalWaterVolume.toStringAsFixed(2)} m3',
      valueColor: VoxColor.blue,
    );
    ui.labelValue(
      'Burning / Smoke',
      '${fluidSim.burningCellCount} / ${fluidSim.totalSmoke.toStringAsFixed(1)}',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'State',
      fluidSim.paused ? 'PAUSED' : 'ACTIVE',
      valueColor: fluidSim.paused ? VoxColor.red : VoxColor.green,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final rainRect = VoxRect(x + pad, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'fld_rain', 'Rain +2m3', rainRect)) {
      fluidSim.addWaterVolume(
        fluidSim.gridWidth ~/ 2,
        fluidSim.gridDepth ~/ 2,
        2.0,
      );
    }

    final fireRect = VoxRect(rainRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'fld_fire', 'Ignite', fireRect)) {
      fluidSim.igniteFire(
        fluidSim.gridWidth ~/ 2,
        fluidSim.gridDepth ~/ 2,
        heat: 2.4,
      );
    }

    final pauseRect = VoxRect(fireRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'fld_pause',
      fluidSim.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      fluidSim.paused = !fluidSim.paused;
    }

    ui.endWindow();
  }
}
