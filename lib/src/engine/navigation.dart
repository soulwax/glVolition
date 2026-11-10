part of '../engine.dart';

/// 2D grid navigation graph supporting 4-way and 8-way A* pathfinding with
/// corner-cutting prevention and per-cell cost weights (E11-1).
///
/// Can be constructed standalone or directly from a [TilemapComponent] via
/// [NavGrid2D.fromTilemap].
final class NavGrid2D {
  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final double originX;
  final double originY;
  final bool allowDiagonal;

  final Uint8List _walkable;
  final Float32List _costs;

  NavGrid2D({
    required this.columns,
    required this.rows,
    this.cellWidth = 1.0,
    this.cellHeight = 1.0,
    this.originX = 0.0,
    this.originY = 0.0,
    this.allowDiagonal = true,
  })  : _walkable = Uint8List(columns * rows)..fillRange(0, columns * rows, 1),
        _costs = Float32List(columns * rows)..fillRange(0, columns * rows, 1.0);

  /// Builds a [NavGrid2D] mirroring the solid/walkable cells of [tilemap].
  factory NavGrid2D.fromTilemap(
    TilemapComponent tilemap, {
    bool allowDiagonal = true,
  }) {
    final nav = NavGrid2D(
      columns: tilemap.columns,
      rows: tilemap.rows,
      cellWidth: tilemap.tileWidth,
      cellHeight: tilemap.tileHeight,
      originX: tilemap.layer.originX,
      originY: tilemap.layer.originY,
      allowDiagonal: allowDiagonal,
    );
    for (var r = 0; r < tilemap.rows; r++) {
      for (var c = 0; c < tilemap.columns; c++) {
        nav.setWalkable(c, r, !tilemap.isSolidCell(c, r));
      }
    }
    return nav;
  }

  bool inBounds(int col, int row) =>
      col >= 0 && col < columns && row >= 0 && row < rows;

  int _idx(int col, int row) => row * columns + col;

  bool isWalkable(int col, int row) =>
      inBounds(col, row) && _walkable[_idx(col, row)] != 0;

  void setWalkable(int col, int row, bool walkable) {
    if (!inBounds(col, row)) return;
    _walkable[_idx(col, row)] = walkable ? 1 : 0;
  }

  double cellCost(int col, int row) =>
      inBounds(col, row) ? _costs[_idx(col, row)] : double.infinity;

  void setCellCost(int col, int row, double cost) {
    if (!inBounds(col, row)) return;
    _costs[_idx(col, row)] = math.max(0.01, cost);
  }

  /// Converts world `(x, y)` into grid cell `(col, row)`.
  (int, int) worldToCell(double worldX, double worldY) => (
        ((worldX - originX) / cellWidth).floor().clamp(0, columns - 1),
        ((worldY - originY) / cellHeight).floor().clamp(0, rows - 1),
      );

  /// Returns the world-space center of `(col, row)`.
  Vec2 cellCenterWorld(int col, int row) => Vec2(
        originX + (col + 0.5) * cellWidth,
        originY + (row + 0.5) * cellHeight,
      );

  /// Computes an A* path of world-space cell centers from [startWorld] to
  /// [goalWorld]. Returns an empty list if no path exists.
  List<Vec2> findPath(Vec2 startWorld, Vec2 goalWorld) {
    final (sc, sr) = worldToCell(startWorld.x, startWorld.y);
    final (gc, gr) = worldToCell(goalWorld.x, goalWorld.y);
    if (!isWalkable(gc, gr)) return const [];
    if (sc == gc && sr == gr) return [cellCenterWorld(gc, gr)];

    final total = columns * rows;
    final gScore = Float64List(total)..fillRange(0, total, double.infinity);
    final fScore = Float64List(total)..fillRange(0, total, double.infinity);
    final cameFrom = Int32List(total)..fillRange(0, total, -1);
    final closed = Uint8List(total);
    final inOpen = Uint8List(total);
    final open = <int>[];

    double heuristic(int c, int r) {
      final dx = (c - gc).abs().toDouble();
      final dy = (r - gr).abs().toDouble();
      if (allowDiagonal) {
        final diag = math.min(dx, dy);
        return diag * math.sqrt2 + (math.max(dx, dy) - diag);
      }
      return dx + dy;
    }

    final startIdx = _idx(sc, sr);
    final goalIdx = _idx(gc, gr);
    gScore[startIdx] = 0.0;
    fScore[startIdx] = heuristic(sc, sr);
    open.add(startIdx);
    inOpen[startIdx] = 1;

    const dirs4 = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];
    const dirs8 = <(int, int)>[
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1),
      (1, 1),
      (1, -1),
      (-1, 1),
      (-1, -1),
    ];
    final dirs = allowDiagonal ? dirs8 : dirs4;

    while (open.isNotEmpty) {
      var bestPos = 0;
      var current = open[0];
      var bestF = fScore[current];
      for (var i = 1; i < open.length; i++) {
        final cand = open[i];
        if (fScore[cand] < bestF) {
          bestF = fScore[cand];
          current = cand;
          bestPos = i;
        }
      }
      open.removeAt(bestPos);
      inOpen[current] = 0;

      if (current == goalIdx) {
        final result = <Vec2>[];
        var cur = goalIdx;
        while (cur != -1 && cur != startIdx) {
          final r = cur ~/ columns;
          final c = cur % columns;
          result.add(cellCenterWorld(c, r));
          cur = cameFrom[cur];
        }
        return result.reversed.toList(growable: false);
      }

      closed[current] = 1;
      final cr = current ~/ columns;
      final cc = current % columns;

      for (final (dc, dr) in dirs) {
        final nc = cc + dc;
        final nr = cr + dr;
        if (!isWalkable(nc, nr)) continue;
        // Prevent diagonal corner cutting adjacent to solid walls.
        if (dc != 0 && dr != 0) {
          if (!isWalkable(cc + dc, cr) || !isWalkable(cc, cr + dr)) continue;
        }
        final nIdx = _idx(nc, nr);
        if (closed[nIdx] != 0) continue;

        final stepDist = (dc != 0 && dr != 0) ? math.sqrt2 : 1.0;
        final tentativeG = gScore[current] + stepDist * _costs[nIdx];
        if (tentativeG < gScore[nIdx]) {
          cameFrom[nIdx] = current;
          gScore[nIdx] = tentativeG;
          fScore[nIdx] = tentativeG + heuristic(nc, nr);
          if (inOpen[nIdx] == 0) {
            open.add(nIdx);
            inOpen[nIdx] = 1;
          }
        }
      }
    }

    return const [];
  }
}

/// Autonomous path-following behaviour on a [NavGrid2D] (in the XY plane by
/// default, or XZ plane when [useXZPlane] is true) with optional local
/// separation from sibling [NavAgent]s (E11-1).
final class NavAgent extends Behaviour {
  NavGrid2D? grid;
  double speed;
  double stoppingDistance;
  double avoidanceRadius;
  double avoidanceWeight;
  bool useXZPlane;

  final List<Vec2> _waypoints = [];
  int _waypointIndex = 0;

  NavAgent({
    this.grid,
    this.speed = 4.0,
    this.stoppingDistance = 0.15,
    this.avoidanceRadius = 0.6,
    this.avoidanceWeight = 1.5,
    this.useXZPlane = false,
  });

  static final spec = ComponentSpec<NavAgent>(
    'NavAgent',
    NavAgent.new,
    [
      Field.number('speed', (a) => a.speed, (a, v) => a.speed = v),
      Field.number('stoppingDistance', (a) => a.stoppingDistance, (a, v) => a.stoppingDistance = v),
      Field.number('avoidanceRadius', (a) => a.avoidanceRadius, (a, v) => a.avoidanceRadius = v),
      Field.number('avoidanceWeight', (a) => a.avoidanceWeight, (a, v) => a.avoidanceWeight = v),
      Field.boolean('useXZPlane', (a) => a.useXZPlane, (a, v) => a.useXZPlane = v),
    ],
  );

  bool get hasPath => _waypointIndex < _waypoints.length;
  List<Vec2> get remainingWaypoints =>
      hasPath ? List.unmodifiable(_waypoints.sublist(_waypointIndex)) : const [];

  Vec2 _pos2D(Vec3 p) => useXZPlane ? Vec2(p.x, p.z) : Vec2(p.x, p.y);

  /// Computes an A* path from the agent's current position to [targetWorld] and
  /// begins following it. Returns `true` if a valid path was found.
  bool setDestination(Vec3 targetWorld) {
    final g = grid;
    if (g == null) return false;
    final start2 = _pos2D(transform.position);
    final goal2 = _pos2D(targetWorld);
    final path = g.findPath(start2, goal2);
    _waypoints
      ..clear()
      ..addAll(path);
    _waypointIndex = 0;
    return _waypoints.isNotEmpty;
  }

  void clearPath() {
    _waypoints.clear();
    _waypointIndex = 0;
  }

  @override
  void update() {
    if (!hasPath) return;
    final dt = time.deltaTime;
    if (dt <= 0) return;

    final cur3 = transform.position;
    final cur2 = _pos2D(cur3);
    final target = _waypoints[_waypointIndex];
    final toTarget = target - cur2;
    final dist = toTarget.length;

    if (dist <= stoppingDistance) {
      _waypointIndex++;
      if (!hasPath) return;
    }

    final wp = _waypoints[_waypointIndex];
    var dir = (wp - cur2).normalized;

    // Local separation from other active NavAgents.
    if (avoidanceRadius > 0 && avoidanceWeight > 0) {
      var sep = Vec2.zero;
      for (final other in scene.findObjectsOfType<NavAgent>()) {
        if (identical(other, this)) continue;
        final delta = cur2 - _pos2D(other.transform.position);
        final d = delta.length;
        if (d > 1e-5 && d < avoidanceRadius) {
          final push = (avoidanceRadius - d) / avoidanceRadius;
          sep = sep + delta * ((1.0 / d) * push);
        }
      }
      if (sep.lengthSquared > 1e-6) {
        dir = (dir + sep * avoidanceWeight).normalized;
      }
    }

    final step = math.min(speed * dt, (wp - cur2).length);
    final next2 = cur2 + dir * step;
    if (useXZPlane) {
      transform.position = Vec3(next2.x, cur3.y, next2.y);
    } else {
      transform.position = Vec3(next2.x, next2.y, cur3.z);
    }
  }
}
