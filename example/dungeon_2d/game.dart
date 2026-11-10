import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

/// Brazier in the dungeon that ignites when the player approaches, emitting
/// a safe light radius that repels [ShadeBehaviour]s (E4-5 Lantern).
final class BrazierBehaviour extends Behaviour {
  double igniteRadius;
  double safeRadius;
  bool isLit;

  BrazierBehaviour({
    this.igniteRadius = 22.0,
    this.safeRadius = 48.0,
    this.isLit = false,
  });

  static final spec = ComponentSpec<BrazierBehaviour>(
    'BrazierBehaviour',
    BrazierBehaviour.new,
    [
      Field.number('igniteRadius', (b) => b.igniteRadius, (b, v) => b.igniteRadius = v),
      Field.number('safeRadius', (b) => b.safeRadius, (b, v) => b.safeRadius = v),
      Field.boolean('isLit', (b) => b.isLit, (b, v) => b.isLit = v),
    ],
  );

  void ignite() {
    if (isLit) return;
    isLit = true;
    final sr = getComponent<SpriteRenderer>();
    if (sr != null) {
      sr
        ..color = 0xFFAA33FF
        ..glow = 0.85;
    }
    final light = getComponent<Light>();
    if (light != null) {
      light.intensity = 2.2;
    }
  }
}

/// Collectible light mote that restores torch fuel and awards score (E4-5).
final class MoteBehaviour extends Behaviour {
  double pickupRadius;
  bool collected;

  MoteBehaviour({this.pickupRadius = 14.0, this.collected = false});

  static final spec = ComponentSpec<MoteBehaviour>(
    'MoteBehaviour',
    MoteBehaviour.new,
    [
      Field.number('pickupRadius', (m) => m.pickupRadius, (m, v) => m.pickupRadius = v),
      Field.boolean('collected', (m) => m.collected, (m, v) => m.collected = v),
    ],
  );
}

/// Shadow enemy that chases the explorer unless repelled by a lit
/// [BrazierBehaviour] or high torch fuel (E4-5).
final class ShadeBehaviour extends Behaviour {
  double speed;
  double hitRadius;

  ShadeBehaviour({this.speed = 36.0, this.hitRadius = 10.0});

  static final spec = ComponentSpec<ShadeBehaviour>(
    'ShadeBehaviour',
    ShadeBehaviour.new,
    [
      Field.number('speed', (s) => s.speed, (s, v) => s.speed = v),
      Field.number('hitRadius', (s) => s.hitRadius, (s, v) => s.hitRadius = v),
    ],
  );

  @override
  void update() {
    final explorer = scene.findObjectOfType<DungeonExplorer>();
    if (explorer == null) return;

    final myPos = transform.localPosition;
    final pPos = explorer.transform.localPosition;

    // Check if inside any lit brazier's safe radius -> repel outward
    for (final b in scene.findObjectsOfType<BrazierBehaviour>()) {
      if (!b.isLit) continue;
      final bPos = b.transform.localPosition;
      final away = Vec2(myPos.x - bPos.x, myPos.y - bPos.y);
      final dist = away.length;
      if (dist < b.safeRadius && dist > 1e-4) {
        final push = away * (speed * 1.4 * time.deltaTime / dist);
        transform.localPosition = Vec3(myPos.x + push.x, myPos.y + push.y, myPos.z);
        return;
      }
    }

    final toPlayer = Vec2(pPos.x - myPos.x, pPos.y - myPos.y);
    final dist = toPlayer.length;
    if (dist <= hitRadius) {
      explorer.takeShadeHit();
      // Knock shade back after hit
      if (dist > 1e-4) {
        final back = toPlayer * (-28.0 / dist);
        transform.localPosition = Vec3(myPos.x + back.x, myPos.y + back.y, myPos.z);
      }
      return;
    }
    if (dist > 1e-4) {
      final step = toPlayer * (math.min(dist, speed * time.deltaTime) / dist);
      transform.localPosition = Vec3(myPos.x + step.x, myPos.y + step.y, myPos.z);
    }
  }
}

/// Top-down 2D dungeon explorer behaviour driven by [InputActions] (`Horizontal`,
/// `Vertical`) and colliding smoothly against a [TilemapComponent] via
/// [TilemapComponent.moveAndSlideCircle] (Phase E4 validation & Lantern port).
final class DungeonExplorer extends Behaviour {
  final TilemapComponent tilemap;
  double moveSpeed;
  double radius;

  int motesCollected = 0;
  int braziersLit = 0;
  int hitsTaken = 0;
  double torchFuel = 1.0;
  bool portalUnlocked = false;
  bool levelCompleted = false;
  Vec2 portalPosition;

  DungeonExplorer({
    required this.tilemap,
    this.moveSpeed = 80.0,
    this.radius = 6.0,
    this.portalPosition = const Vec2(208, 112),
  });

  void takeShadeHit() {
    hitsTaken++;
    torchFuel = math.max(0.0, torchFuel - 0.25);
  }

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

    torchFuel = math.max(0.0, torchFuel - 0.02 * time.deltaTime);

    final anim = getComponent<SpriteAnimator>();
    if (anim != null) {
      anim.play((dx.abs() > 1e-3 || dy.abs() > 1e-3) ? 'walk' : 'idle');
    }

    // Check braziers
    var allLit = true;
    var litCount = 0;
    for (final b in scene.findObjectsOfType<BrazierBehaviour>()) {
      final bp = b.transform.localPosition;
      final d = Vec2(next.x - bp.x, next.y - bp.y).length;
      if (!b.isLit && d <= b.igniteRadius) {
        b.ignite();
      }
      if (b.isLit) {
        litCount++;
      } else {
        allLit = false;
      }
    }
    braziersLit = litCount;
    portalUnlocked = allLit && litCount > 0;

    // Check motes
    for (final m in List.of(scene.findObjectsOfType<MoteBehaviour>())) {
      if (m.collected) continue;
      final mp = m.transform.localPosition;
      if (Vec2(next.x - mp.x, next.y - mp.y).length <= m.pickupRadius) {
        m.collected = true;
        motesCollected++;
        torchFuel = math.min(1.0, torchFuel + 0.35);
        m.gameObject.setActive(false);
      }
    }

    // Check portal exit
    if (portalUnlocked && Vec2(next.x - portalPosition.x, next.y - portalPosition.y).length <= 16.0) {
      levelCompleted = true;
    }

    // Update HUD fuel bar if present
    final hud = scene.findObjectOfType<UICanvas>();
    if (hud != null) {
      for (final el in hud.elements) {
        if (el is UIProgressBar) {
          el.value = torchFuel;
        }
      }
    }
  }
}

/// Registers custom [ComponentSpec]s for the Dungeon2D (Lantern) scene.
void registerDungeon2DSpecs(ComponentRegistry registry) {
  registry
    ..register(BrazierBehaviour.spec)
    ..register(MoteBehaviour.spec)
    ..register(ShadeBehaviour.spec);
}

/// Builds a playable 2D dungeon [Scene] (Lantern port) with a walled room,
/// braziers, light motes, shade enemies, portal, animated explorer, camera,
/// and in-canvas HUD.
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

  // Braziers
  for (final (i, p) in [(0, const Vec3(96, 64, 0)), (1, const Vec3(160, 64, 0))]) {
    scene.createGameObject(
      'Brazier_$i',
      position: p,
      components: [
        SpriteRenderer(region: SpriteRegion.white, width: 10, height: 10, color: 0x554433FF, layer: 1),
        Light.point(color: const LinearColor(1.0, 0.65, 0.25), intensity: 0.0, range: 12.0),
        BrazierBehaviour(),
      ],
    );
  }

  // Light motes
  scene.createGameObject(
    'Mote_0',
    position: const Vec3(80, 64, 0),
    components: [
      SpriteRenderer(region: SpriteRegion.white, width: 6, height: 6, color: 0xFFEE66FF, glow: 0.7, layer: 1),
      MoteBehaviour(),
    ],
  );

  // Shade enemy
  scene.createGameObject(
    'Shade_0',
    position: const Vec3(192, 96, 0),
    components: [
      SpriteRenderer(region: SpriteRegion.white, width: 11, height: 11, color: 0x9922CCFF, layer: 2),
      ShadeBehaviour(),
    ],
  );

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
