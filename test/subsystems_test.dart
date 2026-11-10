import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

import '../example/dungeon_2d/game.dart';
import '../example/island_3d/game.dart';

final class _HealthBehaviour extends Behaviour {
  int hp;
  String faction;
  double speed;

  _HealthBehaviour({this.hp = 100, this.faction = 'neutral', this.speed = 5.0});

  static final spec = ComponentSpec<_HealthBehaviour>(
    'HealthBehaviour',
    _HealthBehaviour.new,
    [
      Field.integer('hp', (b) => b.hp, (b, v) => b.hp = v),
      Field.text('faction', (b) => b.faction, (b, v) => b.faction = v),
      Field.number('speed', (b) => b.speed, (b, v) => b.speed = v),
    ],
  );
}

final class _FixedCounter extends Behaviour {
  int fixedCount = 0;
  int updateCount = 0;

  @override
  void fixedUpdate() => fixedCount++;

  @override
  void update() => updateCount++;
}

final class _PoolTracker extends Behaviour with Poolable {
  int spawnCount = 0;
  int despawnCount = 0;

  @override
  void onSpawned() => spawnCount++;

  @override
  void onDespawned() => despawnCount++;
}

void main() {
  group('E2 — DebugController & Session Snapshot', () {
    test('DebugController pauses, steps single fixed frames, scales time, and reports metrics', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.fixedDeltaTime = 0.02;

      final counter = _FixedCounter();
      final debug = DebugController(isOpen: true);
      engine.scene.createGameObject('Game', components: [debug, counter]);

      engine.step(0.02);
      expect(counter.fixedCount, 1);

      // Pause via Space key while overlay is open
      host.input.press('Space');
      engine.step(0.02);
      host.input.endFrame();
      expect(debug.isPaused, isTrue);
      expect(engine.time.timeScale, 0);

      // While paused, normal engine steps do not run fixedUpdate
      final beforeFixed = counter.fixedCount;
      engine.step(0.1);
      expect(counter.fixedCount, beforeFixed);

      // Single-step via Period (.)
      host.input.press('Period');
      engine.step(0.016);
      host.input.endFrame();
      expect(counter.fixedCount, beforeFixed + 1);
      expect(debug.isPaused, isTrue);

      // Resume and speed up
      debug.resume();
      expect(debug.isPaused, isFalse);
      debug.setTimeScale(2.0);
      expect(engine.time.timeScale, 2.0);

      final m = debug.metrics();
      expect(m.gameObjectCount, 1);
      expect(m.activeBehaviourCount, 2);
      expect(m.paused, isFalse);
    });

    test('captureSessionSnapshot and restoreSessionSnapshot preserve state across reload', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.registry.register(_HealthBehaviour.spec);
      engine.storage.write('high_score', '4200');
      engine.time.timeScale = 0.5;

      engine.scene.createGameObject(
        'Hero',
        position: const Vec3(3, 4, 5),
        tag: 'Player',
        components: [_HealthBehaviour(hp: 77, faction: 'allies', speed: 9.5)],
      );

      final snap = engine.captureSessionSnapshot();

      // Mutate scene and storage, then restore
      engine.loadScene(Scene('Blank'));
      engine.storage.write('high_score', '0');
      engine.time.timeScale = 1.0;

      engine.restoreSessionSnapshot(snap);
      expect(engine.time.timeScale, 0.5);
      expect(engine.storage.read('high_score'), '4200');
      final hero = engine.scene.find('Hero');
      expect(hero, isNotNull);
      expect(hero!.tag, 'Player');
      expect(hero.transform.position, const Vec3(3, 4, 5));
      final hb = hero.getComponent<_HealthBehaviour>();
      expect(hb, isNotNull);
      expect(hb!.hp, 77);
      expect(hb.faction, 'allies');
      expect(hb.speed, 9.5);
    });
  });

  group('E3 — Serialization, Prefabs, ObjectPool & AssetCatalog', () {
    test('SceneSerializer round-trips hierarchy, lights, cameras, colliders, and prefab overrides', () {
      final reg = ComponentRegistry.defaults()..register(_HealthBehaviour.spec);
      final enemyPrefab = Prefab(
        'Enemy',
        (go) => go.addComponent(_HealthBehaviour(hp: 50, faction: 'raiders', speed: 4.0)),
      );

      final s1 = Scene('Level1');
      s1.renderSettings
        ..fogEnabled = true
        ..fogStart = 25
        ..fogEnd = 120;

      final camGo = s1.createGameObject(
        'MainCamera',
        position: const Vec3(0, 10, 20),
        components: [Camera.ortho(orthoHeight: 16)],
      );
      s1.createGameObject(
        'Sun',
        parent: camGo,
        components: [Light.directional(intensity: 1.8)],
      );
      s1.createGameObject(
        'TriggerZone',
        position: const Vec3(1, 2, 3),
        components: [SphereCollider(radius: 3.5, isTrigger: true)],
      );

      final jsonStr = SceneSerializer.toJsonString(s1, registry: reg);
      final map = SceneSerializer.toJson(s1, registry: reg);
      // Inject a prefab instance with an hp override into the JSON object list
      (map['objects'] as List<Object?>).add(<String, Object?>{
        'prefab': 'Enemy',
        'name': 'BossEnemy',
        'transform': {
          'p': [10.0, 0.0, -5.0],
        },
        'components': [
          {
            'type': 'HealthBehaviour',
            'hp': 250,
          },
        ],
      });

      final s2 = SceneSerializer.fromJson(
        map,
        registry: reg,
        prefabs: {'Enemy': enemyPrefab},
      );
      expect(s2.name, 'Level1');
      expect(s2.renderSettings.fogEnabled, isTrue);
      expect(s2.renderSettings.fogStart, 25);
      expect(s2.find('MainCamera')?.getComponent<Camera>()?.orthographic, isTrue);
      expect(s2.find('MainCamera')?.getComponent<Camera>()?.orthoHeight, 16);
      expect(s2.find('Sun')?.parent?.name, 'MainCamera');
      expect(s2.find('Sun')?.getComponent<Light>()?.intensity, 1.8);
      expect(s2.find('TriggerZone')?.getComponent<SphereCollider>()?.radius, 3.5);

      final boss = s2.find('BossEnemy');
      expect(boss, isNotNull);
      expect(boss!.transform.localPosition, const Vec3(10, 0, -5));
      final bossHealth = boss.getComponent<_HealthBehaviour>()!;
      expect(bossHealth.hp, 250);
      expect(bossHealth.faction, 'raiders'); // preserved from prefab default

      // Also verify string round-trip
      final s3 = SceneSerializer.fromJsonString(jsonStr, registry: reg);
      expect(s3.find('MainCamera'), isNotNull);
    });

    test('ObjectPool warms up, acquires, reuses without new allocations, and fires Poolable callbacks', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final prefab = Prefab('Bullet', (go) => go.addComponent(_PoolTracker()));
      final pool = ObjectPool<_PoolTracker>(
        scene: engine.scene,
        prefab: prefab,
        initialCapacity: 8,
      );

      expect(pool.availableCount, 8);
      expect(pool.activeCount, 0);

      final seen = <GameObject>{};
      for (var cycle = 0; cycle < 100; cycle++) {
        final b = pool.acquire(position: Vec3(cycle.toDouble(), 0, 0));
        seen.add(b.gameObject);
        expect(b.gameObject.activeSelf, isTrue);
        expect(b.transform.localPosition.x, cycle.toDouble());
        pool.release(b);
        expect(b.gameObject.activeSelf, isFalse);
      }

      // All 100 acquires were satisfied by the 8 pre-warmed instances
      expect(seen.length, lessThanOrEqualTo(8));
      final tracker = seen.first.getComponent<_PoolTracker>()!;
      expect(tracker.spawnCount, greaterThan(0));
      expect(tracker.despawnCount, equals(tracker.spawnCount));
    });

    test('AssetCatalog preloads procedural textures/audio and releases GPU handles on clear()', () async {
      final host = HeadlessHost();
      final engine = Engine(host);
      final progressLog = <(int, int)>[];

      await engine.catalog.load(
        {
          'beep': const AudioEntry('sfx/beep.wav', volume: 0.7),
          'checker': ProceduralTextureEntry(
            width: 4,
            height: 4,
            generatePixels: () => Uint8List(4 * 4 * 4),
          ),
        },
        onProgress: (loaded, total) => progressLog.add((loaded, total)),
      );

      expect(progressLog.first, (0, 2));
      expect(progressLog.last, (2, 2));

      engine.catalog.registerMesh('cube', Primitives.cube());
      engine.catalog.registerMaterial('mat', const MaterialDefinition(key: 'mat'));

      expect(engine.catalog.clip('beep').path, 'sfx/beep.wav');
      expect(engine.catalog.texture('checker'), isNotNull);
      expect(engine.catalog.mesh('cube'), isNotNull);
      expect(engine.catalog.material('mat'), isNotNull);
      expect(host.graphics.liveMeshes.length, 1);
      expect(host.graphics.liveMaterials.length, 1);
      expect(host.graphics.liveTextures.length, 1);

      engine.catalog.clear();
      expect(host.graphics.liveMeshes, isEmpty);
      expect(host.graphics.liveMaterials, isEmpty);
      expect(host.graphics.liveTextures, isEmpty);
    });
  });

  group('E4 — 2D Sprites, Tilemap Collision, Ortho Camera & Canvas UI', () {
    test('Camera.ortho and screenToGroundPlane project rays onto y == groundHeight', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final camGo = engine.scene.createGameObject(
        'IsoCam',
        position: const Vec3(0, 20, 20),
        rotation: lookRotation(const Vec3(0, -20, -20)),
        components: [Camera.ortho(orthoHeight: 20)],
      );
      final cam = camGo.getComponent<Camera>()!;
      engine.step(0.016);

      // Center of 1280x720 viewport should hit near (0, 0, 0) on ground plane y=0
      final hit = cam.screenToGroundPlane(640, 360, 0);
      expect(hit, isNotNull);
      expect(hit!.x.abs(), lessThan(1e-3));
      expect(hit.y, closeTo(0, 1e-5));
      expect(hit.z.abs(), lessThan(1e-3));
    });

    test('SpriteAnimator steps through clips and updates sibling SpriteRenderer', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.createGameObject('Cam2D', components: [Camera2DComponent()]);

      final f0 = SpriteRegion(texture: null, width: 16, height: 16, u0: 0, v0: 0, u1: 0.5, v1: 1);
      final f1 = SpriteRegion(texture: null, width: 16, height: 16, u0: 0.5, v0: 0, u1: 1.0, v1: 1);

      final sr = SpriteRenderer(region: f0);
      final anim = SpriteAnimator(
        clips: {
          'run': [f0, f1],
        },
        fps: 10,
        initialClip: 'run',
      );
      engine.scene.createGameObject('Runner', components: [sr, anim]);

      engine.step(0.01);
      expect(sr.region, same(f0));

      engine.step(0.12); // total > 0.1s -> frame 1
      expect(sr.region, same(f1));
    });

    test('TilemapComponent.moveAndSlideCircle slides along solid tiles without penetrating', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final layer = TileLayer(
        columns: 8,
        rows: 8,
        tileWidth: 16,
        tileHeight: 16,
        tileset: [SpriteRegion.white, SpriteRegion.white],
      );
      // Place a solid wall at column 3, rows 0..7
      for (var r = 0; r < 8; r++) {
        layer.setTile(3, r, 1);
      }

      final tm = TilemapComponent(layer, solidTiles: {1});
      engine.scene.createGameObject('Map', components: [tm]);

      // Circle of radius 4 at (42, 32) moving (+10, +12) diagonally into wall at x = 3*16 = 48
      final next = tm.moveAndSlideCircle(const Vec2(42, 32), const Vec2(10, 12), 4);
      // X must be clamped to left edge of wall minus radius (48 - 4 = 44), while Y slides freely to 44
      expect(next.x, closeTo(44.0, 1e-4));
      expect(next.y, closeTo(44.0, 1e-4));
    });

    test('UICanvas dispatches UIButton click from ScriptedInput pointer events', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      var clicked = 0;
      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      canvas.add(
        UIButton(
          label: 'START',
          anchor: UIAnchor.center,
          width: 120,
          height: 40,
          onPressed: () => clicked++,
        ),
      );
      engine.scene.createGameObject('HUD', components: [canvas]);

      // Press at center (320, 180)
      host.input
        ..pointerX = 320
        ..pointerY = 180
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(clicked, 0);

      // Release at center (320, 180)
      host.input
        ..pointerDown = false
        ..pointerReleased = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(clicked, 1);
    });
  });

  group('E5 — 3D Animator, Splines, Terrain/Water/Buoyancy & AtmosphereVolume', () {
    test('Animator plays keyframe AnimationClip and respects time.timeScale', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final go = engine.scene.createGameObject('Platform');
      final clip = AnimationClip(
        name: 'slide',
        duration: 1.0,
        loopMode: LoopMode.once,
        tracks: [
          Vector3Track(
            target: go.node,
            keyframes: const [
              Keyframe(0.0, Vec3(0, 0, 0)),
              Keyframe(1.0, Vec3(10, 0, 0)),
            ],
          ),
        ],
      );
      go.addComponent(Animator(initialClips: [clip], defaultClip: 'slide'));

      for (var i = 0; i < 10; i++) {
        engine.step(0.05);
      }
      expect(go.node.localTransform.translation.x, closeTo(5.0, 1e-2));
    });

    test('SplinePath and SplineFollower move along arc length and align rotation', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final path = SplinePath.fromPoints(const [
        Vec3(0, 0, 0),
        Vec3(0, 0, -10),
        Vec3(0, 0, -20),
      ]);
      var finished = false;
      final follower = SplineFollower(
        path: path,
        speed: 10.0,
        loopMode: LoopMode.once,
        onReachedEnd: () => finished = true,
      );
      final cart = engine.scene.createGameObject('Cart', components: [path, follower]);

      for (var i = 0; i < 10; i++) {
        engine.step(0.1);
      }
      expect(cart.transform.position.z, closeTo(-10.0, 0.25));
      expect(finished, isFalse);

      for (var i = 0; i < 15; i++) {
        engine.step(0.1);
      }
      expect(cart.transform.position.z, closeTo(-20.0, 0.1));
      expect(finished, isTrue);
    });

    test('TerrainComponent, WaterSurfaceComponent, and BuoyantBody update height and vessel pose', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final terrain = TerrainComponent(
        TerrainGenerator(subdivisionsX: 16, subdivisionsZ: 16, width: 40, depth: 40, maxHeight: 8, seed: 7),
        biomeTextureSize: 32,
      );
      engine.scene.createGameObject('Island', components: [terrain]);
      expect(terrain.sampleHeight(0, 0).isFinite, isTrue);

      final water = WaterSurfaceComponent(
        surface: WaterSurfaceMesh(subdivisionsX: 8, subdivisionsZ: 8, width: 30, depth: 30),
        waves: GerstnerWaveEvaluator.ocean(),
      );
      engine.scene.createGameObject('Ocean', components: [water]);

      final boat = engine.scene.createGameObject(
        'Boat',
        position: const Vec3(0, 2, 0),
        components: [BuoyantBody()],
      );

      for (var i = 0; i < 10; i++) {
        engine.step(0.05);
      }
      expect(boat.transform.position.y.isFinite, isTrue);
      expect(boat.getComponent<BuoyantBody>()!.roll.isFinite, isTrue);
    });

    test('AtmosphereVolume advances solar cycle and updates scene RenderSettings & sun Light', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final sunLight = Light.directional(intensity: 1.0);
      final atm = AtmosphereVolume(timeOfDayHours: 6.5, hoursPerSecond: 2.0);
      engine.scene.createGameObject('Sky', components: [sunLight, atm]);

      for (var i = 0; i < 10; i++) {
        engine.step(0.1);
      } // advances 1.0s -> from 6.5h (sunrise) to 8.5h (morning)
      expect(atm.timeOfDayHours, closeTo(8.5, 1e-5));
      expect(atm.currentSolarState, isNotNull);
      expect(engine.scene.renderSettings.skybox, isNotNull);
      expect(engine.scene.renderSettings.fogEnabled, isTrue);
      expect(sunLight.intensity, greaterThan(0));
    });

    test('Dungeon2D and Island3D validation scenes step cleanly on HeadlessHost', () {
      final host = HeadlessHost();
      final engine = Engine(host, initialScene: buildDungeon2DScene());

      host.input.press('KeyD');
      for (var i = 0; i < 10; i++) {
        engine.step(0.016);
      }
      host.input.release('KeyD');
      host.input.endFrame();

      final player = engine.scene.find('Player')!;
      expect(player.transform.localPosition.x, greaterThan(64.0));

      // Switch to 3D Island scene
      engine.loadScene(buildIsland3DScene());
      for (var i = 0; i < 20; i++) {
        engine.step(0.05);
      }
      final skiff = engine.scene.find('Skiff')!;
      expect(skiff.transform.position.y.isFinite, isTrue);
      final tourCam = engine.scene.find('TourCamera')!;
      expect(tourCam.getComponent<SplineFollower>()!.distance, greaterThan(0));
    });
  });
}
