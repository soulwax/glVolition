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
    if (id < 0) return true; // Out-of-bounds is treated as solid wall.
    final pred = isSolidPredicate;
    if (pred != null && pred(id)) return true;
    return solidTileIds.contains(id);
  }

  bool isSolidCell(int column, int row) => isSolidTileId(layer.tileAt(column, row));

  (int, int) worldToCell(double worldX, double worldY) {
    final col = ((worldX - layer.originX) / layer.tileWidth).floor();
    final row = ((worldY - layer.originY) / layer.tileHeight).floor();
    return (col, row);
  }

  bool isSolidAtWorld(double worldX, double worldY) {
    final (col, row) = worldToCell(worldX, worldY);
    return isSolidCell(col, row);
  }

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
          final minPen = math.min(math.min(penLeft, penRight), math.min(penTop, penBottom));
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
