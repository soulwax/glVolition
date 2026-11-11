part of '../../engine.dart';

/// Extended Position-Based Dynamics cloth simulation component with aerodynamic wind,
/// live collider syncing, and automatic [MeshRenderer] deformation (E53-2).
final class ClothSimulationComponent extends Behaviour {
  final cloth.XpbdWorld world;
  cloth.ClothPatch? _patch;

  int columns;
  int rows;
  double width;
  double height;
  Vec3 wind;
  double windTurbulence;
  double stretchCompliance;
  double bendingCompliance;
  bool pinTopEdge;
  bool pinTopCorners;
  bool fixedStep;
  bool autoRebuildMeshRenderer;
  bool syncTrackedColliders;

  final List<Collider> trackedColliders = [];
  final Map<Collider, cloth.XpbdCollider> _colliderProxies = {};

  MeshHandle? _dynamicMeshHandle;
  MeshData? _currentMeshData;
  bool _initialized = false;

  ClothSimulationComponent({
    cloth.XpbdWorld? world,
    this.columns = 6,
    this.rows = 6,
    this.width = 2.0,
    this.height = 2.0,
    this.wind = Vec3.zero,
    this.windTurbulence = 0.0,
    this.stretchCompliance = 0.0,
    this.bendingCompliance = 0.05,
    this.pinTopEdge = false,
    this.pinTopCorners = true,
    this.fixedStep = true,
    this.autoRebuildMeshRenderer = true,
    this.syncTrackedColliders = true,
  }) : world = world ?? cloth.XpbdWorld();

  static final spec = ComponentSpec<ClothSimulationComponent>(
    'ClothSimulationComponent',
    ClothSimulationComponent.new,
    [
      Field.integer('columns', (c) => c.columns, (c, v) => c.columns = v),
      Field.integer('rows', (c) => c.rows, (c, v) => c.rows = v),
      Field.number('width', (c) => c.width, (c, v) => c.width = v),
      Field.number('height', (c) => c.height, (c, v) => c.height = v),
      Field.vec3('wind', (c) => c.wind, (c, v) => c.wind = v),
      Field.number('windTurbulence', (c) => c.windTurbulence, (c, v) => c.windTurbulence = v),
      Field.boolean('pinTopEdge', (c) => c.pinTopEdge, (c, v) => c.pinTopEdge = v),
      Field.boolean('pinTopCorners', (c) => c.pinTopCorners, (c, v) => c.pinTopCorners = v),
      Field.boolean('fixedStep', (c) => c.fixedStep, (c, v) => c.fixedStep = v),
    ],
  );

  cloth.ClothPatch? get patch => _patch;
  MeshData? get currentMeshData => _currentMeshData;
  List<cloth.XpbdParticle> get particles => world.particles;

  void addSphereCollider(Vec3 center, double radius, {double friction = 0.2}) {
    world.addCollider(cloth.SphereConstraintCollider(
      center: cloth.XpbdVec3(center.x, center.y, center.z),
      radius: radius,
      friction: friction,
    ));
  }

  void addPlaneCollider(Vec3 point, Vec3 normal, {double friction = 0.4}) {
    world.addCollider(cloth.PlaneConstraintCollider(
      point: cloth.XpbdVec3(point.x, point.y, point.z),
      normal: cloth.XpbdVec3(normal.x, normal.y, normal.z),
      friction: friction,
    ));
  }

  void rebuildPatch() {
    world.particles.clear();
    world.constraints.clear();
    world.triangles.clear();

    final origin = isAttached ? transform.position : Vec3.zero;
    _patch = cloth.ClothGridBuilder.populate(
      world,
      columns: columns,
      rows: rows,
      width: width,
      height: height,
      origin: cloth.XpbdVec3(origin.x - width * 0.5, origin.y, origin.z),
      stretchCompliance: stretchCompliance,
      bendingCompliance: bendingCompliance,
      pinTopEdge: pinTopEdge,
      pinTopCorners: pinTopCorners,
    );
    _initialized = true;
    _updateMeshData();
  }

  void _syncColliders() {
    if (!syncTrackedColliders) return;
    for (final col in List.of(trackedColliders)) {
      if (col.isDestroyed || !col._active) {
        final proxy = _colliderProxies.remove(col);
        if (proxy != null) world.colliders.remove(proxy);
        trackedColliders.remove(col);
        continue;
      }

      if (col is SphereCollider) {
        final existing = _colliderProxies[col];
        final wc = cloth.XpbdVec3(col.worldCenter.x, col.worldCenter.y, col.worldCenter.z);
        if (existing is cloth.SphereConstraintCollider) {
          existing.center = wc;
          existing.radius = col.worldRadius;
        } else {
          final created = cloth.SphereConstraintCollider(center: wc, radius: col.worldRadius);
          _colliderProxies[col] = created;
          world.addCollider(created);
        }
      } else if (col is CapsuleCollider) {
        final existing = _colliderProxies[col];
        final s = cloth.XpbdVec3(col.segmentStart.x, col.segmentStart.y, col.segmentStart.z);
        final e = cloth.XpbdVec3(col.segmentEnd.x, col.segmentEnd.y, col.segmentEnd.z);
        if (existing is cloth.CapsuleConstraintCollider) {
          existing.start = s;
          existing.end = e;
          existing.radius = col.worldRadius;
        } else {
          final created = cloth.CapsuleConstraintCollider(
            start: s,
            end: e,
            radius: col.worldRadius,
          );
          _colliderProxies[col] = created;
          world.addCollider(created);
        }
      }
    }
  }

  void _updateMeshData() {
    final p = _patch;
    if (p == null || p.particles.isEmpty) return;

    final normals = world.computeVertexNormals();
    const stride = 14;
    final vertices = Float32List(p.particles.length * stride);
    final indices = Uint32List.fromList(p.triangleIndices);

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;

    final invWorldPos = isAttached ? transform.position : Vec3.zero;
    for (int i = 0; i < p.particles.length; i++) {
      final pt = p.particles[i];
      final n = normals[pt.index];
      final lx = pt.position.x - invWorldPos.x;
      final ly = pt.position.y - invWorldPos.y;
      final lz = pt.position.z - invWorldPos.z;

      if (lx < minX) minX = lx;
      if (ly < minY) minY = ly;
      if (lz < minZ) minZ = lz;
      if (lx > maxX) maxX = lx;
      if (ly > maxY) maxY = ly;
      if (lz > maxZ) maxZ = lz;

      final base = i * stride;
      vertices[base + 0] = lx;
      vertices[base + 1] = ly;
      vertices[base + 2] = lz;
      vertices[base + 3] = n.x;
      vertices[base + 4] = n.y;
      vertices[base + 5] = n.z;
      vertices[base + 6] = 1.0;
      vertices[base + 7] = 1.0;
      vertices[base + 8] = 1.0;
      vertices[base + 9] = 1.0;
      vertices[base + 10] = 1.0;
      vertices[base + 11] = pt.u;
      vertices[base + 12] = pt.v;
      vertices[base + 13] = 0.0;
    }

    _currentMeshData = MeshData(
      vertices: vertices,
      indices: indices,
      layout: VertexLayoutDescriptor.compatibility14,
      localBounds: Aabb(
        Vec3(minX - 0.02, minY - 0.02, minZ - 0.02),
        Vec3(maxX + 0.02, maxY + 0.02, maxZ + 0.02),
      ),
    );

    if (autoRebuildMeshRenderer && isAttached && scene.isLoaded) {
      final mr = getComponent<MeshRenderer>();
      if (mr != null) {
        final nextHandle = engine.graphics.createMesh(
          _currentMeshData!,
          debugLabel: '${gameObject.name}#cloth',
        );
        final old = _dynamicMeshHandle;
        _dynamicMeshHandle = nextHandle;
        mr.mesh = nextHandle;
        if (old != null) {
          engine.graphics.releaseMesh(old);
        }
      }
    }
  }

  void _stepWorld(double dt) {
    if (!_initialized) rebuildPatch();
    _syncColliders();
    world.wind = cloth.XpbdVec3(wind.x, wind.y, wind.z);
    world.windTurbulence = windTurbulence;
    world.step(dt);
    _updateMeshData();
  }

  @override
  void start() {
    if (!_initialized) rebuildPatch();
  }

  @override
  void fixedUpdate() {
    if (fixedStep) _stepWorld(time.fixedDeltaTime);
  }

  @override
  void update() {
    if (!fixedStep) _stepWorld(time.deltaTime);
  }

  @override
  void onDestroy() {
    if (_dynamicMeshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_dynamicMeshHandle!);
      _dynamicMeshHandle = null;
    }
  }
}

/// Extended Position-Based Dynamics rope/cable simulation optionally bridging [startAnchor]
/// and [endAnchor] and updating a sibling [LineRenderer] (E53-2).
final class RopeSimulationComponent extends Behaviour {
  final cloth.XpbdWorld world;
  final List<cloth.XpbdParticle> nodes = [];

  Vec3 startOffset;
  Vec3 endOffset;
  int segments;
  double stretchCompliance;
  double bendingCompliance;
  bool pinStart;
  bool pinEnd;
  GameObject? startAnchor;
  GameObject? endAnchor;
  bool fixedStep;

  bool _initialized = false;

  RopeSimulationComponent({
    cloth.XpbdWorld? world,
    this.startOffset = Vec3.zero,
    this.endOffset = const Vec3(2.0, 0.0, 0.0),
    this.segments = 10,
    this.stretchCompliance = 0.0,
    this.bendingCompliance = 0.04,
    this.pinStart = true,
    this.pinEnd = false,
    this.startAnchor,
    this.endAnchor,
    this.fixedStep = true,
  }) : world = world ?? cloth.XpbdWorld();

  static final spec = ComponentSpec<RopeSimulationComponent>(
    'RopeSimulationComponent',
    RopeSimulationComponent.new,
    [
      Field.vec3('startOffset', (r) => r.startOffset, (r, v) => r.startOffset = v),
      Field.vec3('endOffset', (r) => r.endOffset, (r, v) => r.endOffset = v),
      Field.integer('segments', (r) => r.segments, (r, v) => r.segments = v),
      Field.boolean('pinStart', (r) => r.pinStart, (r, v) => r.pinStart = v),
      Field.boolean('pinEnd', (r) => r.pinEnd, (r, v) => r.pinEnd = v),
      Field.boolean('fixedStep', (r) => r.fixedStep, (r, v) => r.fixedStep = v),
    ],
  );

  void rebuildRope() {
    world.particles.clear();
    world.constraints.clear();
    nodes.clear();

    final basePos = isAttached ? transform.position : Vec3.zero;
    final startWorld = startAnchor != null ? startAnchor!.transform.position : (basePos + startOffset);
    final endWorld = endAnchor != null ? endAnchor!.transform.position : (basePos + endOffset);

    nodes.addAll(cloth.RopeChainBuilder.populate(
      world,
      start: cloth.XpbdVec3(startWorld.x, startWorld.y, startWorld.z),
      end: cloth.XpbdVec3(endWorld.x, endWorld.y, endWorld.z),
      segments: segments,
      stretchCompliance: stretchCompliance,
      bendingCompliance: bendingCompliance,
      pinStart: pinStart,
      pinEnd: pinEnd,
    ));
    _initialized = true;
    _syncLineRenderer();
  }

  void _syncAnchors() {
    if (nodes.isEmpty) return;
    if (pinStart && startAnchor != null && !startAnchor!.isDestroyed) {
      final p = startAnchor!.transform.position;
      nodes.first.pinned = true;
      nodes.first.position = cloth.XpbdVec3(p.x, p.y, p.z);
    }
    if (pinEnd && endAnchor != null && !endAnchor!.isDestroyed) {
      final p = endAnchor!.transform.position;
      nodes.last.pinned = true;
      nodes.last.position = cloth.XpbdVec3(p.x, p.y, p.z);
    }
  }

  void _syncLineRenderer() {
    if (!isAttached || nodes.isEmpty) return;
    final line = getComponent<LineRenderer>();
    if (line != null) {
      line.setPositions(
        nodes.map((n) => Vec3(n.position.x, n.position.y, n.position.z)),
      );
    }
  }

  void _stepWorld(double dt) {
    if (!_initialized) rebuildRope();
    _syncAnchors();
    world.step(dt);
    _syncLineRenderer();
  }

  @override
  void start() {
    if (!_initialized) rebuildRope();
  }

  @override
  void fixedUpdate() {
    if (fixedStep) _stepWorld(time.fixedDeltaTime);
  }

  @override
  void update() {
    if (!fixedStep) _stepWorld(time.deltaTime);
  }
}

/// Persistent UI interaction state for [XpbdDebuggerUI.render].
final class XpbdDebuggerUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` XPBD cloth & rope constraint telemetry inspector (E53-2).
final class XpbdDebuggerUI {
  static bool _drawButton(
    VoxUiContext ui,
    XpbdDebuggerUiState state,
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
    cloth.XpbdWorld world, {
    XpbdDebuggerUiState? state,
    void Function()? onReset,
    String title = 'XPBD Cloth & Rope Solver',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? XpbdDebuggerUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final avgPct = (world.averageStretchError * 100.0).toStringAsFixed(2);
    final maxPct = (world.maxStretchError * 100.0).toStringAsFixed(2);

    ui.labelValue(
      'Particles / Constraints',
      '${world.particles.length} / ${world.constraints.length}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Substeps / Iters',
      '${world.substeps}x / ${world.constraintIterations}x',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Stretch Error (Avg/Max)',
      '$avgPct% / $maxPct%',
      valueColor: world.maxStretchError < 0.03 ? VoxColor.green : VoxColor.yellow,
    );
    ui.labelValue(
      'Wind Speed',
      '${world.wind.length.toStringAsFixed(2)} m/s',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final gustRect = VoxRect(x + pad, barY, 94.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_gust', '+Wind +Z', gustRect)) {
      world.wind = world.wind + const cloth.XpbdVec3(0.0, 0.0, 2.0);
    }

    final calmRect = VoxRect(gustRect.right + 8.0, barY, 90.0, 22.0);
    if (_drawButton(ui, uiState, 'xpbd_calm', 'Zero Wind', calmRect)) {
      world.wind = cloth.XpbdVec3.zero;
    }

    if (onReset != null) {
      final resetRect = VoxRect(calmRect.right + 8.0, barY, 76.0, 22.0);
      if (_drawButton(ui, uiState, 'xpbd_reset', 'Reset', resetRect)) {
        onReset();
      }
    }

    ui.endWindow();
  }
}
