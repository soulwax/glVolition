part of '../../engine.dart';

/// Wraps a pixeldart [TileLayer] as a component and provides fast grid lookup
/// and circle-vs-tile sliding collision (`moveAndSlideCircle`) (E4-3).
final class TilemapComponent extends Component {
  final TileLayer layer;
  final Set<int> solidTileIds;
  bool Function(int tileId)? isSolidPredicate;

  TilemapComponent(
    this.layer, {
    Iterable<int> solidTiles = const [],
    this.isSolidPredicate,
  }) : solidTileIds = {...solidTiles};

  int get columns => layer.columns;
  int get rows => layer.rows;
  double get tileWidth => layer.tileWidth;
  double get tileHeight => layer.tileHeight;

  int tileAt(int column, int row) => layer.tileAt(column, row);
  void setTile(int column, int row, int id) => layer.setTile(column, row, id);

  bool isSolidTileId(int id) {
    if (id < 0) {
      return false; // Empty tile (-1) or out-of-bounds is non-solid unless explicitly flagged
    }
    final pred = isSolidPredicate;
    if (pred != null && pred(id)) return true;
    return solidTileIds.contains(id);
  }

  bool isSolidCell(int column, int row) {
    if (column < 0 || row < 0 || column >= columns || row >= rows) {
      return true; // Outside map bounds is solid
    }
    return isSolidTileId(layer.tileAt(column, row));
  }

  (int, int) worldToCell(double worldX, double worldY) {
    final col = ((worldX - layer.originX) / layer.tileWidth).floor();
    final row = ((worldY - layer.originY) / layer.tileHeight).floor();
    return (col, row);
  }

  /// Converts a tile grid coordinate `(column, row)` into world coordinates.
  /// When [center] is true, returns the center of the cell; otherwise returns the top-left origin.
  Vec2 cellToWorld(int column, int row, {bool center = false}) {
    final tw = layer.tileWidth;
    final th = layer.tileHeight;
    final ox = layer.originX + column * tw;
    final oy = layer.originY + row * th;
    return center ? Vec2(ox + tw * 0.5, oy + th * 0.5) : Vec2(ox, oy);
  }

  bool isSolidAtWorld(double worldX, double worldY) {
    final (col, row) = worldToCell(worldX, worldY);
    return isSolidCell(col, row);
  }

  /// Traces a 2D line from [start] to [end] across tile cells, returning the first solid hit,
  /// or null if the path is clear.
  ({int column, int row, Vec2 point, double distance})? raycast(
    Vec2 start,
    Vec2 end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final totalDist = math.sqrt(dx * dx + dy * dy);
    if (totalDist < 1e-9) {
      final (c, r) = worldToCell(start.x, start.y);
      if (isSolidCell(c, r)) {
        return (column: c, row: r, point: start, distance: 0.0);
      }
      return null;
    }

    final tw = layer.tileWidth;
    final th = layer.tileHeight;
    final stepSize = math.min(tw, th) * 0.5;
    final numSteps = math.max(1, (totalDist / stepSize).ceil());

    int lastCol = -999999;
    int lastRow = -999999;

    for (var i = 0; i <= numSteps; i++) {
      final t = i / numSteps;
      final px = start.x + dx * t;
      final py = start.y + dy * t;
      final (col, row) = worldToCell(px, py);
      if (col == lastCol && row == lastRow) continue;
      lastCol = col;
      lastRow = row;

      if (isSolidCell(col, row)) {
        final hitPt = Vec2(px, py);
        final dist = t * totalDist;
        return (column: col, row: row, point: hitPt, distance: dist);
      }
    }
    return null;
  }

  /// Returns true if there are no solid tiles along the straight line from [start] to [end].
  bool hasLineOfSight(Vec2 start, Vec2 end) => raycast(start, end) == null;

  /// Moves a circle of [radius] from [position] by [delta] and slides smoothly
  /// along any solid tile edges it contacts.
  Vec2 moveAndSlideCircle(Vec2 position, Vec2 delta, double radius) {
    var x = position.x + delta.x;
    var y = position.y + delta.y;

    final tw = layer.tileWidth;
    final th = layer.tileHeight;
    final ox = layer.originX;
    final oy = layer.originY;

    final minCol = ((x - radius - ox) / tw).floor();
    final maxCol = ((x + radius - ox) / tw).floor();
    final minRow = ((y - radius - oy) / th).floor();
    final maxRow = ((y + radius - oy) / th).floor();

    for (var row = minRow; row <= maxRow; row++) {
      for (var col = minCol; col <= maxCol; col++) {
        if (!isSolidCell(col, row)) continue;
        final left = ox + col * tw;
        final right = left + tw;
        final top = oy + row * th;
        final bottom = top + th;

        final cx = x.clamp(left, right);
        final cy = y.clamp(top, bottom);
        final dx = x - cx;
        final dy = y - cy;
        final d2 = dx * dx + dy * dy;
        if (d2 >= radius * radius) continue;

        if (d2 > 1e-9) {
          final d = math.sqrt(d2);
          final push = radius - d;
          x += (dx / d) * push;
          y += (dy / d) * push;
        } else {
          // Circle center is inside the tile; push out along the shallowest axis.
          final penLeft = (x - left).abs();
          final penRight = (right - x).abs();
          final penTop = (y - top).abs();
          final penBottom = (bottom - y).abs();
          final minPen = math.min(
            math.min(penLeft, penRight),
            math.min(penTop, penBottom),
          );
          if (minPen == penLeft) {
            x = left - radius;
          } else if (minPen == penRight) {
            x = right + radius;
          } else if (minPen == penTop) {
            y = top - radius;
          } else {
            y = bottom + radius;
          }
        }
      }
    }

    return Vec2(x, y);
  }

  @override
  void _onEnableInternal() => scene._tilemaps.add(this);

  @override
  void _onDisableInternal() => scene._tilemaps.remove(this);
}
