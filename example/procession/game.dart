import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';

/// Escort leader carrying a night torch (`torchRadius`) who recruits nearby
/// [VillagerBehaviour]s and guides them into the Sanctuary (E4-5 Procession).
final class LeaderBehaviour extends Behaviour {
  final TilemapComponent tilemap;
  double moveSpeed;
  double radius;
  double torchRadius;
  Vec2 sanctuaryCenter;
  double sanctuaryRadius;

  final List<VillagerBehaviour> chain = [];
  int deliveredCount = 0;

  LeaderBehaviour({
    TilemapComponent? tilemap,
    this.moveSpeed = 85.0,
    this.radius = 6.0,
    this.torchRadius = 56.0,
    this.sanctuaryCenter = const Vec2(240, 80),
    this.sanctuaryRadius = 28.0,
  }) : tilemap =
           tilemap ??
           TilemapComponent(
             TileLayer(
               columns: 1,
               rows: 1,
               tileWidth: 16,
               tileHeight: 16,
               tileset: [SpriteRegion.white],
             ),
           );

  static final spec = ComponentSpec<LeaderBehaviour>(
    'LeaderBehaviour',
    LeaderBehaviour.new,
    [
      Field.number('moveSpeed', (l) => l.moveSpeed, (l, v) => l.moveSpeed = v),
      Field.number('radius', (l) => l.radius, (l, v) => l.radius = v),
      Field.number(
        'torchRadius',
        (l) => l.torchRadius,
        (l, v) => l.torchRadius = v,
      ),
      Field.number(
        'sanctuaryRadius',
        (l) => l.sanctuaryRadius,
        (l, v) => l.sanctuaryRadius = v,
      ),
      Field.integer(
        'deliveredCount',
        (l) => l.deliveredCount,
        (l, v) => l.deliveredCount = v,
      ),
    ],
  );

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

    // Recruit unrecruited villagers within 24px
    for (final v in scene.findObjectsOfType<VillagerBehaviour>()) {
      if (v.recruited || v.delivered) continue;
      final vp = v.transform.localPosition;
      if (Vec2(next.x - vp.x, next.y - vp.y).length <= 24.0) {
        v.recruited = true;
        chain.add(v);
      }
    }

    // Update escort chain positions (each villager follows the previous member)
    var anchor = next;
    for (final v in List.of(chain)) {
      final vp = Vec2(v.transform.localPosition.x, v.transform.localPosition.y);
      final toAnchor = anchor - vp;
      final dist = toAnchor.length;
      const spacing = 14.0;
      if (dist > spacing) {
        final step =
            toAnchor *
            ((dist - spacing) * math.min(1.0, 10.0 * time.deltaTime) / dist);
        final slid = tilemap.moveAndSlideCircle(vp, step, 5.0);
        v.transform.localPosition = Vec3(slid.x, slid.y, 0);
        anchor = slid;
      } else {
        anchor = vp;
      }

      // Deliver if inside Sanctuary
      if ((anchor - sanctuaryCenter).length <= sanctuaryRadius) {
        v.delivered = true;
        chain.remove(v);
        v.gameObject.setActive(false);
        deliveredCount++;
      }
    }
  }
}

final class VillagerBehaviour extends Behaviour {
  bool recruited;
  bool delivered;

  VillagerBehaviour({this.recruited = false, this.delivered = false});

  static final spec = ComponentSpec<VillagerBehaviour>(
    'VillagerBehaviour',
    VillagerBehaviour.new,
    [
      Field.boolean(
        'recruited',
        (v) => v.recruited,
        (v, val) => v.recruited = val,
      ),
      Field.boolean(
        'delivered',
        (v) => v.delivered,
        (v, val) => v.delivered = val,
      ),
    ],
  );
}

/// Night swarm enemy repelled when inside the leader's `torchRadius` (E4-5).
final class SwarmEnemyBehaviour extends Behaviour {
  double speed;

  SwarmEnemyBehaviour({this.speed = 42.0});

  static final spec = ComponentSpec<SwarmEnemyBehaviour>(
    'SwarmEnemyBehaviour',
    SwarmEnemyBehaviour.new,
    [Field.number('speed', (s) => s.speed, (s, val) => s.speed = val)],
  );

  @override
  void update() {
    final leader = scene.findObjectOfType<LeaderBehaviour>();
    if (leader == null) return;
    final lp = Vec2(
      leader.transform.localPosition.x,
      leader.transform.localPosition.y,
    );
    final mp = Vec2(transform.localPosition.x, transform.localPosition.y);
    final delta = mp - lp;
    final dist = delta.length;
    if (dist < leader.torchRadius && dist > 1e-4) {
      // Repelled outward by torch light
      final push = delta * (speed * 1.6 * time.deltaTime / dist);
      transform.localPosition = Vec3(mp.x + push.x, mp.y + push.y, 0);
    } else if (dist > 1e-4) {
      // Creep toward leader when outside torch
      final step = delta * (-speed * 0.6 * time.deltaTime / dist);
      transform.localPosition = Vec3(mp.x + step.x, mp.y + step.y, 0);
    }
  }
}

/// Registers custom [ComponentSpec]s for the Procession scene.
void registerProcessionSpecs(ComponentRegistry registry) {
  registry
    ..register(LeaderBehaviour.spec)
    ..register(VillagerBehaviour.spec)
    ..register(SwarmEnemyBehaviour.spec);
}

/// Builds the Procession 2D escort scene (`example_4` port).
Scene buildProcessionScene({
  double designWidth = 320,
  double designHeight = 180,
}) {
  final scene = Scene('Procession');

  scene.createGameObject(
    'Camera2D',
    position: Vec3(designWidth * 0.5, designHeight * 0.5, 0),
    components: [
      Camera2DComponent(
        designWidth: designWidth,
        designHeight: designHeight,
        followTransform: false,
      ),
      DebugController(),
    ],
  );

  const cols = 20, rows = 12;
  final layer = TileLayer(
    columns: cols,
    rows: rows,
    tileWidth: 16,
    tileHeight: 16,
    tileset: [SpriteRegion.white, SpriteRegion.white],
  );
  layer.fill(
    (c, r) => (c == 0 || r == 0 || c == cols - 1 || r == rows - 1) ? 1 : 0,
  );
  final tilemap = TilemapComponent(layer, solidTiles: const {1});
  scene.createGameObject('GroundTilemap', components: [tilemap]);

  // Leader with torch
  scene.createGameObject(
    'Leader',
    position: const Vec3(64, 80, 0),
    tag: 'Player',
    components: [
      SpriteRenderer(
        region: SpriteRegion.white,
        width: 12,
        height: 12,
        color: 0xFFD266FF,
        glow: 0.9,
        layer: 2,
      ),
      LeaderBehaviour(tilemap: tilemap),
    ],
  );

  // Villagers waiting along the road
  for (final (i, x) in [(0, 96.0), (1, 144.0), (2, 184.0)]) {
    scene.createGameObject(
      'Villager_$i',
      position: Vec3(x, 80, 0),
      components: [
        SpriteRenderer(
          region: SpriteRegion.white,
          width: 10,
          height: 10,
          color: 0x77DDFFFF,
          layer: 2,
        ),
        VillagerBehaviour(),
      ],
    );
  }

  // Night swarm enemy
  scene.createGameObject(
    'Swarm_0',
    position: const Vec3(92, 80, 0),
    components: [
      SpriteRenderer(
        region: SpriteRegion.white,
        width: 9,
        height: 9,
        color: 0xFF3366FF,
        layer: 3,
      ),
      SwarmEnemyBehaviour(),
    ],
  );

  return scene;
}
