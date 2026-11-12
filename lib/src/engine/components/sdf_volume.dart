part of '../../engine.dart';

/// 3D Signed Distance Field CSG sculpting volume, raymarcher & Surface Nets mesher (`voxsdf`) (E74-2).
final class SdfVolumeComponent extends Behaviour {
  int nx;
  int ny;
  int nz;
  double voxelSize;
  double isoLevel;
  double brushRadius;
  double brushSmoothness;
  bool autoCreateMeshRenderer;
  LinearColor surfaceColor;

  sdf.SdfField? _field;
  int _builtNx = -1;
  int _builtNy = -1;
  int _builtNz = -1;
  double _builtVoxel = -1.0;

  final List<sdf.SdfBrush> _brushHistory = [];
  sdf.SdfMeshResult? _lastSurfaceMesh;
  MeshData? _currentMeshData;
  MeshHandle? _meshHandle;
  MaterialHandle? _materialHandle;

  SdfVolumeComponent({
    this.nx = 18,
    this.ny = 18,
    this.nz = 18,
    this.voxelSize = 0.25,
    this.isoLevel = 0.0,
    this.brushRadius = 0.9,
    this.brushSmoothness = 0.25,
    this.autoCreateMeshRenderer = true,
    this.surfaceColor = const LinearColor(0.74, 0.78, 0.84),
  });

  static final spec = ComponentSpec<SdfVolumeComponent>(
    'SdfVolumeComponent',
    SdfVolumeComponent.new,
    [
      Field.integer('nx', (s) => s.nx, (s, v) => s.nx = v),
      Field.integer('ny', (s) => s.ny, (s, v) => s.ny = v),
      Field.integer('nz', (s) => s.nz, (s, v) => s.nz = v),
      Field.number('voxelSize', (s) => s.voxelSize, (s, v) => s.voxelSize = v),
      Field.number('isoLevel', (s) => s.isoLevel, (s, v) => s.isoLevel = v),
      Field.number('brushRadius', (s) => s.brushRadius, (s, v) => s.brushRadius = v),
      Field.number('brushSmoothness', (s) => s.brushSmoothness, (s, v) => s.brushSmoothness = v),
      Field.boolean(
        'autoCreateMeshRenderer',
        (s) => s.autoCreateMeshRenderer,
        (s, v) => s.autoCreateMeshRenderer = v,
      ),
      Field.color('surfaceColor', (s) => s.surfaceColor, (s, v) => s.surfaceColor = v),
    ],
  );

  sdf.SdfField get field {
    final cNx = math.max(4, nx);
    final cNy = math.max(4, ny);
    final cNz = math.max(4, nz);
    final cVox = math.max(0.05, voxelSize);
    if (_field == null ||
        _builtNx != cNx ||
        _builtNy != cNy ||
        _builtNz != cNz ||
        (_builtVoxel - cVox).abs() > 1e-6) {
      _field = sdf.SdfField(nx: cNx, ny: cNy, nz: cNz, voxelSize: cVox);
      _builtNx = cNx;
      _builtNy = cNy;
      _builtNz = cNz;
      _builtVoxel = cVox;
      for (final b in _brushHistory) {
        _field!.applyBrush(b);
      }
    }
    return _field!;
  }

  int get brushCount => _brushHistory.length;
  int get vertexCount => _lastSurfaceMesh?.vertexCount ?? 0;
  int get triangleCount => _lastSurfaceMesh?.triangleCount ?? 0;
  sdf.SdfMeshResult? get lastSurfaceMesh => _lastSurfaceMesh;
  MeshData? get currentMeshData => _currentMeshData;

  void applyBrush(sdf.SdfBrush brush, {bool extractNow = true}) {
    _brushHistory.add(brush);
    field.applyBrush(brush);
    if (extractNow) {
      extractSurfaceMesh();
    }
  }

  void addSphere(
    Vec3 localPos,
    double radius, {
    sdf.SdfOp op = sdf.SdfOp.smoothUnion,
    double? smoothness,
    bool extractNow = true,
  }) {
    applyBrush(
      sdf.SdfBrush(
        primitive: sdf.SdfSphere(
          center: sdf.SdfVec3(localPos.x, localPos.y, localPos.z),
          radius: radius,
        ),
        op: op,
        smoothness: smoothness ?? brushSmoothness,
      ),
      extractNow: extractNow,
    );
  }

  void addBox(
    Vec3 localPos,
    Vec3 halfExtents, {
    sdf.SdfOp op = sdf.SdfOp.union,
    double rounding = 0.0,
    bool extractNow = true,
  }) {
    applyBrush(
      sdf.SdfBrush(
        primitive: sdf.SdfBox(
          center: sdf.SdfVec3(localPos.x, localPos.y, localPos.z),
          halfExtents: sdf.SdfVec3(halfExtents.x, halfExtents.y, halfExtents.z),
          rounding: rounding,
        ),
        op: op,
        smoothness: brushSmoothness,
      ),
      extractNow: extractNow,
    );
  }

  void carveSphere(Vec3 localPos, double radius, {bool extractNow = true}) {
    applyBrush(
      sdf.SdfBrush(
        primitive: sdf.SdfSphere(
          center: sdf.SdfVec3(localPos.x, localPos.y, localPos.z),
          radius: radius,
        ),
        op: sdf.SdfOp.subtract,
      ),
      extractNow: extractNow,
    );
  }

  bool undoLastBrush({bool extractNow = true}) {
    if (_brushHistory.isEmpty) return false;
    _brushHistory.removeLast();
    field.clear();
    for (final b in _brushHistory) {
      field.applyBrush(b);
    }
    if (extractNow) {
      extractSurfaceMesh();
    }
    return true;
  }

  void clearVolume({bool extractNow = true}) {
    _brushHistory.clear();
    field.clear();
    if (extractNow) {
      extractSurfaceMesh();
    }
  }

  /// Extracts smooth Surface Nets mesh into `compatibility14` [MeshData] and updates [MeshRenderer].
  MeshData extractSurfaceMesh() {
    final res = sdf.SdfSurfaceNets.extract(field, isoLevel: isoLevel);
    _lastSurfaceMesh = res;

    final vCount = res.vertexCount;
    if (vCount == 0 || res.indices.isEmpty) {
      final fallback = Primitives.cube(size: 0.01);
      _currentMeshData = fallback;
      return fallback;
    }

    const stride = 14;
    final vertices = Float32List(vCount * stride);
    for (var i = 0; i < vCount; i++) {
      final p = res.positions[i];
      final n = res.normals[i];
      final base = i * stride;
      vertices[base + 0] = p.x;
      vertices[base + 1] = p.y;
      vertices[base + 2] = p.z;
      vertices[base + 3] = n.x;
      vertices[base + 4] = n.y;
      vertices[base + 5] = n.z;
      vertices[base + 6] = surfaceColor.r;
      vertices[base + 7] = surfaceColor.g;
      vertices[base + 8] = surfaceColor.b;
      vertices[base + 9] = 1.0;
      vertices[base + 10] = 1.0;
      vertices[base + 11] = p.x * 0.25 + 0.5;
      vertices[base + 12] = p.z * 0.25 + 0.5;
      vertices[base + 13] = 0.0;
    }

    final b = sdf.computeSdfMeshBounds(res);
    final List<int> typedIndices = vCount <= 65535
        ? Uint16List.fromList(res.indices)
        : Uint32List.fromList(res.indices);

    final data = MeshData(
      layout: VertexLayoutDescriptor.compatibility14,
      vertices: vertices,
      indices: typedIndices,
      localBounds: Aabb(
        Vec3(b.min.x - 1e-4, b.min.y - 1e-4, b.min.z - 1e-4),
        Vec3(b.max.x + 1e-4, b.max.y + 1e-4, b.max.z + 1e-4),
      ),
    );
    data.validate();
    _currentMeshData = data;

    if (isAttached && scene.isLoaded) {
      final graphics = engine.graphics;
      final nextMesh = graphics.createMesh(
        data,
        debugLabel: '${gameObject.name}#sdf_surface_nets',
      );
      _materialHandle ??= graphics.createMaterial(
        MaterialDefinition(
          key: '${gameObject.name}#sdf_mat',
          tintR: surfaceColor.r,
          tintG: surfaceColor.g,
          tintB: surfaceColor.b,
          roughness: 0.45,
        ),
      );
      final oldMesh = _meshHandle;
      _meshHandle = nextMesh;

      var mr = getComponent<MeshRenderer>();
      if (mr == null && autoCreateMeshRenderer) {
        mr = gameObject.addComponent(
          MeshRenderer(mesh: nextMesh, meshData: data, material: _materialHandle),
        );
      } else if (mr != null) {
        mr.mesh = nextMesh;
        mr.material = _materialHandle;
        mr._leaf?.meshData = data;
        mr._leaf?.bounds = data.bounds;
      }
      if (oldMesh != null) {
        graphics.releaseMesh(oldMesh);
      }
    }

    return data;
  }

  /// Sphere-traces a world ray against the sculpted SDF volume.
  sdf.SdfRayHit? raymarchWorld(
    Vec3 worldOrigin,
    Vec3 worldDirection, {
    double maxDistance = 64.0,
  }) {
    final origin = isAttached ? transform.position : Vec3.zero;
    final localOrigin = worldOrigin - origin;
    final hit = field.raymarch(
      sdf.SdfVec3(localOrigin.x, localOrigin.y, localOrigin.z),
      sdf.SdfVec3(worldDirection.x, worldDirection.y, worldDirection.z),
      maxDistance: maxDistance,
    );
    if (hit == null) return null;
    return sdf.SdfRayHit(
      distance: hit.distance,
      point: sdf.SdfVec3(
        hit.point.x + origin.x,
        hit.point.y + origin.y,
        hit.point.z + origin.z,
      ),
      normal: hit.normal,
      steps: hit.steps,
    );
  }

  @override
  void onDestroy() {
    if (_meshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_meshHandle!);
      _meshHandle = null;
    }
  }
}

/// Persistent UI interaction state for [SdfSculptInspectorUI.render].
final class SdfSculptInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` SDF CSG sculpting & Surface Nets remeshing panel (E74-2).
final class SdfSculptInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    SdfSculptInspectorUiState state,
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
    SdfVolumeComponent vol, {
    SdfSculptInspectorUiState? state,
    String title = 'SDF CSG Sculptor',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 240.0,
  }) {
    final uiState = state ?? SdfSculptInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Grid / Voxel',
      '${vol.nx}x${vol.ny}x${vol.nz} @ ${vol.voxelSize.toStringAsFixed(2)}m',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Mesh Tris / Vtx',
      '${vol.triangleCount} tris / ${vol.vertexCount} vtx',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Brushes / Smooth',
      '${vol.brushCount} ops / k=${vol.brushSmoothness.toStringAsFixed(2)}',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Radius / Iso',
      '${vol.brushRadius.toStringAsFixed(2)}m / iso ${vol.isoLevel.toStringAsFixed(2)}',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final addRect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'sdf_add', 'Add Sph', addRect)) {
      vol.addSphere(Vec3.zero, vol.brushRadius);
    }

    final carveRect = VoxRect(addRect.right + 8.0, barY, 70.0, 22.0);
    if (_drawButton(ui, uiState, 'sdf_carve', 'Carve', carveRect)) {
      vol.carveSphere(Vec3(vol.brushRadius * 0.45, vol.brushRadius * 0.45, 0.0), vol.brushRadius * 0.7);
    }

    final remeshRect = VoxRect(carveRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'sdf_remesh', 'Remesh', remeshRect)) {
      vol.extractSurfaceMesh();
    }

    final radRect = VoxRect(remeshRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'sdf_rad', 'Rad +0.2', radRect)) {
      vol.brushRadius = (vol.brushRadius + 0.2).clamp(0.25, 3.0).toDouble();
    }

    ui.endWindow();
  }
}
