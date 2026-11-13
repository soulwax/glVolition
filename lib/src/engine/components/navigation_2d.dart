part of '../../engine.dart';

/// Autonomous 2D agent navigation component following waypoints on a [NavGrid] (E30-2).
final class NavAgent2D extends Behaviour {
  double speed;
  double stoppingDistance;
  double acceleration;
  bool rotateTowardsTarget;

  NavGrid? grid;
  final List<Vec2> _waypoints = [];
  int _currentWaypointIndex = 0;
  bool _isMoving = false;
  bool _isPaused = false;

  void Function()? onDestinationReached;
  void Function(int waypointIndex, Vec2 point)? onWaypointReached;

  NavAgent2D({
    this.speed = 4.0,
    this.stoppingDistance = 0.1,
    this.acceleration = 12.0,
    this.rotateTowardsTarget = true,
    this.grid,
  });

  /// Whether the agent is currently tracking an active path.
  bool get isMoving => _isMoving && !_isPaused;

  /// Whether the agent has pending waypoints.
  bool get hasPath =>
      _waypoints.isNotEmpty && _currentWaypointIndex < _waypoints.length;

  /// Remaining waypoints on current path.
  List<Vec2> get remainingWaypoints =>
      hasPath ? _waypoints.sublist(_currentWaypointIndex) : const [];

  /// Current target waypoint in world space.
  Vec2? get currentWaypoint =>
      hasPath ? _waypoints[_currentWaypointIndex] : null;

  /// Sets destination in 2D coordinates `(x, y)` using [grid] or provided [navGrid].
  ///
  /// If [smooth] is true, applies [PathSmoother.smooth] to eliminate jagged stair-step corners.
  bool setDestination(
    Vec2 target, {
    NavGrid? navGrid,
    bool smooth = true,
    double tileSize = 1.0,
  }) {
    final activeGrid = navGrid ?? grid;
    final currentPos = Vec2(transform.position.x, transform.position.z);

    if (activeGrid != null) {
      final startTile = GridPoint(
        (currentPos.x / tileSize).floor(),
        (currentPos.y / tileSize).floor(),
      );
      final targetTile = GridPoint(
        (target.x / tileSize).floor(),
        (target.y / tileSize).floor(),
      );

      const finder = AStarFinder();
      var tilePath = finder.findPath(activeGrid, startTile, targetTile);
      if (tilePath.isEmpty) {
        stop();
        return false;
      }

      if (smooth) {
        tilePath = PathSmoother.smooth(activeGrid, tilePath);
      }

      _waypoints.clear();
      for (final p in tilePath) {
        _waypoints.add(Vec2((p.x + 0.5) * tileSize, (p.y + 0.5) * tileSize));
      }
    } else {
      // Direct straight line
      _waypoints.clear();
      _waypoints.add(target);
    }

    _currentWaypointIndex = 0;
    _isMoving = true;
    _isPaused = false;
    return true;
  }

  /// Sets explicit world-space waypoints directly without grid search.
  void setWaypoints(Iterable<Vec2> points) {
    _waypoints.clear();
    _waypoints.addAll(points);
    _currentWaypointIndex = 0;
    _isMoving = _waypoints.isNotEmpty;
    _isPaused = false;
  }

  /// Halts movement and clears current path.
  void stop() {
    _isMoving = false;
    _waypoints.clear();
    _currentWaypointIndex = 0;
  }

  /// Pauses advancement along current path.
  void pause() => _isPaused = true;

  /// Resumes advancement along current path.
  void resume() => _isPaused = false;

  @override
  void update() {
    if (!_isMoving || _isPaused || !hasPath) return;

    final dt = time.deltaTime;
    if (dt <= 0.0) return;

    final target = _waypoints[_currentWaypointIndex];
    final currentPos = Vec2(transform.position.x, transform.position.z);
    final toTarget = target - currentPos;
    final dist = toTarget.length;

    final isFinalWaypoint = _currentWaypointIndex == _waypoints.length - 1;
    final arrivalThreshold = isFinalWaypoint ? stoppingDistance : 0.3;

    if (dist <= arrivalThreshold) {
      onWaypointReached?.call(_currentWaypointIndex, target);
      _currentWaypointIndex++;

      if (_currentWaypointIndex >= _waypoints.length) {
        _isMoving = false;
        onDestinationReached?.call();
        return;
      }
    }

    // Step toward target waypoint
    final dir = toTarget.normalized;
    final step = dir * speed * dt;

    if (step.length >= dist) {
      transform.position = Vec3(target.x, transform.position.y, target.y);
    } else {
      transform.position = Vec3(
        transform.position.x + step.x,
        transform.position.y,
        transform.position.z + step.y,
      );
    }

    if (rotateTowardsTarget && toTarget.lengthSquared > 1e-6) {
      final angle = math.atan2(dir.x, dir.y);
      transform.rotation = Quat.axisAngle(kUp, angle);
    }
  }
}

/// Computes and caches a crowd flow field on a [NavGrid] for $O(1)$ multi-agent steering (E30-3).
final class FlowField2DComponent extends Component {
  final NavGrid grid;
  final double tileSize;
  FlowField? _flowField;

  FlowField2DComponent({required this.grid, this.tileSize = 1.0});

  /// Cached flow field instance or null if not yet computed.
  FlowField? get flowField => _flowField;

  /// Recalculates the vector flow field targeting [targetTile].
  void setTarget(GridPoint targetTile) {
    _flowField = FlowField.calculate(grid, targetTile);
  }

  /// Recalculates the vector flow field targeting multiple [targetTiles].
  void setTargets(Iterable<GridPoint> targetTiles) {
    _flowField = FlowField.calculateMulti(grid, targetTiles);
  }

  /// Returns normalized 2D world steering direction `(dx, dz)` at [worldPos].
  Vec2 getSteeringVector(Vec3 worldPos) {
    if (_flowField == null) return Vec2.zero;

    final tileX = (worldPos.x / tileSize).floor();
    final tileZ = (worldPos.z / tileSize).floor();

    final dir = _flowField!.getDirection(tileX, tileZ);
    return Vec2(dir.dx, dir.dy);
  }
}
