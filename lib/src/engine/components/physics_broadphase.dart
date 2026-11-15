part of '../../engine.dart';

/// Broadphase spatial acceleration contract used by [PhysicsWorld] to avoid
/// quadratic `O(N^2)` pairwise intersection loops and linear spatial queries.
abstract interface class PhysicsBroadphase {
  void sync(Iterable<Collider> colliders);
  void upsert(Collider collider);
  void remove(Collider collider);
  void clear();

  /// Candidate active colliders whose world bounds overlap [bounds].
  List<Collider> queryAabb(Aabb bounds);

  /// Candidate active colliders whose world bounds overlap a sphere query.
  List<Collider> querySphere(Vec3 center, double radius);

  /// Candidate active colliders intersected by [ray] up to [maxDistance].
  List<Collider> queryRay(Ray ray, {double maxDistance = double.infinity});

  /// Candidate active colliders whose padded bounds intersect a sphere sweep.
  List<Collider> querySweptSphere(
    Ray ray,
    double radius, {
    double maxDistance = double.infinity,
  });

  /// Candidate overlapping collider pairs from [activeColliders].
  List<(Collider, Collider)> queryCandidatePairs(
    List<Collider> activeColliders,
  );
}

/// Default linear fallback broadphase; reference brute-force baseline.
final class LinearPhysicsBroadphase implements PhysicsBroadphase {
  final List<Collider> _tracked = [];

  @override
  void sync(Iterable<Collider> colliders) {
    _tracked
      ..clear()
      ..addAll(colliders);
  }

  @override
  void upsert(Collider collider) {
    if (!_tracked.contains(collider)) {
      _tracked.add(collider);
    }
  }

  @override
  void remove(Collider collider) {
    _tracked.remove(collider);
  }

  @override
  void clear() {
    _tracked.clear();
  }

  @override
  List<Collider> queryAabb(Aabb bounds) {
    final result = <Collider>[];
    for (final c in _tracked) {
      if (!c._active || c._destroyRequested) continue;
      if (PhysicsNarrowphase.aabbIntersects(c.worldBounds, bounds)) {
        result.add(c);
      }
    }
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySphere(Vec3 center, double radius) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    return queryAabb(Aabb(center - pad, center + pad));
  }

  @override
  List<Collider> queryRay(Ray ray, {double maxDistance = double.infinity}) {
    final result = <Collider>[];
    for (final c in _tracked) {
      if (!c._active || c._destroyRequested) continue;
      final t = ray.intersectAabb(c.worldBounds);
      if (t != null && t <= maxDistance) {
        result.add(c);
      }
    }
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySweptSphere(
    Ray ray,
    double radius, {
    double maxDistance = double.infinity,
  }) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    final result = <Collider>[];
    for (final c in _tracked) {
      if (!c._active || c._destroyRequested) continue;
      final b = c.worldBounds;
      final padded = Aabb(b.min - pad, b.max + pad);
      final t = ray.intersectAabb(padded);
      if (t != null && t <= maxDistance) {
        result.add(c);
      }
    }
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<(Collider, Collider)> queryCandidatePairs(
    List<Collider> activeColliders,
  ) {
    final pairs = <(Collider, Collider)>[];
    for (var i = 0; i < activeColliders.length; i++) {
      final a = activeColliders[i];
      if (!a._active || a._destroyRequested) continue;
      for (var j = i + 1; j < activeColliders.length; j++) {
        final b = activeColliders[j];
        if (!b._active || b._destroyRequested) continue;
        if (PhysicsNarrowphase.aabbIntersects(a.worldBounds, b.worldBounds)) {
          pairs.add((a, b));
        }
      }
    }
    pairs.sort((p1, p2) {
      final c1 = p1.$1.instanceId.compareTo(p2.$1.instanceId);
      if (c1 != 0) return c1;
      return p1.$2.instanceId.compareTo(p2.$2.instanceId);
    });
    return pairs;
  }
}

/// Uniform spatial hash broadphase accelerator with separate loose/global
/// bucket for unbounded/huge colliders (e.g., giant floors/walls).
final class SpatialPhysicsBroadphase implements PhysicsBroadphase {
  double cellSize;
  final int maxCellsPerAxis;
  final int maxCellsPerCollider;

  final Map<(int, int, int), List<Collider>> _buckets = {};
  final Map<Collider, List<(int, int, int)>> _colliderCells = {};
  final Map<Collider, Aabb> _colliderBounds = {};
  final Set<Collider> _largeColliders = {};
  final Set<Collider> _tracked = {};

  Aabb? _gridBounds;
  int _gridMinCellX = 0;
  int _gridMaxCellX = 0;
  int _gridMinCellY = 0;
  int _gridMaxCellY = 0;
  int _gridMinCellZ = 0;
  int _gridMaxCellZ = 0;

  SpatialPhysicsBroadphase({
    this.cellSize = 4.0,
    this.maxCellsPerAxis = 12,
    this.maxCellsPerCollider = 64,
  }) {
    if (cellSize <= 0.0) {
      cellSize = 4.0;
    }
  }

  int get trackedCount => _tracked.length;
  int get occupiedCellCount => _buckets.length;
  int get largeColliderCount => _largeColliders.length;

  double get averageBucketLoad {
    if (_buckets.isEmpty) return 0.0;
    var total = 0;
    for (final b in _buckets.values) {
      total += b.length;
    }
    return total / _buckets.length;
  }

  int _cellCoord(double v) => (v / cellSize).floor();

  @override
  void sync(Iterable<Collider> colliders) {
    final next = <Collider>{};
    for (final c in colliders) {
      if (c._active && !c._destroyRequested) {
        next.add(c);
      }
    }

    final toRemove = <Collider>[];
    for (final c in _tracked) {
      if (!next.contains(c)) {
        toRemove.add(c);
      }
    }
    for (final c in toRemove) {
      remove(c);
    }

    for (final c in next) {
      upsert(c);
    }
  }

  @override
  void upsert(Collider collider) {
    if (!collider._active || collider._destroyRequested) {
      remove(collider);
      return;
    }

    final b = collider.worldBounds;
    final oldBounds = _colliderBounds[collider];
    if (oldBounds != null &&
        oldBounds.min == b.min &&
        oldBounds.max == b.max &&
        _tracked.contains(collider)) {
      return;
    }

    _tracked.add(collider);
    _colliderBounds[collider] = b;

    final minX = _cellCoord(b.min.x);
    final maxX = _cellCoord(b.max.x);
    final minY = _cellCoord(b.min.y);
    final maxY = _cellCoord(b.max.y);
    final minZ = _cellCoord(b.min.z);
    final maxZ = _cellCoord(b.max.z);

    final spanX = maxX - minX + 1;
    final spanY = maxY - minY + 1;
    final spanZ = maxZ - minZ + 1;
    final totalCells = spanX * spanY * spanZ;

    final isLarge =
        spanX > maxCellsPerAxis ||
        spanY > maxCellsPerAxis ||
        spanZ > maxCellsPerAxis ||
        totalCells > maxCellsPerCollider;

    if (isLarge) {
      _removeCells(collider);
      _largeColliders.add(collider);
      return;
    }

    _largeColliders.remove(collider);

    final oldCells = _colliderCells[collider];
    if (oldCells != null && oldCells.length == totalCells) {
      if (oldCells.first == (minX, minY, minZ) &&
          oldCells.last == (maxX, maxY, maxZ)) {
        return;
      }
    }

    _removeCells(collider);

    final newCells = <(int, int, int)>[];
    for (var cx = minX; cx <= maxX; cx++) {
      for (var cy = minY; cy <= maxY; cy++) {
        for (var cz = minZ; cz <= maxZ; cz++) {
          final key = (cx, cy, cz);
          newCells.add(key);
          (_buckets[key] ??= <Collider>[]).add(collider);
        }
      }
    }
    _colliderCells[collider] = newCells;

    _expandGridBounds(b, minX, maxX, minY, maxY, minZ, maxZ);
  }

  void _removeCells(Collider collider) {
    final cells = _colliderCells.remove(collider);
    if (cells != null) {
      for (final key in cells) {
        final bucket = _buckets[key];
        if (bucket != null) {
          bucket.remove(collider);
          if (bucket.isEmpty) {
            _buckets.remove(key);
          }
        }
      }
    }
  }

  void _expandGridBounds(
    Aabb b,
    int minX,
    int maxX,
    int minY,
    int maxY,
    int minZ,
    int maxZ,
  ) {
    if (_gridBounds == null) {
      _gridBounds = b;
      _gridMinCellX = minX;
      _gridMaxCellX = maxX;
      _gridMinCellY = minY;
      _gridMaxCellY = maxY;
      _gridMinCellZ = minZ;
      _gridMaxCellZ = maxZ;
    } else {
      _gridBounds = Aabb(
        Vec3(
          math.min(_gridBounds!.min.x, b.min.x),
          math.min(_gridBounds!.min.y, b.min.y),
          math.min(_gridBounds!.min.z, b.min.z),
        ),
        Vec3(
          math.max(_gridBounds!.max.x, b.max.x),
          math.max(_gridBounds!.max.y, b.max.y),
          math.max(_gridBounds!.max.z, b.max.z),
        ),
      );
      _gridMinCellX = math.min(_gridMinCellX, minX);
      _gridMaxCellX = math.max(_gridMaxCellX, maxX);
      _gridMinCellY = math.min(_gridMinCellY, minY);
      _gridMaxCellY = math.max(_gridMaxCellY, maxY);
      _gridMinCellZ = math.min(_gridMinCellZ, minZ);
      _gridMaxCellZ = math.max(_gridMaxCellZ, maxZ);
    }
  }

  @override
  void remove(Collider collider) {
    _tracked.remove(collider);
    _largeColliders.remove(collider);
    _colliderBounds.remove(collider);
    _removeCells(collider);
    if (_tracked.isEmpty) {
      _gridBounds = null;
    }
  }

  @override
  void clear() {
    _tracked.clear();
    _largeColliders.clear();
    _colliderBounds.clear();
    _colliderCells.clear();
    _buckets.clear();
    _gridBounds = null;
  }

  @override
  List<Collider> queryAabb(Aabb bounds) {
    final result = <Collider>[];
    final visited = <Collider>{};

    for (final c in _largeColliders) {
      if (!c._active || c._destroyRequested) continue;
      if (PhysicsNarrowphase.aabbIntersects(c.worldBounds, bounds)) {
        if (visited.add(c)) {
          result.add(c);
        }
      }
    }

    if (_buckets.isEmpty || _gridBounds == null) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    if (!PhysicsNarrowphase.aabbIntersects(bounds, _gridBounds!)) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final minX = math.max(_cellCoord(bounds.min.x), _gridMinCellX);
    final maxX = math.min(_cellCoord(bounds.max.x), _gridMaxCellX);
    final minY = math.max(_cellCoord(bounds.min.y), _gridMinCellY);
    final maxY = math.min(_cellCoord(bounds.max.y), _gridMaxCellY);
    final minZ = math.max(_cellCoord(bounds.min.z), _gridMinCellZ);
    final maxZ = math.min(_cellCoord(bounds.max.z), _gridMaxCellZ);

    if (minX <= maxX && minY <= maxY && minZ <= maxZ) {
      for (var cx = minX; cx <= maxX; cx++) {
        for (var cy = minY; cy <= maxY; cy++) {
          for (var cz = minZ; cz <= maxZ; cz++) {
            final bucket = _buckets[(cx, cy, cz)];
            if (bucket == null) continue;
            for (var i = 0; i < bucket.length; i++) {
              final c = bucket[i];
              if (!c._active || c._destroyRequested) continue;
              if (visited.add(c)) {
                if (PhysicsNarrowphase.aabbIntersects(c.worldBounds, bounds)) {
                  result.add(c);
                }
              }
            }
          }
        }
      }
    }

    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySphere(Vec3 center, double radius) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    return queryAabb(Aabb(center - pad, center + pad));
  }

  static (double, double)? _rayAabbInterval(Ray ray, Aabb box) {
    var tmin = -double.infinity;
    var tmax = double.infinity;

    // X axis
    if (ray.direction.x.abs() < 1e-9) {
      if (ray.origin.x < box.min.x || ray.origin.x > box.max.x) return null;
    } else {
      final invD = 1.0 / ray.direction.x;
      var t1 = (box.min.x - ray.origin.x) * invD;
      var t2 = (box.max.x - ray.origin.x) * invD;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    // Y axis
    if (ray.direction.y.abs() < 1e-9) {
      if (ray.origin.y < box.min.y || ray.origin.y > box.max.y) return null;
    } else {
      final invD = 1.0 / ray.direction.y;
      var t1 = (box.min.y - ray.origin.y) * invD;
      var t2 = (box.max.y - ray.origin.y) * invD;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    // Z axis
    if (ray.direction.z.abs() < 1e-9) {
      if (ray.origin.z < box.min.z || ray.origin.z > box.max.z) return null;
    } else {
      final invD = 1.0 / ray.direction.z;
      var t1 = (box.min.z - ray.origin.z) * invD;
      var t2 = (box.max.z - ray.origin.z) * invD;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    return (tmin, tmax);
  }

  @override
  List<Collider> queryRay(Ray ray, {double maxDistance = double.infinity}) {
    final result = <Collider>[];
    final visited = <Collider>{};

    for (final c in _largeColliders) {
      if (!c._active || c._destroyRequested) continue;
      final t = ray.intersectAabb(c.worldBounds);
      if (t != null && t <= maxDistance) {
        if (visited.add(c)) {
          result.add(c);
        }
      }
    }

    if (_buckets.isEmpty || _gridBounds == null) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final interval = _rayAabbInterval(ray, _gridBounds!);
    if (interval == null) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final (tEnter, tExit) = interval;
    if (tExit < 0.0 || tEnter > maxDistance) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final segStart = math.max(0.0, tEnter);
    final segEnd = math.min(maxDistance, tExit);
    if (segStart > segEnd) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final stepSize = cellSize * 2.0;
    var t = segStart;
    const eps = 0.001;

    while (t <= segEnd) {
      final tNext = math.min(segEnd, t + stepSize);
      final p0 = ray.at(t);
      final p1 = ray.at(tNext);

      final minX = math.max(
        _cellCoord(math.min(p0.x, p1.x) - eps),
        _gridMinCellX,
      );
      final maxX = math.min(
        _cellCoord(math.max(p0.x, p1.x) + eps),
        _gridMaxCellX,
      );
      final minY = math.max(
        _cellCoord(math.min(p0.y, p1.y) - eps),
        _gridMinCellY,
      );
      final maxY = math.min(
        _cellCoord(math.max(p0.y, p1.y) + eps),
        _gridMaxCellY,
      );
      final minZ = math.max(
        _cellCoord(math.min(p0.z, p1.z) - eps),
        _gridMinCellZ,
      );
      final maxZ = math.min(
        _cellCoord(math.max(p0.z, p1.z) + eps),
        _gridMaxCellZ,
      );

      if (minX <= maxX && minY <= maxY && minZ <= maxZ) {
        for (var cx = minX; cx <= maxX; cx++) {
          for (var cy = minY; cy <= maxY; cy++) {
            for (var cz = minZ; cz <= maxZ; cz++) {
              final bucket = _buckets[(cx, cy, cz)];
              if (bucket == null) continue;
              for (var i = 0; i < bucket.length; i++) {
                final c = bucket[i];
                if (!c._active || c._destroyRequested) continue;
                if (visited.add(c)) {
                  final hitT = ray.intersectAabb(c.worldBounds);
                  if (hitT != null && hitT <= maxDistance) {
                    result.add(c);
                  }
                }
              }
            }
          }
        }
      }

      if (tNext >= segEnd) break;
      t = tNext;
    }

    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySweptSphere(
    Ray ray,
    double radius, {
    double maxDistance = double.infinity,
  }) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    final result = <Collider>[];
    final visited = <Collider>{};

    for (final c in _largeColliders) {
      if (!c._active || c._destroyRequested) continue;
      final b = c.worldBounds;
      final padded = Aabb(b.min - pad, b.max + pad);
      final t = ray.intersectAabb(padded);
      if (t != null && t <= maxDistance) {
        if (visited.add(c)) {
          result.add(c);
        }
      }
    }

    if (_buckets.isEmpty || _gridBounds == null) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final paddedGrid = Aabb(_gridBounds!.min - pad, _gridBounds!.max + pad);
    final interval = _rayAabbInterval(ray, paddedGrid);
    if (interval == null) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final (tEnter, tExit) = interval;
    if (tExit < 0.0 || tEnter > maxDistance) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final segStart = math.max(0.0, tEnter);
    final segEnd = math.min(maxDistance, tExit);
    if (segStart > segEnd) {
      result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
      return result;
    }

    final stepSize = cellSize * 2.0;
    var t = segStart;
    const eps = 0.001;

    while (t <= segEnd) {
      final tNext = math.min(segEnd, t + stepSize);
      final p0 = ray.at(t);
      final p1 = ray.at(tNext);

      final minX = math.max(
        _cellCoord(math.min(p0.x, p1.x) - r - eps),
        _gridMinCellX,
      );
      final maxX = math.min(
        _cellCoord(math.max(p0.x, p1.x) + r + eps),
        _gridMaxCellX,
      );
      final minY = math.max(
        _cellCoord(math.min(p0.y, p1.y) - r - eps),
        _gridMinCellY,
      );
      final maxY = math.min(
        _cellCoord(math.max(p0.y, p1.y) + r + eps),
        _gridMaxCellY,
      );
      final minZ = math.max(
        _cellCoord(math.min(p0.z, p1.z) - r - eps),
        _gridMinCellZ,
      );
      final maxZ = math.min(
        _cellCoord(math.max(p0.z, p1.z) + r + eps),
        _gridMaxCellZ,
      );

      if (minX <= maxX && minY <= maxY && minZ <= maxZ) {
        for (var cx = minX; cx <= maxX; cx++) {
          for (var cy = minY; cy <= maxY; cy++) {
            for (var cz = minZ; cz <= maxZ; cz++) {
              final bucket = _buckets[(cx, cy, cz)];
              if (bucket == null) continue;
              for (var i = 0; i < bucket.length; i++) {
                final c = bucket[i];
                if (!c._active || c._destroyRequested) continue;
                if (visited.add(c)) {
                  final b = c.worldBounds;
                  final padded = Aabb(b.min - pad, b.max + pad);
                  final hitT = ray.intersectAabb(padded);
                  if (hitT != null && hitT <= maxDistance) {
                    result.add(c);
                  }
                }
              }
            }
          }
        }
      }

      if (tNext >= segEnd) break;
      t = tNext;
    }

    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<(Collider, Collider)> queryCandidatePairs(
    List<Collider> activeColliders,
  ) {
    sync(activeColliders);
    final pairs = <(Collider, Collider)>[];
    final seen = <(int, int)>{};

    for (final bucket in _buckets.values) {
      final len = bucket.length;
      if (len < 2) continue;
      for (var i = 0; i < len; i++) {
        final a = bucket[i];
        if (!a._active || a._destroyRequested) continue;
        for (var j = i + 1; j < len; j++) {
          final b = bucket[j];
          if (!b._active || b._destroyRequested) continue;
          if (identical(a, b)) continue;

          final idA = a.instanceId;
          final idB = b.instanceId;
          final minId = idA < idB ? idA : idB;
          final maxId = idA < idB ? idB : idA;

          if (seen.add((minId, maxId))) {
            if (PhysicsNarrowphase.aabbIntersects(
              a.worldBounds,
              b.worldBounds,
            )) {
              pairs.add(idA == minId ? (a, b) : (b, a));
            }
          }
        }
      }
    }

    if (_largeColliders.isNotEmpty) {
      for (final large in _largeColliders) {
        if (!large._active || large._destroyRequested) continue;
        final largeBounds = large.worldBounds;
        for (var i = 0; i < activeColliders.length; i++) {
          final other = activeColliders[i];
          if (identical(large, other) ||
              !other._active ||
              other._destroyRequested) {
            continue;
          }

          final idA = large.instanceId;
          final idB = other.instanceId;
          final minId = idA < idB ? idA : idB;
          final maxId = idA < idB ? idB : idA;

          if (seen.add((minId, maxId))) {
            if (PhysicsNarrowphase.aabbIntersects(
              largeBounds,
              other.worldBounds,
            )) {
              pairs.add(idA == minId ? (large, other) : (other, large));
            }
          }
        }
      }
    }

    pairs.sort((p1, p2) {
      final c1 = p1.$1.instanceId.compareTo(p2.$1.instanceId);
      if (c1 != 0) return c1;
      return p1.$2.instanceId.compareTo(p2.$2.instanceId);
    });
    return pairs;
  }
}

/// Convenience alias for [SpatialPhysicsBroadphase].
typedef SpatialHashPhysicsBroadphase = SpatialPhysicsBroadphase;

/// BVH broadphase spatial accelerator backed by [vgrid.DynamicBvh].
final class BvhPhysicsBroadphase implements PhysicsBroadphase {
  final vgrid.DynamicBvh<Collider> _bvh;
  final Set<Collider> _tracked = {};

  BvhPhysicsBroadphase({double fatMargin = 0.15})
    : _bvh = vgrid.DynamicBvh<Collider>(fatMargin: fatMargin);

  static vgrid.GridAabb _toGridAabb(Aabb box) => vgrid.GridAabb(
    vgrid.GridVec3(box.min.x, box.min.y, box.min.z),
    vgrid.GridVec3(box.max.x, box.max.y, box.max.z),
  );

  static vgrid.GridRay _toGridRay(Ray ray) => vgrid.GridRay(
    origin: vgrid.GridVec3(ray.origin.x, ray.origin.y, ray.origin.z),
    direction: vgrid.GridVec3(
      ray.direction.x,
      ray.direction.y,
      ray.direction.z,
    ),
  );

  @override
  void sync(Iterable<Collider> colliders) {
    final active = <Collider>{};
    for (final c in colliders) {
      if (c._active && !c._destroyRequested) {
        active.add(c);
      }
    }

    final toRemove = <Collider>[];
    for (final c in _tracked) {
      if (!active.contains(c)) {
        toRemove.add(c);
      }
    }
    for (final c in toRemove) {
      remove(c);
    }

    for (final c in active) {
      upsert(c);
    }
  }

  @override
  void upsert(Collider collider) {
    if (!collider._active || collider._destroyRequested) {
      remove(collider);
      return;
    }
    _tracked.add(collider);
    _bvh.upsert(collider, _toGridAabb(collider.worldBounds));
  }

  @override
  void remove(Collider collider) {
    if (_tracked.remove(collider)) {
      _bvh.removeItem(collider);
    }
  }

  @override
  void clear() {
    _tracked.clear();
    _bvh.clear();
  }

  @override
  List<Collider> queryAabb(Aabb bounds) {
    final result = _bvh.queryAabb(
      _toGridAabb(bounds),
      filter: (c) =>
          c._active &&
          !c._destroyRequested &&
          PhysicsNarrowphase.aabbIntersects(c.worldBounds, bounds),
    );
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySphere(Vec3 center, double radius) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    return queryAabb(Aabb(center - pad, center + pad));
  }

  @override
  List<Collider> queryRay(Ray ray, {double maxDistance = double.infinity}) {
    final hits = _bvh.raycastAll(
      _toGridRay(ray),
      maxDistance: maxDistance,
      filter: (c) => c._active && !c._destroyRequested,
      narrowPhase: (c, r, maxD) {
        final t = ray.intersectAabb(c.worldBounds);
        if (t != null && t <= maxD) return t;
        return null;
      },
    );
    final result = hits.map((h) => h.item).toList();
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<Collider> querySweptSphere(
    Ray ray,
    double radius, {
    double maxDistance = double.infinity,
  }) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    final result = <Collider>[];
    for (final c in _tracked) {
      if (!c._active || c._destroyRequested) continue;
      final b = c.worldBounds;
      final padded = Aabb(b.min - pad, b.max + pad);
      final t = ray.intersectAabb(padded);
      if (t != null && t <= maxDistance) {
        result.add(c);
      }
    }
    result.sort((a, b) => a.instanceId.compareTo(b.instanceId));
    return result;
  }

  @override
  List<(Collider, Collider)> queryCandidatePairs(
    List<Collider> activeColliders,
  ) {
    sync(activeColliders);
    final raw = _bvh.queryOverlapPairs();
    final pairs = <(Collider, Collider)>[];
    for (final p in raw) {
      final a = p.$1;
      final b = p.$2;
      if (a._active &&
          !a._destroyRequested &&
          b._active &&
          !b._destroyRequested) {
        if (PhysicsNarrowphase.aabbIntersects(a.worldBounds, b.worldBounds)) {
          final idA = a.instanceId;
          final idB = b.instanceId;
          pairs.add(idA < idB ? (a, b) : (b, a));
        }
      }
    }
    pairs.sort((p1, p2) {
      final c1 = p1.$1.instanceId.compareTo(p2.$1.instanceId);
      if (c1 != 0) return c1;
      return p1.$2.instanceId.compareTo(p2.$2.instanceId);
    });
    return pairs;
  }
}
