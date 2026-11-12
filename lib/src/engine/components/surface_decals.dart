part of '../../engine.dart';

/// Converts a `voxdecal` [decal.DecalMesh] into a validated `compatibility14` [MeshData].
MeshData decalMeshToMeshData(
  decal.DecalMesh mesh, {
  LinearColor tint = LinearColor.white,
  double opacity = 1.0,
}) {
  const stride = 14;
  final vCount = mesh.vertexCount;
  final vertices = Float32List(vCount * stride);

  for (var i = 0; i < vCount; i++) {
    final v = mesh.vertices[i];
    final base = i * stride;
    vertices[base + 0] = v.position.x;
    vertices[base + 1] = v.position.y;
    vertices[base + 2] = v.position.z;
    vertices[base + 3] = v.normal.x;
    vertices[base + 4] = v.normal.y;
    vertices[base + 5] = v.normal.z;
    vertices[base + 6] = tint.r;
    vertices[base + 7] = tint.g;
    vertices[base + 8] = tint.b;
    vertices[base + 9] = 1.0;
    vertices[base + 10] = (v.alpha * opacity).clamp(0.0, 1.0);
    vertices[base + 11] = v.uv.x;
    vertices[base + 12] = v.uv.y;
    vertices[base + 13] = 0.0;
  }

  final minP = Vec3(mesh.boundsMin.x - 1e-4, mesh.boundsMin.y - 1e-4, mesh.boundsMin.z - 1e-4);
  final maxP = Vec3(mesh.boundsMax.x + 1e-4, mesh.boundsMax.y + 1e-4, mesh.boundsMax.z + 1e-4);
  final List<int> typedIndices = vCount <= 65535
      ? Uint16List.fromList(mesh.indices)
      : Uint32List.fromList(mesh.indices);

  final data = MeshData(
    layout: VertexLayoutDescriptor.compatibility14,
    vertices: vertices,
    indices: typedIndices,
    localBounds: Aabb(minP, maxP),
  );
  data.validate();
  return data;
}

/// Extracts world-space triangles from [mr] scaled/transformed by [tr] for decal clipping.
decal.DecalSourceMesh decalSourceFromMeshRenderer(
  MeshRenderer mr,
  TransformComponent tr,
) {
  final data = mr.meshData;
  if (data == null || data.vertexCount == 0) {
    return const decal.DecalSourceMesh(positions: [], normals: [], indices: []);
  }
  final layout = data.layout;
  final stride = layout.strideFloats;
  final posSlot = layout.attributes.firstWhere((a) => a.kind == VertexAttributeKind.position);
  final normSlot = layout.attributes
      .where((a) => a.kind == VertexAttributeKind.normal)
      .firstOrNull;

  final wPos = tr.position;
  final wRot = tr.rotation;
  final wScale = tr.lossyScale;
  final stretch = tr.localStretch;
  final sx = wScale * stretch.x;
  final sy = wScale * stretch.y;
  final sz = wScale * stretch.z;

  final vCount = data.vertexCount;
  final positions = List<decal.DecalVec3>.generate(vCount, (i) {
    final base = i * stride;
    final lp = Vec3(
      data.vertices[base + posSlot.floatOffset] * sx,
      data.vertices[base + posSlot.floatOffset + 1] * sy,
      data.vertices[base + posSlot.floatOffset + 2] * sz,
    );
    final gp = wPos + wRot.rotate(lp);
    return decal.DecalVec3(gp.x, gp.y, gp.z);
  });

  final normals = List<decal.DecalVec3>.generate(vCount, (i) {
    if (normSlot == null) return decal.DecalVec3.unitY;
    final base = i * stride;
    final ln = Vec3(
      data.vertices[base + normSlot.floatOffset],
      data.vertices[base + normSlot.floatOffset + 1],
      data.vertices[base + normSlot.floatOffset + 2],
    );
    final wn = wRot.rotate(ln).normalized;
    return decal.DecalVec3(wn.x, wn.y, wn.z);
  });

  final indices = data.indices != null
      ? List<int>.of(data.indices!)
      : List<int>.generate(vCount, (i) => i);

  return decal.DecalSourceMesh(
    positions: positions,
    normals: normals,
    indices: indices,
  );
}

/// Manages a fixed-capacity ring buffer of surface decal stamps, aging and freeing GPU handles (E60-2).
final class DecalPoolComponent extends Behaviour {
  int maxCapacity;
  double mergeCullRadius;
  double defaultLifetimeSeconds;
  double defaultFadeDurationSeconds;

  decal.DecalPoolManager? _pool;
  int? _configuredCap;
  double? _configuredMerge;
  final Map<int, ({MeshHandle handle, SceneNode node})> _visuals = {};
  MaterialHandle? _defaultMaterial;

  DecalPoolComponent({
    this.maxCapacity = 64,
    this.mergeCullRadius = 0.08,
    this.defaultLifetimeSeconds = 20.0,
    this.defaultFadeDurationSeconds = 3.0,
  });

  static final spec = ComponentSpec<DecalPoolComponent>(
    'DecalPoolComponent',
    DecalPoolComponent.new,
    [
      Field.integer('maxCapacity', (p) => p.maxCapacity, (p, v) => p.maxCapacity = v),
      Field.number(
        'mergeCullRadius',
        (p) => p.mergeCullRadius,
        (p, v) => p.mergeCullRadius = v,
      ),
      Field.number(
        'defaultLifetimeSeconds',
        (p) => p.defaultLifetimeSeconds,
        (p, v) => p.defaultLifetimeSeconds = v,
      ),
      Field.number(
        'defaultFadeDurationSeconds',
        (p) => p.defaultFadeDurationSeconds,
        (p, v) => p.defaultFadeDurationSeconds = v,
      ),
    ],
  );

  decal.DecalPoolManager _ensurePool() {
    if (_pool != null &&
        _configuredCap == maxCapacity &&
        _configuredMerge == mergeCullRadius) {
      return _pool!;
    }
    _clearVisuals();
    _pool = decal.DecalPoolManager(
      maxCapacity: math.max(1, maxCapacity),
      mergeCullRadius: math.max(0.0, mergeCullRadius),
      defaultLifetimeSeconds: defaultLifetimeSeconds,
      defaultFadeDurationSeconds: defaultFadeDurationSeconds,
    );
    _configuredCap = maxCapacity;
    _configuredMerge = mergeCullRadius;
    return _pool!;
  }

  decal.DecalPoolStats get stats => _ensurePool().stats;
  int get activeCount => _ensurePool().activeCount;
  int get evictedCount => _ensurePool().evictedCount;
  int get mergeCulledCount => _ensurePool().mergeCulledCount;

  /// Stamps a world-space decal clipped onto [target] (or synthetic fallback plane if omitted).
  decal.DecalPoolEntry? stampDecal({
    required Vec3 worldPosition,
    required Vec3 worldNormal,
    Vec3 size = const Vec3(1.0, 1.0, 0.5),
    GameObject? target,
    String tag = 'scar',
    double? lifetimeSeconds,
    double? fadeDurationSeconds,
    LinearColor tint = LinearColor.white,
    MaterialHandle? material,
    bool bypassMergeCull = false,
  }) {
    final pool = _ensurePool();
    final rot = decal.DecalQuat.lookDirection(
      decal.DecalVec3(-worldNormal.x, -worldNormal.y, -worldNormal.z),
    );
    final spec = decal.DecalBoxSpec(
      center: decal.DecalVec3(worldPosition.x, worldPosition.y, worldPosition.z),
      rotation: rot,
      size: decal.DecalVec3(size.x, size.y, size.z),
    );

    decal.DecalMesh projected = decal.DecalMesh.empty;
    if (target != null) {
      final mr = target.getComponent<MeshRenderer>();
      if (mr != null && mr.meshData != null) {
        projected = decal.DecalBoxProjector.project(
          target: decalSourceFromMeshRenderer(mr, target.transform),
          box: spec,
        );
      }
    } else if (isAttached) {
      projected = _projectAgainstSceneMeshes(spec);
    }

    if (projected.isEmpty) {
      // Fallback small tangential patch aligned with normal when no detailed mesh is targeted.
      final surf = decal.DecalSourceMesh.plane(
        width: size.x * 2.0,
        depth: size.y * 2.0,
        center: decal.DecalVec3(worldPosition.x, worldPosition.y, worldPosition.z),
      );
      projected = decal.DecalBoxProjector.project(target: surf, box: spec);
    }

    final entry = pool.spawn(
      tag: tag,
      position: decal.DecalVec3(worldPosition.x, worldPosition.y, worldPosition.z),
      normal: decal.DecalVec3(worldNormal.x, worldNormal.y, worldNormal.z),
      rotation: rot,
      size: decal.DecalVec3(size.x, size.y, size.z),
      mesh: projected,
      lifetimeSeconds: lifetimeSeconds ?? defaultLifetimeSeconds,
      fadeDurationSeconds: fadeDurationSeconds ?? defaultFadeDurationSeconds,
      bypassMergeCull: bypassMergeCull,
    );
    if (entry == null) return null;

    _syncEvictedOrExpiredVisuals();

    if (!projected.isEmpty && isAttached && scene.isLoaded) {
      final data = decalMeshToMeshData(projected, tint: tint);
      final meshHandle = engine.graphics.createMesh(
        data,
        debugLabel: 'Decal_${entry.id}_$tag',
      );
      _defaultMaterial ??= engine.graphics.createMaterial(
        MaterialDefinition.dielectric(
          key: 'voxdecal_default',
          color: const LinearColor(0.18, 0.16, 0.14),
        ),
      );
      final node = SceneNode(
        name: 'DecalNode_${entry.id}',
        mesh: meshHandle,
        meshData: data,
        bounds: data.bounds,
        material: material ?? _defaultMaterial,
        blendMode: BlendMode.alpha,
        castsShadow: false,
      );
      scene.root.addChild(node);
      _visuals[entry.id] = (handle: meshHandle, node: node);
    }
    return entry;
  }

  decal.DecalMesh _projectAgainstSceneMeshes(decal.DecalBoxSpec spec) {
    final pos = <decal.DecalVec3>[];
    final norm = <decal.DecalVec3>[];
    final idx = <int>[];

    void visit(GameObject go) {
      if (!identical(go, gameObject)) {
        final mr = go.getComponent<MeshRenderer>();
        if (mr != null && mr.meshData != null) {
          final src = decalSourceFromMeshRenderer(mr, go.transform);
          final base = pos.length;
          pos.addAll(src.positions);
          norm.addAll(src.normals);
          for (final index in src.indices) {
            idx.add(base + index);
          }
        }
      }
      for (final c in go.children) {
        visit(c);
      }
    }

    for (final root in scene.rootGameObjects) {
      visit(root);
    }
    if (idx.isEmpty) return decal.DecalMesh.empty;
    return decal.DecalBoxProjector.project(
      target: decal.DecalSourceMesh(positions: pos, normals: norm, indices: idx),
      box: spec,
    );
  }

  void _syncEvictedOrExpiredVisuals() {
    final activeIds = {for (final e in _ensurePool().entries) e.id};
    final staleIds = _visuals.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in staleIds) {
      final vis = _visuals.remove(id);
      if (vis != null) {
        vis.node.removeFromParent();
        if (isAttached && scene.isLoaded) {
          engine.graphics.releaseMesh(vis.handle);
        }
      }
    }
  }

  void _clearVisuals() {
    for (final vis in _visuals.values) {
      vis.node.removeFromParent();
      if (isAttached && scene.isLoaded) {
        engine.graphics.releaseMesh(vis.handle);
      }
    }
    _visuals.clear();
  }

  void pruneByTime(double seconds) {
    _ensurePool().tick(seconds);
    _syncEvictedOrExpiredVisuals();
  }

  void clearDecals() {
    _ensurePool().clear();
    _clearVisuals();
  }

  @override
  void update() {
    _ensurePool().tick(time.deltaTime);
    _syncEvictedOrExpiredVisuals();
  }

  @override
  void onDestroy() {
    _clearVisuals();
  }
}

/// Projects an oriented decal volume onto a target [MeshRenderer] or all overlapping scene meshes (E60-2).
final class DecalProjectorComponent extends Component {
  Vec3 size;
  double maxNormalAngleDegrees;
  double surfaceOffset;
  double edgeFadeFraction;
  LinearColor tintColor;
  double opacity;
  bool projectOnEnable;
  MaterialHandle? material;

  decal.DecalMesh _lastMesh = decal.DecalMesh.empty;
  MeshData? _lastMeshData;
  MeshHandle? _meshHandle;
  SceneNode? _node;

  DecalProjectorComponent({
    this.size = const Vec3(1.2, 1.2, 0.6),
    this.maxNormalAngleDegrees = 65.0,
    this.surfaceOffset = 0.01,
    this.edgeFadeFraction = 0.15,
    this.tintColor = LinearColor.white,
    this.opacity = 1.0,
    this.projectOnEnable = true,
    this.material,
  });

  static final spec = ComponentSpec<DecalProjectorComponent>(
    'DecalProjectorComponent',
    DecalProjectorComponent.new,
    [
      Field.vec3('size', (d) => d.size, (d, v) => d.size = v),
      Field.number(
        'maxNormalAngleDegrees',
        (d) => d.maxNormalAngleDegrees,
        (d, v) => d.maxNormalAngleDegrees = v,
      ),
      Field.number('surfaceOffset', (d) => d.surfaceOffset, (d, v) => d.surfaceOffset = v),
      Field.color('tintColor', (d) => d.tintColor, (d, v) => d.tintColor = v),
      Field.number('opacity', (d) => d.opacity, (d, v) => d.opacity = v),
      Field.boolean(
        'projectOnEnable',
        (d) => d.projectOnEnable,
        (d, v) => d.projectOnEnable = v,
      ),
    ],
  );

  decal.DecalMesh get lastProjectedMesh => _lastMesh;
  MeshData? get currentMeshData => _lastMeshData;
  int get triangleCount => _lastMesh.triangleCount;

  decal.DecalMesh projectOntoTarget(GameObject target) {
    final mr = target.getComponent<MeshRenderer>();
    if (mr == null || mr.meshData == null) return decal.DecalMesh.empty;
    final src = decalSourceFromMeshRenderer(mr, target.transform);
    return _projectSource(src);
  }

  decal.DecalMesh projectOntoScene() {
    if (!isAttached) return decal.DecalMesh.empty;
    final pos = <decal.DecalVec3>[];
    final norm = <decal.DecalVec3>[];
    final idx = <int>[];

    void visit(GameObject go) {
      if (!identical(go, gameObject)) {
        final mr = go.getComponent<MeshRenderer>();
        if (mr != null && mr.meshData != null) {
          final src = decalSourceFromMeshRenderer(mr, go.transform);
          final base = pos.length;
          pos.addAll(src.positions);
          norm.addAll(src.normals);
          for (final index in src.indices) {
            idx.add(base + index);
          }
        }
      }
      for (final c in go.children) {
        visit(c);
      }
    }

    for (final root in scene.rootGameObjects) {
      visit(root);
    }
    return _projectSource(
      decal.DecalSourceMesh(positions: pos, normals: norm, indices: idx),
    );
  }

  decal.DecalMesh _projectSource(decal.DecalSourceMesh src) {
    final p = isAttached ? transform.position : Vec3.zero;
    final q = isAttached ? transform.rotation : Quat.identity;
    final res = decal.DecalBoxProjector.project(
      target: src,
      box: decal.DecalBoxSpec(
        center: decal.DecalVec3(p.x, p.y, p.z),
        rotation: decal.DecalQuat(q.x, q.y, q.z, q.w),
        size: decal.DecalVec3(size.x, size.y, size.z),
        maxNormalAngleDegrees: maxNormalAngleDegrees,
        surfaceOffset: surfaceOffset,
        edgeFadeFraction: edgeFadeFraction,
      ),
    );
    _lastMesh = res;
    _uploadMesh(res);
    return res;
  }

  void _uploadMesh(decal.DecalMesh mesh) {
    if (mesh.isEmpty) {
      _node?.visible = false;
      return;
    }
    final data = decalMeshToMeshData(mesh, tint: tintColor, opacity: opacity);
    _lastMeshData = data;
    if (!isAttached || !scene.isLoaded) return;

    final nextHandle = engine.graphics.createMesh(
      data,
      debugLabel: '${gameObject.name}#decal',
    );
    final oldHandle = _meshHandle;
    _meshHandle = nextHandle;

    final mat = material ??
        engine.graphics.createMaterial(
          MaterialDefinition.dielectric(
            key: '${gameObject.name}#decalMat',
            color: tintColor,
          ),
        );
    if (_node == null) {
      _node = SceneNode(
        name: '${gameObject.name}#decal',
        mesh: nextHandle,
        meshData: data,
        bounds: data.bounds,
        material: mat,
        blendMode: BlendMode.alpha,
        castsShadow: false,
      );
      scene.root.addChild(_node!);
    } else {
      _node!
        ..mesh = nextHandle
        ..meshData = data
        ..bounds = data.bounds
        ..visible = true;
    }
    if (oldHandle != null) engine.graphics.releaseMesh(oldHandle);
  }

  @override
  void onEnable() {
    if (projectOnEnable) projectOntoScene();
  }

  @override
  void onDestroy() {
    _node?.removeFromParent();
    _node = null;
    if (_meshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_meshHandle!);
      _meshHandle = null;
    }
  }
}

/// Emits continuous ground-aligned tire skid or footprint strips using `voxdecal` (E60-2).
final class SurfaceSkidTrailComponent extends Behaviour {
  double ribbonWidth;
  double minSegmentDistance;
  double lifetimeSeconds;
  double fadeDurationSeconds;
  bool emitting;
  bool autoSamplePosition;
  LinearColor tintColor;
  MaterialHandle? material;

  decal.SkidRibbonBuilder? _builder;
  MeshHandle? _meshHandle;
  MeshData? _lastMeshData;
  SceneNode? _node;
  bool _dirty = false;

  SurfaceSkidTrailComponent({
    this.ribbonWidth = 0.28,
    this.minSegmentDistance = 0.16,
    this.lifetimeSeconds = 10.0,
    this.fadeDurationSeconds = 2.0,
    this.emitting = true,
    this.autoSamplePosition = false,
    this.tintColor = const LinearColor(0.12, 0.12, 0.12),
    this.material,
  });

  static final spec = ComponentSpec<SurfaceSkidTrailComponent>(
    'SurfaceSkidTrailComponent',
    SurfaceSkidTrailComponent.new,
    [
      Field.number('ribbonWidth', (s) => s.ribbonWidth, (s, v) => s.ribbonWidth = v),
      Field.number(
        'minSegmentDistance',
        (s) => s.minSegmentDistance,
        (s, v) => s.minSegmentDistance = v,
      ),
      Field.number(
        'lifetimeSeconds',
        (s) => s.lifetimeSeconds,
        (s, v) => s.lifetimeSeconds = v,
      ),
      Field.boolean('emitting', (s) => s.emitting, (s, v) => s.emitting = v),
      Field.boolean(
        'autoSamplePosition',
        (s) => s.autoSamplePosition,
        (s, v) => s.autoSamplePosition = v,
      ),
      Field.color('tintColor', (s) => s.tintColor, (s, v) => s.tintColor = v),
    ],
  );

  decal.SkidRibbonBuilder _ensureBuilder() => _builder ??= decal.SkidRibbonBuilder(
        defaultWidth: ribbonWidth,
        minSegmentDistance: minSegmentDistance,
        lifetimeSeconds: lifetimeSeconds,
        fadeDurationSeconds: fadeDurationSeconds,
      );

  int get sampleCount => _ensureBuilder().sampleCount;
  MeshData? get currentMeshData => _lastMeshData;
  int get triangleCount => _lastMeshData?.indices != null ? _lastMeshData!.indices!.length ~/ 3 : 0;

  bool addStamp(Vec3 worldPosition, {Vec3 normal = Vec3.unitY, double intensity = 1.0}) {
    final added = _ensureBuilder().addSample(
      position: decal.DecalVec3(worldPosition.x, worldPosition.y, worldPosition.z),
      normal: decal.DecalVec3(normal.x, normal.y, normal.z),
      intensity: intensity,
      width: ribbonWidth,
    );
    if (added) _dirty = true;
    return added;
  }

  void breakStrip() => _ensureBuilder().breakStrip();

  void clearTrail() {
    _ensureBuilder().clear();
    _dirty = true;
    _rebuildGpuMesh();
  }

  void _rebuildGpuMesh() {
    final mesh = _ensureBuilder().buildMesh();
    if (mesh.isEmpty) {
      _lastMeshData = null;
      _node?.visible = false;
      return;
    }
    final data = decalMeshToMeshData(mesh, tint: tintColor);
    _lastMeshData = data;
    if (!isAttached || !scene.isLoaded) return;

    final nextHandle = engine.graphics.createMesh(
      data,
      debugLabel: '${gameObject.name}#skid',
    );
    final oldHandle = _meshHandle;
    _meshHandle = nextHandle;
    final mat = material ??
        engine.graphics.createMaterial(
          MaterialDefinition.dielectric(
            key: '${gameObject.name}#skidMat',
            color: tintColor,
          ),
        );
    if (_node == null) {
      _node = SceneNode(
        name: '${gameObject.name}#skid',
        mesh: nextHandle,
        meshData: data,
        bounds: data.bounds,
        material: mat,
        blendMode: BlendMode.alpha,
        castsShadow: false,
      );
      scene.root.addChild(_node!);
    } else {
      _node!
        ..mesh = nextHandle
        ..meshData = data
        ..bounds = data.bounds
        ..visible = true;
    }
    if (oldHandle != null) engine.graphics.releaseMesh(oldHandle);
  }

  @override
  void update() {
    final b = _ensureBuilder();
    final beforeCount = b.sampleCount;
    b.advance(time.deltaTime);
    if (b.sampleCount != beforeCount) _dirty = true;
    if (autoSamplePosition && emitting && isAttached) {
      addStamp(transform.position);
    }
    if (_dirty) {
      _dirty = false;
      _rebuildGpuMesh();
    }
  }

  @override
  void onDestroy() {
    _node?.removeFromParent();
    _node = null;
    if (_meshHandle != null && isAttached && scene.isLoaded) {
      engine.graphics.releaseMesh(_meshHandle!);
      _meshHandle = null;
    }
  }
}

/// Persistent UI interaction state for [DecalPoolInspectorUI.render].
final class DecalPoolInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` inspector for [DecalPoolComponent] and [SurfaceSkidTrailComponent] (E60-2).
final class DecalPoolInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    DecalPoolInspectorUiState state,
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
    DecalPoolComponent pool, {
    SurfaceSkidTrailComponent? skidTrail,
    DecalPoolInspectorUiState? state,
    String title = 'Surface Decals Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? DecalPoolInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final st = pool.stats;
    ui.labelValue(
      'Active / Cap',
      '${st.activeCount} / ${st.maxCapacity}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Evicted / Culled',
      '${st.evictedCount} / ${st.mergeCulledCount}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Decal Tris / Skid',
      '${st.totalTriangles} / ${skidTrail?.triangleCount ?? 0}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Lifetime / Merge',
      '${pool.defaultLifetimeSeconds.toStringAsFixed(0)}s / ${pool.mergeCullRadius.toStringAsFixed(2)}m',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final stampRect = VoxRect(x + pad, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'dec_stamp', 'Stamp', stampRect)) {
      pool.stampDecal(
        worldPosition: Vec3((st.activeCount + 1) * 1.1, 0.0, 0.0),
        worldNormal: Vec3.unitY,
        bypassMergeCull: true,
      );
    }

    final pruneRect = VoxRect(stampRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'dec_prune', 'Age +5s', pruneRect)) {
      pool.pruneByTime(5.0);
    }

    final clearRect = VoxRect(pruneRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'dec_clear', 'Clear', clearRect)) {
      pool.clearDecals();
      skidTrail?.clearTrail();
    }

    ui.endWindow();
  }
}
