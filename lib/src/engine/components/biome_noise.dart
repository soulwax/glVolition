part of '../../engine.dart';

/// Deterministic multi-biome terrain synthesizer using `voxbiome` noise graphs,
/// hydraulic droplet & thermal talus erosion, and splatmap generation (E55-2).
final class BiomeTerrainGeneratorComponent extends Component {
  int seed;
  int gridWidth;
  int gridHeight;
  double worldWidth;
  double worldDepth;
  double amplitude;
  double baseOffset;
  double frequency;
  int octaves;
  double warpStrength;
  double islandFalloffRadius;
  double seaLevel;
  int initialErosionDroplets;
  int initialThermalIterations;
  double roughness;
  double metallic;
  bool autoCreateMeshRenderer;

  biome.NoiseNode? customNoiseNode;
  biome.BiomeSplatClassifier? customClassifier;

  biome.TerrainHeightGrid? _grid;
  biome.DropletErosionStats? _lastErosionStats;
  double _lastThermalMovedVolume = 0.0;
  Uint8List? _albedoPixels;
  Uint8List? _splatMaskPixels;

  MeshData? _currentMeshData;
  MeshHandle? _dynamicMeshHandle;
  TextureHandle? _dynamicAlbedoTex;
  MaterialHandle? _dynamicMaterial;

  BiomeTerrainGeneratorComponent({
    this.seed = 1337,
    this.gridWidth = 32,
    this.gridHeight = 32,
    this.worldWidth = 32.0,
    this.worldDepth = 32.0,
    this.amplitude = 7.5,
    this.baseOffset = -0.5,
    this.frequency = 0.075,
    this.octaves = 4,
    this.warpStrength = 2.5,
    this.islandFalloffRadius = 0.0,
    this.seaLevel = 0.0,
    this.initialErosionDroplets = 250,
    this.initialThermalIterations = 4,
    this.roughness = 0.9,
    this.metallic = 0.0,
    this.autoCreateMeshRenderer = true,
    this.customNoiseNode,
    this.customClassifier,
  });

  static final spec = ComponentSpec<BiomeTerrainGeneratorComponent>(
    'BiomeTerrainGeneratorComponent',
    BiomeTerrainGeneratorComponent.new,
    [
      Field.integer('seed', (b) => b.seed, (b, v) => b.seed = v),
      Field.integer('gridWidth', (b) => b.gridWidth, (b, v) => b.gridWidth = v),
      Field.integer('gridHeight', (b) => b.gridHeight, (b, v) => b.gridHeight = v),
      Field.number('worldWidth', (b) => b.worldWidth, (b, v) => b.worldWidth = v),
      Field.number('worldDepth', (b) => b.worldDepth, (b, v) => b.worldDepth = v),
      Field.number('amplitude', (b) => b.amplitude, (b, v) => b.amplitude = v),
      Field.number('frequency', (b) => b.frequency, (b, v) => b.frequency = v),
      Field.integer('octaves', (b) => b.octaves, (b, v) => b.octaves = v),
      Field.number('seaLevel', (b) => b.seaLevel, (b, v) => b.seaLevel = v),
      Field.integer(
        'initialErosionDroplets',
        (b) => b.initialErosionDroplets,
        (b, v) => b.initialErosionDroplets = v,
      ),
    ],
  );

  biome.TerrainHeightGrid? get grid => _grid;
  biome.DropletErosionStats? get lastErosionStats => _lastErosionStats;
  double get lastThermalMovedVolume => _lastThermalMovedVolume;
  Uint8List? get albedoPixels => _albedoPixels;
  Uint8List? get splatMaskPixels => _splatMaskPixels;
  MeshData? get currentMeshData => _currentMeshData;
  MaterialHandle? get currentMaterial => _dynamicMaterial;
  int get vertexCount => _currentMeshData?.vertexCount ?? 0;
  int get triangleCount => (_currentMeshData?.indices?.length ?? 0) ~/ 3;

  biome.NoiseNode resolveNoiseGraph() {
    if (customNoiseNode != null) return customNoiseNode!;
    final rolling = biome.FbmLayer(
      seed: seed,
      octaves: math.max(1, octaves),
      frequency: frequency,
      mode: biome.FractalMode.standard,
    );
    final ridges = biome.FbmLayer(
      seed: seed ^ 0x55aa,
      octaves: math.max(1, octaves - 1),
      frequency: frequency * 1.4,
      mode: biome.FractalMode.ridged,
      amplitude: 0.45,
    );
    final combined = biome.BlendNoiseNode(
      primary: rolling,
      secondary: ridges,
      op: biome.NoiseBlendOp.add,
      factor: 0.55,
    );
    if (warpStrength > 1e-4) {
      return biome.DomainWarpField(
        source: combined,
        seed: seed ^ 0x9933,
        warpStrength: warpStrength,
        warpFrequency: frequency * 0.85,
      );
    }
    return combined;
  }

  biome.BiomeSplatClassifier resolveClassifier() =>
      customClassifier ??
      biome.BiomeSplatClassifier.temperateDefault(
        seaLevel: seaLevel,
        maxElevation: amplitude,
        moistureField: biome.SimplexNoise2D(seed: seed ^ 0x4242, frequency: frequency * 0.9),
      );

  /// Synthesizes heightfield from the noise graph and runs optional erosion & splat bake.
  void regenerate({bool applyErosion = true}) {
    final g = biome.TerrainHeightGrid.fromNoiseNode(
      resolveNoiseGraph(),
      width: math.max(2, gridWidth),
      height: math.max(2, gridHeight),
      worldWidth: worldWidth,
      worldDepth: worldDepth,
      amplitude: amplitude,
      offset: baseOffset,
      islandFalloffRadius: islandFalloffRadius,
    );
    _grid = g;
    _lastErosionStats = null;
    _lastThermalMovedVolume = 0.0;

    if (applyErosion) {
      if (initialErosionDroplets > 0) {
        _lastErosionStats = biome.HydraulicDropletErosion(seed: seed + 17)
            .erode(g, dropletCount: initialErosionDroplets);
      }
      if (initialThermalIterations > 0) {
        _lastThermalMovedVolume = const biome.ThermalTalusSolver()
            .relax(g, iterations: initialThermalIterations);
      }
    }

    _rebuildOutputs();
  }

  /// Applies [dropletCount] additional hydraulic erosion droplets to the active grid.
  biome.DropletErosionStats erodeDroplets({int dropletCount = 250, int? erosionSeed}) {
    if (_grid == null) regenerate(applyErosion: false);
    final g = _grid!;
    final prev = _lastErosionStats;
    final runSeed = erosionSeed ?? (seed + (prev?.dropletsSimulated ?? 0) + 31);
    final delta = biome.HydraulicDropletErosion(seed: runSeed)
        .erode(g, dropletCount: dropletCount);
    _lastErosionStats = biome.DropletErosionStats(
      dropletsSimulated: (prev?.dropletsSimulated ?? 0) + delta.dropletsSimulated,
      totalErodedVolume: (prev?.totalErodedVolume ?? 0.0) + delta.totalErodedVolume,
      totalDepositedVolume:
          (prev?.totalDepositedVolume ?? 0.0) + delta.totalDepositedVolume,
    );
    _rebuildOutputs();
    return delta;
  }

  /// Applies [iterations] additional thermal talus slope relaxation passes.
  double relaxThermal({int iterations = 6}) {
    if (_grid == null) regenerate(applyErosion: false);
    final moved = const biome.ThermalTalusSolver().relax(_grid!, iterations: iterations);
    _lastThermalMovedVolume += moved;
    _rebuildOutputs();
    return moved;
  }

  double sampleHeight(double worldX, double worldZ) {
    if (_grid == null) regenerate();
    return _grid!.sampleWorldHeight(worldX, worldZ);
  }

  Vec3 sampleNormal(double worldX, double worldZ) {
    if (_grid == null) regenerate();
    final n = _grid!.sampleWorldNormal(worldX, worldZ);
    return Vec3(n.x, n.y, n.z);
  }

  biome.BiomeSample classifyAt(double worldX, double worldZ) {
    if (_grid == null) regenerate();
    final g = _grid!;
    final h = g.sampleWorldHeight(worldX, worldZ);
    final slope = g.sampleWorldSlopeRadians(worldX, worldZ);
    final classifier = resolveClassifier();
    final rawM = classifier.moistureField?.sample(worldX, worldZ) ?? 0.5;
    final moisture = rawM < 0.0 ? (rawM * 0.5 + 0.5).clamp(0.0, 1.0) : rawM.clamp(0.0, 1.0);
    return classifier.classifyPoint(h, slope, moisture: moisture);
  }

  void _rebuildOutputs() {
    final g = _grid;
    if (g == null) return;

    final classifier = resolveClassifier();
    _albedoPixels = classifier.generateAlbedoRgba(g);
    _splatMaskPixels = classifier.generateSplatMaskRgba(g);

    final w = g.width;
    final h = g.height;
    final halfW = g.worldWidth * 0.5;
    final halfD = g.worldDepth * 0.5;

    const stride = 14;
    final vertices = Float32List(w * h * stride);
    final indices = <int>[];

    var minY = double.infinity;
    var maxY = -double.infinity;

    for (var iz = 0; iz < h; iz++) {
      final v = iz / (h - 1);
      final wz = -halfD + iz * g.cellSizeZ;
      for (var ix = 0; ix < w; ix++) {
        final u = ix / (w - 1);
        final wx = -halfW + ix * g.cellSizeX;
        final wy = g.at(ix, iz);
        if (wy < minY) minY = wy;
        if (wy > maxY) maxY = wy;

        final hL = g.at(ix - 1, iz);
        final hR = g.at(ix + 1, iz);
        final hD = g.at(ix, iz - 1);
        final hU = g.at(ix, iz + 1);
        final nxRaw = -(hR - hL) / (g.cellSizeX * 2.0);
        const nyRaw = 1.0;
        final nzRaw = -(hU - hD) / (g.cellSizeZ * 2.0);
        final nLen = math.sqrt(nxRaw * nxRaw + nyRaw * nyRaw + nzRaw * nzRaw);

        final pIdx = (iz * w + ix) * 4;
        final cr = _albedoPixels![pIdx] / 255.0;
        final cg = _albedoPixels![pIdx + 1] / 255.0;
        final cb = _albedoPixels![pIdx + 2] / 255.0;

        final base = (iz * w + ix) * stride;
        vertices[base + 0] = wx;
        vertices[base + 1] = wy;
        vertices[base + 2] = wz;
        vertices[base + 3] = nxRaw / nLen;
        vertices[base + 4] = nyRaw / nLen;
        vertices[base + 5] = nzRaw / nLen;
        vertices[base + 6] = cr;
        vertices[base + 7] = cg;
        vertices[base + 8] = cb;
        vertices[base + 9] = 1.0;
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
    _currentMeshData = meshData;

    if (isAttached && scene.isLoaded) {
      final graphics = engine.graphics;
      final nextMesh = graphics.createMesh(
        meshData,
        debugLabel: '${gameObject.name}#biome_terrain',
      );
      final nextTex = graphics.createTexture(
        width: w,
        height: h,
        pixels: _albedoPixels!,
        hasMips: true,
        minFilter: GpuTextureFilter.linearMipmapLinear,
        magFilter: GpuTextureFilter.linear,
        wrap: GpuTextureWrap.clampToEdge,
        debugLabel: '${gameObject.name}#biome_albedo',
      );
      final nextMat = graphics.createMaterial(
        MaterialDefinition(
          key: '${gameObject.name}#biome_mat_${_lastErosionStats?.dropletsSimulated ?? 0}',
          albedoTexture: nextTex,
          roughness: roughness,
          metallic: metallic,
        ),
      );

      final oldMesh = _dynamicMeshHandle;
      final oldTex = _dynamicAlbedoTex;
      _dynamicMeshHandle = nextMesh;
      _dynamicAlbedoTex = nextTex;
      _dynamicMaterial = nextMat;

      var mr = getComponent<MeshRenderer>();
      if (mr == null && autoCreateMeshRenderer) {
        mr = gameObject.addComponent(
          MeshRenderer(
            mesh: nextMesh,
            meshData: meshData,
            material: nextMat,
          ),
        );
      } else if (mr != null) {
        mr.mesh = nextMesh;
        mr.material = nextMat;
        mr._leaf?.meshData = meshData;
        mr._leaf?.bounds = meshData.bounds;
      }

      if (oldMesh != null) graphics.releaseMesh(oldMesh);
      if (oldTex != null) graphics.releaseTexture(oldTex);
    }
  }

  @override
  void onEnable() {
    if (_grid == null) regenerate();
  }

  @override
  void onDestroy() {
    if (isAttached && scene.isLoaded) {
      if (_dynamicMeshHandle != null) {
        engine.graphics.releaseMesh(_dynamicMeshHandle!);
        _dynamicMeshHandle = null;
      }
      if (_dynamicAlbedoTex != null) {
        engine.graphics.releaseTexture(_dynamicAlbedoTex!);
        _dynamicAlbedoTex = null;
      }
      _dynamicMaterial = null;
    }
  }
}

/// Persistent UI interaction state for [NoiseErosionUI.render].
final class NoiseErosionUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` telemetry and interactive erosion workbench (E55-2).
final class NoiseErosionUI {
  static bool _drawButton(
    VoxUiContext ui,
    NoiseErosionUiState state,
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
    BiomeTerrainGeneratorComponent terrain, {
    NoiseErosionUiState? state,
    String title = 'Biome Noise & Erosion',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? NoiseErosionUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final g = terrain.grid;
    final stats = terrain.lastErosionStats;
    final minH = g != null ? g.minHeight.toStringAsFixed(2) : '--';
    final maxH = g != null ? g.maxHeight.toStringAsFixed(2) : '--';

    ui.labelValue(
      'Seed / Grid',
      '${terrain.seed} / ${terrain.gridWidth}x${terrain.gridHeight}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Elevation Range',
      '${minH}m .. ${maxH}m',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Droplets / Eroded',
      '${stats?.dropletsSimulated ?? 0} / ${(stats?.totalErodedVolume ?? 0.0).toStringAsFixed(2)}',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Thermal Moved',
      terrain.lastThermalMovedVolume.toStringAsFixed(2),
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final erodeRect = VoxRect(x + pad, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'biome_erode', 'Erode +250', erodeRect)) {
      terrain.erodeDroplets(dropletCount: 250);
    }

    final thermalRect = VoxRect(erodeRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'biome_thermal', 'Thermal', thermalRect)) {
      terrain.relaxThermal(iterations: 6);
    }

    final regenRect = VoxRect(thermalRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'biome_regen', 'Regenerate', regenRect)) {
      terrain.regenerate();
    }

    ui.endWindow();
  }
}
