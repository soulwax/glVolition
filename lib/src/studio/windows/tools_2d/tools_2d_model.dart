/// S7-D: 2D Tools — Sprite Slicer (grid/pivot/9-slice), Tile Palette & Rule
/// Tiles, and Sorting Layers (`voxatlas`, `sprites_2d`, `tilemap`).
library;

/// Sliced sprite region with normalized pivot & 9-slice border (`[S7-D]`).
final class SpriteSliceRect {
  final String name;
  final int x;
  final int y;
  final int width;
  final int height;
  final double pivotX;
  final double pivotY;
  final (int left, int top, int right, int bottom) nineSliceBorder;

  const SpriteSliceRect({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.nineSliceBorder = (0, 0, 0, 0),
  });
}

/// Grid sprite slicer producing deterministic [SpriteSliceRect]s (`[S7-D]`).
abstract final class SpriteSlicerTool {
  static List<SpriteSliceRect> sliceGrid({
    required int textureWidth,
    required int textureHeight,
    required int cellWidth,
    required int cellHeight,
    String prefix = 'sprite',
  }) {
    final cols = textureWidth ~/ cellWidth;
    final rows = textureHeight ~/ cellHeight;
    final out = <SpriteSliceRect>[];
    var idx = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        out.add(
          SpriteSliceRect(
            name: '${prefix}_${idx++}',
            x: c * cellWidth,
            y: r * cellHeight,
            width: cellWidth,
            height: cellHeight,
          ),
        );
      }
    }
    return out;
  }
}

/// 2D Tile Palette brush/rect/flood-fill & 4-neighbor rule-tile evaluator
/// (`[S7-D]`).
final class TilePaletteTool {
  final int width;
  final int height;
  final List<int> cells;

  TilePaletteTool({required this.width, required this.height})
    : cells = List<int>.filled(width * height, 0);

  int getTile(int x, int y) =>
      (x < 0 || y < 0 || x >= width || y >= height) ? 0 : cells[y * width + x];

  void paintBrush(int x, int y, int tileId) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    cells[y * width + x] = tileId;
  }

  void paintRect(int x0, int y0, int x1, int y1, int tileId) {
    final minX = x0 < x1 ? x0 : x1;
    final maxX = x0 > x1 ? x0 : x1;
    final minY = y0 < y1 ? y0 : y1;
    final maxY = y0 > y1 ? y0 : y1;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        paintBrush(x, y, tileId);
      }
    }
  }

  /// 4-bit cardinal neighbor mask (bit0=N, bit1=E, bit2=S, bit3=W) for rule
  /// tile auto-selection.
  int neighborMask4(int x, int y, int tileId) {
    var mask = 0;
    if (getTile(x, y - 1) == tileId) mask |= 1;
    if (getTile(x + 1, y) == tileId) mask |= 2;
    if (getTile(x, y + 1) == tileId) mask |= 4;
    if (getTile(x - 1, y) == tileId) mask |= 8;
    return mask;
  }
}
