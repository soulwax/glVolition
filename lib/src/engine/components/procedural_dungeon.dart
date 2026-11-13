part of '../../engine.dart';

/// Generates a randomized dungeon using binary space partitioning and exposes navigation data (E31-2).
final class ProceduralDungeonComponent extends Component {
  int width;
  int height;
  int minRoomSize;
  int maxRoomSize;
  double tileSize;
  int? seed;

  DungeonResult? _dungeonResult;
  NavGrid? _navGrid;

  ProceduralDungeonComponent({
    this.width = 40,
    this.height = 40,
    this.minRoomSize = 5,
    this.maxRoomSize = 12,
    this.tileSize = 1.0,
    this.seed,
  });

  /// Generated dungeon layout details.
  DungeonResult? get dungeonResult => _dungeonResult;

  /// Generated traversable [NavGrid] matching dungeon floors.
  NavGrid? get navGrid => _navGrid;

  /// List of rectangular rooms carved in this dungeon.
  List<ProcRect> get rooms => _dungeonResult?.rooms ?? const [];

  /// World-space centers of all carved rooms.
  List<Vec3> get roomCenters => rooms
      .map(
        (r) => Vec3(
          (r.center.x + 0.5) * tileSize,
          0.0,
          (r.center.y + 0.5) * tileSize,
        ),
      )
      .toList();

  /// Recommended world spawn position for player (center of first room).
  Vec3 get playerSpawn {
    if (_dungeonResult == null || rooms.isEmpty) {
      return Vec3((width * 0.5) * tileSize, 0.0, (height * 0.5) * tileSize);
    }
    final s = _dungeonResult!.playerSpawn;
    return Vec3((s.x + 0.5) * tileSize, 0.0, (s.y + 0.5) * tileSize);
  }

  /// Generates the dungeon layout and updates the navigation grid.
  /// If a [TilemapComponent] is attached to this GameObject, populates its layers.
  DungeonResult generate({int? customSeed, TilemapComponent? targetTilemap}) {
    final s = customSeed ?? seed;
    final bsp = BspDungeonGenerator(
      minRoomSize: minRoomSize,
      maxRoomSize: maxRoomSize,
    );

    final result = bsp.generate(width: width, height: height, seed: s);
    _dungeonResult = result;

    // Build NavGrid (floor = 1/walkable, wall = 0/blocked)
    final grid = NavGrid(width, height, defaultWalkable: false);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (result.isFloor(x, y)) {
          grid.setWalkable(x, y, true);
        }
      }
    }
    _navGrid = grid;

    // Populate Tilemap if available
    final tilemap =
        targetTilemap ?? gameObject.getComponent<TilemapComponent>();
    if (tilemap != null) {
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final isFloor = result.isFloor(x, y);
          tilemap.setTile(x, y, isFloor ? 1 : 0);
        }
      }
    }

    return result;
  }
}

/// Distributes objects across a 2D rectangular area using blue-noise Poisson Disk sampling (E31-3).
final class PoissonScatterComponent extends Component {
  double areaWidth;
  double areaHeight;
  double minDistance;
  int? seed;

  PoissonScatterComponent({
    this.areaWidth = 20.0,
    this.areaHeight = 20.0,
    this.minDistance = 3.0,
    this.seed,
  });

  /// Samples non-overlapping 2D coordinates adhering to [minDistance].
  List<Vec3> sampleWorldPositions({double y = 0.0, int? customSeed}) {
    final points = PoissonDiskSampler2D.sample(
      width: areaWidth,
      height: areaHeight,
      minDistance: minDistance,
      seed: customSeed ?? seed,
    );

    final origin = transform.position;
    return points
        .map((p) => Vec3(origin.x + p.x, origin.y + y, origin.z + p.y))
        .toList(growable: false);
  }

  /// Instantiates [prefab] at all sampled Poisson positions.
  List<GameObject> spawnPrefabs(
    Prefab prefab, {
    GameObject? parent,
    double y = 0.0,
    int? customSeed,
  }) {
    final positions = sampleWorldPositions(y: y, customSeed: customSeed);
    final p = parent ?? gameObject;
    final spawned = <GameObject>[];

    for (final pos in positions) {
      final go = prefab.instantiate(scene, parent: p, position: pos);
      spawned.add(go);
    }

    return spawned;
  }
}
