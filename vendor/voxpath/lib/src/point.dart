import 'dart:math' as math;

/// An integer 2D coordinate on a navigation grid.
final class GridPoint {
  final int x;
  final int y;

  const GridPoint(this.x, this.y);

  static const GridPoint zero = GridPoint(0, 0);

  GridPoint operator +(GridPoint other) => GridPoint(x + other.x, y + other.y);
  GridPoint operator -(GridPoint other) => GridPoint(x - other.x, y - other.y);
  GridPoint operator -() => GridPoint(-x, -y);

  /// Euclidean straight-line distance.
  double distanceTo(GridPoint other) {
    final dx = (x - other.x).toDouble();
    final dy = (y - other.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Manhattan taxicab distance (|dx| + |dy|).
  int manhattanDistanceTo(GridPoint other) {
    return (x - other.x).abs() + (y - other.y).abs();
  }

  /// Chebyshev distance max(|dx|, |dy|).
  int chebyshevDistanceTo(GridPoint other) {
    return math.max((x - other.x).abs(), (y - other.y).abs());
  }

  /// Octile distance (diagonal steps cost sqrt(2), orthogonal cost 1.0).
  double octileDistanceTo(GridPoint other) {
    final dx = (x - other.x).abs();
    final dy = (y - other.y).abs();
    const sqrt2Minus1 = 0.41421356237309504;
    return (dx < dy)
        ? (sqrt2Minus1 * dx + dy).toDouble()
        : (sqrt2Minus1 * dy + dx).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}
