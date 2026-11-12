part of '../../engine.dart';

/// Marks a spawned scene [GameObject] belonging to a [ConstructionPlannerComponent] piece (E62-2).
final class BlueprintPieceComponent extends Component {
  String defId;
  int pieceInstanceId;
  int yawSteps;
  bool supported;

  BlueprintPieceComponent({
    this.defId = 'floor',
    this.pieceInstanceId = 0,
    this.yawSteps = 0,
    this.supported = true,
  });

  static final spec = ComponentSpec<BlueprintPieceComponent>(
    'BlueprintPieceComponent',
    BlueprintPieceComponent.new,
    [
      Field.text('defId', (b) => b.defId, (b, v) => b.defId = v),
      Field.integer('pieceInstanceId', (b) => b.pieceInstanceId, (b, v) => b.pieceInstanceId = v),
      Field.integer('yawSteps', (b) => b.yawSteps, (b, v) => b.yawSteps = v),
      Field.boolean('supported', (b) => b.supported, (b, v) => b.supported = v),
    ],
  );
}

/// Interactive modular base-building controller wrapping `voxbuild`'s [vbuild.SnapGridSolver] (E62-2).
final class ConstructionPlannerComponent extends Behaviour {
  double gridSize;
  double heightStep;
  double socketSnapRadius;
  double clearanceMargin;
  double groundHeight;
  bool showGhostPreview;

  vbuild.SnapGridSolver? _solver;
  double? _cfgGrid;
  double? _cfgHeight;
  double? _cfgSnap;
  double? _cfgClearance;

  final Map<String, MeshData> _pieceMeshes = {};
  final Map<String, LinearColor> _pieceColors = {};
  final Map<int, GameObject> _placedObjects = {};
  final List<int> _history = [];
  final List<vbuild.ConstructionBlueprint> savedBlueprints = [];

  String activeDefId = 'floor';
  int activeYawSteps = 0;
  Vec3 cursorWorld = Vec3.zero;
  vbuild.BuildSnapCandidate? lastCandidate;
  GameObject? _ghostObject;

  ConstructionPlannerComponent({
    this.gridSize = 2.0,
    this.heightStep = 1.5,
    this.socketSnapRadius = 1.25,
    this.clearanceMargin = 0.02,
    this.groundHeight = 0.0,
    this.showGhostPreview = true,
  });

  static final spec = ComponentSpec<ConstructionPlannerComponent>(
    'ConstructionPlannerComponent',
    ConstructionPlannerComponent.new,
    [
      Field.number('gridSize', (c) => c.gridSize, (c, v) => c.gridSize = v),
      Field.number('heightStep', (c) => c.heightStep, (c, v) => c.heightStep = v),
      Field.number('socketSnapRadius', (c) => c.socketSnapRadius, (c, v) => c.socketSnapRadius = v),
      Field.number('clearanceMargin', (c) => c.clearanceMargin, (c, v) => c.clearanceMargin = v),
      Field.number('groundHeight', (c) => c.groundHeight, (c, v) => c.groundHeight = v),
      Field.boolean('showGhostPreview', (c) => c.showGhostPreview, (c, v) => c.showGhostPreview = v),
    ],
  );

  vbuild.SnapGridSolver _ensureSolver() {
    if (_solver == null) {
      _solver = vbuild.SnapGridSolver(
        gridSize: gridSize,
        heightStep: heightStep,
        socketSnapRadius: socketSnapRadius,
        clearanceMargin: clearanceMargin,
      );
    } else if (_cfgGrid != gridSize ||
        _cfgHeight != heightStep ||
        _cfgSnap != socketSnapRadius ||
        _cfgClearance != clearanceMargin) {
      _solver!
        ..gridSize = gridSize
        ..heightStep = heightStep
        ..socketSnapRadius = socketSnapRadius
        ..clearanceMargin = clearanceMargin;
    }
    _cfgGrid = gridSize;
    _cfgHeight = heightStep;
    _cfgSnap = socketSnapRadius;
    _cfgClearance = clearanceMargin;
    return _solver!;
  }

  vbuild.SnapGridSolver get solver => _ensureSolver();
  int get placedCount => _ensureSolver().placedPieces.length;

  void registerPieceDef(
    vbuild.BuildPieceDef def, {
    MeshData? meshData,
    LinearColor? tintColor,
  }) {
    _ensureSolver().registerPiece(def);
    if (meshData != null) {
      _pieceMeshes[def.id] = meshData;
    }
    if (tintColor != null) {
      _pieceColors[def.id] = tintColor;
    }
    activeDefId = _ensureSolver().definitions.keys.contains(activeDefId)
        ? activeDefId
        : def.id;
  }

  void rotateClockwise([int steps = 1]) {
    activeYawSteps = (activeYawSteps + steps) % 4;
    previewAt(cursorWorld);
  }

  /// Evaluates placement at [worldCursor] and updates the scene ghost preview mesh.
  vbuild.BuildSnapCandidate previewAt(
    Vec3 worldCursor, {
    String? defId,
    int? yawSteps,
  }) {
    cursorWorld = worldCursor;
    final targetId = defId ?? activeDefId;
    final yaw = yawSteps ?? activeYawSteps;
    final cand = _ensureSolver().evaluatePlacement(
      defId: targetId,
      cursorWorld: vbuild.BuildVec3(worldCursor.x, worldCursor.y, worldCursor.z),
      yawSteps: yaw,
      groundHeight: groundHeight,
    );
    lastCandidate = cand;
    _syncGhost(cand);
    return cand;
  }

  void _syncGhost(vbuild.BuildSnapCandidate cand) {
    if (!showGhostPreview || !isAttached || !scene.isLoaded) {
      _ghostObject?.setActive(false);
      return;
    }
    final def = _ensureSolver().definitions[cand.defId];
    if (def == null) {
      _ghostObject?.setActive(false);
      return;
    }

    final meshData = _pieceMeshes[def.id] ?? Primitives.cube(size: 1.0);
    final ghostTint = cand.isValid
        ? const LinearColor(0.2, 0.9, 0.35)
        : const LinearColor(0.95, 0.25, 0.2);

    if (_ghostObject == null) {
      _ghostObject = scene.createGameObject(
        '${gameObject.name}#GhostPreview',
        components: [
          MeshRenderer(
            meshData: meshData,
            tintColor: ghostTint,
            castsShadow: false,
          ),
        ],
      );
    } else {
      final mr = _ghostObject!.getComponent<MeshRenderer>();
      mr?.setTint(ghostTint);
      _ghostObject!.setActive(true);
    }
    _ghostObject!.transform.position = Vec3(cand.position.x, cand.position.y, cand.position.z);
    _ghostObject!.transform.rotation = Quat(
      cand.rotation.x,
      cand.rotation.y,
      cand.rotation.z,
      cand.rotation.w,
    );
    if (!_pieceMeshes.containsKey(def.id)) {
      _ghostObject!.transform.localStretch = Vec3(
        def.halfExtents.x * 2.0,
        def.halfExtents.y * 2.0,
        def.halfExtents.z * 2.0,
      );
    }
  }

  /// Validates and commits a piece at [worldCursor], spawning its scene [GameObject].
  GameObject? placeAt(
    Vec3 worldCursor, {
    String? defId,
    int? yawSteps,
  }) {
    cursorWorld = worldCursor;
    final targetId = defId ?? activeDefId;
    final yaw = yawSteps ?? activeYawSteps;
    final placed = _ensureSolver().place(
      defId: targetId,
      cursorWorld: vbuild.BuildVec3(worldCursor.x, worldCursor.y, worldCursor.z),
      yawSteps: yaw,
      groundHeight: groundHeight,
    );
    if (placed == null) return null;
    final go = _spawnGameObjectForPlaced(placed);
    previewAt(worldCursor, defId: targetId, yawSteps: yaw);
    return go;
  }

  GameObject _spawnGameObjectForPlaced(vbuild.PlacedBuildPiece placed) {
    if (!isAttached) {
      throw StateError('ConstructionPlannerComponent must be attached to a Scene.');
    }
    final def = _ensureSolver().definitions[placed.defId]!;
    final meshData = _pieceMeshes[def.id] ?? Primitives.cube(size: 1.0);
    final tint = _pieceColors[def.id] ?? const LinearColor(0.75, 0.68, 0.58);
    final go = scene.createGameObject(
      'Build_${placed.defId}_${placed.instanceId}',
      position: Vec3(placed.position.x, placed.position.y, placed.position.z),
      rotation: Quat(placed.rotation.x, placed.rotation.y, placed.rotation.z, placed.rotation.w),
      components: [
        MeshRenderer(meshData: meshData, tintColor: tint),
        BoxCollider(
          size: Vec3(def.halfExtents.x * 2.0, def.halfExtents.y * 2.0, def.halfExtents.z * 2.0),
        ),
        BlueprintPieceComponent(
          defId: placed.defId,
          pieceInstanceId: placed.instanceId,
          yawSteps: placed.yawSteps,
          supported: placed.supported,
        ),
      ],
    );
    if (!_pieceMeshes.containsKey(def.id)) {
      go.transform.localStretch = Vec3(
        def.halfExtents.x * 2.0,
        def.halfExtents.y * 2.0,
        def.halfExtents.z * 2.0,
      );
    }
    _placedObjects[placed.instanceId] = go;
    _history.add(placed.instanceId);
    return go;
  }

  /// Removes a placed piece and returns any now-unsupported floating piece [GameObject]s.
  List<GameObject> demolishPiece(int pieceInstanceId, {bool destroyOrphans = false}) {
    final removed = _ensureSolver().removePiece(pieceInstanceId);
    if (!removed) return const [];
    _history.remove(pieceInstanceId);
    final targetGo = _placedObjects.remove(pieceInstanceId);
    if (targetGo != null && isAttached) {
      targetGo.destroy();
    }

    final orphanIds = _ensureSolver().recomputeSupport();
    final orphans = <GameObject>[];
    for (final oid in orphanIds) {
      final go = _placedObjects[oid];
      if (go == null) continue;
      final bp = go.getComponent<BlueprintPieceComponent>();
      bp?.supported = false;
      orphans.add(go);
      if (destroyOrphans) {
        _ensureSolver().removePiece(oid);
        _placedObjects.remove(oid);
        _history.remove(oid);
        if (isAttached) go.destroy();
      }
    }
    return orphans;
  }

  bool undoLastPlacement() {
    if (_history.isEmpty) return false;
    final lastId = _history.last;
    demolishPiece(lastId);
    return true;
  }

  vbuild.ConstructionBlueprint captureBlueprint(String name, {Vec3? origin}) {
    final bp = vbuild.ConstructionBlueprint.capture(
      name: name,
      pieces: _ensureSolver().placedPieces.values,
      definitions: _ensureSolver().definitions,
      origin: origin != null ? vbuild.BuildVec3(origin.x, origin.y, origin.z) : null,
    );
    savedBlueprints.add(bp);
    return bp;
  }

  List<GameObject> stampBlueprint(
    vbuild.ConstructionBlueprint bp,
    Vec3 worldOrigin, {
    int yawSteps = 0,
  }) {
    final placed = bp.stamp(
      _ensureSolver(),
      worldOrigin: vbuild.BuildVec3(worldOrigin.x, worldOrigin.y, worldOrigin.z),
      yawSteps: yawSteps,
      groundHeight: groundHeight,
    );
    return [for (final p in placed) _spawnGameObjectForPlaced(p)];
  }

  Map<String, double> get totalStructureCost {
    final totals = <String, double>{};
    final s = _ensureSolver();
    for (final p in s.placedPieces.values) {
      final def = s.definitions[p.defId];
      if (def == null) continue;
      for (final c in def.costs) {
        totals[c.resourceId] = (totals[c.resourceId] ?? 0.0) + c.amount;
      }
    }
    return totals;
  }

  @override
  void onDestroy() {
    _ghostObject?.destroy();
    _ghostObject = null;
  }
}

/// Persistent UI interaction state for [BuilderInspectorUI.render].
final class BuilderInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` modular building inspector & stamp palette (E62-2).
final class BuilderInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    BuilderInspectorUiState state,
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
    ConstructionPlannerComponent planner, {
    BuilderInspectorUiState? state,
    String title = 'Modular Builder',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 240.0,
  }) {
    final uiState = state ?? BuilderInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final cand = planner.lastCandidate;
    final validityText = cand == null
        ? 'IDLE'
        : (cand.isValid ? 'VALID' : cand.validity.name.toUpperCase());
    final costMap = planner.totalStructureCost;
    final costSummary = costMap.isEmpty
        ? '0 res'
        : costMap.entries.map((e) => '${e.key}:${e.value.toInt()}').join(' ');

    ui.labelValue(
      'Piece / Yaw',
      '${planner.activeDefId} / ${planner.activeYawSteps * 90}deg',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Placed / Status',
      '${planner.placedCount} pcs / $validityText',
      valueColor: (cand?.isValid ?? true) ? VoxColor.green : VoxColor.red,
    );
    ui.labelValue(
      'Snap / Cost',
      '${cand?.snappedToSocketId ?? "grid"} / $costSummary',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Grid / BPs',
      '${planner.gridSize.toStringAsFixed(1)}m / ${planner.savedBlueprints.length}',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final placeRect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'bld_place', 'Place', placeRect)) {
      planner.placeAt(planner.cursorWorld);
    }

    final rotRect = VoxRect(placeRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'bld_rot', 'Rot +90', rotRect)) {
      planner.rotateClockwise();
    }

    final undoRect = VoxRect(rotRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'bld_undo', 'Undo', undoRect)) {
      planner.undoLastPlacement();
    }

    final stampRect = VoxRect(undoRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'bld_stamp', 'Stamp BP', stampRect) &&
        planner.savedBlueprints.isNotEmpty) {
      planner.stampBlueprint(
        planner.savedBlueprints.last,
        planner.cursorWorld + Vec3(planner.gridSize * 2.0, 0.0, 0.0),
        yawSteps: planner.activeYawSteps,
      );
    }

    ui.endWindow();
  }
}
