part of '../../engine.dart';

/// Spatial hash & sweep-and-prune broadphase + continuous swept-AABB TOI world (`voxbroad`) (E80-2).
final class BroadphaseWorldComponent extends Behaviour {
  double cellSize;
  broad.SapAxis sapAxis;
  bool useSapBroadphase;
  bool autoSyncSceneColliders;
  bool ignoreStaticStatic;

  late broad.SpatialHashGrid3D grid;
  late broad.SweepAndPrune1D sap;

  final Map<int, Collider> _idToCollider = {};
  final Map<Collider, int> _colliderToId = {};
  double _builtCellSize;
  broad.SapAxis _builtSapAxis;

  List<broad.BroadPair> _lastPairs = const [];
  int _toiSweepCount = 0;

  BroadphaseWorldComponent({
    this.cellSize = 4.0,
    this.sapAxis = broad.SapAxis.x,
    this.useSapBroadphase = false,
    this.autoSyncSceneColliders = true,
    this.ignoreStaticStatic = true,
  })  : _builtCellSize = math.max(0.25, cellSize),
        _builtSapAxis = sapAxis {
    grid = broad.SpatialHashGrid3D(cellSize: _builtCellSize);
    sap = broad.SweepAndPrune1D(axis: _builtSapAxis);
  }

  static final spec = ComponentSpec<BroadphaseWorldComponent>(
    'BroadphaseWorldComponent',
    BroadphaseWorldComponent.new,
    [
      Field.number('cellSize', (c) => c.cellSize, (c, v) => c.setCellSize(v)),
      Field.enumValue<BroadphaseWorldComponent, broad.SapAxis>(
        'sapAxis',
        broad.SapAxis.values,
        (c) => c.sapAxis,
        (c, v) => c.setSapAxis(v),
      ),
      Field.boolean(
        'useSapBroadphase',
        (c) => c.useSapBroadphase,
        (c, v) => c.useSapBroadphase = v,
      ),
      Field.boolean(
        'autoSyncSceneColliders',
        (c) => c.autoSyncSceneColliders,
        (c, v) => c.autoSyncSceneColliders = v,
      ),
      Field.boolean(
        'ignoreStaticStatic',
        (c) => c.ignoreStaticStatic,
        (c, v) => c.ignoreStaticStatic = v,
      ),
    ],
  );

  int get trackedCount => grid.entryCount;
  int get occupiedCellCount => grid.occupiedCellCount;
  double get averageBucketLoad => grid.averageBucketLoad;
  int get overlapPairCount => _lastPairs.length;
  int get toiSweepCount => _toiSweepCount;
  List<broad.BroadPair> get overlapPairs => _lastPairs;

  Collider? colliderByEntryId(int id) => _idToCollider[id];

  int _idForCollider(Collider c) {
    final existing = _colliderToId[c];
    if (existing != null) return existing;
    final id = c.instanceId;
    _colliderToId[c] = id;
    _idToCollider[id] = c;
    return id;
  }

  void setCellSize(double nextSize) {
    final safe = math.max(0.25, nextSize);
    cellSize = safe;
    if ((safe - _builtCellSize).abs() > 1e-6) {
      _builtCellSize = safe;
      grid = broad.SpatialHashGrid3D(cellSize: _builtCellSize);
      syncFromScene();
    }
  }

  void setSapAxis(broad.SapAxis nextAxis) {
    sapAxis = nextAxis;
    if (nextAxis != _builtSapAxis) {
      _builtSapAxis = nextAxis;
      sap = broad.SweepAndPrune1D(axis: _builtSapAxis);
      syncFromScene();
    }
  }

  static broad.BroadAabb _toBroadAabb(Aabb aabb) => broad.BroadAabb(
        broad.BroadVec3(aabb.min.x, aabb.min.y, aabb.min.z),
        broad.BroadVec3(aabb.max.x, aabb.max.y, aabb.max.z),
      );

  void upsertEntry(broad.BroadEntry entry) {
    grid.insertOrUpdate(entry);
    sap.insertOrUpdate(entry);
  }

  void clear() {
    grid.clear();
    sap.clear();
    _idToCollider.clear();
    _colliderToId.clear();
    _lastPairs = const [];
  }

  /// Rebuilds broadphase proxies from all active [Collider] components in [scene].
  List<broad.BroadPair> syncFromScene() {
    final safeCell = math.max(0.25, cellSize);
    if ((safeCell - _builtCellSize).abs() > 1e-6) {
      _builtCellSize = safeCell;
      grid = broad.SpatialHashGrid3D(cellSize: _builtCellSize);
    }
    if (sapAxis != _builtSapAxis) {
      _builtSapAxis = sapAxis;
      sap = broad.SweepAndPrune1D(axis: _builtSapAxis);
    }

    grid.clear();
    sap.clear();
    _idToCollider.clear();
    _colliderToId.clear();

    if (isAttached && scene.isLoaded) {
      for (final col in scene.findObjectsOfType<Collider>()) {
        if (!col.isActiveAndEnabled) continue;
        final id = _idForCollider(col);
        final isStatic = col.getComponent<RigidBody>()?.isKinematic ?? false;
        final entry = broad.BroadEntry(
          id: id,
          aabb: _toBroadAabb(col.worldBounds),
          layerMask: col.collidesWithMask,
          isStatic: isStatic,
        );
        grid.insertOrUpdate(entry);
        sap.insertOrUpdate(entry);
      }
    }

    _lastPairs = useSapBroadphase
        ? sap.computeOverlapPairs(ignoreStaticStatic: ignoreStaticStatic)
        : grid.computeOverlapPairs(ignoreStaticStatic: ignoreStaticStatic);
    return _lastPairs;
  }

  List<Collider> queryAabb(Aabb bounds, {int mask = -1, Collider? exclude}) {
    final exId = exclude == null ? null : _colliderToId[exclude];
    final hits = grid.queryAabb(_toBroadAabb(bounds), mask: mask, excludeId: exId);
    final out = <Collider>[];
    for (final e in hits) {
      final col = _idToCollider[e.id];
      if (col != null) out.add(col);
    }
    return out;
  }

  /// Sweeps [moverBounds] along [displacement] against broadphase candidates to prevent tunneling.
  broad.ToiHitResult? sweepAabbToi(
    Aabb moverBounds,
    Vec3 displacement, {
    int layerMask = -1,
    Collider? exclude,
  }) {
    _toiSweepCount++;
    final minCorner = Vec3(
      math.min(moverBounds.min.x, moverBounds.min.x + displacement.x),
      math.min(moverBounds.min.y, moverBounds.min.y + displacement.y),
      math.min(moverBounds.min.z, moverBounds.min.z + displacement.z),
    );
    final maxCorner = Vec3(
      math.max(moverBounds.max.x, moverBounds.max.x + displacement.x),
      math.max(moverBounds.max.y, moverBounds.max.y + displacement.y),
      math.max(moverBounds.max.z, moverBounds.max.z + displacement.z),
    );
    final sweptBounds = _toBroadAabb(Aabb(minCorner, maxCorner));
    final exId = exclude == null ? null : _colliderToId[exclude];
    final candidates = grid.queryAabb(
      sweptBounds,
      mask: layerMask,
      excludeId: exId,
    );
    return broad.SweptAabbToi.sweepFirstHit(
      mover: _toBroadAabb(moverBounds),
      delta: broad.BroadVec3(displacement.x, displacement.y, displacement.z),
      obstacles: candidates,
      excludeId: exId,
      layerMask: layerMask,
    );
  }

  @override
  void fixedUpdate() {
    if (autoSyncSceneColliders) {
      syncFromScene();
    }
  }
}

/// Persistent UI state for [BroadphaseStatsUI.render].
final class BroadphaseStatsUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` broadphase spatial hash & SAP diagnostics inspector (E80-2).
final class BroadphaseStatsUI {
  static bool _drawButton(
    VoxUiContext ui,
    BroadphaseStatsUiState state,
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
    BroadphaseWorldComponent world, {
    BroadphaseStatsUiState? state,
    String title = 'Broadphase World',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? BroadphaseStatsUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Backend / Cell',
      '${world.useSapBroadphase ? 'SAP (${world.sapAxis.name})' : 'HashGrid3D'} | ${world.cellSize.toStringAsFixed(1)}m',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Proxies / Cells',
      '${world.trackedCount} bodies | ${world.occupiedCellCount} cells (load ${world.averageBucketLoad.toStringAsFixed(2)})',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Pairs / TOI',
      '${world.overlapPairCount} overlaps | ${world.toiSweepCount} sweeps',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Static Filter',
      world.ignoreStaticStatic ? 'Ignore Static-Static' : 'Include All Pairs',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final syncRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'bp_sync', 'Sync Now', syncRect)) {
      world.syncFromScene();
    }

    final modeRect = VoxRect(syncRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'bp_mode', 'Toggle SAP', modeRect)) {
      world.useSapBroadphase = !world.useSapBroadphase;
      world.syncFromScene();
    }

    final cellRect = VoxRect(modeRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'bp_cell', 'Cell +1m', cellRect)) {
      world.setCellSize(world.cellSize + 1.0);
    }

    final clearRect = VoxRect(cellRect.right + 8.0, barY, 68.0, 22.0);
    if (_drawButton(ui, uiState, 'bp_clear', 'Clear', clearRect)) {
      world.clear();
    }

    ui.endWindow();
  }
}
