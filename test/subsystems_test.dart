import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../example/dungeon_2d/game.dart';
import '../example/island_3d/game.dart';
import '../example/procession/game.dart';

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

    test('Dungeon2D (Lantern), Procession, and Island3D (Tidewatch) full gameplay loops', () {
      // 1. Lantern (Dungeon2D): collect mote, light both braziers, unlock portal
      final host = HeadlessHost();
      final engine = Engine(host, initialScene: buildDungeon2DScene());

      host.input.press('KeyD');
      for (var i = 0; i < 90; i++) {
        engine.step(0.02);
      }
      host.input.release('KeyD');
      host.input.endFrame();

      final explorer = engine.scene.findObjectOfType<DungeonExplorer>()!;
      expect(explorer.motesCollected, 1);
      expect(explorer.braziersLit, 2);
      expect(explorer.portalUnlocked, isTrue);

      // Move down to portal at (208, 112)
      host.input.press('KeyS');
      for (var i = 0; i < 45; i++) {
        engine.step(0.02);
      }
      host.input.release('KeyS');
      host.input.endFrame();
      expect(explorer.levelCompleted, isTrue);

      // 2. Procession: recruit 3 villagers, repel swarm with torch, deliver to Sanctuary
      engine.loadScene(buildProcessionScene());
      final leader = engine.scene.findObjectOfType<LeaderBehaviour>()!;
      final swarm = engine.scene.findObjectOfType<SwarmEnemyBehaviour>()!;
      final initialSwarmDist = (swarm.transform.localPosition - leader.transform.localPosition).length;
      engine.step(0.05);
      final afterSwarmDist = (swarm.transform.localPosition - leader.transform.localPosition).length;
      expect(afterSwarmDist, greaterThan(initialSwarmDist));

      host.input.press('KeyD');
      for (var i = 0; i < 140; i++) {
        engine.step(0.02);
      }
      host.input.release('KeyD');
      host.input.endFrame();
      expect(leader.deliveredCount, 3);

      // 3. Tidewatch (Island3D): guide ship with lighthouse beam or launch flare, test reef wreck
      engine.loadScene(buildIsland3DScene());
      final lighthouse = engine.scene.findObjectOfType<LighthouseBehaviour>()!;
      final skiffAgent = engine.scene.findObjectOfType<ShipAgentBehaviour>()!;
      final harbour = engine.scene.findObjectOfType<HarbourDirector>()!;

      // Launch a flare so the ship stays guided along its full route into harbour
      harbour.launchFlareAt(skiffAgent.transform.position);
      expect(harbour.flaresLaunched, 1);

      for (var i = 0; i < 40; i++) {
        lighthouse.aimPoint = skiffAgent.transform.localPosition;
        engine.step(0.1);
      }
      expect(skiffAgent.dockedSafely, isTrue);

      // Verify unguided ship wrecks on reef when lighthouse aims away and no flare is active
      engine.loadScene(buildIsland3DScene());
      final unguidedLighthouse = engine.scene.findObjectOfType<LighthouseBehaviour>()!;
      unguidedLighthouse.aimPoint = const Vec3(-100, 0, -100);
      final unguidedShip = engine.scene.findObjectOfType<ShipAgentBehaviour>()!;
      for (var i = 0; i < 30; i++) {
        engine.step(0.1);
      }
      expect(unguidedShip.wreckedOnReef, isTrue);
    });
  });

  group('E7 — EditorSession (Play/Stop Snapshot, Free-Look Camera & 3D Gizmo Drag)', () {
    test('enterPlayMode and stopPlayMode discard runtime mutations and destroyed objects', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.registry.register(_HealthBehaviour.spec);

      final crate = engine.scene.createGameObject(
        'Crate',
        position: const Vec3(2, 0, -4),
        components: [_HealthBehaviour(hp: 100)],
      );
      final enemy = engine.scene.createGameObject('TempEnemy', position: const Vec3(5, 0, 0));

      engine.editor.enterPlayMode();

      // Mutate crate and destroy TempEnemy during Play mode
      crate.transform.localPosition = const Vec3(99, 50, 12);
      crate.getComponent<_HealthBehaviour>()!.hp = 10;
      enemy.destroy();
      engine.step(0.016);
      expect(engine.scene.find('TempEnemy'), isNull);

      // Stop Play mode -> scene restores to pre-Play snapshot
      engine.editor.stopPlayMode();
      expect(engine.editor.isPlaying, isFalse);
      expect(engine.time.timeScale, 0.0);

      final restoredCrate = engine.scene.find('Crate');
      expect(restoredCrate, isNotNull);
      expect(restoredCrate!.transform.localPosition, const Vec3(2, 0, -4));
      expect(restoredCrate.getComponent<_HealthBehaviour>()!.hp, 100);
      expect(engine.scene.find('TempEnemy'), isNotNull);
    });

    test('setFreeLook overrides scene camera with editor OrbitCameraController', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.createGameObject('MainCam', components: [Camera()]);
      engine.step(0.016);
      expect(host.graphics.camera, isNot(same(engine.editor.freeLookCamera)));

      engine.editor.setFreeLook(true);
      engine.step(0.016);
      expect(host.graphics.camera, same(engine.editor.freeLookCamera));

      engine.editor.setFreeLook(false);
      engine.step(0.016);
      expect(host.graphics.camera, isNot(same(engine.editor.freeLookCamera)));
    });

    test('computeAxisDragPosition translates object along +X axis from pointer rays', () {
      const origin = Vec3(0, 0, 0);
      const startRay = Ray(origin: Vec3(0, 0, 10), direction: Vec3(0, 0, -1));
      const dragRay = Ray(origin: Vec3(4.5, 0, 10), direction: Vec3(0, 0, -1));

      final nextPos = EditorSession.computeAxisDragPosition(
        initialWorldPosition: origin,
        axisDir: const Vec3(1, 0, 0),
        startRay: startRay,
        currentRay: dragRay,
      );
      expect(nextPos.x, closeTo(4.5, 1e-5));
      expect(nextPos.y, closeTo(0.0, 1e-5));
      expect(nextPos.z, closeTo(0.0, 1e-5));
    });
  });

  group('E6 — Native GlesDevice & NativeEngineHost (DefaultSceneRendererFactory)', () {
    test('NativeEngineHost boots SceneRenderer on GlesDevice, renders 2D and 3D scenes, resizes, and releases all GPU objects on dispose', () async {
      final commands = <String>[];
      final device = GlesDevice(
        onCommand: (cmd, _) => commands.add(cmd),
      );

      final runner = await NativeEngineHost.boot(
        device: device,
        width: 800,
        height: 600,
        requestedProfile: QualityProfile.clean,
        initialScene: buildDungeon2DScene(),
      );

      expect(device.programCompileCalls, greaterThan(0));
      expect(device.liveObjectCount, greaterThan(0));

      // Render a frame of the 2D Dungeon (Lantern) scene through SceneRenderer
      final stats2d = runner.renderFrame(1 / 60);
      expect(stats2d.drawCalls, greaterThan(0));
      expect(commands, contains('useProgram'));

      // Switch to the 3D Island (Tidewatch) scene and render frames
      runner.engine.loadScene(buildIsland3DScene());
      final stats3d = runner.renderFrame(1 / 60);
      expect(stats3d.drawCalls, greaterThan(0));
      expect(stats3d.trianglesSubmitted, greaterThan(0));

      // Resize native surface and render again
      await runner.resize(1024, 768);
      expect(runner.host.graphics.viewportWidth, 1024);
      expect(runner.host.graphics.viewportHeight, 768);
      final statsResized = runner.renderFrame(1 / 60);
      expect(statsResized.drawCalls, greaterThan(0));

      // Dispose runner and verify 100% of GPU objects are freed
      runner.dispose();
      expect(device.liveObjectCount, 0);
    });
  });

  group('E8 — SceneEvents, Coroutines, PostProcessVolume & Modular UICanvas Controls', () {
    test('SceneEvents dispatches typed events and unsubscribes automatically when owner is disabled/destroyed', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final go = engine.scene.createGameObject('ListenerObj', components: [_HealthBehaviour(hp: 100)]);
      final health = go.getComponent<_HealthBehaviour>()!;

      var hits = 0;
      health.listen<int>((dmg) {
        health.hp -= dmg;
        hits++;
      });

      engine.scene.events.emit<int>(25);
      expect(health.hp, 75);
      expect(hits, 1);

      // Inactive object skips listener
      go.setActive(false);
      engine.scene.events.emit<int>(25);
      expect(health.hp, 75);
      expect(hits, 1);

      // Re-activated object receives listener again
      go.setActive(true);
      engine.scene.events.emit<int>(15);
      expect(health.hp, 60);
      expect(hits, 2);

      // Destroyed object is removed from bus
      go.destroy();
      engine.step(0.016);
      engine.scene.events.emit<int>(10);
      expect(hits, 2);
    });

    test('Behaviour.startCoroutine steps through NextFrame, WaitForSeconds, and WaitUntil', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final go = engine.scene.createGameObject('Runner', components: [_HealthBehaviour(hp: 0)]);
      final beh = go.getComponent<_HealthBehaviour>()!;

      final stages = <String>[];
      var gateOpen = false;

      beh.startCoroutine(() sync* {
        stages.add('start');
        yield const NextFrame();
        stages.add('after_next_frame');
        yield const WaitForSeconds(0.15);
        stages.add('after_wait_seconds');
        yield WaitUntil(() => gateOpen);
        stages.add('after_gate');
      });

      // Immediately ran up to the first yield
      expect(stages, ['start']);

      engine.step(0.05);
      expect(stages, ['start', 'after_next_frame']);

      engine.step(0.08);
      expect(stages, ['start', 'after_next_frame']);

      engine.step(0.08);
      expect(stages, ['start', 'after_next_frame', 'after_wait_seconds']);

      engine.step(0.05);
      expect(stages, ['start', 'after_next_frame', 'after_wait_seconds']);

      gateOpen = true;
      engine.step(0.05);
      expect(stages, ['start', 'after_next_frame', 'after_wait_seconds', 'after_gate']);
    });

    test('PostProcessVolume blends spatial exposure, bloom, and vignette by camera distance', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final camGo = engine.scene.createGameObject(
        'MainCam',
        position: const Vec3(0, 0, 20),
        components: [Camera()],
      );
      engine.scene.createGameObject(
        'BossZoneVolume',
        position: Vec3.zero,
        components: [
          PostProcessVolume(
            isGlobal: false,
            radius: 5.0,
            blendDistance: 5.0,
            exposure: 2.0,
            bloomStrength: 0.8,
            vignette: 0.6,
          ),
        ],
      );

      // Outside radius + blendDistance (dist = 20 > 10): weight = 0
      engine.scene.renderSettings.post = const PostProcessState(exposure: 1.0, bloomStrength: 0.0, vignette: 0.0);
      engine.step(0.016);
      expect(engine.scene.renderSettings.post.exposure, closeTo(1.0, 1e-5));

      // Halfway through feather band (dist = 7.5, radius = 5, blend = 5 -> weight = 0.5)
      camGo.transform.localPosition = const Vec3(0, 0, 7.5);
      engine.scene.renderSettings.post = const PostProcessState(exposure: 1.0, bloomStrength: 0.0, vignette: 0.0);
      engine.step(0.016);
      expect(engine.scene.renderSettings.post.exposure, closeTo(1.5, 1e-5));
      expect(engine.scene.renderSettings.post.bloomStrength, closeTo(0.4, 1e-5));
      expect(engine.scene.renderSettings.post.vignette, closeTo(0.3, 1e-5));

      // Inside core radius (dist = 2 <= 5 -> weight = 1.0)
      camGo.transform.localPosition = const Vec3(0, 0, 2.0);
      engine.scene.renderSettings.post = const PostProcessState(exposure: 1.0, bloomStrength: 0.0, vignette: 0.0);
      engine.step(0.016);
      expect(engine.scene.renderSettings.post.exposure, closeTo(2.0, 1e-5));
      expect(engine.scene.renderSettings.post.bloomStrength, closeTo(0.8, 1e-5));
      expect(engine.scene.renderSettings.post.vignette, closeTo(0.6, 1e-5));
    });

    test('UIStack lays out UIToggle and UISlider and dispatches pointer interactions', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      var toggledValue = false;
      var sliderValue = 0.0;

      final toggle = UIToggle(
        label: 'Mute',
        width: 20,
        height: 20,
        onChanged: (v) => toggledValue = v,
      );
      final slider = UISlider(
        width: 100,
        height: 12,
        min: 0,
        max: 100,
        value: 20,
        onChanged: (v) => sliderValue = v,
      );
      final stack = UIStack(
        anchor: UIAnchor.topLeft,
        x: 10,
        y: 10,
        padding: 4,
        spacing: 6,
        children: [toggle, slider],
      );
      canvas.add(stack);
      engine.scene.createGameObject('HUD', components: [canvas]);

      // Verify vertical layout coordinates
      stack.layout(canvasW: 640, canvasH: 360);
      expect(toggle.x, closeTo(14, 1e-5));
      expect(toggle.y, closeTo(14, 1e-5));
      expect(slider.x, closeTo(14, 1e-5));
      expect(slider.y, closeTo(40, 1e-5));

      // Click toggle at (20, 20)
      host.input
        ..pointerX = 20
        ..pointerY = 20
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(toggle.value, isTrue);
      expect(toggledValue, isTrue);

      // Drag slider to 75% at x = 14 + 75 = 89, y = 45
      host.input
        ..pointerX = 89
        ..pointerY = 45
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(sliderValue, closeTo(75.0, 1e-4));
    });
  });

  group('E9 — InstancedMeshRenderer, Tweening, RigidBody Collision & StateMachine', () {
    test('InstancedMeshRenderer batches multiple instances and supports per-instance raycast picking', () async {
      final device = GlesDevice();
      final runner = await NativeEngineHost.boot(device: device, width: 640, height: 360);
      final scene = runner.scene;
      scene.createGameObject('Cam', position: const Vec3(0, 2, 12), components: [Camera()]);

      final instanced = InstancedMeshRenderer(
        meshData: Primitives.cube(size: 1.0),
        materialDefinition: const MaterialDefinition(key: 'inst_cube'),
        transforms: [
          Transform.at(const Vec3(-3, 0, 0)),
          Transform.at(const Vec3(0, 0, 0)),
          Transform.at(const Vec3(3, 0, 0)),
        ],
      );
      final go = scene.createGameObject('CubeCluster', components: [instanced]);

      final stats = runner.renderFrame(1 / 60);
      expect(stats.instancesSubmitted, greaterThanOrEqualTo(3));

      // Raycast straight at the third instance at (3, 0, 0)
      final ray = const Ray(origin: Vec3(3, 0, 5), direction: Vec3(0, 0, -1));
      final pick = scene.raycastVisuals(ray);
      expect(pick, isNotNull);
      expect(pick!.$1, same(go));
      expect(pick.$2.instanceIndex, 2);

      runner.dispose();
      expect(device.liveObjectCount, 0);
    });

    test('BehaviourTweenExt tweens localPosition and localScale with Curves and pingPong', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final go = engine.scene.createGameObject('Box', components: [_HealthBehaviour()]);
      final beh = go.getComponent<_HealthBehaviour>()!;

      var completed = false;
      beh.tweenPosition(
        const Vec3(10, 4, -2),
        duration: 0.2,
        curve: Curves.easeOutCubic,
        onComplete: () => completed = true,
      );
      beh.tweenScale(2.5, duration: 0.2, curve: Curves.linear);

      engine.step(0.1);
      expect(go.transform.localPosition.x, greaterThan(5.0)); // easeOutCubic > 0.5 at t=0.5
      expect(go.transform.localScale, closeTo(1.75, 1e-4));
      expect(completed, isFalse);

      engine.step(0.1);
      expect(go.transform.localPosition.x, closeTo(10.0, 1e-4));
      expect(go.transform.localPosition.y, closeTo(4.0, 1e-4));
      expect(go.transform.localScale, closeTo(2.5, 1e-4));
      expect(completed, isTrue);
    });

    test('RigidBody integrates gravity, resolves solid sphere-box collision, and fires onCollisionEnter', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      Collision? recordedCollision;
      final ball = engine.scene.createGameObject(
        'Ball',
        position: const Vec3(0, 2.0, 0),
        components: [
          SphereCollider(radius: 0.5, isTrigger: false),
          RigidBody(restitution: 0.8, linearDrag: 0.0),
          _CollisionSpy((c) => recordedCollision = c),
        ],
      );
      engine.scene.createGameObject(
        'Floor',
        position: const Vec3(0, -0.5, 0),
        components: [
          BoxCollider(size: const Vec3(10, 1, 10), isTrigger: false),
          RigidBody(isKinematic: true, restitution: 0.8),
        ],
      );

      for (var i = 0; i < 45; i++) {
        engine.step(1 / 60);
      }

      expect(recordedCollision, isNotNull);
      expect(recordedCollision!.other.gameObject.name, 'Floor');
      expect(recordedCollision!.contactNormal.y, closeTo(1.0, 1e-4));
      // Ball should have bounced upward and stayed above the floor surface (y = 0)
      expect(ball.transform.position.y, greaterThanOrEqualTo(0.45));
    });

    test('StateMachine transitions between states and tracks stateTime', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final log = <String>[];
      final fsm = StateMachine<String>('idle')
        ..defineState(
          'idle',
          onEnter: () => log.add('enter:idle'),
          onExit: () => log.add('exit:idle'),
        )
        ..defineState(
          'alert',
          onEnter: () => log.add('enter:alert'),
          onUpdate: (dt) => log.add('update:alert:${dt.toStringAsFixed(2)}'),
        );

      engine.scene.createGameObject('Guard', components: [fsm]);
      engine.step(0.05);
      expect(fsm.currentState, 'idle');
      expect(fsm.stateTime, closeTo(0.05, 1e-5));
      expect(log, ['enter:idle']);

      fsm.transitionTo('alert');
      expect(fsm.previousState, 'idle');
      expect(fsm.currentState, 'alert');
      expect(fsm.stateTime, 0.0);

      engine.step(0.05);
      expect(fsm.stateTime, closeTo(0.05, 1e-5));
      expect(log, ['enter:idle', 'exit:idle', 'enter:alert', 'update:alert:0.05']);
    });
  });

  group('E10 — Spatial 3D Audio, CharacterController 3D & Line/Trail Renderers', () {
    test('AudioListener, AudioMixer, and spatial AudioSource attenuate volume and pan', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scene.createGameObject(
        'Listener',
        position: Vec3.zero,
        components: [AudioListener(volume: 1.0)],
      );
      final src = AudioSource(
        clip: host.audio.clip('beacon.wav'),
        volume: 1.0,
        bus: 'sfx',
        spatialBlend: 1.0,
        minDistance: 2.0,
        maxDistance: 12.0,
        loop: true,
        playOnAwake: true,
      );
      final beacon = engine.scene.createGameObject(
        'Beacon',
        position: const Vec3(7.0, 0, 0), // halfway between min=2 and max=12 -> t=0.5 -> atten=0.25, right=+1
        components: [src],
      );

      engine.step(1 / 60);
      final eval = src.evaluateSpatial();
      expect(eval.volume, closeTo(0.25, 1e-4));
      expect(eval.pan, closeTo(1.0, 1e-4));

      // Mute the 'sfx' bus on Scene.audioMixer
      engine.scene.audioMixer.bus('sfx').muted = true;
      expect(src.evaluateSpatial().volume, 0.0);

      // Unmute and move within minDistance on the left (-X)
      engine.scene.audioMixer.bus('sfx').muted = false;
      beacon.transform.position = const Vec3(-1.0, 0, 0);
      final nearEval = src.evaluateSpatial();
      expect(nearEval.volume, closeTo(1.0, 1e-4));
      expect(nearEval.pan, closeTo(-1.0, 1e-4));
    });

    test('CharacterController slides along solid BoxCollider and grounds on floor', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scene.createGameObject(
        'Floor',
        position: const Vec3(0, -0.5, 0),
        components: [BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false)],
      );
      engine.scene.createGameObject(
        'Wall',
        position: const Vec3(2.0, 1.0, 0),
        components: [BoxCollider(size: const Vec3(1, 3, 6), isTrigger: false)],
      );

      final cc = CharacterController(radius: 0.4, height: 1.8, center: const Vec3(0, 0.9, 0));
      final player = engine.scene.createGameObject(
        'Player',
        position: const Vec3(0, 0.2, 0),
        components: [cc],
      );

      // Step downward + forward into the floor and toward the wall at x=1.5
      final flags = cc.move(const Vec3(3.0, -0.5, 1.5));
      expect(cc.isGrounded, isTrue);
      expect(flags & CollisionFlags.below, isNonZero);
      expect(flags & CollisionFlags.sides, isNonZero);
      // Stopped outside the wall's -X face (wall min.x = 1.5, minus radius ~0.42)
      expect(player.transform.position.x, lessThanOrEqualTo(1.12));
      // Still slid along Z!
      expect(player.transform.position.z, closeTo(1.5, 1e-3));
    });

    test('LineRenderer and TrailRenderer build ribbon MeshData as GameObjects move', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final line = LineRenderer(
        positions: const [Vec3(0, 0, 0), Vec3(0, 2, -4), Vec3(2, 3, -8)],
        startWidth: 0.4,
        endWidth: 0.1,
      );
      engine.scene.createGameObject('Beam', components: [line]);

      final trail = TrailRenderer(
        timeLength: 1.0,
        minVertexDistance: 0.2,
        startWidth: 0.3,
        endWidth: 0.05,
      );
      final missile = engine.scene.createGameObject('Missile', components: [trail]);

      engine.step(0.05);
      expect(line.meshData, isNotNull);
      expect(line.meshData!.vertexCount, 6); // 3 points * 2 vertices

      missile.transform.position = const Vec3(0, 0, -1.0);
      engine.step(0.05);
      missile.transform.position = const Vec3(0, 0.5, -2.5);
      engine.step(0.05);

      expect(trail.sampleCount, 3);
      expect(trail.meshData, isNotNull);
      expect(trail.meshData!.vertexCount, 6);
    });
  });

  group('E11 — NavGrid2D & NavAgent, LodGroup & Billboard, UIWorldAnchor, and SceneManager', () {
    test('NavGrid2D A* routes around solid walls without corner-cutting and NavAgent reaches goal', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final grid = NavGrid2D(columns: 6, rows: 6, cellWidth: 1.0, cellHeight: 1.0);
      // Vertical wall at col=2, rows 0..3
      for (var r = 0; r <= 3; r++) {
        grid.setWalkable(2, r, false);
      }

      final path = grid.findPath(const Vec2(0.5, 0.5), const Vec2(4.5, 0.5));
      expect(path, isNotEmpty);
      // Every waypoint must be on a walkable cell (never col==2 && row<=3)
      for (final wp in path) {
        final (c, r) = grid.worldToCell(wp.x, wp.y);
        expect(grid.isWalkable(c, r), isTrue);
      }

      final agent = NavAgent(grid: grid, speed: 10.0, stoppingDistance: 0.15);
      final go = engine.scene.createGameObject(
        'Runner',
        position: const Vec3(0.5, 0.5, 0),
        components: [agent],
      );
      expect(agent.setDestination(const Vec3(4.5, 0.5, 0)), isTrue);

      for (var i = 0; i < 60; i++) {
        engine.step(1 / 30);
      }

      expect(agent.hasPath, isFalse);
      expect((go.transform.position - const Vec3(4.5, 0.5, 0)).length, lessThan(0.25));
    });

    test('LodGroup switches active child by camera distance and Billboard faces camera', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final camGo = engine.scene.createGameObject(
        'Cam',
        position: const Vec3(0, 0, 5),
        components: [Camera()],
      );

      final tree = engine.scene.createGameObject('Tree', position: Vec3.zero);
      final lod0 = engine.scene.createGameObject('LOD0', parent: tree);
      final lod1 = engine.scene.createGameObject('LOD1', parent: tree);
      final lodGroup = LodGroup(
        levels: [
          LodLevel(maxDistance: 10.0, target: lod0),
          LodLevel(maxDistance: 30.0, target: lod1),
        ],
        cullDistance: 50.0,
      );
      tree.addComponent(lodGroup);

      final banner = engine.scene.createGameObject(
        'Banner',
        position: const Vec3(5, 0, 0),
        components: [Billboard(cylindrical: true)],
      );

      // Distance = 5 -> LOD0 active
      engine.step(0.016);
      expect(lodGroup.activeLevelIndex, 0);
      expect(lod0.activeSelf, isTrue);
      expect(lod1.activeSelf, isFalse);
      // Banner at (5,0,0) facing Cam at (0,0,5) -> forward points along (-1, 0, 1).normalized
      expect(banner.transform.forward.x, closeTo(-0.70710678, 1e-3));
      expect(banner.transform.forward.z, closeTo(0.70710678, 1e-3));

      // Move camera to z = 20 -> LOD1 active
      camGo.transform.position = const Vec3(0, 0, 20);
      engine.step(0.016);
      expect(lodGroup.activeLevelIndex, 1);
      expect(lod0.activeSelf, isFalse);
      expect(lod1.activeSelf, isTrue);

      // Move camera to z = 60 -> culled (-1)
      camGo.transform.position = const Vec3(0, 0, 60);
      engine.step(0.016);
      expect(lodGroup.activeLevelIndex, -1);
      expect(lod0.activeSelf, isFalse);
      expect(lod1.activeSelf, isFalse);
    });

    test('Camera.worldToScreenPoint and UIWorldAnchor project 3D target onto UICanvas', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final cam = Camera(fovYRadians: 1.0);
      engine.scene.createGameObject(
        'MainCam',
        position: const Vec3(0, 0, 5),
        components: [cam],
      );
      final unit = engine.scene.createGameObject('Unit', position: Vec3.zero);

      final bar = UIProgressBar(width: 40, height: 6, value: 0.75);
      final anchor = UIWorldAnchor(target: unit, child: bar);
      final canvas = UICanvas(designWidth: 640, designHeight: 360)..add(anchor);
      engine.scene.createGameObject('HUD', components: [canvas]);

      engine.step(0.016);
      expect(anchor.isInFrontOfCamera, isTrue);
      // Unit at origin dead-center in front of camera -> bar centered at (320 - 20, 180 - 3)
      expect(bar.x, closeTo(300.0, 1.0));
      expect(bar.y, closeTo(177.0, 1.0));

      // Move unit behind camera (z = 10 > cam.z = 5)
      unit.transform.position = const Vec3(0, 0, 10);
      engine.step(0.016);
      expect(anchor.isInFrontOfCamera, isFalse);
    });

    test('SceneManager loads named scenes and migrates dontDestroyOnLoad objects', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scenes.register('level_1', () {
        final s = Scene('Level1');
        s.createGameObject('Level1Prop');
        return s;
      });
      engine.scenes.register('level_2', () {
        final s = Scene('Level2');
        s.createGameObject('Level2Prop');
        return s;
      });

      engine.scenes.load('level_1');
      final sessionAudio = engine.scene.createGameObject(
        'SessionAudio',
        components: [AudioListener(volume: 0.8)],
      );
      engine.scenes.dontDestroyOnLoad(sessionAudio);

      expect(engine.scene.name, 'Level1');
      expect(engine.scene.find('Level1Prop'), isNotNull);
      expect(engine.scene.find('SessionAudio'), same(sessionAudio));

      // Transition to level_2: SessionAudio survives and re-registers AudioListener!
      engine.scenes.load('level_2');
      expect(engine.scene.name, 'Level2');
      expect(engine.scene.find('Level1Prop'), isNull);
      expect(engine.scene.find('Level2Prop'), isNotNull);
      expect(engine.scene.find('SessionAudio'), same(sessionAudio));
      expect(AudioListener.of(engine.scene)?.volume, closeTo(0.8, 1e-5));
    });
  });

  group('E12 — SmoothFollowCamera, CinematicTourCamera, Spatial Physics Queries, SaveSystem & Editor Duplicate', () {
    test('SmoothFollowCamera tracks target, CinematicTourCamera completes tour, and Camera.shake perturbs view', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final hero = engine.scene.createGameObject('Hero', position: const Vec3(10, 0, -5));
      final follow = SmoothFollowCamera(target: hero, distance: 6.0, height: 2.0);
      final cam = Camera();
      final camGo = engine.scene.createGameObject('FollowCam', components: [cam, follow]);

      engine.step(0.1);
      expect((camGo.transform.position - hero.transform.position).length, lessThan(12.0));

      // Trigger trauma shake and verify shakeEngine perturbs the view after stepping
      final unshakenEye = cam.toCameraView(16 / 9).eye;
      cam.shake(trauma: 0.8);
      engine.step(0.05);
      final shakenEye = cam.toCameraView(16 / 9).eye;
      expect((shakenEye - unshakenEye).length, greaterThan(1e-4));

      // CinematicTourCamera non-looping tour fires onCompleted
      var tourFinished = false;
      final tour = CinematicTourCamera(
        waypoints: const [
          CameraWaypoint(eye: Vec3(0, 2, 10), target: Vec3.zero),
          CameraWaypoint(eye: Vec3(5, 4, 5), target: Vec3.zero),
        ],
        duration: 0.2,
        loop: false,
        onCompleted: () => tourFinished = true,
      );
      engine.scene.createGameObject('TourCam', components: [Camera(), tour]);
      engine.step(0.1);
      expect(tour.progress, closeTo(0.5, 1e-2));
      expect(tourFinished, isFalse);

      engine.step(0.15);
      expect(tour.progress, closeTo(1.0, 1e-4));
      expect(tourFinished, isTrue);
    });

    test('PhysicsWorld overlapBox, raycastAll, and sphereCast query colliders accurately', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scene.createGameObject(
        'CrateA',
        position: const Vec3(0, 0, -4),
        components: [BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false)],
      );
      engine.scene.createGameObject(
        'CrateB',
        position: const Vec3(0, 0, -9),
        components: [SphereCollider(radius: 0.8, isTrigger: true)],
      );
      engine.scene.createGameObject(
        'OffsetTarget',
        position: const Vec3(1.2, 0, -6),
        components: [SphereCollider(radius: 0.5, isTrigger: false)],
      );

      final boxHits = engine.physics
          .overlapBox(Aabb(const Vec3(-2, -2, -5), const Vec3(2, 2, -3)))
          .map((c) => c.gameObject.name)
          .toList();
      expect(boxHits, ['CrateA']);

      final ray = Ray(origin: const Vec3(0, 0, 0), direction: const Vec3(0, 0, -1));
      final allHits = engine.physics.raycastAll(ray);
      expect(allHits.map((h) => h.gameObject.name).toList(), ['CrateA', 'CrateB']);
      expect(allHits[0].distance, lessThan(allHits[1].distance));

      // Excluding triggers omits CrateB
      final solidHits = engine.physics.raycastAll(ray, includeTriggers: false);
      expect(solidHits.map((h) => h.gameObject.name).toList(), ['CrateA']);

      // Thin ray along X=0 misses OffsetTarget at X=1.2 (radius 0.5 -> min X=0.7),
      // but sphereCast with radius 0.8 hits it!
      final sweepHit = engine.physics.sphereCast(
        Ray(origin: const Vec3(0, 0, -6), direction: const Vec3(1, 0, 0)),
        0.8,
      );
      expect(sweepHit, isNotNull);
      expect(sweepHit!.gameObject.name, 'OffsetTarget');
    });

    test('SaveSystem persists named data slots and full checkpoints, and EditorSession.duplicate clones subtrees', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final beacon = engine.scene.createGameObject(
        'Beacon',
        position: const Vec3(3, 4, 5),
        tag: 'Landmark',
        components: [
          Light.point(color: const LinearColor(0.2, 0.8, 1.0), intensity: 3.5),
        ],
      );
      engine.scene.createGameObject('ChildOrb', parent: beacon, position: const Vec3(0, 1, 0));

      // Duplicate Beacon via EditorSession.duplicate
      final copy = engine.editor.duplicate(beacon);
      expect(copy, isNotNull);
      expect(copy!.name, 'Beacon_Copy');
      expect(copy.tag, 'Landmark');
      expect(copy.transform.localPosition.x, closeTo(3.0, 1e-4));
      expect(copy.getComponent<Light>()?.intensity, closeTo(3.5, 1e-4));
      expect(copy.find('ChildOrb'), isNotNull);

      // Save data + checkpoint into slot 'slot_1'
      engine.saves.saveData('slot_1', {'coins': 42, 'chapter': 'harbour'}, summary: 'Harbour Dock');
      engine.saves.saveCheckpoint('slot_1', summary: 'Harbour Dock');

      final slots = engine.saves.listSlots();
      expect(slots.length, 1);
      expect(slots.first.slot, 'slot_1');
      expect(slots.first.hasCheckpoint, isTrue);
      expect(engine.saves.loadData('slot_1')?['coins'], 42);

      // Mutate scene, then restore checkpoint
      beacon.destroy();
      copy.destroy();
      engine.step(0.016);
      expect(engine.scene.find('Beacon'), isNull);

      expect(engine.saves.loadCheckpoint('slot_1'), isTrue);
      expect(engine.scene.find('Beacon'), isNotNull);
      expect(engine.scene.find('Beacon_Copy'), isNotNull);

      engine.saves.deleteSlot('slot_1');
      expect(engine.saves.listSlots(), isEmpty);
    });
  });

  group('E13 — CapsuleCollider, Volumetric/Thermal Sources, Editor Undo/Redo & UITextField', () {
    test('CapsuleCollider intersects spheres/boxes/rays and round-trips via SceneSerializer', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final pillar = engine.scene.createGameObject(
        'Pillar',
        position: const Vec3(0, 1.0, -5.0),
        components: [CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: false)],
      );

      // Ray aimed at top hemisphere (y = 1.5) hits Pillar
      final hit = engine.physics.raycast(
        const Ray(origin: Vec3(0, 1.5, 0), direction: Vec3(0, 0, -1)),
      );
      expect(hit, isNotNull);
      expect(hit!.gameObject, same(pillar));

      // Overlap sphere near bottom hemisphere (y = 0.5) hits Pillar
      final overlaps = engine.physics.overlapSphere(const Vec3(0.4, 0.5, -5.0), 0.3).toList();
      expect(overlaps.length, 1);
      expect(overlaps.first.gameObject, same(pillar));

      // Serialization round-trip preserves CapsuleCollider radius and height
      final json = SceneSerializer.toJson(engine.scene, registry: engine.registry);
      final restored = SceneSerializer.fromJson(json, registry: engine.registry);
      final restoredCap = restored.find('Pillar')?.getComponent<CapsuleCollider>();
      expect(restoredCap, isNotNull);
      expect(restoredCap!.radius, closeTo(0.5, 1e-5));
      expect(restoredCap.height, closeTo(2.0, 1e-5));
    });

    test('VolumetricLightSource and ThermalSourceComponent populate FrameEnvironment and sampleThermalDissolution', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scene.createGameObject(
        'Cam',
        position: const Vec3(0, 2, 6),
        components: [Camera()],
      );
      engine.scene.createGameObject(
        'Brazier',
        position: const Vec3(2, 0, 0),
        components: [
          VolumetricLightSource(
            color: const LinearColor(1.0, 0.6, 0.2),
            luminousIntensity: 4.0,
          ),
          ThermalSourceComponent(radiusMeters: 3.0, dissolution01: 1.0),
        ],
      );

      engine.step(0.016);
      expect(host.graphics.environment.volumetricSources.length, 1);
      expect(host.graphics.environment.thermalSources.length, 1);

      // Inside radius (distance = 1 <= 3.0) -> dissolution == 1.0
      expect(engine.scene.sampleThermalDissolution(const Vec3(3, 0, 0)), closeTo(1.0, 1e-4));
      // At distance = 6.0 (2x radius) -> dissolution == 0.5
      expect(engine.scene.sampleThermalDissolution(const Vec3(8, 0, 0)), closeTo(0.5, 1e-4));
    });

    test('EditorSession recordUndoState, undo, and redo restore scene hierarchy and properties', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final crate = engine.scene.createGameObject('Crate', position: const Vec3(1, 2, 3));
      engine.editor.selected = crate;

      engine.editor.recordUndoState('move crate');
      crate.transform.localPosition = const Vec3(10, 20, 30);

      engine.editor.recordUndoState('create barrel');
      engine.scene.createGameObject('Barrel', position: const Vec3(-4, 0, 0));

      expect(engine.editor.canUndo, isTrue);
      expect(engine.editor.undoCount, 2);

      // First undo removes Barrel
      expect(engine.editor.undo(), isTrue);
      expect(engine.scene.find('Barrel'), isNull);
      expect(engine.scene.find('Crate')?.transform.localPosition.x, closeTo(10.0, 1e-4));

      // Second undo restores Crate position to (1, 2, 3)
      expect(engine.editor.undo(), isTrue);
      expect(engine.scene.find('Crate')?.transform.localPosition.x, closeTo(1.0, 1e-4));

      // Redo brings Crate back to (10, 20, 30)
      expect(engine.editor.canRedo, isTrue);
      expect(engine.editor.redo(), isTrue);
      expect(engine.scene.find('Crate')?.transform.localPosition.x, closeTo(10.0, 1e-4));
    });

    test('UITextField focuses on click, edits text on key presses, and fires onSubmitted on Enter', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      String? submittedText;
      final field = UITextField(
        anchor: UIAnchor.topLeft,
        x: 20,
        y: 20,
        width: 140,
        height: 24,
        onSubmitted: (t) => submittedText = t,
      );
      final canvas = UICanvas(designWidth: 640, designHeight: 360)..add(field);
      engine.scene.createGameObject('UI', components: [canvas]);

      // Click inside UITextField to focus
      host.input
        ..pointerX = 40
        ..pointerY = 30
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      host.input.endFrame();
      expect(field.isFocused, isTrue);

      // Type 'H', 'i', '!', Backspace, 'Enter'
      host.input
        ..press('ShiftLeft')
        ..press('KeyH');
      engine.step(0.016);
      host.input
        ..release('ShiftLeft')
        ..release('KeyH')
        ..endFrame();

      host.input
        ..press('KeyI')
        ..press('Digit1');
      engine.step(0.016);
      host.input
        ..release('KeyI')
        ..release('Digit1')
        ..endFrame();
      expect(field.text, 'Hi1');

      host.input
        ..press('Backspace')
        ..press('Enter');
      engine.step(0.016);
      host.input
        ..release('Backspace')
        ..release('Enter')
        ..endFrame();

      expect(field.text, 'Hi');
      expect(submittedText, 'Hi');
    });
  });

  group('E14 — Model Prefabs & Capsule Contact Manifolds', () {
    test('Prefab.fromGlbResult builds GameObject hierarchy with MeshRenderers and shared GPU handles', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final cube = Primitives.cube();
      final root = SceneNode.group(name: 'Ship');
      final hull = SceneNode(
        name: 'Hull',
        meshData: cube,
        transform: const Transform(translation: Vec3(0, 1, 0)),
      );
      final fin = SceneNode(name: 'Fin', meshData: cube);
      root.addChild(hull);
      hull.addChild(fin);
      final glb = GlbResult(
        rootNode: root,
        meshes: [cube],
        materials: [MaterialDefinition(key: 'paint')],
        nodeMaterials: {hull: 0, fin: 0},
      );

      final meshesBefore = host.graphics.liveMeshes.length;
      final prefab = Prefab.fromGlbResult('Ship', glb, engine);
      // Shared MeshData is uploaded exactly once.
      expect(host.graphics.liveMeshes.length - meshesBefore, 1);

      final a = engine.scene.instantiate(prefab, position: const Vec3(5, 0, 0));
      final b = engine.scene.instantiate(prefab, position: const Vec3(-5, 0, 0));
      for (final ship in [a, b]) {
        final hullGo = ship.children.single;
        expect(hullGo.name, 'Hull');
        expect(hullGo.transform.localPosition.y, closeTo(1.0, 1e-6));
        expect(hullGo.getComponent<MeshRenderer>()?.mesh, isNotNull);
        expect(hullGo.children.single.getComponent<MeshRenderer>(), isNotNull);
      }
      expect(a.transform.position.x, closeTo(5, 1e-6));
      expect(
        a.children.single.getComponent<MeshRenderer>()!.mesh,
        same(b.children.single.getComponent<MeshRenderer>()!.mesh),
      );
      expect(host.graphics.liveMeshes.length - meshesBefore, 1);
    });

    test('Capsule RigidBody rests on a box floor and bounces off spheres with axis-accurate normals', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      engine.scene.createGameObject(
        'Floor',
        position: const Vec3(0, -0.5, 0),
        components: [BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false)],
      );
      final capsule = engine.scene.createGameObject(
        'Capsule',
        position: const Vec3(0, 3, 0),
        components: [
          CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: false),
          RigidBody(restitution: 0.0, linearDrag: 0.0),
        ],
      );

      for (var i = 0; i < 240; i++) {
        engine.step(1 / 60);
      }
      // Capsule half-height is 1.0, so its centre settles near y == 1.
      expect(capsule.transform.position.y, closeTo(1.0, 0.15));
      expect(capsule.getComponent<RigidBody>()!.velocity.y.abs(), lessThan(1.0));

      // A sphere touching the capsule's side gets a horizontal normal, not a
      // vertical AABB face normal.
      final probe = engine.scene.createGameObject(
        'Probe',
        position: Vec3(0.8, capsule.transform.position.y + 0.6, 0),
        components: [SphereCollider(radius: 0.4, isTrigger: false)],
      );
      final manifold = PhysicsWorld.debugManifold(
        capsule.getComponent<CapsuleCollider>()!,
        probe.getComponent<SphereCollider>()!,
      );
      expect(manifold, isNotNull);
      expect(manifold!.$1.x, greaterThan(0.99));
      expect(manifold.$2, greaterThan(0));
    });
  });
}

final class _CollisionSpy extends Behaviour {
  final void Function(Collision) onHit;
  _CollisionSpy(this.onHit);

  @override
  void onCollisionEnter(Collision collision) => onHit(collision);
}
