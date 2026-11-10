import 'package:gl_volition/gl_volition.dart';

/// Top-down 2D dungeon explorer behaviour driven by [InputActions] (`Horizontal`,
/// `Vertical`) and colliding smoothly against a [TilemapComponent] via
/// [TilemapComponent.moveAndSlideCircle] (Phase E4 validation).
final class DungeonExplorer extends Behaviour {
  final TilemapComponent tilemap;
  double moveSpeed;
  double radius;
  int coinsCollected = 0;

  DungeonExplorer({
    required this.tilemap,
    this.moveSpeed = 80.0,
    this.radius = 6.0,
  });

  @override
  void update() {
    final dx = input.getAxis('Horizontal') * moveSpeed * time.deltaTime;
    final dy = -input.getAxis('Vertical') * moveSpeed * time.deltaTime;
    final pos = transform.localPosition;
    final next = tilemap.moveAndSlideCircle(
      Vec2(pos.x, pos.y),
      Vec2(dx, dy),
      radius,
    );
    transform.localPosition = Vec3(next.x, next.y, pos.z);

    final anim = getComponent<SpriteAnimator>();
    if (anim != null) {
      anim.play((dx.abs() > 1e-3 || dy.abs() > 1e-3) ? 'walk' : 'idle');
    }
  }
}

/// Builds a playable 2D dungeon [Scene] with a walled room, animated explorer,
/// camera, and in-canvas HUD.
Scene buildDungeon2DScene({double designWidth = 320, double designHeight = 180}) {
  final scene = Scene('Dungeon2D');

  final camGo = scene.createGameObject(
    'Camera2D',
    position: Vec3(designWidth * 0.5, designHeight * 0.5, 0),
    components: [
      Camera2DComponent(designWidth: designWidth, designHeight: designHeight),
      DebugController(),
    ],
  );

  // 16x10 room of 16x16 tiles (0 = floor, 1 = wall)
  const cols = 16, rows = 10;
  final layer = TileLayer(
    columns: cols,
    rows: rows,
    tileWidth: 16,
    tileHeight: 16,
    tileset: [SpriteRegion.white, SpriteRegion.white],
  );
  layer.fill((c, r) => (c == 0 || r == 0 || c == cols - 1 || r == rows - 1) ? 1 : 0);

  final tilemap = TilemapComponent(layer, solidTiles: const {1});
  scene.createGameObject('Tilemap', components: [tilemap]);

  final idleRegion = SpriteRegion.white;
  final walkRegion = SpriteRegion.white;
  final player = scene.createGameObject(
    'Player',
    position: const Vec3(64, 64, 0),
    tag: 'Player',
    components: [
      SpriteRenderer(region: idleRegion, width: 12, height: 12, color: 0x4DFFAAFF, layer: 2),
      SpriteAnimator(
        clips: {
          'idle': [idleRegion],
          'walk': [idleRegion, walkRegion],
        },
        initialClip: 'idle',
      ),
      DungeonExplorer(tilemap: tilemap),
    ],
  );

  // Follow player with camera
  camGo.transform.localPosition = player.transform.localPosition;

  // HUD overlay
  final hud = UICanvas(designWidth: designWidth, designHeight: designHeight);
  hud.add(
    UIPanel(
      anchor: UIAnchor.topLeft,
      x: 6,
      y: 6,
      width: 96,
      height: 20,
    ),
  );
  hud.add(
    UIProgressBar(
      anchor: UIAnchor.topLeft,
      x: 10,
      y: 11,
      width: 88,
      height: 10,
      value: 1.0,
    ),
  );
  scene.createGameObject('HUD', components: [hud]);

  return scene;
}
