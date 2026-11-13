part of '../../engine.dart';

/// Gameplay & visibility metadata stored per cell on a [HexGridComponent].
final class HexCellData {
  String terrain;
  double moveCost;
  bool passable;
  bool blocksSight;
  int elevation;
  Object? metadata;

  HexCellData({
    this.terrain = 'plains',
    this.moveCost = 1.0,
    this.passable = true,
    this.blocksSight = false,
    this.elevation = 0,
    this.metadata,
  });
}

/// Strategy / tactics axial hex board integrated with [GameObject] world space,
/// A*/Dijkstra reachability, line-of-sight FOV, and WFC biome generation.
final class HexGridComponent extends Component {
  final hex.HexLayout layout;
  final hex.HexMap<HexCellData> map;

  /// When `true` (default 3D ground plane), hex XY projects onto XZ world coordinates.
  /// When `false` (2D mode), hex XY projects directly onto world XY coordinates.
  final bool useXZPlane;

  HexGridComponent({
    hex.HexOrientation orientation = hex.HexOrientation.pointyTop,
    double hexSize = 1.0,
    this.useXZPlane = true,
    hex.HexMap<HexCellData>? map,
  }) : layout = hex.HexLayout(orientation: orientation, size: hexSize),
       map = map ?? hex.HexMap<HexCellData>();

  factory HexGridComponent.radial({
    int radius = 4,
    hex.HexOrientation orientation = hex.HexOrientation.pointyTop,
    double hexSize = 1.0,
    bool useXZPlane = true,
    HexCellData Function(hex.HexCoord coord)? builder,
  }) {
    final populated = hex.HexMap<HexCellData>.radial(
      radius,
      builder ?? (_) => HexCellData(),
    );
    return HexGridComponent(
      orientation: orientation,
      hexSize: hexSize,
      useXZPlane: useXZPlane,
      map: populated,
    );
  }

  /// Converts a world-space point (relative to this grid's transform origin) to [hex.HexCoord].
  hex.HexCoord worldToHex(Vec3 worldPos) {
    final origin = isAttached ? transform.position : Vec3.zero;
    final lx = worldPos.x - origin.x;
    final ly = useXZPlane ? (worldPos.z - origin.z) : (worldPos.y - origin.y);
    return layout.fromPixel(lx, ly);
  }

  /// Converts a [hex.HexCoord] back to world-space center coordinates.
  Vec3 hexToWorld(hex.HexCoord coord, {double heightOffset = 0.0}) {
    final origin = isAttached ? transform.position : Vec3.zero;
    final px = layout.toPixel(coord);
    if (useXZPlane) {
      return Vec3(origin.x + px.x, origin.y + heightOffset, origin.z + px.y);
    }
    return Vec3(origin.x + px.x, origin.y + px.y, origin.z + heightOffset);
  }

  List<hex.HexCoord>? findPath(hex.HexCoord start, hex.HexCoord goal) =>
      hex.HexPathfinder.findPath(
        start,
        goal,
        isPassable: (c) => map[c]?.passable ?? false,
        moveCost: (_, to) => map[to]?.moveCost ?? 1.0,
      );

  hex.HexReachableResult reachableFrom(
    hex.HexCoord origin,
    double budget, {
    bool Function(hex.HexCoord coord)? stopsMovement,
  }) => hex.HexPathfinder.reachable(
    origin,
    budget: budget,
    isPassable: (c) => map[c]?.passable ?? false,
    moveCost: (_, to) => map[to]?.moveCost ?? 1.0,
    stopsMovement: stopsMovement,
  );

  Set<hex.HexCoord> computeVisible(
    hex.HexCoord origin, {
    required int radius,
  }) => hex.HexFov.computeVisible(
    origin,
    radius: radius,
    blocksSight: (c) => map[c]?.blocksSight ?? true,
    inBounds: (c) => map.contains(c),
  );

  /// Generates terrain biomes across all cells currently present in [map] using Wave-Function Collapse.
  bool generateWfcBiomes({
    required hex.WfcRuleSet<String> rules,
    int? seed,
    Map<hex.HexCoord, String>? preplaced,
    Map<String, ({double moveCost, bool passable, bool blocksSight})>?
    terrainCatalog,
  }) {
    final solved = hex.WfcHexGrid.solve<String>(
      coords: map.coords,
      rules: rules,
      seed: seed,
      preplaced: preplaced,
    );
    if (solved == null) return false;
    for (final e in solved.entries) {
      final props = terrainCatalog?[e.value];
      final cell = map[e.key] ?? HexCellData();
      cell.terrain = e.value;
      if (props != null) {
        cell
          ..moveCost = props.moveCost
          ..passable = props.passable
          ..blocksSight = props.blocksSight;
      }
      map[e.key] = cell;
    }
    return true;
  }
}

/// Populates a 2D [TileLayer] using Wave-Function Collapse constraint rules.
abstract final class WfcTilemapGenerator {
  static bool populate({
    required TileLayer layer,
    required hex.WfcRuleSet<int> rules,
    int? seed,
    Map<(int x, int y), int>? preplaced,
  }) {
    final solved = hex.WfcGrid2D.solve<int>(
      width: layer.columns,
      height: layer.rows,
      rules: rules,
      seed: seed,
      preplaced: preplaced,
    );
    if (solved == null) return false;
    for (int y = 0; y < layer.rows; y++) {
      for (int x = 0; x < layer.columns; x++) {
        layer.setTile(x, y, solved[y][x]);
      }
    }
    return true;
  }
}

/// Immediate-mode `voxui` tactical hex board overlay & mouse picker.
final class HexGridUI {
  static hex.HexCoord? render(
    VoxUiContext ui,
    HexGridComponent grid, {
    String title = 'Tactical Hex Map',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 340.0,
    double uiScale = 16.0,
    hex.HexCoord? selectedHex,
    Set<hex.HexCoord>? reachable,
    Set<hex.HexCoord>? visible,
    List<hex.HexCoord>? path,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return null;
    }

    final originX = x + width * 0.5;
    final originY =
        y + ui.style.titleBarHeight + (height - ui.style.titleBarHeight) * 0.5;
    final uiLayout = hex.HexLayout(
      orientation: grid.layout.orientation,
      size: uiScale,
      originX: originX,
      originY: originY,
    );

    final dl = ui.drawList;
    final bodyRect = VoxRect(
      x,
      y + ui.style.titleBarHeight,
      width,
      height - ui.style.titleBarHeight,
    );
    hex.HexCoord? hovered;
    if (bodyRect.contains(ui.input.mouseX, ui.input.mouseY)) {
      final candidate = uiLayout.fromPixel(ui.input.mouseX, ui.input.mouseY);
      if (grid.map.contains(candidate)) {
        hovered = candidate;
      }
    }

    for (final entry in grid.map.entries) {
      final c = entry.key;
      final cell = entry.value;
      final corners = uiLayout.polygonCorners(c);
      final center = uiLayout.toPixel(c);

      final isSelected = c == selectedHex;
      final isHovered = c == hovered;
      final inReach = reachable?.contains(c) ?? false;
      final isVis = visible?.contains(c) ?? true;

      var outlineCol = const VoxColor(75, 85, 105, 220);
      if (!cell.passable) {
        outlineCol = const VoxColor(180, 60, 60, 230);
      } else if (isSelected) {
        outlineCol = VoxColor.yellow;
      } else if (inReach) {
        outlineCol = VoxColor.cyan;
      } else if (isHovered) {
        outlineCol = VoxColor.white;
      }

      if (!isVis) {
        outlineCol = outlineCol.withAlpha(80);
      }

      if (inReach) {
        dl.addCircleFilled(
          center.x,
          center.y,
          uiScale * 0.4,
          const VoxColor(60, 190, 230, 90),
        );
      }
      if (!cell.passable) {
        dl.addCircleFilled(
          center.x,
          center.y,
          uiScale * 0.35,
          const VoxColor(170, 55, 55, 140),
        );
      }

      for (int i = 0; i < 6; i++) {
        final p1 = corners[i];
        final p2 = corners[(i + 1) % 6];
        dl.addLine(
          p1.x,
          p1.y,
          p2.x,
          p2.y,
          outlineCol,
          thickness: isSelected ? 2.2 : 1.2,
        );
      }
    }

    if (path != null && path.length >= 2) {
      for (int i = 1; i < path.length; i++) {
        final a = uiLayout.toPixel(path[i - 1]);
        final b = uiLayout.toPixel(path[i]);
        dl.addLine(a.x, a.y, b.x, b.y, VoxColor.yellow, thickness: 2.5);
      }
    }

    ui.endWindow();
    return hovered;
  }
}
