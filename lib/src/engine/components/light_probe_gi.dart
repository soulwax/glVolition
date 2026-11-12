part of '../../engine.dart';

/// 3D tetrahedral light-probe Global Illumination volume & L2 SH3 irradiance sampler (`voxprobe`) (E68-2).
final class LightProbeVolumeComponent extends Behaviour {
  Vec3 minCorner;
  Vec3 maxCorner;
  int nx;
  int ny;
  int nz;
  LinearColor skyColor;
  LinearColor horizonColor;
  LinearColor groundColor;
  bool autoSyncSky;
  bool checkColliderOcclusion;

  /// Optional custom probe interior-wall test returning true when inside solid geometry.
  bool Function(Vec3 worldPos)? occlusionPredicate;

  /// Optional shadow line-of-sight test returning true if geometry blocks `[from, to]`.
  bool Function(Vec3 from, Vec3 to)? shadowRayPredicate;

  probe.TetrahedralProbeGrid? _grid;
  Vec3? _builtOrigin;
  Vec3? _builtMin;
  Vec3? _builtMax;
  int _builtNx = -1;
  int _builtNy = -1;
  int _builtNz = -1;
  int _bakeGeneration = 0;

  LightProbeVolumeComponent({
    this.minCorner = const Vec3(-10.0, 0.0, -10.0),
    this.maxCorner = const Vec3(10.0, 8.0, 10.0),
    this.nx = 4,
    this.ny = 3,
    this.nz = 4,
    this.skyColor = const LinearColor(0.28, 0.42, 0.65),
    this.horizonColor = const LinearColor(0.45, 0.48, 0.52),
    this.groundColor = const LinearColor(0.14, 0.12, 0.1),
    this.autoSyncSky = true,
    this.checkColliderOcclusion = false,
    this.occlusionPredicate,
    this.shadowRayPredicate,
  });

  static final spec = ComponentSpec<LightProbeVolumeComponent>(
    'LightProbeVolumeComponent',
    LightProbeVolumeComponent.new,
    [
      Field.vec3('minCorner', (p) => p.minCorner, (p, v) => p.minCorner = v),
      Field.vec3('maxCorner', (p) => p.maxCorner, (p, v) => p.maxCorner = v),
      Field.integer('nx', (p) => p.nx, (p, v) => p.nx = v),
      Field.integer('ny', (p) => p.ny, (p, v) => p.ny = v),
      Field.integer('nz', (p) => p.nz, (p, v) => p.nz = v),
      Field.color('skyColor', (p) => p.skyColor, (p, v) => p.skyColor = v),
      Field.color('horizonColor', (p) => p.horizonColor, (p, v) => p.horizonColor = v),
      Field.color('groundColor', (p) => p.groundColor, (p, v) => p.groundColor = v),
      Field.boolean('autoSyncSky', (p) => p.autoSyncSky, (p, v) => p.autoSyncSky = v),
      Field.boolean(
        'checkColliderOcclusion',
        (p) => p.checkColliderOcclusion,
        (p, v) => p.checkColliderOcclusion = v,
      ),
    ],
  );

  static probe.ProbeVec3 _toProbeVec3(Vec3 v) => probe.ProbeVec3(v.x, v.y, v.z);

  static probe.ProbeColor3 _toProbeColor(LinearColor c) =>
      probe.ProbeColor3(c.r, c.g, c.b);

  static LinearColor _toLinearColor(probe.ProbeColor3 c) =>
      LinearColor(c.r, c.g, c.b);

  probe.TetrahedralProbeGrid get grid {
    final origin = isAttached ? transform.position : Vec3.zero;
    if (_grid == null ||
        _builtOrigin != origin ||
        _builtMin != minCorner ||
        _builtMax != maxCorner ||
        _builtNx != nx ||
        _builtNy != ny ||
        _builtNz != nz) {
      rebuildGrid();
    }
    return _grid!;
  }

  int get totalProbeCount => grid.probes.length;
  int get activeProbeCount => grid.activeProbeCount;
  int get occludedProbeCount => grid.occludedProbeCount;
  int get bakeGeneration => _bakeGeneration;

  void rebuildGrid() {
    final origin = isAttached ? transform.position : Vec3.zero;
    final worldMin = origin + minCorner;
    final worldMax = origin + maxCorner;
    _builtOrigin = origin;
    _builtMin = minCorner;
    _builtMax = maxCorner;
    _builtNx = nx;
    _builtNy = ny;
    _builtNz = nz;
    _grid = probe.TetrahedralProbeGrid.fromVolume(
      probe.ProbeBakeVolume(
        minCorner: _toProbeVec3(worldMin),
        maxCorner: _toProbeVec3(worldMax),
        nx: math.max(2, nx),
        ny: math.max(2, ny),
        nz: math.max(2, nz),
      ),
    );
  }

  /// Pulls zenith/horizon/ground sky colors from [DayNightSkyComponent] or `renderSettings.skybox`.
  bool syncSkyFromScene() {
    if (!isAttached) return false;
    final dayNights = scene.findObjectsOfType<DayNightSkyComponent>();
    if (dayNights.isNotEmpty) {
      final stop = dayNights.first.lastSkyStop;
      if (stop != null) {
        skyColor = LinearColor(stop.zenithColor.r, stop.zenithColor.g, stop.zenithColor.b);
        horizonColor = LinearColor(
          stop.horizonColor.r,
          stop.horizonColor.g,
          stop.horizonColor.b,
        );
        groundColor = LinearColor(stop.groundColor.r, stop.groundColor.g, stop.groundColor.b);
        return true;
      }
    }
    final skybox = scene.renderSettings.skybox;
    if (skybox != null) {
      skyColor = skybox.zenith;
      horizonColor = skybox.horizon;
      groundColor = skybox.ground;
      return true;
    }
    return false;
  }

  /// Bakes sky hemisphere + all active scene [Light]s into the tetrahedral probe lattice.
  void bakeFromScene() {
    if (autoSyncSky) {
      syncSkyFromScene();
    }
    final inputs = <probe.ProbeLightInput>[];
    if (isAttached) {
      for (final l in scene._lights) {
        if (!l._active || l.intensity <= 0.0) continue;
        switch (l.type) {
          case LightType.directional:
            inputs.add(
              probe.ProbeLightInput.directional(
                directionToLight: _toProbeVec3(-l.transform.forward),
                color: _toProbeColor(l.color),
                intensity: l.intensity,
              ),
            );
          case LightType.point:
            inputs.add(
              probe.ProbeLightInput.point(
                position: _toProbeVec3(l.transform.position),
                color: _toProbeColor(l.color),
                intensity: l.intensity,
                range: l.range,
              ),
            );
          case LightType.spot:
            inputs.add(
              probe.ProbeLightInput.point(
                position: _toProbeVec3(l.transform.position),
                color: _toProbeColor(l.color),
                intensity: l.intensity * 0.75,
                range: l.range,
              ),
            );
        }
      }
    }

    bool Function(probe.ProbeVec3 pos)? occFn;
    if (occlusionPredicate != null || (checkColliderOcclusion && isAttached)) {
      occFn = (p) {
        final wp = Vec3(p.x, p.y, p.z);
        if (occlusionPredicate != null && occlusionPredicate!(wp)) return true;
        if (checkColliderOcclusion && isAttached) {
          return scene.physics.overlapSphere(wp, 0.15, includeTriggers: false).isNotEmpty;
        }
        return false;
      };
    }

    bool Function(probe.ProbeVec3 from, probe.ProbeVec3 to)? rayFn;
    if (shadowRayPredicate != null) {
      rayFn = (a, b) => shadowRayPredicate!(Vec3(a.x, a.y, a.z), Vec3(b.x, b.y, b.z));
    }

    grid.bakeFromLights(
      inputs,
      skyColor: _toProbeColor(skyColor),
      horizonColor: _toProbeColor(horizonColor),
      groundColor: _toProbeColor(groundColor),
      isOccluded: occFn,
      isLineBlocked: rayFn,
    );
    _bakeGeneration++;
  }

  void clearProbes() {
    grid.clear();
  }

  LinearColor sampleIrradiance(Vec3 worldPos, Vec3 normal) =>
      _toLinearColor(grid.sampleIrradiance(_toProbeVec3(worldPos), _toProbeVec3(normal)));

  Float32List sampleUniformSH27(Vec3 worldPos) =>
      grid.sampleAt(_toProbeVec3(worldPos)).toFlatArray27();
}

/// Persistent UI interaction state for [ProbeGiInspectorUI.render].
final class ProbeGiInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` Light Probe GI volume inspector & bake trigger (E68-2).
final class ProbeGiInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ProbeGiInspectorUiState state,
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
    LightProbeVolumeComponent probes, {
    ProbeGiInspectorUiState? state,
    String title = 'Light Probe GI',
    double x = 20.0,
    double y = 20.0,
    double width = 340.0,
    double height = 230.0,
  }) {
    final uiState = state ?? ProbeGiInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Active Probes',
      '${probes.activeProbeCount}/${probes.totalProbeCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Occluded',
      '${probes.occludedProbeCount}',
      valueColor: probes.occludedProbeCount > 0 ? VoxColor.yellow : VoxColor.green,
    );
    ui.labelValue(
      'Bake Pass',
      '#${probes.bakeGeneration}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Grid Lattice',
      '${probes.nx}x${probes.ny}x${probes.nz}',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final bakeRect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'gi_bake', 'Bake GI', bakeRect)) {
      probes.bakeFromScene();
    }

    final skyRect = VoxRect(bakeRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'gi_sky', 'Sync Sky', skyRect)) {
      probes.syncSkyFromScene();
    }

    final clearRect = VoxRect(skyRect.right + 8.0, barY, 68.0, 22.0);
    if (_drawButton(ui, uiState, 'gi_clear', 'Clear', clearRect)) {
      probes.clearProbes();
    }

    ui.endWindow();
  }
}
