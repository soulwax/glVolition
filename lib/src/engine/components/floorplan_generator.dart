part of '../../engine.dart';

/// Procedural architectural floorplan generator & geometry builder powered by `voxarch` (E72-2).
final class FloorplanGeneratorComponent extends Behaviour {
  double boundsWidth;
  double boundsDepth;
  double wallHeight;
  double wallThickness;
  double minRoomExtent;
  double doorWidth;
  double corridorWidth;
  double windowWidth;
  int seed;
  bool carveCentralCorridor;
  bool spawnGeometry;
  bool autoGenerateOnEnable;

  final List<arch.ArchRoomSpec> programSpecs = [
    const arch.ArchRoomSpec(
      id: 'foyer',
      role: 'entry',
      targetWeight: 0.8,
      connectsToExterior: true,
      requiredAdjacencyIds: ['living'],
    ),
    const arch.ArchRoomSpec(
      id: 'living',
      role: 'common',
      targetWeight: 1.6,
      requiredAdjacencyIds: ['kitchen'],
    ),
    const arch.ArchRoomSpec(id: 'kitchen', role: 'utility', targetWeight: 1.0),
    const arch.ArchRoomSpec(id: 'study', role: 'office', targetWeight: 1.0),
    const arch.ArchRoomSpec(
      id: 'bath',
      role: 'wet',
      targetWeight: 0.7,
      preferredExteriorWindow: false,
    ),
  ];

  arch.ArchFloorplanResult? _lastResult;
  final List<GameObject> _generatedObjects = [];

  FloorplanGeneratorComponent({
    this.boundsWidth = 18.0,
    this.boundsDepth = 12.0,
    this.wallHeight = 3.0,
    this.wallThickness = 0.25,
    this.minRoomExtent = 2.4,
    this.doorWidth = 1.2,
    this.corridorWidth = 1.8,
    this.windowWidth = 1.4,
    this.seed = 42,
    this.carveCentralCorridor = false,
    this.spawnGeometry = true,
    this.autoGenerateOnEnable = true,
  });

  static final spec = ComponentSpec<FloorplanGeneratorComponent>(
    'FloorplanGeneratorComponent',
    FloorplanGeneratorComponent.new,
    [
      Field.number('boundsWidth', (f) => f.boundsWidth, (f, v) => f.boundsWidth = v),
      Field.number('boundsDepth', (f) => f.boundsDepth, (f, v) => f.boundsDepth = v),
      Field.number('wallHeight', (f) => f.wallHeight, (f, v) => f.wallHeight = v),
      Field.number('wallThickness', (f) => f.wallThickness, (f, v) => f.wallThickness = v),
      Field.number('minRoomExtent', (f) => f.minRoomExtent, (f, v) => f.minRoomExtent = v),
      Field.number('doorWidth', (f) => f.doorWidth, (f, v) => f.doorWidth = v),
      Field.number('corridorWidth', (f) => f.corridorWidth, (f, v) => f.corridorWidth = v),
      Field.number('windowWidth', (f) => f.windowWidth, (f, v) => f.windowWidth = v),
      Field.integer('seed', (f) => f.seed, (f, v) => f.seed = v),
      Field.boolean(
        'carveCentralCorridor',
        (f) => f.carveCentralCorridor,
        (f, v) => f.carveCentralCorridor = v,
      ),
      Field.boolean('spawnGeometry', (f) => f.spawnGeometry, (f, v) => f.spawnGeometry = v),
      Field.boolean(
        'autoGenerateOnEnable',
        (f) => f.autoGenerateOnEnable,
        (f, v) => f.autoGenerateOnEnable = v,
      ),
    ],
  );

  arch.ArchFloorplanResult? get lastResult => _lastResult;
  int get spawnedObjectCount => _generatedObjects.length;

  void setProgramSpecs(Iterable<arch.ArchRoomSpec> specs) {
    programSpecs
      ..clear()
      ..addAll(specs);
  }

  /// Generates a deterministic floorplan layout and optionally spawns floor/wall [GameObject]s.
  arch.ArchFloorplanResult generateFloorplan({int? customSeed}) {
    if (customSeed != null) {
      seed = customSeed;
    }
    final solver = arch.ArchFloorplanSolver(
      boundsWidth: math.max(4.0, boundsWidth),
      boundsDepth: math.max(4.0, boundsDepth),
      minRoomExtent: math.max(1.2, minRoomExtent),
      doorWidth: math.max(0.7, doorWidth),
      corridorWidth: math.max(1.0, corridorWidth),
      windowWidth: math.max(0.8, windowWidth),
      carveCentralCorridor: carveCentralCorridor,
    );
    final res = solver.solve(programSpecs, seed: seed);
    _lastResult = res;

    if (spawnGeometry && isAttached) {
      syncSceneGeometry();
    } else {
      clearGeneratedGeometry();
    }
    return res;
  }

  void clearGeneratedGeometry() {
    for (final go in _generatedObjects) {
      if (go.scene.isLoaded) {
        go.destroy();
      }
    }
    _generatedObjects.clear();
  }

  GameObject _spawnBox({
    required String name,
    required Vec3 worldPos,
    required Vec3 dimensions,
    required LinearColor tint,
    bool collider = true,
  }) {
    final unitCube = Primitives.cube(size: 1.0);
    final go = scene.createGameObject(
      name,
      position: worldPos,
      components: [
        MeshRenderer(meshData: unitCube, tintColor: tint),
        if (collider) BoxCollider(size: dimensions, isTrigger: false),
      ],
    );
    go.transform.localStretch = dimensions;
    _generatedObjects.add(go);
    return go;
  }

  /// Spawns centered floor slabs and doorway-cut wall colliders matching [lastResult].
  int syncSceneGeometry() {
    clearGeneratedGeometry();
    if (!isAttached) return 0;
    final res = _lastResult ?? generateFloorplan();

    final origin = transform.position;
    final halfW = res.boundsWidth * 0.5;
    final halfD = res.boundsDepth * 0.5;
    final t = math.max(0.08, wallThickness);
    final h = math.max(0.5, wallHeight);

    // Floor slabs
    for (final r in res.rooms) {
      final tint = r.isCorridor
          ? const LinearColor(0.52, 0.54, 0.58)
          : const LinearColor(0.68, 0.64, 0.56);
      _spawnBox(
        name: 'ArchFloor_${r.id}',
        worldPos: Vec3(origin.x + r.centerX - halfW, origin.y - 0.05, origin.z + r.centerY - halfD),
        dimensions: Vec3(r.width, 0.1, r.height),
        tint: tint,
        collider: true,
      );
    }

    // Deduplicated wall segments with doorway openings excised
    final emittedWallKeys = <String>{};
    var wallIdx = 1;

    void emitWallSegment({
      required bool alongX,
      required double fixedCoord,
      required double start,
      required double end,
      required List<(double, double)> cutouts,
    }) {
      if (end - start <= 0.1) return;
      final qCoord = (fixedCoord * 100).round();
      final qStart = (start * 100).round();
      final qEnd = (end * 100).round();
      final key = '${alongX ? "X" : "Z"}_${qCoord}_${qStart}_$qEnd';
      if (!emittedWallKeys.add(key)) return;

      final sortedCuts = List<(double, double)>.from(cutouts)..sort((a, b) => a.$1.compareTo(b.$1));
      var cursor = start;
      final spans = <(double, double)>[];
      for (final cut in sortedCuts) {
        final cs = cut.$1.clamp(start, end);
        final ce = cut.$2.clamp(start, end);
        if (cs > cursor + 0.05) {
          spans.add((cursor, cs));
        }
        if (ce > cursor) {
          cursor = ce;
        }
      }
      if (cursor < end - 0.05) {
        spans.add((cursor, end));
      }

      for (final span in spans) {
        final len = span.$2 - span.$1;
        if (len < 0.1) continue;
        final mid = (span.$1 + span.$2) * 0.5;
        final wx = origin.x + (alongX ? mid - halfW : fixedCoord - halfW);
        final wz = origin.z + (alongX ? fixedCoord - halfD : mid - halfD);
        final dims = alongX ? Vec3(len, h, t) : Vec3(t, h, len);
        _spawnBox(
          name: 'ArchWall_${wallIdx++}',
          worldPos: Vec3(wx, origin.y + h * 0.5, wz),
          dimensions: dims,
          tint: const LinearColor(0.84, 0.82, 0.78),
          collider: true,
        );
      }
    }

    // Partition walls between adjacent rooms
    for (var i = 0; i < res.rooms.length; i++) {
      for (var j = i + 1; j < res.rooms.length; j++) {
        final shared = res.rooms[i].sharedWallWith(res.rooms[j]);
        if (shared == null) continue;
        final cuts = <(double, double)>[];
        for (final d in res.doorways) {
          if ((d.roomAId == shared.roomAId && d.roomBId == shared.roomBId) ||
              (d.roomAId == shared.roomBId && d.roomBId == shared.roomAId)) {
            final c = shared.spansAlongX ? d.centerX : d.centerY;
            cuts.add((c - d.width * 0.5, c + d.width * 0.5));
          }
        }
        emitWallSegment(
          alongX: shared.spansAlongX,
          fixedCoord: shared.wallCoord,
          start: shared.overlapStart,
          end: shared.overlapEnd,
          cutouts: cuts,
        );
      }
    }

    // Exterior perimeter walls with exterior entrance cutouts
    for (final r in res.rooms) {
      for (final side in r.exteriorSides) {
        final alongX = side == arch.ArchWallSide.north || side == arch.ArchWallSide.south;
        final fixedCoord = switch (side) {
          arch.ArchWallSide.north => r.top,
          arch.ArchWallSide.south => r.bottom,
          arch.ArchWallSide.west => r.left,
          arch.ArchWallSide.east => r.right,
        };
        final start = alongX ? r.left : r.top;
        final end = alongX ? r.right : r.bottom;
        final cuts = <(double, double)>[];
        for (final d in res.doorways) {
          if (d.isExteriorEntrance && d.roomAId == r.id && d.wallSideOnA == side) {
            final c = alongX ? d.centerX : d.centerY;
            cuts.add((c - d.width * 0.5, c + d.width * 0.5));
          }
        }
        emitWallSegment(
          alongX: alongX,
          fixedCoord: fixedCoord,
          start: start,
          end: end,
          cutouts: cuts,
        );
      }
    }

    return _generatedObjects.length;
  }

  /// Exports a walkable [NavGrid] carving interior rooms and doorway openings.
  NavGrid toNavGrid({double cellSize = 1.0}) {
    final res = _lastResult ?? generateFloorplan();
    final step = math.max(0.25, cellSize);
    final cols = math.max(2, (res.boundsWidth / step).round());
    final rows = math.max(2, (res.boundsDepth / step).round());
    final grid = NavGrid(cols, rows, defaultWalkable: true);

    // Block grid cells straddling solid walls unless carved by a doorway
    for (var gy = 0; gy < rows; gy++) {
      final wy = (gy + 0.5) * step;
      for (var gx = 0; gx < cols; gx++) {
        final wx = (gx + 0.5) * step;
        final onOuterBorder = wx < step * 0.6 ||
            wx > res.boundsWidth - step * 0.6 ||
            wy < step * 0.6 ||
            wy > res.boundsDepth - step * 0.6;
        if (!onOuterBorder) continue;
        final nearEntrance = res.doorways.any(
          (d) =>
              d.isExteriorEntrance &&
              (wx - d.centerX).abs() <= d.width * 0.6 &&
              (wy - d.centerY).abs() <= d.width * 0.6,
        );
        if (!nearEntrance) {
          grid.setWalkable(gx, gy, false);
        }
      }
    }
    return grid;
  }

  @override
  void onEnable() {
    if (autoGenerateOnEnable && _lastResult == null) {
      generateFloorplan();
    }
  }

  @override
  void onDestroy() {
    clearGeneratedGeometry();
  }
}

/// Persistent UI interaction state for [FloorplanInspectorUI.render].
final class FloorplanInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` architectural split-grammar floorplan inspector (E72-2).
final class FloorplanInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    FloorplanInspectorUiState state,
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
    FloorplanGeneratorComponent comp, {
    FloorplanInspectorUiState? state,
    String title = 'Floorplan Generator',
    double x = 20.0,
    double y = 20.0,
    double width = 380.0,
    double height = 240.0,
  }) {
    final uiState = state ?? FloorplanInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final res = comp.lastResult;

    ui.labelValue(
      'Rooms / Doors',
      res == null ? 'Not built' : '${res.rooms.length} rms / ${res.doorways.length} doors',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Windows / Spine',
      res == null
          ? '-'
          : '${res.windows.length} wins / ${comp.carveCentralCorridor ? "Corridor" : "Open"}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Graph Status',
      res == null ? 'IDLE' : (res.isFullyConnected ? 'CONNECTED' : 'DISCONNECTED'),
      valueColor: (res?.isFullyConnected ?? true) ? VoxColor.green : VoxColor.red,
    );
    ui.labelValue(
      'Seed / Geom',
      '#${comp.seed} / ${comp.spawnedObjectCount} objs',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final regenRect = VoxRect(x + pad, barY, 74.0, 22.0);
    if (_drawButton(ui, uiState, 'fp_regen', 'Regen', regenRect)) {
      comp.generateFloorplan();
    }

    final seedRect = VoxRect(regenRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(ui, uiState, 'fp_seed', 'Seed +1', seedRect)) {
      comp.generateFloorplan(customSeed: comp.seed + 1);
    }

    final spineRect = VoxRect(seedRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'fp_spine', 'Corridor', spineRect)) {
      comp.carveCentralCorridor = !comp.carveCentralCorridor;
      comp.generateFloorplan();
    }

    final geoRect = VoxRect(spineRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'fp_geo', 'Build Geo', geoRect)) {
      comp.spawnGeometry = !comp.spawnGeometry;
      if (comp.spawnGeometry) {
        comp.syncSceneGeometry();
      } else {
        comp.clearGeneratedGeometry();
      }
    }

    ui.endWindow();
  }
}
