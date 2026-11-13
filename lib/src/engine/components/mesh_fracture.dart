part of '../../engine.dart';

/// Converts a `voxfracture` [frac.FractureMesh] into a validated `compatibility14` [MeshData].
MeshData fractureMeshToMeshData(frac.FractureMesh mesh) {
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
    vertices[base + 6] = 1.0;
    vertices[base + 7] = 1.0;
    vertices[base + 8] = 1.0;
    vertices[base + 9] = 1.0;
    vertices[base + 10] = 1.0;
    vertices[base + 11] = v.uv.x;
    vertices[base + 12] = v.uv.y;
    vertices[base + 13] = 0.0;
  }

  final bounds = mesh.computeBounds();
  final minP = Vec3(
    bounds.min.x - 1e-4,
    bounds.min.y - 1e-4,
    bounds.min.z - 1e-4,
  );
  final maxP = Vec3(
    bounds.max.x + 1e-4,
    bounds.max.y + 1e-4,
    bounds.max.z + 1e-4,
  );
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

/// Converts any pixeldart [MeshData] layout into a `voxfracture` [frac.FractureMesh].
frac.FractureMesh meshDataToFractureMesh(MeshData data) {
  final layout = data.layout;
  final stride = layout.strideFloats;
  final posSlot = layout.attributes.firstWhere(
    (a) => a.kind == VertexAttributeKind.position,
  );
  final normSlot = layout.attributes
      .where((a) => a.kind == VertexAttributeKind.normal)
      .firstOrNull;
  final uvSlot = layout.attributes
      .where((a) => a.kind == VertexAttributeKind.uv0)
      .firstOrNull;

  final vCount = data.vertexCount;
  final verts = List<frac.FractureVertex>.generate(vCount, (i) {
    final base = i * stride;
    final px = data.vertices[base + posSlot.floatOffset];
    final py = data.vertices[base + posSlot.floatOffset + 1];
    final pz = data.vertices[base + posSlot.floatOffset + 2];

    final nx = normSlot != null
        ? data.vertices[base + normSlot.floatOffset]
        : 0.0;
    final ny = normSlot != null
        ? data.vertices[base + normSlot.floatOffset + 1]
        : 1.0;
    final nz = normSlot != null
        ? data.vertices[base + normSlot.floatOffset + 2]
        : 0.0;

    final u = uvSlot != null ? data.vertices[base + uvSlot.floatOffset] : 0.0;
    final v = uvSlot != null
        ? data.vertices[base + uvSlot.floatOffset + 1]
        : 0.0;

    return frac.FractureVertex(
      position: frac.FracVec3(px, py, pz),
      normal: frac.FracVec3(nx, ny, nz).normalized,
      uv: frac.FracVec2(u, v),
    );
  });

  final idx = data.indices != null
      ? List<int>.of(data.indices!)
      : List<int>.generate(vCount, (i) => i);

  return frac.FractureMesh(vertices: verts, indices: idx);
}

/// Enables runtime CSG plane slicing and seeded Voronoi fragmentation on a [GameObject] (E59-2).
///
/// Consumes [sourceMesh], a sibling [MeshRenderer]'s [MeshData], or a fallback unit box,
/// spawning centered debris [GameObject]s with validated [MeshData], [MeshRenderer], and
/// optional [RigidBody] impulses.
final class FracturableMeshComponent extends Component {
  frac.FractureMesh? sourceMesh;
  int voronoiCellCount;
  int seed;
  double clusterBias;
  double debrisImpulse;
  double debrisMass;
  bool hideOriginalOnFracture;
  bool autoAddRigidBodies;
  MaterialHandle? materialOverride;

  final List<GameObject> _spawnedPieces = [];
  final List<MeshHandle> _ownedMeshHandles = [];
  bool _isFractured = false;
  int _lastShardCount = 0;
  double _lastTotalVolume = 0.0;

  FracturableMeshComponent({
    this.sourceMesh,
    this.voronoiCellCount = 8,
    this.seed = 42,
    this.clusterBias = 0.35,
    this.debrisImpulse = 5.5,
    this.debrisMass = 12.0,
    this.hideOriginalOnFracture = true,
    this.autoAddRigidBodies = true,
    this.materialOverride,
  });

  static final spec = ComponentSpec<FracturableMeshComponent>(
    'FracturableMeshComponent',
    FracturableMeshComponent.new,
    [
      Field.integer(
        'voronoiCellCount',
        (f) => f.voronoiCellCount,
        (f, v) => f.voronoiCellCount = v,
      ),
      Field.integer('seed', (f) => f.seed, (f, v) => f.seed = v),
      Field.number(
        'clusterBias',
        (f) => f.clusterBias,
        (f, v) => f.clusterBias = v,
      ),
      Field.number(
        'debrisImpulse',
        (f) => f.debrisImpulse,
        (f, v) => f.debrisImpulse = v,
      ),
      Field.number(
        'debrisMass',
        (f) => f.debrisMass,
        (f, v) => f.debrisMass = v,
      ),
      Field.boolean(
        'hideOriginalOnFracture',
        (f) => f.hideOriginalOnFracture,
        (f, v) => f.hideOriginalOnFracture = v,
      ),
      Field.boolean(
        'autoAddRigidBodies',
        (f) => f.autoAddRigidBodies,
        (f, v) => f.autoAddRigidBodies = v,
      ),
    ],
  );

  bool get isFractured => _isFractured;
  int get shardCount => _lastShardCount;
  double get lastTotalVolume => _lastTotalVolume;
  List<GameObject> get spawnedPieces => List.unmodifiable(_spawnedPieces);

  frac.FractureMesh resolveSourceMesh() {
    if (sourceMesh != null) return sourceMesh!;
    if (isAttached) {
      final mr = getComponent<MeshRenderer>();
      if (mr?.meshData != null) {
        return meshDataToFractureMesh(mr!.meshData!);
      }
      final stretch = transform.localStretch;
      return frac.FractureMesh.box(
        size: frac.FracVec3(stretch.x.abs(), stretch.y.abs(), stretch.z.abs()),
      );
    }
    return frac.FractureMesh.box();
  }

  GameObject _spawnMeshPiece({
    required String name,
    required frac.FractureMesh localCenteredMesh,
    required Vec3 worldPosition,
    required Quat worldRotation,
    required MaterialHandle? mat,
    required Vec3 initialVelocity,
    required double pieceMass,
  }) {
    final meshData = fractureMeshToMeshData(localCenteredMesh);
    MeshHandle? handle;
    if (scene.isLoaded) {
      handle = engine.graphics.createMesh(meshData, debugLabel: name);
      _ownedMeshHandles.add(handle);
    }

    final components = <Component>[
      MeshRenderer(mesh: handle, meshData: meshData, material: mat),
    ];
    if (autoAddRigidBodies) {
      components.add(
        RigidBody(mass: math.max(0.2, pieceMass), velocity: initialVelocity),
      );
    }

    final go = scene.createGameObject(
      name,
      position: worldPosition,
      rotation: worldRotation,
      components: components,
    );
    _spawnedPieces.add(go);
    return go;
  }

  /// Cuts this object along the world-space plane `(worldPoint, worldNormal)` into two capped halves.
  ({GameObject? positive, GameObject? negative, bool hadCut}) sliceAlongPlane(
    Vec3 worldPoint,
    Vec3 worldNormal, {
    double separationSpeed = 1.5,
  }) {
    final src = resolveSourceMesh();
    final invRot = isAttached ? transform.rotation.inverse : Quat.identity;
    final pos = isAttached ? transform.position : Vec3.zero;
    final localPt = invRot.rotate(worldPoint - pos);
    final localNorm = invRot.rotate(worldNormal).normalized;

    final plane = frac.FracPlane.fromPointNormal(
      frac.FracVec3(localPt.x, localPt.y, localPt.z),
      frac.FracVec3(localNorm.x, localNorm.y, localNorm.z),
    );
    final result = frac.MeshPlaneSlicer.slice(src, plane);
    if (!result.hadCut || !isAttached) {
      return (positive: null, negative: null, hadCut: result.hadCut);
    }

    resetIntact();
    final siblingMr = getComponent<MeshRenderer>();
    final mat = materialOverride ?? siblingMr?.material;
    if (hideOriginalOnFracture && siblingMr != null) {
      siblingMr._leaf?.visible = false;
    }

    final baseRot = transform.rotation;
    final totalVol = math.max(1e-5, src.computeSignedVolume().abs());
    GameObject? posGo;
    GameObject? negGo;
    var spawnedVol = 0.0;

    if (result.positive != null) {
      final half = result.positive!;
      final c = half.computeCentroid();
      final vol = half.computeSignedVolume().abs();
      spawnedVol += vol;
      final centered = half.translated(-c);
      final wPos = pos + baseRot.rotate(Vec3(c.x, c.y, c.z));
      final sepDir = worldNormal.normalized * separationSpeed;
      posGo = _spawnMeshPiece(
        name: '${gameObject.name}_PosHalf',
        localCenteredMesh: centered,
        worldPosition: wPos,
        worldRotation: baseRot,
        mat: mat,
        initialVelocity: sepDir,
        pieceMass: debrisMass * (vol / totalVol),
      );
    }

    if (result.negative != null) {
      final half = result.negative!;
      final c = half.computeCentroid();
      final vol = half.computeSignedVolume().abs();
      spawnedVol += vol;
      final centered = half.translated(-c);
      final wPos = pos + baseRot.rotate(Vec3(c.x, c.y, c.z));
      final sepDir = -worldNormal.normalized * separationSpeed;
      negGo = _spawnMeshPiece(
        name: '${gameObject.name}_NegHalf',
        localCenteredMesh: centered,
        worldPosition: wPos,
        worldRotation: baseRot,
        mat: mat,
        initialVelocity: sepDir,
        pieceMass: debrisMass * (vol / totalVol),
      );
    }

    _isFractured = true;
    _lastShardCount = _spawnedPieces.length;
    _lastTotalVolume = spawnedVol;
    return (positive: posGo, negative: negGo, hadCut: true);
  }

  /// Shatters this object into [voronoiCellCount] convex Voronoi shards pushed away from [worldImpactPoint].
  List<GameObject> shatterVoronoi({
    int? cellCount,
    int? seedOverride,
    Vec3? worldImpactPoint,
    double? impulseSpeed,
  }) {
    final src = resolveSourceMesh();
    final pos = isAttached ? transform.position : Vec3.zero;
    final rot = isAttached ? transform.rotation : Quat.identity;
    final invRot = rot.inverse;

    frac.FracVec3? localImpact;
    if (worldImpactPoint != null) {
      final lp = invRot.rotate(worldImpactPoint - pos);
      localImpact = frac.FracVec3(lp.x, lp.y, lp.z);
    }

    final shards = frac.VoronoiFractureBuilder.fracture(
      mesh: src,
      cellCount: math.max(2, cellCount ?? voronoiCellCount),
      seed: seedOverride ?? seed,
      impactPoint: localImpact,
      clusterBias: clusterBias,
    );
    if (!isAttached || shards.isEmpty) return const [];

    resetIntact();
    final siblingMr = getComponent<MeshRenderer>();
    final mat = materialOverride ?? siblingMr?.material;
    if (hideOriginalOnFracture && siblingMr != null) {
      siblingMr._leaf?.visible = false;
    }

    final totalVol = math.max(1e-5, src.computeSignedVolume().abs());
    final blastOrigin = worldImpactPoint ?? pos;
    final speed = impulseSpeed ?? debrisImpulse;
    var volSum = 0.0;

    for (final shard in shards) {
      volSum += shard.volume;
      final centered = shard.mesh.translated(-shard.centroid);
      final worldCentroid =
          pos +
          rot.rotate(
            Vec3(shard.centroid.x, shard.centroid.y, shard.centroid.z),
          );
      final away = worldCentroid - blastOrigin;
      final dir = away.lengthSquared > 1e-6 ? away.normalized : Vec3.unitY;
      _spawnMeshPiece(
        name: '${gameObject.name}_Shard_${shard.index}',
        localCenteredMesh: centered,
        worldPosition: worldCentroid,
        worldRotation: rot,
        mat: mat,
        initialVelocity: dir * speed,
        pieceMass: debrisMass * (shard.volume / totalVol),
      );
    }

    _isFractured = true;
    _lastShardCount = _spawnedPieces.length;
    _lastTotalVolume = volSum;
    return List<GameObject>.unmodifiable(_spawnedPieces);
  }

  /// Destroys any spawned shards and restores the original [MeshRenderer].
  void resetIntact() {
    for (final go in _spawnedPieces) {
      if (!go.isDestroyed) go.destroy();
    }
    _spawnedPieces.clear();

    if (isAttached && scene.isLoaded) {
      for (final h in _ownedMeshHandles) {
        engine.graphics.releaseMesh(h);
      }
    }
    _ownedMeshHandles.clear();

    if (isAttached) {
      final mr = getComponent<MeshRenderer>();
      if (mr != null) mr._leaf?.visible = true;
    }
    _isFractured = false;
    _lastShardCount = 0;
    _lastTotalVolume = 0.0;
  }

  @override
  void onDestroy() {
    resetIntact();
  }
}

/// Manages load-bearing structural piece graphs (`voxfracture`) and detaches unsupported islands (E59-2).
final class StructuralSupportComponent extends Component {
  final frac.StructuralSupportGraph graph = frac.StructuralSupportGraph();
  final Map<String, GameObject> _pieceById = {};
  double cantileverLeverageFactor;
  bool autoDropUnsupported;

  frac.CollapseResult? _lastCollapse;

  StructuralSupportComponent({
    this.cantileverLeverageFactor = 1.5,
    this.autoDropUnsupported = true,
  });

  static final spec = ComponentSpec<StructuralSupportComponent>(
    'StructuralSupportComponent',
    StructuralSupportComponent.new,
    [
      Field.number(
        'cantileverLeverageFactor',
        (s) => s.cantileverLeverageFactor,
        (s, v) => s.cantileverLeverageFactor = v,
      ),
      Field.boolean(
        'autoDropUnsupported',
        (s) => s.autoDropUnsupported,
        (s, v) => s.autoDropUnsupported = v,
      ),
    ],
  );

  int get totalPieceCount => graph.nodes.length;
  int get intactCount => graph.intactCount;
  double get stabilityRatio => graph.stabilityRatio;
  frac.CollapseResult? get lastCollapse => _lastCollapse;

  String linkPiece(
    GameObject piece, {
    bool isAnchor = false,
    double mass = 1.0,
    double maxHitPoints = 100.0,
  }) {
    final id = 'node_${piece.transform.instanceId}';
    final p = piece.transform.position;
    _pieceById[id] = piece;
    graph.addNode(
      frac.SupportNode(
        id: id,
        position: frac.FracVec3(p.x, p.y, p.z),
        mass: mass,
        isAnchor: isAnchor,
        maxHitPoints: maxHitPoints,
      ),
    );
    return id;
  }

  void connectPieces(GameObject a, GameObject b, {double bondStrength = 24.0}) {
    graph.addEdge(
      frac.SupportEdge(
        nodeA: 'node_${a.transform.instanceId}',
        nodeB: 'node_${b.transform.instanceId}',
        bondStrength: bondStrength,
      ),
    );
  }

  frac.CollapseResult recomputeStability() {
    final res = graph.recomputeStability(
      cantileverLeverageFactor: cantileverLeverageFactor,
    );
    _applyCollapseToPieces(res);
    return res;
  }

  frac.CollapseResult applyBlastDamage(
    Vec3 worldOrigin, {
    double radius = 2.5,
    double damage = 150.0,
  }) {
    final res = graph.applyDamageAt(
      frac.FracVec3(worldOrigin.x, worldOrigin.y, worldOrigin.z),
      radius: radius,
      damage: damage,
    );
    _applyCollapseToPieces(res);
    return res;
  }

  void _applyCollapseToPieces(frac.CollapseResult res) {
    _lastCollapse = res;
    if (!autoDropUnsupported) return;
    for (final id in res.detachedNodeIds) {
      final piece = _pieceById[id];
      if (piece == null || piece.isDestroyed) continue;
      final rb = piece.getComponent<RigidBody>();
      if (rb != null) {
        rb.isKinematic = false;
        rb.useGravity = true;
      } else {
        piece.addComponent(RigidBody(mass: 5.0, useGravity: true));
      }
    }
  }
}

/// Persistent UI interaction state for [DestructionInspectorUI.render].
final class DestructionInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` mesh slicing, Voronoi shatter & stability inspector (E59-2).
final class DestructionInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    DestructionInspectorUiState state,
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
    FracturableMeshComponent fracturable, {
    StructuralSupportComponent? support,
    DestructionInspectorUiState? state,
    String title = 'Mesh Destruction Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? DestructionInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final statusStr = fracturable.isFractured ? 'SHATTERED' : 'INTACT';
    final stabilityPct = support != null
        ? '${(support.stabilityRatio * 100).round()}%'
        : '100%';
    final intactLabel = support != null
        ? '${support.intactCount}/${support.totalPieceCount}'
        : 'N/A';

    ui.labelValue(
      'State / Shards',
      '$statusStr / ${fracturable.shardCount}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Stability / Nodes',
      '$stabilityPct / $intactLabel',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Cells / Bias',
      '${fracturable.voronoiCellCount} / ${fracturable.clusterBias.toStringAsFixed(2)}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Fractured Vol',
      '${fracturable.lastTotalVolume.toStringAsFixed(2)} m3',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final sliceRect = VoxRect(x + pad, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'frac_slice', 'Slice Y', sliceRect)) {
      final pos = fracturable.isAttached
          ? fracturable.transform.position
          : Vec3.zero;
      fracturable.sliceAlongPlane(pos, Vec3.unitY);
    }

    final voroRect = VoxRect(sliceRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'frac_voronoi', 'Voronoi', voroRect)) {
      fracturable.shatterVoronoi();
    }

    final resetRect = VoxRect(voroRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'frac_reset', 'Reset', resetRect)) {
      fracturable.resetIntact();
    }

    ui.endWindow();
  }
}
