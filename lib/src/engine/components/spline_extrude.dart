part of '../../engine.dart';

/// Built-in cross-section preset modes supported by [SplineExtrudeComponent] (E54-2).
enum ExtrudeProfilePreset { road, riverRibbon, circle, boxBeam }

/// Procedurally sweeps a cross-section profile along a sibling or linked [SplinePath]
/// using twist-free Bishop rotation-minimizing frames (or horizon-locked mode for roads),
/// writing the generated [MeshData] to a sibling [MeshRenderer] (E54-2).
final class SplineExtrudeComponent extends Component {
  SplinePath? path;
  ext.CrossSectionProfile? customProfile;
  ExtrudeProfilePreset profilePreset;
  int subdivisionsPerSegment;
  double width;
  double height;
  double radius;
  bool upLocked;
  bool capEnds;
  bool closedLoop;
  double uvScaleU;
  double uvScaleV;
  bool autoCreateMeshRenderer;
  MaterialHandle? material;

  ext.ExtrudedMeshData? _lastExtrudedMesh;
  MeshData? _currentMeshData;
  MeshHandle? _dynamicMeshHandle;
  int _sampleCount = 0;

  SplineExtrudeComponent({
    this.path,
    this.customProfile,
    this.profilePreset = ExtrudeProfilePreset.road,
    this.subdivisionsPerSegment = 10,
    this.width = 6.0,
    this.height = 0.5,
    this.radius = 0.5,
    this.upLocked = true,
    this.capEnds = true,
    this.closedLoop = false,
    this.uvScaleU = 1.0,
    this.uvScaleV = 0.25,
    this.autoCreateMeshRenderer = true,
    this.material,
  });

  static final spec = ComponentSpec<SplineExtrudeComponent>(
    'SplineExtrudeComponent',
    SplineExtrudeComponent.new,
    [
      Field.enumValue<SplineExtrudeComponent, ExtrudeProfilePreset>(
        'profilePreset',
        ExtrudeProfilePreset.values,
        (s) => s.profilePreset,
        (s, v) => s.profilePreset = v,
      ),
      Field.integer(
        'subdivisionsPerSegment',
        (s) => s.subdivisionsPerSegment,
        (s, v) => s.subdivisionsPerSegment = v,
      ),
      Field.number('width', (s) => s.width, (s, v) => s.width = v),
      Field.number('height', (s) => s.height, (s, v) => s.height = v),
      Field.number('radius', (s) => s.radius, (s, v) => s.radius = v),
      Field.boolean('upLocked', (s) => s.upLocked, (s, v) => s.upLocked = v),
      Field.boolean('capEnds', (s) => s.capEnds, (s, v) => s.capEnds = v),
      Field.boolean(
        'closedLoop',
        (s) => s.closedLoop,
        (s, v) => s.closedLoop = v,
      ),
      Field.number('uvScaleU', (s) => s.uvScaleU, (s, v) => s.uvScaleU = v),
      Field.number('uvScaleV', (s) => s.uvScaleV, (s, v) => s.uvScaleV = v),
    ],
  );

  ext.ExtrudedMeshData? get lastExtrudedMesh => _lastExtrudedMesh;
  MeshData? get currentMeshData => _currentMeshData;
  int get sampleCount => _sampleCount;
  int get vertexCount => _lastExtrudedMesh?.vertexCount ?? 0;
  int get triangleCount => _lastExtrudedMesh?.triangleCount ?? 0;
  double get totalArcLength => _lastExtrudedMesh?.totalArcLength ?? 0.0;

  ext.CrossSectionProfile resolveProfile() {
    if (customProfile != null) return customProfile!;
    return switch (profilePreset) {
      ExtrudeProfilePreset.road => ext.CrossSectionProfile.road(width: width),
      ExtrudeProfilePreset.riverRibbon => ext.CrossSectionProfile.riverRibbon(
        width: width,
      ),
      ExtrudeProfilePreset.circle => ext.CrossSectionProfile.circle(
        radius: radius,
      ),
      ExtrudeProfilePreset.boxBeam => ext.CrossSectionProfile.boxBeam(
        width: width,
        height: height,
      ),
    };
  }

  /// Generates extruded geometry from [targetPath] (or sibling/linked [path]) and
  /// uploads the mesh to a sibling [MeshRenderer] when attached to an active [Scene].
  ext.ExtrudedMeshData? rebuildMesh([SplinePath? targetPath]) {
    final activePath =
        targetPath ?? path ?? (isAttached ? getComponent<SplinePath>() : null);
    if (activePath == null) return null;

    final pts = activePath.spline.controlPoints;
    if (pts.length < 2) return null;

    final extPoints = [for (final p in pts) ext.ExtVec3(p.x, p.y, p.z)];
    final samples = ext.ExtrusionResampler.fromCatmullRom(
      extPoints,
      closed: activePath.spline.closed || closedLoop,
      subdivisionsPerSegment: math.max(1, subdivisionsPerSegment),
    );
    _sampleCount = samples.length;

    final built = ext.SplineSweepBuilder.build(
      samples: samples,
      profile: resolveProfile(),
      upLocked: upLocked,
      closedLoop: closedLoop,
      capEnds: capEnds,
      uvScaleU: uvScaleU,
      uvScaleV: uvScaleV,
    );
    _lastExtrudedMesh = built;

    const stride = 14;
    final vCount = built.vertexCount;
    final vertices = Float32List(vCount * stride);
    final invOffset = isAttached ? transform.position : Vec3.zero;

    for (var i = 0; i < vCount; i++) {
      final p = built.positionAt(i);
      final n = built.normalAt(i);
      final uv = built.uvAt(i);
      final base = i * stride;
      vertices[base + 0] = p.x - invOffset.x;
      vertices[base + 1] = p.y - invOffset.y;
      vertices[base + 2] = p.z - invOffset.z;
      vertices[base + 3] = n.x;
      vertices[base + 4] = n.y;
      vertices[base + 5] = n.z;
      vertices[base + 6] = 1.0;
      vertices[base + 7] = 1.0;
      vertices[base + 8] = 1.0;
      vertices[base + 9] = 1.0;
      vertices[base + 10] = 1.0;
      vertices[base + 11] = uv.x;
      vertices[base + 12] = uv.y;
      vertices[base + 13] = 0.0;
    }

    final localMin = Vec3(
      built.boundsMin.x - invOffset.x - 0.02,
      built.boundsMin.y - invOffset.y - 0.02,
      built.boundsMin.z - invOffset.z - 0.02,
    );
    final localMax = Vec3(
      built.boundsMax.x - invOffset.x + 0.02,
      built.boundsMax.y - invOffset.y + 0.02,
      built.boundsMax.z - invOffset.z + 0.02,
    );

    final meshData = MeshData(
      layout: VertexLayoutDescriptor.compatibility14,
      vertices: vertices,
      indices: built.indices,
      localBounds: Aabb(localMin, localMax),
    );
    _currentMeshData = meshData;

    if (isAttached && scene.isLoaded) {
      var mr = getComponent<MeshRenderer>();
      final handle = engine.graphics.createMesh(
        meshData,
        debugLabel: '${gameObject.name}#extrude',
      );
      final oldHandle = _dynamicMeshHandle;
      _dynamicMeshHandle = handle;

      if (mr == null && autoCreateMeshRenderer) {
        mr = gameObject.addComponent(
          MeshRenderer(mesh: handle, meshData: meshData, material: material),
        );
      } else if (mr != null) {
        mr.mesh = handle;
        mr._leaf?.meshData = meshData;
        mr._leaf?.bounds = meshData.bounds;
        if (material != null) mr.material = material;
      }

      if (oldHandle != null) {
        engine.graphics.releaseMesh(oldHandle);
      }
    }

    return built;
  }

  @override
  void onEnable() {
    rebuildMesh();
  }

  @override
  void onDestroy() {
    if (_dynamicMeshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_dynamicMeshHandle!);
      _dynamicMeshHandle = null;
    }
  }
}

/// Persistent UI interaction state for [ExtrusionInspectorUI.render].
final class ExtrusionInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` inspector for [SplineExtrudeComponent] meshes (E54-2).
final class ExtrusionInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ExtrusionInspectorUiState state,
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
    SplineExtrudeComponent extrude, {
    ExtrusionInspectorUiState? state,
    String title = 'Spline Extrude Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? ExtrusionInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Profile / UpLock',
      '${extrude.profilePreset.name} / ${extrude.upLocked ? "ON" : "OFF"}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Vertices / Tris',
      '${extrude.vertexCount} / ${extrude.triangleCount}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Stations / ArcLen',
      '${extrude.sampleCount} / ${extrude.totalArcLength.toStringAsFixed(2)}m',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Cap Ends / Closed',
      '${extrude.capEnds ? "Yes" : "No"} / ${extrude.closedLoop ? "Yes" : "No"}',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final upRect = VoxRect(x + pad, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'ext_uplock', 'UpLock', upRect)) {
      extrude.upLocked = !extrude.upLocked;
      extrude.rebuildMesh();
    }

    final capsRect = VoxRect(upRect.right + 8.0, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'ext_caps', 'Toggle Caps', capsRect)) {
      extrude.capEnds = !extrude.capEnds;
      extrude.rebuildMesh();
    }

    final rebuildRect = VoxRect(capsRect.right + 8.0, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'ext_rebuild', 'Rebuild', rebuildRect)) {
      extrude.rebuildMesh();
    }

    ui.endWindow();
  }
}
