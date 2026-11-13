part of '../engine.dart';

/// Fast broad-phase spatial hash grid for 2D query optimization (E26-3).
///
/// Reduces $O(N^2)$ distance checks to $O(N)$ local cell lookups for bullets,
/// enemies, boids, and spatial triggers.
final class SpatialGrid2D<T> {
  final double cellSize;
  final Map<int, List<T>> _buckets = {};
  final Map<T, Set<int>> _itemBuckets = {};

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
    insertAabb(
      item,
      position.x - radius,
      position.y - radius,
      position.x + radius,
      position.y + radius,
    );
  }

  /// Inserts [item] covering an axis-aligned bounding box.
  void insertAabb(T item, double minX, double minY, double maxX, double maxY) {
    remove(item);

    final minCx = (minX / cellSize).floor();
    final maxCx = (maxX / cellSize).floor();
    final minCy = (minY / cellSize).floor();
    final maxCy = (maxY / cellSize).floor();

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

  /// Removes [item] from all grid cells it previously occupied.
  bool remove(T item) {
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

  /// Queries all unique items residing within or overlapping the circular region
  /// defined by [center] and [radius].
  List<T> querySphere(Vec2 center, double radius, [List<T>? out]) {
    return queryAabb(
      center.x - radius,
      center.y - radius,
      center.x + radius,
      center.y + radius,
      out,
    );
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
  }
}
