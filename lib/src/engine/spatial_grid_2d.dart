part of '../engine.dart';

/// Fast broad-phase spatial hash grid for 2D query optimization (E26-3).
///
/// Reduces $O(N^2)$ distance checks to $O(N)$ local cell lookups for bullets,
/// enemies, boids, and spatial triggers.
final class SpatialGrid2D<T> {
  final double cellSize;
  final Map<int, List<T>> _buckets = {};
  final Map<T, Set<int>> _itemBuckets = {};
  final Map<T, Vec2> _itemCenters = {};
  final Map<T, double> _itemRadii = {};
  final Map<T, (int, int, int, int)> _itemCellBounds = {};

  SpatialGrid2D({this.cellSize = 64.0}) {
    if (cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize', 'must be > 0');
    }
  }

  /// Total number of unique items currently tracked in this grid.
  int get count => _itemBuckets.length;

  int _hashCell(int cx, int cy) {
    // 32-bit Cantor / spatial hash
    return (cx * 73856093) ^ (cy * 19349663);
  }

  /// Inserts [item] covering a bounding circle at [position] with [radius].
  void insert(T item, Vec2 position, [double radius = 0.0]) {
    _itemCenters[item] = position;
    _itemRadii[item] = math.max(0.0, radius);
    insertAabb(
      item,
      position.x - radius,
      position.y - radius,
      position.x + radius,
      position.y + radius,
    );
  }

  /// Fast cell-coherent update for moving items; skips bucket re-indexing when
  /// the item's cell span has not changed (P13-W21-B).
  void update(T item, Vec2 position, [double radius = 0.0]) {
    final r = math.max(0.0, radius);
    _itemCenters[item] = position;
    _itemRadii[item] = r;

    final minCx = ((position.x - r) / cellSize).floor();
    final maxCx = ((position.x + r) / cellSize).floor();
    final minCy = ((position.y - r) / cellSize).floor();
    final maxCy = ((position.y + r) / cellSize).floor();
    final prev = _itemCellBounds[item];
    if (prev != null &&
        prev.$1 == minCx &&
        prev.$2 == minCy &&
        prev.$3 == maxCx &&
        prev.$4 == maxCy) {
      return;
    }
    insertAabb(
      item,
      position.x - r,
      position.y - r,
      position.x + r,
      position.y + r,
    );
  }

  /// Inserts [item] covering an axis-aligned bounding box.
  void insertAabb(T item, double minX, double minY, double maxX, double maxY) {
    _removeBucketsOnly(item);

    _itemCenters.putIfAbsent(
      item,
      () => Vec2((minX + maxX) * 0.5, (minY + maxY) * 0.5),
    );
    _itemRadii.putIfAbsent(
      item,
      () => math.max((maxX - minX).abs(), (maxY - minY).abs()) * 0.5,
    );

    final minCx = (minX / cellSize).floor();
    final maxCx = (maxX / cellSize).floor();
    final minCy = (minY / cellSize).floor();
    final maxCy = (maxY / cellSize).floor();
    _itemCellBounds[item] = (minCx, minCy, maxCx, maxCy);

    final buckets = <int>{};
    for (var cy = minCy; cy <= maxCy; cy++) {
      for (var cx = minCx; cx <= maxCx; cx++) {
        final key = _hashCell(cx, cy);
        buckets.add(key);
        _buckets.putIfAbsent(key, () => []).add(item);
      }
    }
    _itemBuckets[item] = buckets;
  }

  bool _removeBucketsOnly(T item) {
    final oldBuckets = _itemBuckets.remove(item);
    if (oldBuckets == null) return false;
    for (final key in oldBuckets) {
      final list = _buckets[key];
      if (list != null) {
        list.remove(item);
        if (list.isEmpty) _buckets.remove(key);
      }
    }
    return true;
  }

  /// Removes [item] from all grid cells it previously occupied.
  bool remove(T item) {
    _itemCenters.remove(item);
    _itemRadii.remove(item);
    _itemCellBounds.remove(item);
    return _removeBucketsOnly(item);
  }

  /// Queries all unique items residing within or overlapping the circular region
  /// defined by [center] and [radius] (broadphase cell query).
  List<T> querySphere(Vec2 center, double radius, [List<T>? out]) {
    return queryAabb(
      center.x - radius,
      center.y - radius,
      center.x + radius,
      center.y + radius,
      out,
    );
  }

  /// Queries all items whose stored bounding circle genuinely intersects the
  /// circle at [center] with [radius] (P13-W21-B).
  List<T> queryCircleExact(Vec2 center, double radius, [List<T>? out]) {
    final candidates = querySphere(center, radius);
    final results = out ?? <T>[];
    results.clear();
    final r = math.max(0.0, radius);
    for (final item in candidates) {
      final pos = _itemCenters[item];
      if (pos == null) continue;
      final itemR = _itemRadii[item] ?? 0.0;
      final maxDist = r + itemR;
      final dx = pos.x - center.x;
      final dy = pos.y - center.y;
      if (dx * dx + dy * dy <= maxDist * maxDist) {
        results.add(item);
      }
    }
    return results;
  }

  /// Finds the nearest tracked item to [point] within [maxRadius], optionally
  /// filtered by [where] (P13-W21-B).
  T? findNearest(
    Vec2 point, {
    double maxRadius = double.infinity,
    bool Function(T item)? where,
  }) {
    final Iterable<T> candidates = maxRadius.isFinite
        ? querySphere(point, maxRadius)
        : _itemCenters.keys;
    T? best;
    var bestDistSq = maxRadius.isFinite
        ? maxRadius * maxRadius
        : double.infinity;

    for (final item in candidates) {
      if (where != null && !where(item)) continue;
      final pos = _itemCenters[item];
      if (pos == null) continue;
      final dx = pos.x - point.x;
      final dy = pos.y - point.y;
      final distSq = dx * dx + dy * dy;
      if (distSq <= bestDistSq) {
        bestDistSq = distSq;
        best = item;
      }
    }
    return best;
  }

  /// Traverses grid cells intersected by the 2D line segment `[origin, end]`
  /// using Amanatides-Woo DDA and returns all unique candidate items (P13-W21-B).
  List<T> queryRay(Vec2 origin, Vec2 end, [List<T>? out]) {
    final results = out ?? <T>[];
    results.clear();
    final visited = <T>{};

    var cx = (origin.x / cellSize).floor();
    var cy = (origin.y / cellSize).floor();
    final endCx = (end.x / cellSize).floor();
    final endCy = (end.y / cellSize).floor();

    void collectCell(int x, int y) {
      final list = _buckets[_hashCell(x, y)];
      if (list == null) return;
      for (final item in list) {
        if (visited.add(item)) results.add(item);
      }
    }

    collectCell(cx, cy);
    if (cx == endCx && cy == endCy) return results;

    final dx = end.x - origin.x;
    final dy = end.y - origin.y;
    final stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
    final stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0);

    final tDeltaX = dx.abs() > 1e-9 ? (cellSize / dx.abs()) : double.infinity;
    final tDeltaY = dy.abs() > 1e-9 ? (cellSize / dy.abs()) : double.infinity;

    var tMaxX = dx > 1e-9
        ? (((cx + 1) * cellSize - origin.x) / dx)
        : (dx < -1e-9 ? ((cx * cellSize - origin.x) / dx) : double.infinity);
    var tMaxY = dy > 1e-9
        ? (((cy + 1) * cellSize - origin.y) / dy)
        : (dy < -1e-9 ? ((cy * cellSize - origin.y) / dy) : double.infinity);

    final maxSteps = (endCx - cx).abs() + (endCy - cy).abs() + 2;
    for (var i = 0; i < maxSteps; i++) {
      if (tMaxX < tMaxY) {
        if (tMaxX > 1.0) break;
        cx += stepX;
        tMaxX += tDeltaX;
      } else {
        if (tMaxY > 1.0) break;
        cy += stepY;
        tMaxY += tDeltaY;
      }
      collectCell(cx, cy);
      if (cx == endCx && cy == endCy) break;
    }
    return results;
  }

  /// Queries all unique items residing within or overlapping the bounding rectangle.
  List<T> queryAabb(
    double minX,
    double minY,
    double maxX,
    double maxY, [
    List<T>? out,
  ]) {
    final results = out ?? <T>[];
    results.clear();

    final minCx = (minX / cellSize).floor();
    final maxCx = (maxX / cellSize).floor();
    final minCy = (minY / cellSize).floor();
    final maxCy = (maxY / cellSize).floor();

    final visited = <T>{};
    for (var cy = minCy; cy <= maxCy; cy++) {
      for (var cx = minCx; cx <= maxCx; cx++) {
        final key = _hashCell(cx, cy);
        final list = _buckets[key];
        if (list == null) continue;

        for (final item in list) {
          if (visited.add(item)) {
            results.add(item);
          }
        }
      }
    }

    return results;
  }

  /// Clears all items and cell buckets from this grid.
  void clear() {
    _buckets.clear();
    _itemBuckets.clear();
    _itemCenters.clear();
    _itemRadii.clear();
    _itemCellBounds.clear();
  }
}
