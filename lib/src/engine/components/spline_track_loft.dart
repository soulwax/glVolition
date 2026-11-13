part of '../../engine.dart';

/// Procedural banked cubic-Hermite spline & Bishop-frame track loft builder (`voxspline3d`) (E86-2).
final class SplineTrackLoftComponent extends Component {
  double trackWidth;
  double curbHeight;
  int sampleCount;
  double vTilesPerMeter;
  bool closedLoop;
  bool autoCreateMeshRenderer;
  MaterialHandle? material;

  spline3d.CubicHermiteSpline3D? splineCurve;
  spline3d.TrackLoftMesh? _lastLoft;
  List<spline3d.SplineSampleFrame> _lastFrames = const [];
  MeshData? _currentMeshData;
  MeshHandle? _dynamicMeshHandle;

  SplineTrackLoftComponent({
    this.trackWidth = 6.0,
    this.curbHeight = 0.35,
    this.sampleCount = 24,
    this.vTilesPerMeter = 0.25,
    this.closedLoop = false,
    this.autoCreateMeshRenderer = true,
    this.material,
    this.splineCurve,
  });

  static final spec = ComponentSpec<SplineTrackLoftComponent>(
    'SplineTrackLoftComponent',
    SplineTrackLoftComponent.new,
    [
      Field.number(
        'trackWidth',
        (c) => c.trackWidth,
        (c, v) => c.trackWidth = v,
      ),
      Field.number(
        'curbHeight',
        (c) => c.curbHeight,
        (c, v) => c.curbHeight = v,
      ),
      Field.integer(
        'sampleCount',
        (c) => c.sampleCount,
        (c, v) => c.sampleCount = v,
      ),
      Field.number(
        'vTilesPerMeter',
        (c) => c.vTilesPerMeter,
        (c, v) => c.vTilesPerMeter = v,
      ),
      Field.boolean(
        'closedLoop',
        (c) => c.closedLoop,
        (c, v) => c.closedLoop = v,
      ),
      Field.boolean(
        'autoCreateMeshRenderer',
        (c) => c.autoCreateMeshRenderer,
        (c, v) => c.autoCreateMeshRenderer = v,
      ),
    ],
  );

  spline3d.TrackLoftMesh? get lastLoft => _lastLoft;
  List<spline3d.SplineSampleFrame> get lastFrames => _lastFrames;
  MeshData? get currentMeshData => _currentMeshData;
  int get vertexCount => _lastLoft?.vertexCount ?? 0;
  int get triangleCount => _lastLoft?.triangleCount ?? 0;
  double get totalArcLength => _lastLoft?.totalArcLength ?? 0.0;

  spline3d.CubicHermiteSpline3D _resolveCurve() {
    if (splineCurve != null) return splineCurve!;
    return spline3d.CubicHermiteSpline3D.catmullRom(
      const [
        spline3d.SplineVec3(0.0, 0.0, 0.0),
        spline3d.SplineVec3(6.0, 1.5, -12.0),
        spline3d.SplineVec3(-4.0, 2.5, -24.0),
        spline3d.SplineVec3(4.0, 0.0, -36.0),
      ],
      closed: closedLoop,
      rollsRadians: const [0.0, 0.25, -0.3, 0.0],
    );
  }

  /// Regenerates Bishop frames and the indexed banked track [MeshData].
  spline3d.TrackLoftMesh rebuildTrackMesh() {
    final curve = _resolveCurve();
    final frames = spline3d.BishopFrameTransport.sampleFrames(
      curve,
      sampleCount: math.max(2, sampleCount),
    );
    _lastFrames = frames;
    final loft = spline3d.TrackLoftBuilder.buildTrackRibbon(
      frames,
      trackWidth: trackWidth,
      curbHeight: curbHeight,
      vTilesPerMeter: vTilesPerMeter,
    );
    _lastLoft = loft;

    if (loft.vertexCount > 0 && loft.indices.isNotEmpty) {
      const stride = 14;
      final vertices = Float32List(loft.vertexCount * stride);
      var minX = double.infinity,
          minY = double.infinity,
          minZ = double.infinity;
      var maxX = -double.infinity,
          maxY = -double.infinity,
          maxZ = -double.infinity;

      for (var i = 0; i < loft.vertexCount; i++) {
        final v = loft.vertices[i];
        final p = v.position;
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.z < minZ) minZ = p.z;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
        if (p.z > maxZ) maxZ = p.z;

        final base = i * stride;
        vertices[base + 0] = p.x;
        vertices[base + 1] = p.y;
        vertices[base + 2] = p.z;
        vertices[base + 3] = v.normal.x;
        vertices[base + 4] = v.normal.y;
        vertices[base + 5] = v.normal.z;
        vertices[base + 6] = 1.0;
        vertices[base + 7] = 1.0;
        vertices[base + 8] = 1.0;
        vertices[base + 9] = 1.0;
        vertices[base + 10] = 1.0;
        vertices[base + 11] = v.u;
        vertices[base + 12] = v.v;
        vertices[base + 13] = 0.0;
      }

      final meshData = MeshData(
        layout: VertexLayoutDescriptor.compatibility14,
        vertices: vertices,
        indices: Uint16List.fromList(loft.indices),
        localBounds: Aabb(
          Vec3(minX - 0.05, minY - 0.05, minZ - 0.05),
          Vec3(maxX + 0.05, maxY + 0.05, maxZ + 0.05),
        ),
      );
      _currentMeshData = meshData;

      if (isAttached && scene.isLoaded) {
        var mr = getComponent<MeshRenderer>();
        final handle = engine.graphics.createMesh(
          meshData,
          debugLabel: '${gameObject.name}#trackLoft',
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
    }
    return loft;
  }

  @override
  void onEnable() {
    rebuildTrackMesh();
  }

  @override
  void onDestroy() {
    if (_dynamicMeshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_dynamicMeshHandle!);
      _dynamicMeshHandle = null;
    }
  }
}

/// Persistent UI state for [SplineTrackInspectorUI.render].
final class SplineTrackInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` cubic-Hermite track loft & Bishop frame inspector (E86-2).
final class SplineTrackInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SplineTrackInspectorUiState state,
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
    SplineTrackLoftComponent loft, {
    SplineTrackInspectorUiState? state,
    String title = 'Spline Track Loft',
    double x = 20.0,
    double y = 20.0,
    double width = 410.0,
    double height = 245.0,
  }) {
    final uiState = state ?? SplineTrackInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Arc Length / Loop',
      '${loft.totalArcLength.toStringAsFixed(1)}m | ${loft.closedLoop ? 'Closed' : 'Open'}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Track Width / Curb',
      '${loft.trackWidth.toStringAsFixed(1)}m | ${loft.curbHeight.toStringAsFixed(2)}m',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Samples / Tris',
      '${loft.sampleCount} frames | ${loft.triangleCount} tris',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Vertices / V-Tile',
      '${loft.vertexCount} verts | ${loft.vTilesPerMeter.toStringAsFixed(2)}/m',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final loopRect = VoxRect(x + pad, barY, 78.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'stl_loop',
      loft.closedLoop ? 'Loop: On' : 'Loop: Off',
      loopRect,
    )) {
      loft.closedLoop = !loft.closedLoop;
      loft.rebuildTrackMesh();
    }

    final widthRect = VoxRect(loopRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'stl_width', 'Width +1.0', widthRect)) {
      loft.trackWidth += 1.0;
      loft.rebuildTrackMesh();
    }

    final sampRect = VoxRect(widthRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'stl_samp', 'Samples +8', sampRect)) {
      loft.sampleCount += 8;
      loft.rebuildTrackMesh();
    }

    final rebRect = VoxRect(sampRect.right + 8.0, barY, 74.0, 22.0);
    if (_drawButton(ui, uiState, 'stl_reb', 'Rebuild', rebRect)) {
      loft.rebuildTrackMesh();
    }

    ui.endWindow();
  }
}
