import 'dart:math' as math;
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

  static final spec =
      ComponentSpec<_HealthBehaviour>('HealthBehaviour', _HealthBehaviour.new, [
        Field.integer('hp', (b) => b.hp, (b, v) => b.hp = v),
        Field.text('faction', (b) => b.faction, (b, v) => b.faction = v),
        Field.number('speed', (b) => b.speed, (b, v) => b.speed = v),
      ]);
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
    test(
      'DebugController pauses, steps single fixed frames, scales time, and reports metrics',
      () {
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
      },
    );

    test(
      'captureSessionSnapshot and restoreSessionSnapshot preserve state across reload',
      () {
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
      },
    );
  });

  group('E3 — Serialization, Prefabs, ObjectPool & AssetCatalog', () {
    test(
      'SceneSerializer round-trips hierarchy, lights, cameras, colliders, and prefab overrides',
      () {
        final reg = ComponentRegistry.defaults()
          ..register(_HealthBehaviour.spec);
        final enemyPrefab = Prefab(
          'Enemy',
          (go) => go.addComponent(
            _HealthBehaviour(hp: 50, faction: 'raiders', speed: 4.0),
          ),
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
            {'type': 'HealthBehaviour', 'hp': 250},
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
        expect(
          s2.find('MainCamera')?.getComponent<Camera>()?.orthographic,
          isTrue,
        );
        expect(s2.find('MainCamera')?.getComponent<Camera>()?.orthoHeight, 16);
        expect(s2.find('Sun')?.parent?.name, 'MainCamera');
        expect(s2.find('Sun')?.getComponent<Light>()?.intensity, 1.8);
        expect(
          s2.find('TriggerZone')?.getComponent<SphereCollider>()?.radius,
          3.5,
        );

        final boss = s2.find('BossEnemy');
        expect(boss, isNotNull);
        expect(boss!.transform.localPosition, const Vec3(10, 0, -5));
        final bossHealth = boss.getComponent<_HealthBehaviour>()!;
        expect(bossHealth.hp, 250);
        expect(bossHealth.faction, 'raiders'); // preserved from prefab default

        // Also verify string round-trip
        final s3 = SceneSerializer.fromJsonString(jsonStr, registry: reg);
        expect(s3.find('MainCamera'), isNotNull);
      },
    );

    test(
      'ObjectPool warms up, acquires, reuses without new allocations, and fires Poolable callbacks',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final prefab = Prefab(
          'Bullet',
          (go) => go.addComponent(_PoolTracker()),
        );
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
      },
    );

    test(
      'AssetCatalog preloads procedural textures/audio and releases GPU handles on clear()',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        final progressLog = <(int, int)>[];

        await engine.catalog.load({
          'beep': const AudioEntry('sfx/beep.wav', volume: 0.7),
          'checker': ProceduralTextureEntry(
            width: 4,
            height: 4,
            generatePixels: () => Uint8List(4 * 4 * 4),
          ),
        }, onProgress: (loaded, total) => progressLog.add((loaded, total)));

        expect(progressLog.first, (0, 2));
        expect(progressLog.last, (2, 2));

        engine.catalog.registerMesh('cube', Primitives.cube());
        engine.catalog.registerMaterial(
          'mat',
          const MaterialDefinition(key: 'mat'),
        );

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
      },
    );
  });

  group('E4 — 2D Sprites, Tilemap Collision, Ortho Camera & Canvas UI', () {
    test(
      'Camera.ortho and screenToGroundPlane project rays onto y == groundHeight',
      () {
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
      },
    );

    test(
      'SpriteAnimator steps through clips and updates sibling SpriteRenderer',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.createGameObject(
          'Cam2D',
          components: [Camera2DComponent()],
        );

        final f0 = SpriteRegion(
          texture: null,
          width: 16,
          height: 16,
          u0: 0,
          v0: 0,
          u1: 0.5,
          v1: 1,
        );
        final f1 = SpriteRegion(
          texture: null,
          width: 16,
          height: 16,
          u0: 0.5,
          v0: 0,
          u1: 1.0,
          v1: 1,
        );

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
      },
    );

    test(
      'TilemapComponent.moveAndSlideCircle slides along solid tiles without penetrating',
      () {
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
        final next = tm.moveAndSlideCircle(
          const Vec2(42, 32),
          const Vec2(10, 12),
          4,
        );
        // X must be clamped to left edge of wall minus radius (48 - 4 = 44), while Y slides freely to 44
        expect(next.x, closeTo(44.0, 1e-4));
        expect(next.y, closeTo(44.0, 1e-4));
      },
    );

    test(
      'UICanvas dispatches UIButton click from ScriptedInput pointer events',
      () {
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
      },
    );
  });

  group('E5 — 3D Animator, Splines, Terrain/Water/Buoyancy & AtmosphereVolume', () {
    test(
      'Animator plays keyframe AnimationClip and respects time.timeScale',
      () {
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
      },
    );

    test(
      'SplinePath and SplineFollower move along arc length and align rotation',
      () {
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
        final cart = engine.scene.createGameObject(
          'Cart',
          components: [path, follower],
        );

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
      },
    );

    test(
      'TerrainComponent, WaterSurfaceComponent, and BuoyantBody update height and vessel pose',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final terrain = TerrainComponent(
          TerrainGenerator(
            subdivisionsX: 16,
            subdivisionsZ: 16,
            width: 40,
            depth: 40,
            maxHeight: 8,
            seed: 7,
          ),
          biomeTextureSize: 32,
        );
        engine.scene.createGameObject('Island', components: [terrain]);
        expect(terrain.sampleHeight(0, 0).isFinite, isTrue);

        final water = WaterSurfaceComponent(
          surface: WaterSurfaceMesh(
            subdivisionsX: 8,
            subdivisionsZ: 8,
            width: 30,
            depth: 30,
          ),
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
      },
    );

    test(
      'AtmosphereVolume advances solar cycle and updates scene RenderSettings & sun Light',
      () {
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
      },
    );

    test(
      'Dungeon2D (Lantern), Procession, and Island3D (Tidewatch) full gameplay loops',
      () {
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
        final initialSwarmDist =
            (swarm.transform.localPosition - leader.transform.localPosition)
                .length;
        engine.step(0.05);
        final afterSwarmDist =
            (swarm.transform.localPosition - leader.transform.localPosition)
                .length;
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
        final lighthouse = engine.scene
            .findObjectOfType<LighthouseBehaviour>()!;
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
        final unguidedLighthouse = engine.scene
            .findObjectOfType<LighthouseBehaviour>()!;
        unguidedLighthouse.aimPoint = const Vec3(-100, 0, -100);
        final unguidedShip = engine.scene
            .findObjectOfType<ShipAgentBehaviour>()!;
        for (var i = 0; i < 30; i++) {
          engine.step(0.1);
        }
        expect(unguidedShip.wreckedOnReef, isTrue);
      },
    );
  });

  group(
    'E7 — EditorSession (Play/Stop Snapshot, Free-Look Camera & 3D Gizmo Drag)',
    () {
      test(
        'enterPlayMode and stopPlayMode discard runtime mutations and destroyed objects',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          engine.registry.register(_HealthBehaviour.spec);

          final crate = engine.scene.createGameObject(
            'Crate',
            position: const Vec3(2, 0, -4),
            components: [_HealthBehaviour(hp: 100)],
          );
          final enemy = engine.scene.createGameObject(
            'TempEnemy',
            position: const Vec3(5, 0, 0),
          );

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
        },
      );

      test(
        'setFreeLook overrides scene camera with editor OrbitCameraController',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          engine.scene.createGameObject('MainCam', components: [Camera()]);
          engine.step(0.016);
          expect(
            host.graphics.camera,
            isNot(same(engine.editor.freeLookCamera)),
          );

          engine.editor.setFreeLook(true);
          engine.step(0.016);
          expect(host.graphics.camera, same(engine.editor.freeLookCamera));

          engine.editor.setFreeLook(false);
          engine.step(0.016);
          expect(
            host.graphics.camera,
            isNot(same(engine.editor.freeLookCamera)),
          );
        },
      );

      test(
        'computeAxisDragPosition translates object along +X axis from pointer rays',
        () {
          const origin = Vec3(0, 0, 0);
          const startRay = Ray(
            origin: Vec3(0, 0, 10),
            direction: Vec3(0, 0, -1),
          );
          const dragRay = Ray(
            origin: Vec3(4.5, 0, 10),
            direction: Vec3(0, 0, -1),
          );

          final nextPos = EditorSession.computeAxisDragPosition(
            initialWorldPosition: origin,
            axisDir: const Vec3(1, 0, 0),
            startRay: startRay,
            currentRay: dragRay,
          );
          expect(nextPos.x, closeTo(4.5, 1e-5));
          expect(nextPos.y, closeTo(0.0, 1e-5));
          expect(nextPos.z, closeTo(0.0, 1e-5));
        },
      );
    },
  );

  group(
    'E6 — Native GlesDevice & NativeEngineHost (DefaultSceneRendererFactory)',
    () {
      test(
        'NativeEngineHost boots SceneRenderer on GlesDevice, renders 2D and 3D scenes, resizes, and releases all GPU objects on dispose',
        () async {
          final commands = <String>[];
          final device = GlesDevice(onCommand: (cmd, _) => commands.add(cmd));

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
        },
      );
    },
  );

  group(
    'E8 — SceneEvents, Coroutines, PostProcessVolume & Modular UICanvas Controls',
    () {
      test(
        'SceneEvents dispatches typed events and unsubscribes automatically when owner is disabled/destroyed',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          final go = engine.scene.createGameObject(
            'ListenerObj',
            components: [_HealthBehaviour(hp: 100)],
          );
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
        },
      );

      test(
        'Behaviour.startCoroutine steps through NextFrame, WaitForSeconds, and WaitUntil',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          final go = engine.scene.createGameObject(
            'Runner',
            components: [_HealthBehaviour(hp: 0)],
          );
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
          expect(stages, [
            'start',
            'after_next_frame',
            'after_wait_seconds',
            'after_gate',
          ]);
        },
      );

      test(
        'PostProcessVolume blends spatial exposure, bloom, and vignette by camera distance',
        () {
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
          engine.scene.renderSettings.post = const PostProcessState(
            exposure: 1.0,
            bloomStrength: 0.0,
            vignette: 0.0,
          );
          engine.step(0.016);
          expect(engine.scene.renderSettings.post.exposure, closeTo(1.0, 1e-5));

          // Halfway through feather band (dist = 7.5, radius = 5, blend = 5 -> weight = 0.5)
          camGo.transform.localPosition = const Vec3(0, 0, 7.5);
          engine.scene.renderSettings.post = const PostProcessState(
            exposure: 1.0,
            bloomStrength: 0.0,
            vignette: 0.0,
          );
          engine.step(0.016);
          expect(engine.scene.renderSettings.post.exposure, closeTo(1.5, 1e-5));
          expect(
            engine.scene.renderSettings.post.bloomStrength,
            closeTo(0.4, 1e-5),
          );
          expect(engine.scene.renderSettings.post.vignette, closeTo(0.3, 1e-5));

          // Inside core radius (dist = 2 <= 5 -> weight = 1.0)
          camGo.transform.localPosition = const Vec3(0, 0, 2.0);
          engine.scene.renderSettings.post = const PostProcessState(
            exposure: 1.0,
            bloomStrength: 0.0,
            vignette: 0.0,
          );
          engine.step(0.016);
          expect(engine.scene.renderSettings.post.exposure, closeTo(2.0, 1e-5));
          expect(
            engine.scene.renderSettings.post.bloomStrength,
            closeTo(0.8, 1e-5),
          );
          expect(engine.scene.renderSettings.post.vignette, closeTo(0.6, 1e-5));
        },
      );

      test(
        'UIStack lays out UIToggle and UISlider and dispatches pointer interactions',
        () {
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
        },
      );
    },
  );

  group('E9 — InstancedMeshRenderer, Tweening, RigidBody Collision & StateMachine', () {
    test(
      'InstancedMeshRenderer batches multiple instances and supports per-instance raycast picking',
      () async {
        final device = GlesDevice();
        final runner = await NativeEngineHost.boot(
          device: device,
          width: 640,
          height: 360,
        );
        final scene = runner.scene;
        scene.createGameObject(
          'Cam',
          position: const Vec3(0, 2, 12),
          components: [Camera()],
        );

        final instanced = InstancedMeshRenderer(
          meshData: Primitives.cube(size: 1.0),
          materialDefinition: const MaterialDefinition(key: 'inst_cube'),
          transforms: [
            Transform.at(const Vec3(-3, 0, 0)),
            Transform.at(const Vec3(0, 0, 0)),
            Transform.at(const Vec3(3, 0, 0)),
          ],
        );
        final go = scene.createGameObject(
          'CubeCluster',
          components: [instanced],
        );

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
      },
    );

    test(
      'BehaviourTweenExt tweens localPosition and localScale with Curves and pingPong',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final go = engine.scene.createGameObject(
          'Box',
          components: [_HealthBehaviour()],
        );
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
        expect(
          go.transform.localPosition.x,
          greaterThan(5.0),
        ); // easeOutCubic > 0.5 at t=0.5
        expect(go.transform.localScale, closeTo(1.75, 1e-4));
        expect(completed, isFalse);

        engine.step(0.1);
        expect(go.transform.localPosition.x, closeTo(10.0, 1e-4));
        expect(go.transform.localPosition.y, closeTo(4.0, 1e-4));
        expect(go.transform.localScale, closeTo(2.5, 1e-4));
        expect(completed, isTrue);
      },
    );

    test(
      'RigidBody integrates gravity, resolves solid sphere-box collision, and fires onCollisionEnter',
      () {
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
      },
    );

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
      expect(log, [
        'enter:idle',
        'exit:idle',
        'enter:alert',
        'update:alert:0.05',
      ]);
    });
  });

  group('E10 — Spatial 3D Audio, CharacterController 3D & Line/Trail Renderers', () {
    test(
      'AudioListener, AudioMixer, and spatial AudioSource attenuate volume and pan',
      () {
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
          position: const Vec3(
            7.0,
            0,
            0,
          ), // halfway between min=2 and max=12 -> t=0.5 -> atten=0.25, right=+1
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
      },
    );

    test(
      'CharacterController slides along solid BoxCollider and grounds on floor',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false),
          ],
        );
        engine.scene.createGameObject(
          'Wall',
          position: const Vec3(2.0, 1.0, 0),
          components: [
            BoxCollider(size: const Vec3(1, 3, 6), isTrigger: false),
          ],
        );

        final cc = CharacterController(
          radius: 0.4,
          height: 1.8,
          center: const Vec3(0, 0.9, 0),
        );
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
      },
    );

    test(
      'LineRenderer and TrailRenderer build ribbon MeshData as GameObjects move',
      () {
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
        final missile = engine.scene.createGameObject(
          'Missile',
          components: [trail],
        );

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
      },
    );
  });

  group(
    'E11 — NavGrid2D & NavAgent, LodGroup & Billboard, UIWorldAnchor, and SceneManager',
    () {
      test(
        'NavGrid2D A* routes around solid walls without corner-cutting and NavAgent reaches goal',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final grid = NavGrid2D(
            columns: 6,
            rows: 6,
            cellWidth: 1.0,
            cellHeight: 1.0,
          );
          // Vertical wall at col=2, rows 0..3
          for (var r = 0; r <= 3; r++) {
            grid.setWalkable(2, r, false);
          }

          final path = grid.findPath(
            const Vec2(0.5, 0.5),
            const Vec2(4.5, 0.5),
          );
          expect(path, isNotEmpty);
          // Every waypoint must be on a walkable cell (never col==2 && row<=3)
          for (final wp in path) {
            final (c, r) = grid.worldToCell(wp.x, wp.y);
            expect(grid.isWalkable(c, r), isTrue);
          }

          final agent = NavAgent(
            grid: grid,
            speed: 10.0,
            stoppingDistance: 0.15,
          );
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
          expect(
            (go.transform.position - const Vec3(4.5, 0.5, 0)).length,
            lessThan(0.25),
          );
        },
      );

      test(
        'LodGroup switches active child by camera distance and Billboard faces camera',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final camGo = engine.scene.createGameObject(
            'Cam',
            position: const Vec3(0, 0, 5),
            components: [Camera()],
          );

          final tree = engine.scene.createGameObject(
            'Tree',
            position: Vec3.zero,
          );
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
        },
      );

      test(
        'Camera.worldToScreenPoint and UIWorldAnchor project 3D target onto UICanvas',
        () {
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
          final unit = engine.scene.createGameObject(
            'Unit',
            position: Vec3.zero,
          );

          final bar = UIProgressBar(width: 40, height: 6, value: 0.75);
          final anchor = UIWorldAnchor(target: unit, child: bar);
          final canvas = UICanvas(designWidth: 640, designHeight: 360)
            ..add(anchor);
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
        },
      );

      test(
        'SceneManager loads named scenes and migrates dontDestroyOnLoad objects',
        () {
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
        },
      );
    },
  );

  group(
    'E12 — SmoothFollowCamera, CinematicTourCamera, Spatial Physics Queries, SaveSystem & Editor Duplicate',
    () {
      test(
        'SmoothFollowCamera tracks target, CinematicTourCamera completes tour, and Camera.shake perturbs view',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final hero = engine.scene.createGameObject(
            'Hero',
            position: const Vec3(10, 0, -5),
          );
          final follow = SmoothFollowCamera(
            target: hero,
            distance: 6.0,
            height: 2.0,
          );
          final cam = Camera();
          final camGo = engine.scene.createGameObject(
            'FollowCam',
            components: [cam, follow],
          );

          engine.step(0.1);
          expect(
            (camGo.transform.position - hero.transform.position).length,
            lessThan(12.0),
          );

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
          engine.scene.createGameObject(
            'TourCam',
            components: [Camera(), tour],
          );
          engine.step(0.1);
          expect(tour.progress, closeTo(0.5, 1e-2));
          expect(tourFinished, isFalse);

          engine.step(0.15);
          expect(tour.progress, closeTo(1.0, 1e-4));
          expect(tourFinished, isTrue);
        },
      );

      test(
        'PhysicsWorld overlapBox, raycastAll, and sphereCast query colliders accurately',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          engine.scene.createGameObject(
            'CrateA',
            position: const Vec3(0, 0, -4),
            components: [
              BoxCollider(size: const Vec3(1, 1, 1), isTrigger: false),
            ],
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

          final ray = Ray(
            origin: const Vec3(0, 0, 0),
            direction: const Vec3(0, 0, -1),
          );
          final allHits = engine.physics.raycastAll(ray);
          expect(allHits.map((h) => h.gameObject.name).toList(), [
            'CrateA',
            'CrateB',
          ]);
          expect(allHits[0].distance, lessThan(allHits[1].distance));

          // Excluding triggers omits CrateB
          final solidHits = engine.physics.raycastAll(
            ray,
            includeTriggers: false,
          );
          expect(solidHits.map((h) => h.gameObject.name).toList(), ['CrateA']);

          // Thin ray along X=0 misses OffsetTarget at X=1.2 (radius 0.5 -> min X=0.7),
          // but sphereCast with radius 0.8 hits it!
          final sweepHit = engine.physics.sphereCast(
            Ray(origin: const Vec3(0, 0, -6), direction: const Vec3(1, 0, 0)),
            0.8,
          );
          expect(sweepHit, isNotNull);
          expect(sweepHit!.gameObject.name, 'OffsetTarget');
        },
      );

      test(
        'SaveSystem persists named data slots and full checkpoints, and EditorSession.duplicate clones subtrees',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final beacon = engine.scene.createGameObject(
            'Beacon',
            position: const Vec3(3, 4, 5),
            tag: 'Landmark',
            components: [
              Light.point(
                color: const LinearColor(0.2, 0.8, 1.0),
                intensity: 3.5,
              ),
            ],
          );
          engine.scene.createGameObject(
            'ChildOrb',
            parent: beacon,
            position: const Vec3(0, 1, 0),
          );

          // Duplicate Beacon via EditorSession.duplicate
          final copy = engine.editor.duplicate(beacon);
          expect(copy, isNotNull);
          expect(copy!.name, 'Beacon_Copy');
          expect(copy.tag, 'Landmark');
          expect(copy.transform.localPosition.x, closeTo(3.0, 1e-4));
          expect(copy.getComponent<Light>()?.intensity, closeTo(3.5, 1e-4));
          expect(copy.find('ChildOrb'), isNotNull);

          // Save data + checkpoint into slot 'slot_1'
          engine.saves.saveData('slot_1', {
            'coins': 42,
            'chapter': 'harbour',
          }, summary: 'Harbour Dock');
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
        },
      );
    },
  );

  group(
    'E13 — CapsuleCollider, Volumetric/Thermal Sources, Editor Undo/Redo & UITextField',
    () {
      test(
        'CapsuleCollider intersects spheres/boxes/rays and round-trips via SceneSerializer',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final pillar = engine.scene.createGameObject(
            'Pillar',
            position: const Vec3(0, 1.0, -5.0),
            components: [
              CapsuleCollider(radius: 0.5, height: 2.0, isTrigger: false),
            ],
          );

          // Ray aimed at top hemisphere (y = 1.5) hits Pillar
          final hit = engine.physics.raycast(
            const Ray(origin: Vec3(0, 1.5, 0), direction: Vec3(0, 0, -1)),
          );
          expect(hit, isNotNull);
          expect(hit!.gameObject, same(pillar));

          // Overlap sphere near bottom hemisphere (y = 0.5) hits Pillar
          final overlaps = engine.physics
              .overlapSphere(const Vec3(0.4, 0.5, -5.0), 0.3)
              .toList();
          expect(overlaps.length, 1);
          expect(overlaps.first.gameObject, same(pillar));

          // Serialization round-trip preserves CapsuleCollider radius and height
          final json = SceneSerializer.toJson(
            engine.scene,
            registry: engine.registry,
          );
          final restored = SceneSerializer.fromJson(
            json,
            registry: engine.registry,
          );
          final restoredCap = restored
              .find('Pillar')
              ?.getComponent<CapsuleCollider>();
          expect(restoredCap, isNotNull);
          expect(restoredCap!.radius, closeTo(0.5, 1e-5));
          expect(restoredCap.height, closeTo(2.0, 1e-5));
        },
      );

      test(
        'VolumetricLightSource and ThermalSourceComponent populate FrameEnvironment and sampleThermalDissolution',
        () {
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
          expect(
            engine.scene.sampleThermalDissolution(const Vec3(3, 0, 0)),
            closeTo(1.0, 1e-4),
          );
          // At distance = 6.0 (2x radius) -> dissolution == 0.5
          expect(
            engine.scene.sampleThermalDissolution(const Vec3(8, 0, 0)),
            closeTo(0.5, 1e-4),
          );
        },
      );

      test(
        'EditorSession recordUndoState, undo, and redo restore scene hierarchy and properties',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final crate = engine.scene.createGameObject(
            'Crate',
            position: const Vec3(1, 2, 3),
          );
          engine.editor.selected = crate;

          engine.editor.recordUndoState('move crate');
          crate.transform.localPosition = const Vec3(10, 20, 30);

          engine.editor.recordUndoState('create barrel');
          engine.scene.createGameObject(
            'Barrel',
            position: const Vec3(-4, 0, 0),
          );

          expect(engine.editor.canUndo, isTrue);
          expect(engine.editor.undoCount, 2);

          // First undo removes Barrel
          expect(engine.editor.undo(), isTrue);
          expect(engine.scene.find('Barrel'), isNull);
          expect(
            engine.scene.find('Crate')?.transform.localPosition.x,
            closeTo(10.0, 1e-4),
          );

          // Second undo restores Crate position to (1, 2, 3)
          expect(engine.editor.undo(), isTrue);
          expect(
            engine.scene.find('Crate')?.transform.localPosition.x,
            closeTo(1.0, 1e-4),
          );

          // Redo brings Crate back to (10, 20, 30)
          expect(engine.editor.canRedo, isTrue);
          expect(engine.editor.redo(), isTrue);
          expect(
            engine.scene.find('Crate')?.transform.localPosition.x,
            closeTo(10.0, 1e-4),
          );
        },
      );

      test(
        'UITextField focuses on click, edits text on key presses, and fires onSubmitted on Enter',
        () {
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
          final canvas = UICanvas(designWidth: 640, designHeight: 360)
            ..add(field);
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
        },
      );
    },
  );

  group('E14 — Model Prefabs & Capsule Contact Manifolds', () {
    test(
      'Prefab.fromGlbResult builds GameObject hierarchy with MeshRenderers and shared GPU handles',
      () {
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

        final a = engine.scene.instantiate(
          prefab,
          position: const Vec3(5, 0, 0),
        );
        final b = engine.scene.instantiate(
          prefab,
          position: const Vec3(-5, 0, 0),
        );
        for (final ship in [a, b]) {
          final hullGo = ship.children.single;
          expect(hullGo.name, 'Hull');
          expect(hullGo.transform.localPosition.y, closeTo(1.0, 1e-6));
          expect(hullGo.getComponent<MeshRenderer>()?.mesh, isNotNull);
          expect(
            hullGo.children.single.getComponent<MeshRenderer>(),
            isNotNull,
          );
        }
        expect(a.transform.position.x, closeTo(5, 1e-6));
        expect(
          a.children.single.getComponent<MeshRenderer>()!.mesh,
          same(b.children.single.getComponent<MeshRenderer>()!.mesh),
        );
        expect(host.graphics.liveMeshes.length - meshesBefore, 1);
      },
    );

    test(
      'Capsule RigidBody rests on a box floor and bounces off spheres with axis-accurate normals',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'Floor',
          position: const Vec3(0, -0.5, 0),
          components: [
            BoxCollider(size: const Vec3(20, 1, 20), isTrigger: false),
          ],
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
        expect(
          capsule.getComponent<RigidBody>()!.velocity.y.abs(),
          lessThan(1.0),
        );

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
      },
    );
  });

  group('E15 — Gizmos & Catalog Prefab Shortcut', () {
    test(
      'Gizmos collect collider wireframes, contacts and selection, project to screen, and clear after encode',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = engine.scene;

        scene.createGameObject(
          'Cam',
          position: const Vec3(0, 2, 10),
          components: [Camera()],
        );
        final box = scene.createGameObject(
          'Box',
          components: [BoxCollider(size: const Vec3(2, 2, 2), isTrigger: true)],
        );
        scene.createGameObject(
          'Ball',
          position: const Vec3(0.8, 0, 0),
          components: [SphereCollider(radius: 0.5, isTrigger: true)],
        );
        scene.createGameObject(
          'Pill',
          position: const Vec3(-4, 0, 0),
          components: [CapsuleCollider(radius: 0.3, height: 1.5)],
        );

        // Disabled by default: nothing is queued.
        scene.gizmos.line(Vec3.zero, const Vec3(1, 0, 0));
        expect(scene.gizmos.lineCount, 0);

        engine.step(0.05);
        expect(scene.physics.contactPairs.length, 1);

        scene.gizmos
          ..enabled = true
          ..showContacts = false
          ..showSelection = false;
        scene.gizmos.collectAuto();
        final boxLines = 12;
        final sphereLines = 3 * scene.gizmos.circleSegments;
        final collidersOnly = scene.gizmos.lineCount;
        expect(collidersOnly, greaterThan(boxLines + sphereLines));

        scene.gizmos
          ..clear()
          ..showContacts = true;
        scene.gizmos.collectAuto();
        expect(
          scene.gizmos.lineCount,
          collidersOnly + 4,
        ); // cross (3) + normal ray (1)
        expect(
          scene.gizmos.lines
              .where((l) => l.color == scene.gizmos.contactColor)
              .length,
          4,
        );

        scene.gizmos
          ..clear()
          ..showColliders = false
          ..showContacts = false
          ..showSelection = true;
        engine.editor.selected = box;
        scene.gizmos.collectAuto();
        // 3 axis rays + the selected box's 12 edges in selection colour.
        expect(scene.gizmos.lineCount, 15);
        expect(
          scene.gizmos.lines
              .where((l) => l.color == scene.gizmos.selectionColor)
              .length,
          12,
        );

        // Projection lands on-screen around the viewport centre.
        final projected = scene.gizmos.project(Camera.of(scene)!);
        expect(projected.length, 15);
        for (final s in projected) {
          expect(s.x0, inInclusiveRange(0, 1280));
          expect(s.y0, inInclusiveRange(0, 720));
        }

        // A segment crossing behind the camera is clipped, not dropped or flipped.
        scene.gizmos
          ..clear()
          ..line(Vec3.zero, const Vec3(0, 2, 20));
        final clipped = scene.gizmos.project(Camera.of(scene)!);
        expect(clipped.length, 1);
      },
    );

    test(
      'AssetCatalog.prefab lazily wraps ModelAssets and spawn instantiates them',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cube = Primitives.cube();
        final root = SceneNode.group(name: 'Crate');
        root.addChild(SceneNode(name: 'Body', meshData: cube));
        final glb = GlbResult(
          rootNode: root,
          meshes: [cube],
          materials: [MaterialDefinition(key: 'wood')],
        );
        final asset = ModelAsset.fromGlb(
          glb,
          _HeadlessResources(host.graphics),
          name: 'crate',
        );
        engine.catalog.putModel('crate', asset);

        expect(engine.catalog.hasPrefab('crate'), isTrue);
        final p1 = engine.catalog.prefab('crate');
        expect(engine.catalog.prefab('crate'), same(p1));

        final go = engine.catalog.spawn('crate', position: const Vec3(3, 0, 0));
        expect(go.name, 'crate');
        expect(go.transform.position.x, closeTo(3, 1e-6));
        expect(
          go.children.single.getComponent<MeshRenderer>()?.mesh,
          isNotNull,
        );
        expect(() => engine.catalog.prefab('missing'), throwsArgumentError);

        engine.catalog.clear();
        expect(engine.catalog.hasPrefab('crate'), isFalse);
      },
    );
  });

  group('E16 — PhysicsRaycaster 3D Interaction, LayerMask & Gizmo Extensions', () {
    test(
      'PhysicsRaycaster dispatches enter, down, up, click, and exit to 3D Behaviour colliders',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0, 0, 5),
          components: [Camera(), PhysicsRaycaster()],
        );

        final spy = _PointerSpy();
        final target = engine.scene.createGameObject(
          'InteractiveChest',
          position: const Vec3(0, 0, 0),
          components: [
            BoxCollider(size: const Vec3(2, 2, 2)),
            spy,
          ],
        );

        // Frame 1: Pointer at (640, 360) aiming straight through center at target.
        host.input.pointerX = 640;
        host.input.pointerY = 360;
        engine.step(0.016);
        expect(spy.events, ['enter']);
        expect(spy.lastHit?.gameObject, same(target));

        // Frame 2: Pointer pressed -> fires onPointerDown.
        host.input.pointerPressed = true;
        host.input.pointerDown = true;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down']);

        // Frame 3: Pointer released over same target -> fires onPointerUp and onPointerClick.
        host.input.pointerPressed = false;
        host.input.pointerReleased = true;
        host.input.pointerDown = false;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down', 'up', 'click']);

        // Frame 4: Pointer moves away to (50, 50) -> fires onPointerExit.
        host.input.pointerReleased = false;
        host.input.pointerX = 50;
        host.input.pointerY = 50;
        engine.step(0.016);
        expect(spy.events, ['enter', 'down', 'up', 'click', 'exit']);
      },
    );

    test('LayerMask calculates bitmasks and filters physics queries', () {
      expect(LayerMask.none.value, 0);
      expect(LayerMask.all.value, -1);
      expect(LayerMask.defaultLayer.value, 1);

      final mask = LayerMask.fromLayers([1, 3, 5]);
      expect(mask.contains(0), isFalse);
      expect(mask.contains(1), isTrue);
      expect(mask.contains(2), isFalse);
      expect(mask.contains(3), isTrue);
      expect(mask.contains(5), isTrue);

      final modified = mask.withLayer(2).withoutLayer(1);
      expect(modified.contains(1), isFalse);
      expect(modified.contains(2), isTrue);

      // Verify layer mask filtering in PhysicsWorld
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.createGameObject(
        'HiddenObstacle',
        layer: 8,
        position: const Vec3(0, 0, 0),
        components: [BoxCollider(size: const Vec3(2, 2, 2))],
      );

      final ray = const Ray(origin: Vec3(0, 0, 5), direction: Vec3(0, 0, -1));

      // Query excluding layer 8 finds nothing
      final hitDefault = engine.scene.physics.raycast(
        ray,
        layerMask: LayerMask.fromLayer(0),
      );
      expect(hitDefault, isNull);

      // Query including layer 8 hits HiddenObstacle
      final hitLayer8 = engine.scene.physics.raycast(
        ray,
        layerMask: LayerMask.fromLayer(8),
      );
      expect(hitLayer8, isNotNull);
      expect(hitLayer8!.gameObject.name, 'HiddenObstacle');
    });

    test(
      'Gizmos.arrow and Gizmos.wireDisc queue segments and project properly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final cam = engine.scene
            .createGameObject(
              'Cam',
              position: const Vec3(0, 0, 5),
              components: [Camera()],
            )
            .getComponent<Camera>()!;

        engine.scene.gizmos.enabled = true;
        engine.scene.gizmos.arrow(
          const Vec3(0, 0, 0),
          const Vec3(0, 1, 0),
          headSize: 0.2,
        );
        // Shaft (1) + 4 head base lines = 5 lines
        expect(engine.scene.gizmos.lineCount, 5);

        engine.scene.gizmos.wireDisc(
          const Vec3(0, 0, 0),
          1.0,
          const Vec3(0, 1, 0),
        );
        expect(
          engine.scene.gizmos.lineCount,
          5 + engine.scene.gizmos.circleSegments,
        );

        final projected = engine.scene.gizmos.project(cam);
        expect(projected.length, 5 + engine.scene.gizmos.circleSegments);
      },
    );
  });

  group(
    'E17 — Layer Collision Matrix, Radial Explosion Impulses & Spatial Camera Shake',
    () {
      test(
        'PhysicsWorld layer collision matrix selectively disables layer-pair collisions',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          final physics = engine.scene.physics;

          // By default all 32x32 layers can collide
          expect(physics.getLayerCollision(2, 2), isTrue);
          expect(physics.getLayerCollision(0, 1), isTrue);

          engine.scene.createGameObject(
            'DebrisA',
            layer: 2,
            position: const Vec3(0, 0, 0),
            components: [SphereCollider(radius: 1.0, isTrigger: true)],
          );
          engine.scene.createGameObject(
            'DebrisB',
            layer: 2,
            position: const Vec3(0.5, 0, 0),
            components: [SphereCollider(radius: 1.0, isTrigger: true)],
          );

          // Disable layer 2 vs layer 2 collision
          physics.setLayerCollision(2, 2, false);
          expect(physics.getLayerCollision(2, 2), isFalse);

          engine.step(0.05);
          expect(physics.contactPairs.length, 0);

          // Re-enable layer 2 vs layer 2 collision
          physics.setLayerCollision(2, 2, true);
          expect(physics.getLayerCollision(2, 2), isTrue);

          engine.step(0.05);
          expect(physics.contactPairs.length, 1);
        },
      );

      test(
        'RigidBody and PhysicsWorld radial explosion impulse applies outward velocity and upwards loft',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final body = engine.scene
              .createGameObject(
                'Barrel',
                position: const Vec3(2, 0, 0),
                components: [
                  SphereCollider(radius: 0.5),
                  RigidBody(useGravity: false, linearDrag: 0.0),
                ],
              )
              .getComponent<RigidBody>()!;

          // Explosion at origin, radius 5, force 10
          // Distance is 2, factor is (1 - 2/5) = 0.6 -> impulse 6 along +X
          body.addExplosionForce(10.0, Vec3.zero, 5.0, upwardsModifier: 1.5);
          expect(body.velocity.x, greaterThan(0));
          expect(
            body.velocity.y,
            greaterThan(0),
          ); // lifted upwards by upwardsModifier

          // Multiple bodies via PhysicsWorld.addExplosionForce
          final farBody = engine.scene
              .createGameObject(
                'FarBarrel',
                position: const Vec3(10, 0, 0),
                components: [
                  SphereCollider(radius: 0.5),
                  RigidBody(useGravity: false, linearDrag: 0.0),
                ],
              )
              .getComponent<RigidBody>()!;

          engine.scene.physics.addExplosionForce(20.0, Vec3.zero, 6.0);
          expect(farBody.velocity.length, 0.0); // beyond radius 6.0
        },
      );

      test(
        'Camera.shakeAt, Scene.shakeCamerasAt, and Scene.explode shake nearby cameras and query input metadata',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final nearCam = engine.scene
              .createGameObject(
                'NearCam',
                position: const Vec3(0, 0, 5),
                components: [Camera()],
              )
              .getComponent<Camera>()!;

          final farCam = engine.scene
              .createGameObject(
                'FarCam',
                position: const Vec3(0, 0, 50),
                components: [Camera()],
              )
              .getComponent<Camera>()!;

          // Unified scene.explode shakes nearCam but leaves farCam untouched
          engine.scene.explode(
            Vec3.zero,
            force: 15.0,
            radius: 6.0,
            cameraTrauma: 0.8,
            cameraMaxDistance: 20.0,
          );

          expect(nearCam.shakeEngine.trauma, greaterThan(0.0));
          expect(farCam.shakeEngine.trauma, closeTo(0.0, 1e-6));

          // InputActions queries
          expect(engine.input.hasButton('Submit'), isTrue);
          expect(engine.input.hasButton('UnknownButton'), isFalse);
          expect(engine.input.hasAxis('Horizontal'), isTrue);
          expect(engine.input.hasAxis('UnknownAxis'), isFalse);
          expect(engine.input.buttonNames, contains('Submit'));
          expect(engine.input.axisNames, contains('Vertical'));
          expect(engine.input.getAxisRaw('Horizontal'), closeTo(0.0, 1e-6));
        },
      );
    },
  );

  group(
    'E18 — Particle System Presets, Spatial Audio One-Shots & Transform Ergonomics',
    () {
      test(
        'ParticleSystem preset factories instantiate emitters, burst, and reset active counts',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final mesh = host.graphics.createMesh(Primitives.cube());
          final mat = host.graphics.createMaterial(
            MaterialDefinition(key: 'fire'),
          );

          final campfire = ParticleSystem.campfire(mesh: mesh, material: mat);
          final explosion = ParticleSystem.explosion(mesh: mesh, material: mat);
          final fireflies = ParticleSystem.fireflies(mesh: mesh, material: mat);

          final go = engine.scene.createGameObject(
            'VFX',
            components: [campfire],
          );

          expect(campfire.activeParticleCount, 0);
          final spawned = campfire.burst(25);
          expect(spawned, 25);
          expect(campfire.activeParticleCount, 25);

          campfire.reset();
          expect(campfire.activeParticleCount, 0);

          // Verify explosion and fireflies can burst
          go.addComponent(explosion);
          final expSpawned = explosion.burst(50);
          expect(expSpawned, 50);
          expect(explosion.activeParticleCount, 50);
          explosion.clear();
          expect(explosion.activeParticleCount, 0);

          go.addComponent(fireflies);
          final ffSpawned = fireflies.burst(10);
          expect(ffSpawned, 10);
          expect(fireflies.activeParticleCount, 10);
          fireflies.clear();
          expect(fireflies.activeParticleCount, 0);
        },
      );

      test(
        'AudioSource.playClipAtPoint and Scene.playClipAt spawn spatial one-shot GameObject that auto-destroys',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          final clip = host.audio.clip('explosion.wav');

          final initialObjects = engine.scene.rootGameObjects.length;
          final go = engine.scene.playClipAt(
            clip,
            const Vec3(10, 0, 0),
            spatialBlend: 1.0,
            minDistance: 2.0,
            maxDistance: 30.0,
            duration: 0.1,
          );

          expect(go, isNotNull);
          expect(engine.scene.rootGameObjects.length, initialObjects + 1);
          final src = go!.getComponent<AudioSource>();
          expect(src, isNotNull);
          expect(src!.spatialBlend, closeTo(1.0, 1e-6));
          expect(src.minDistance, closeTo(2.0, 1e-6));
          expect(src.maxDistance, closeTo(30.0, 1e-6));

          // Advance time beyond duration (0.1s)
          engine.step(0.06);
          engine.step(0.06);
          // Deferred destruction flushes at end of frame
          expect(go.isDestroyed, isTrue);
        },
      );

      test('TransformComponent directional properties and rotation helpers', () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final go = engine.scene.createGameObject('Target');
        final t = go.transform;

        // Identity orientation: forward = (0, 0, 1), up = (0, 1, 0), right = (1, 0, 0)
        expect(t.back, equals(-t.forward));
        expect(t.left, equals(-t.right));
        expect(t.down, equals(-t.up));

        // Rotate 90 deg around Y
        t.rotateY(math.pi * 0.5);
        expect(t.right.x, closeTo(0, 1e-5));
        expect(t.right.z, closeTo(-1, 1e-5));

        // Reset
        t.resetLocal();
        expect(t.localPosition, Vec3.zero);
        expect(t.localRotation, Quat.identity);
        expect(t.localScale, 1.0);
      });
    },
  );

  group('E19 — 2D Spatial & Raycast Queries, UIImage, and Camera2D Follow/Clamp', () {
    test('TilemapComponent cellToWorld, raycast, and hasLineOfSight', () {
      final layer = TileLayer(
        columns: 10,
        rows: 10,
        tileWidth: 16,
        tileHeight: 16,
        originX: 0,
        originY: 0,
        tileset: [SpriteRegion.white, SpriteRegion.white],
      );
      // Place a wall at column 5, row 2
      layer.setTile(5, 2, 1);

      final tilemap = TilemapComponent(layer, solidTiles: [1]);

      // cellToWorld check
      final originCorner = tilemap.cellToWorld(2, 3);
      expect(originCorner.x, 32.0);
      expect(originCorner.y, 48.0);

      final centerPt = tilemap.cellToWorld(2, 3, center: true);
      expect(centerPt.x, 40.0);
      expect(centerPt.y, 56.0);

      // Line of sight horizontally across row 2 (from col 1 to col 8) -> hits wall at col 5
      final startBlocked = tilemap.cellToWorld(1, 2, center: true);
      final endBlocked = tilemap.cellToWorld(8, 2, center: true);
      final hit = tilemap.raycast(startBlocked, endBlocked);

      expect(hit, isNotNull);
      expect(hit!.column, 5);
      expect(hit.row, 2);
      expect(tilemap.hasLineOfSight(startBlocked, endBlocked), isFalse);

      // Line of sight horizontally across row 3 (from col 1 to col 8) -> completely clear
      final startClear = tilemap.cellToWorld(1, 3, center: true);
      final endClear = tilemap.cellToWorld(8, 3, center: true);
      final hitClear = tilemap.raycast(startClear, endClear);

      expect(hitClear, isNull);
      expect(tilemap.hasLineOfSight(startClear, endClear), isTrue);
    });

    test('UIImage renders into UICanvas SpriteBatch without crashing', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      engine.scene.createGameObject('UI', components: [canvas]);

      final img = canvas.add(
        UIImage(
          region: SpriteRegion.white,
          x: 10,
          y: 20,
          width: 64,
          height: 64,
          tintColor: 0xFF00FFFF,
          flipX: true,
        ),
      );

      expect(canvas.elements.contains(img), isTrue);

      // Stepping engine runs UICanvas.update and renders batch
      engine.step(0.016);
    });

    test(
      'Camera2DComponent smoothFollow and clampToBounds constrain ortho camera view',
      () {
        final cam = Camera2DComponent(
          designWidth: 400,
          designHeight: 225,
          followTransform: false,
        );
        cam.x = 0;
        cam.y = 0;

        // Smooth follow towards (100, 50)
        cam.smoothFollow(const Vec2(100, 50), smoothing: 10.0, dt: 0.1);
        expect(cam.x, greaterThan(0.0));
        expect(cam.x, lessThan(100.0));
        expect(cam.y, greaterThan(0.0));
        expect(cam.y, lessThan(50.0));

        // Repeated follow converges
        for (var i = 0; i < 60; i++) {
          cam.smoothFollow(const Vec2(100, 50), smoothing: 10.0, dt: 0.1);
        }
        expect(cam.x, closeTo(100.0, 1e-2));
        expect(cam.y, closeTo(50.0, 1e-2));

        // Clamping to bounds [10..80, 5..30]
        cam.clampToBounds(minX: 10, maxX: 80, minY: 5, maxY: 30);
        expect(cam.x, closeTo(80.0, 1e-5));
        expect(cam.y, closeTo(30.0, 1e-5));
      },
    );
  });

  group(
    'E20 — Camera Viewport Projections & Culling, MeshRenderer Material Overrides, and NavGrid2D Line-of-Sight',
    () {
      test(
        'Camera worldToViewportPoint, viewportToWorldPoint, and cullingMask serialization',
        () {
          final host = HeadlessHost();
          host.graphics
            ..viewportWidth = 800
            ..viewportHeight = 600;
          final engine = Engine(host);

          final camObj = engine.scene.createGameObject(
            'MainCamera',
            position: const Vec3(0, 0, 5),
            components: [Camera(cullingMask: 0x05)],
          );
          final cam = camObj.getComponent<Camera>()!;
          expect(cam.cullingMask, 0x05);

          // Point right at the center of the camera's view (0, 0, 0)
          final vpCenter = cam.worldToViewportPoint(const Vec3(0, 0, 0));
          expect(vpCenter, isNotNull);
          expect(vpCenter!.x, closeTo(0.5, 1e-3));
          expect(vpCenter.y, closeTo(0.5, 1e-3));
          expect(vpCenter.depth, greaterThan(0));

          // Reconstruct world ray at distance = 5.0
          final reconstructed = cam.viewportToWorldPoint(Vec3(0.5, 0.5, 5.0));
          expect(reconstructed, isNotNull);
          expect(reconstructed!.x, closeTo(0.0, 1e-3));
          expect(reconstructed.y, closeTo(0.0, 1e-3));
          expect(reconstructed.z, closeTo(0.0, 1e-3));

          // Round-trip Camera via SceneSerializer to ensure cullingMask is preserved
          final json = SceneSerializer.toJson(
            engine.scene,
            registry: engine.registry,
          );
          final restored = SceneSerializer.fromJson(
            json,
            registry: engine.registry,
          );
          final restoredCam = restored
              .find('MainCamera')
              ?.getComponent<Camera>();
          expect(restoredCam, isNotNull);
          expect(restoredCam!.cullingMask, 0x05);
        },
      );

      test('MeshRenderer tintColor and materialOverride dynamic updates', () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final meshHandle = host.graphics.createMesh(Primitives.cube());
        final renderer = MeshRenderer(
          mesh: meshHandle,
          tintColor: const LinearColor(1.0, 0.5, 0.2),
        );

        final obj = engine.scene.createGameObject(
          'TintedBox',
          components: [renderer],
        );
        engine.step(0.016);
        expect(obj.activeInHierarchy, isTrue);

        expect(renderer.tintColor, isNotNull);
        expect(renderer.material, isNotNull);

        // Dynamically change tint
        renderer.setTint(const LinearColor(0.1, 0.9, 0.3));
        expect(renderer.tintColor?.g, closeTo(0.9, 1e-4));
        expect(renderer.material, isNotNull);

        // Set material override
        renderer.materialOverride = const MaterialDefinition(
          key: 'custom_override',
          tintR: 0.0,
          tintG: 0.0,
          tintB: 1.0,
        );
        expect(renderer.materialOverride?.key, 'custom_override');
        expect(renderer.material, isNotNull);
      });

      test(
        'NavGrid2D hasLineOfSight and raycast verify straight-line traversability',
        () {
          // 10x10 nav grid
          final nav = NavGrid2D(
            columns: 10,
            rows: 10,
            cellWidth: 1.0,
            cellHeight: 1.0,
          );
          // Place a 1-cell pillar obstacle at (5, 5)
          nav.setWalkable(5, 5, false);

          // Line from (1, 5) to (8, 5) crosses (5, 5) => blocked
          final blockedStart = Vec2(1.5, 5.5);
          final blockedEnd = Vec2(8.5, 5.5);
          expect(nav.hasLineOfSight(blockedStart, blockedEnd), isFalse);

          final hit = nav.raycast(blockedStart, blockedEnd);
          expect(hit, isNotNull);
          expect(hit!.column, 5);
          expect(hit.row, 5);
          expect(hit.distance, greaterThan(0));

          // Line from (1, 2) to (8, 2) does not cross row 5 => clear
          final clearStart = Vec2(1.5, 2.5);
          final clearEnd = Vec2(8.5, 2.5);
          expect(nav.hasLineOfSight(clearStart, clearEnd), isTrue);
          expect(nav.raycast(clearStart, clearEnd), isNull);
        },
      );
    },
  );

  group('E21 — SpriteSheet Grid Slicing, UIDropdown, and Time.smoothDamp', () {
    test(
      'SpriteSheet slices uniform grid cells and slices sub-ranges for animation clips',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        // 4 columns x 2 rows of 16x16 tiles (total 64x32)
        final dummyTex = host.graphics.createTexture(
          width: 64,
          height: 32,
          pixels: Uint8List(64 * 32 * 4),
        );

        final sheet = engine.catalog.registerSpriteSheet(
          'hero_sheet',
          texture: dummyTex,
          cellWidth: 16,
          cellHeight: 16,
          columns: 4,
          rows: 2,
        );

        expect(sheet.count, 8);
        expect(sheet.all.length, 8);

        final first = sheet.cell(0, 0);
        expect(first.width, 16.0);
        expect(first.height, 16.0);

        final bottomCorner = sheet.cell(3, 1);
        expect(bottomCorner, isNotNull);

        // Slicing animation clip [0..4]
        final walkClip = sheet.slice(0, 4);
        expect(walkClip.length, 4);

        // Create SpriteRenderer from region
        final renderer = SpriteRenderer.fromRegion(
          first,
          color: 0xFF5566FF,
          layer: 2,
        );
        expect(renderer.layer, 2);
        expect(renderer.color, 0xFF5566FF);
        expect(renderer.region, first);

        // Look up from catalog
        expect(engine.catalog.spriteSheet('hero_sheet'), same(sheet));
      },
    );

    test('UIDropdown toggles popup menu and selects items on click', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      engine.scene.createGameObject('UI', components: [canvas]);

      int selectedIdx = -1;
      String selectedVal = '';
      final dropdown = canvas.add(
        UIDropdown(
          options: ['Quality: Low', 'Quality: Medium', 'Quality: Ultra'],
          selectedIndex: 0,
          x: 10,
          y: 10,
          width: 140,
          height: 24,
          onSelected: (idx, val) {
            selectedIdx = idx;
            selectedVal = val;
          },
        ),
      );

      expect(dropdown.isOpen, isFalse);
      expect(dropdown.selectedOption, 'Quality: Low');

      // Click dropdown header (10, 10) to open
      final input = host.input;
      input
        ..pointerX = 20
        ..pointerY = 20
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      expect(dropdown.isOpen, isTrue);

      // Release pointer
      input
        ..pointerDown = false
        ..pointerPressed = false
        ..pointerReleased = true;
      engine.step(0.016);

      // Click on item 2 (Quality: Ultra):
      // header is [10..34]
      // item 0 is [34..58]
      // item 1 is [58..82]
      // item 2 is [82..106] -> y = 90
      input
        ..pointerX = 20
        ..pointerY = 90
        ..pointerDown = true
        ..pointerPressed = true
        ..pointerReleased = false;
      engine.step(0.016);

      expect(selectedIdx, 2);
      expect(selectedVal, 'Quality: Ultra');
      expect(dropdown.selectedOption, 'Quality: Ultra');
      expect(dropdown.isOpen, isFalse);
    });

    test(
      'Time.smoothDamp and smoothDampVec3 converge critically to target without oscillation',
      () {
        final time = Time();

        // Smooth damp scalar from 0 to 100 with smoothTime = 0.2s
        var current = 0.0;
        var velocity = 0.0;
        const target = 100.0;

        for (var i = 0; i < 30; i++) {
          final res = time.smoothDamp(
            current,
            target,
            velocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          current = res.current;
          velocity = res.velocity;
        }

        expect(current, greaterThan(80.0));
        expect(current, lessThanOrEqualTo(100.0));

        // After 60 more steps (total ~1.44s), converges to target
        for (var i = 0; i < 60; i++) {
          final res = time.smoothDamp(
            current,
            target,
            velocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          current = res.current;
          velocity = res.velocity;
        }
        expect(current, closeTo(100.0, 1e-2));
        expect(velocity, closeTo(0.0, 1e-2));

        // Smooth damp Vec3
        var vCurrent = Vec3.zero;
        var vVelocity = Vec3.zero;
        const vTarget = Vec3(10, 20, 30);

        for (var i = 0; i < 90; i++) {
          final res = time.smoothDampVec3(
            vCurrent,
            vTarget,
            vVelocity,
            smoothTime: 0.2,
            dt: 0.016,
          );
          vCurrent = res.current;
          vVelocity = res.velocity;
        }
        expect(vCurrent.x, closeTo(10.0, 1e-3));
        expect(vCurrent.y, closeTo(20.0, 1e-3));
        expect(vCurrent.z, closeTo(30.0, 1e-3));
      },
    );
  });

  group(
    'E22 — SplineMeshRenderer, Stylized PostProcess Presets, and Multi-Camera Split-Screen Viewports',
    () {
      test(
        'SplineMeshRenderer samples SplinePath and generates ribbon mesh via LineRenderer',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          // Create a 3D curved spline with 4 control points
          final splineObj = engine.scene.createGameObject('SplineCable');
          final path = splineObj.addComponent(
            SplinePath.fromPoints([
              const Vec3(0, 0, 0),
              const Vec3(2, 4, 1),
              const Vec3(6, 3, 2),
              const Vec3(10, 0, 0),
            ]),
          );

          final smr = splineObj.addComponent(
            SplineMeshRenderer(
              path: path,
              sampleCount: 16,
              startWidth: 0.3,
              endWidth: 0.1,
              color: const LinearColor(0.2, 0.9, 0.4),
            ),
          );

          engine.step(0.016);

          final line = splineObj.getComponent<LineRenderer>();
          expect(line, isNotNull);
          expect(line!.positionCount, 16);
          expect(line.startWidth, closeTo(0.3, 1e-4));
          expect(line.endWidth, closeTo(0.1, 1e-4));
          expect(line.color.g, closeTo(0.9, 1e-4));

          // Rebuild with different widths
          smr.startWidth = 0.5;
          smr.endWidth = 0.5;
          smr.rebuild();
          expect(line.startWidth, closeTo(0.5, 1e-4));
          expect(line.endWidth, closeTo(0.5, 1e-4));
        },
      );

      test(
        'PostProcessVolume retro and cinematic presets configure stylized effects',
        () {
          final retro = PostProcessVolume.retro(
            weight: 0.8,
            grain: 0.5,
            vignette: 0.4,
            dither: 0.6,
            chromaticAberration: 0.35,
          );

          expect(retro.grain, 0.5);
          expect(retro.vignette, 0.4);
          expect(retro.ditherStrength, 0.6);
          expect(retro.chromaticAberration, 0.35);

          var state = const PostProcessState();
          state = retro.blendOnto(state, 1.0);
          expect(state.grain, closeTo(0.5, 1e-4));
          expect(state.vignette, closeTo(0.4, 1e-4));
          expect(state.ditherStrength, closeTo(0.6, 1e-4));
          expect(state.vhsChromaWeight, closeTo(0.35, 1e-4));

          final cine = PostProcessVolume.cinematic(
            weight: 1.0,
            exposure: 1.2,
            bloomStrength: 0.5,
            ssaoStrength: 0.7,
          );
          expect(cine.toneMapping, ToneMappingMode.aces);
          expect(cine.bloomStrength, 0.5);

          final cineState = cine.blendOnto(const PostProcessState(), 1.0);
          expect(cineState.exposure, closeTo(1.2, 1e-4));
          expect(cineState.bloomStrength, closeTo(0.5, 1e-4));
          expect(cineState.ssaoStrength, closeTo(0.7, 1e-4));
          expect(cineState.toneMapping, ToneMappingMode.aces);
        },
      );

      test(
        'Camera multi-viewport split-screen and depth ordering round-trip via SceneSerializer',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          // Player 1 Camera (left half: x: 0, y: 0, w: 0.5, h: 1)
          final cam1Obj = engine.scene.createGameObject(
            'Player1Camera',
            position: const Vec3(0, 1.5, 5),
            components: [
              Camera(
                normalizedViewportRect: const Vec4(0, 0, 0.5, 1.0),
                depth: 0,
              ),
            ],
          );

          // Player 2 Camera (right half: x: 0.5, y: 0, w: 0.5, h: 1)
          final cam2Obj = engine.scene.createGameObject(
            'Player2Camera',
            position: const Vec3(10, 1.5, 5),
            components: [
              Camera(
                normalizedViewportRect: const Vec4(0.5, 0, 0.5, 1.0),
                depth: 1,
              ),
            ],
          );

          final c1 = cam1Obj.getComponent<Camera>()!;
          final c2 = cam2Obj.getComponent<Camera>()!;
          expect(c1.normalizedViewportRect.z, closeTo(0.5, 1e-4));
          expect(c2.normalizedViewportRect.x, closeTo(0.5, 1e-4));
          expect(c2.depth, 1);

          // Verify serialization round-trip of depth and properties
          final json = SceneSerializer.toJson(
            engine.scene,
            registry: engine.registry,
          );
          final restored = SceneSerializer.fromJson(
            json,
            registry: engine.registry,
          );
          final restoredC2 = restored
              .find('Player2Camera')
              ?.getComponent<Camera>();
          expect(restoredC2, isNotNull);
          expect(restoredC2!.depth, 1);
        },
      );
    },
  );

  group(
    'E23 — Scene.createPrimitive, UIButton Enabled State, and InputActions.getVector2',
    () {
      test(
        'Scene.createPrimitive builds Cube, Sphere, and Capsule with MeshRenderer and Collider',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          // Create a Cube primitive
          final cube = engine.scene.createPrimitive(
            PrimitiveType.cube,
            position: const Vec3(1, 2, 3),
            color: const LinearColor(1, 0, 0),
          );
          expect(cube.name, 'Cube');
          expect(cube.getComponent<MeshRenderer>(), isNotNull);
          expect(cube.getComponent<BoxCollider>(), isNotNull);
          expect(cube.transform.position.x, closeTo(1.0, 1e-4));

          // Create a Sphere primitive
          final sphere = engine.scene.createPrimitive(
            PrimitiveType.sphere,
            name: 'PlayerBall',
            isTrigger: true,
          );
          expect(sphere.name, 'PlayerBall');
          final sphereCol = sphere.getComponent<SphereCollider>();
          expect(sphereCol, isNotNull);
          expect(sphereCol!.isTrigger, isTrue);

          // Create a Capsule primitive
          final capsule = engine.scene.createPrimitive(PrimitiveType.capsule);
          expect(capsule.name, 'Capsule');
          expect(capsule.getComponent<CapsuleCollider>(), isNotNull);
        },
      );

      test(
        'UIButton enabled state controls hover/press interactions and disabled colors',
        () {
          final host = HeadlessHost();
          host.graphics
            ..viewportWidth = 640
            ..viewportHeight = 360;
          final engine = Engine(host);

          final canvas = UICanvas(designWidth: 640, designHeight: 360);
          engine.scene.createGameObject('UI', components: [canvas]);

          var clicked = false;
          final btn = canvas.add(
            UIButton(
              label: 'Submit',
              x: 10,
              y: 10,
              width: 100,
              height: 30,
              enabled: false,
              onPressed: () => clicked = true,
            ),
          );

          // Pointer click while disabled -> no click, no hover
          final input = host.input;
          input
            ..pointerX = 20
            ..pointerY = 20
            ..pointerDown = true
            ..pointerPressed = true;
          engine.step(0.016);
          expect(btn.isHovered, isFalse);
          expect(btn.isPressed, isFalse);
          expect(clicked, isFalse);

          // Enable button and click again -> succeeds
          btn.enabled = true;
          engine.step(0.016);
          expect(btn.isPressed, isTrue);

          input
            ..pointerDown = false
            ..pointerPressed = false
            ..pointerReleased = true;
          engine.step(0.016);
          expect(clicked, isTrue);
        },
      );

      test(
        'InputActions.getVector2 evaluates clamped/normalized composite 2D input',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);

          // Only Right held -> (1.0, 0.0)
          host.input.press('KeyD');
          expect(engine.input.getVector2().x, closeTo(1.0, 1e-4));
          expect(engine.input.getVector2().y, closeTo(0.0, 1e-4));

          // Both Right + Up held -> (1.0, 1.0) normalized to ~ (0.7071, 0.7071)
          host.input.press('KeyW');
          final diag = engine.input.getVector2(normalize: true);
          expect(diag.x, closeTo(math.sqrt(0.5), 1e-4));
          expect(diag.y, closeTo(math.sqrt(0.5), 1e-4));
          expect(diag.length, closeTo(1.0, 1e-4));

          // Without normalization -> (1.0, 1.0)
          final unnorm = engine.input.getVector2(normalize: false);
          expect(unnorm.x, closeTo(1.0, 1e-4));
          expect(unnorm.y, closeTo(1.0, 1e-4));
        },
      );
    },
  );

  group('E24 — Mathfx Utilities, ParallaxBackground2D, and SceneManager.fadeTo', () {
    test(
      'Mathfx evaluates inverseLerp, pingPong, repeat, deltaAngle, moveTowards, and damp',
      () {
        // inverseLerp
        expect(Mathfx.inverseLerp(10, 20, 15), closeTo(0.5, 1e-5));
        expect(Mathfx.inverseLerp(10, 20, 5), closeTo(0.0, 1e-5));
        expect(Mathfx.inverseLerp(10, 20, 25), closeTo(1.0, 1e-5));

        // pingPong
        expect(Mathfx.pingPong(0.0, 5.0), closeTo(0.0, 1e-5));
        expect(Mathfx.pingPong(3.0, 5.0), closeTo(3.0, 1e-5));
        expect(Mathfx.pingPong(7.0, 5.0), closeTo(3.0, 1e-5));
        expect(Mathfx.pingPong(10.0, 5.0), closeTo(0.0, 1e-5));

        // repeat
        expect(Mathfx.repeat(2.5, 5.0), closeTo(2.5, 1e-5));
        expect(Mathfx.repeat(7.5, 5.0), closeTo(2.5, 1e-5));

        // deltaAngle & deltaAngleDeg
        expect(
          Mathfx.deltaAngle(0, math.pi * 0.5),
          closeTo(math.pi * 0.5, 1e-5),
        );
        expect(
          Mathfx.deltaAngle(math.pi * 0.9, -math.pi * 0.9),
          closeTo(math.pi * 0.2, 1e-4),
        );
        expect(Mathfx.deltaAngleDeg(10, 350), closeTo(-20.0, 1e-4));

        // moveTowards
        expect(Mathfx.moveTowards(0.0, 10.0, 2.5), closeTo(2.5, 1e-5));
        expect(Mathfx.moveTowards(9.0, 10.0, 2.5), closeTo(10.0, 1e-5));

        // moveTowardsVec3
        final v1 = Mathfx.moveTowardsVec3(Vec3.zero, const Vec3(10, 0, 0), 3.0);
        expect(v1.x, closeTo(3.0, 1e-4));
        expect(v1.y, closeTo(0.0, 1e-4));

        // damp & dampVec3
        final d = Mathfx.damp(0.0, 10.0, 5.0, 0.1);
        expect(d, greaterThan(0.0));
        expect(d, lessThan(10.0));

        final dv = Mathfx.dampVec3(Vec3.zero, const Vec3(10, 20, 0), 5.0, 0.1);
        expect(dv.x, greaterThan(0.0));
        expect(dv.y, greaterThan(0.0));
      },
    );

    test(
      'ParallaxBackground2D advances parallax layers with camera delta and autoScroll',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject(
          'Cam2D',
          position: Vec3.zero,
        );
        camGo.addComponent(
          Camera2DComponent(designWidth: 640, designHeight: 360),
        );

        final bg = ParallaxBackground2D(
          layers: [
            ParallaxLayer(
              factor: const Vec2(0.2, 0.0),
              autoScroll: const Vec2(10.0, 0.0),
              width: 640.0,
              repeatX: true,
            ),
            ParallaxLayer(
              factor: const Vec2(0.8, 0.0),
              autoScroll: Vec2.zero,
              width: 640.0,
              repeatX: true,
            ),
          ],
        );
        engine.scene.createGameObject('Background', components: [bg]);

        // Initial frame establishes baseline position
        engine.step(0.1);
        expect(
          bg.layers[0].offset.x,
          closeTo(1.0, 1e-4),
        ); // 10.0 * 0.1s autoScroll = 1.0

        // Move camera 100 units right over 0.1s
        camGo.transform.position = const Vec3(100.0, 0, 0);
        engine.step(0.1);

        // Layer 0: prev offset (1.0) + autoScroll (10 * 0.1 = 1.0) + camera delta (100 * 0.2 = 20) = 22.0
        expect(bg.layers[0].offset.x, closeTo(22.0, 1e-3));

        // Layer 1: camera delta (100 * 0.8 = 80)
        expect(bg.layers[1].offset.x, closeTo(80.0, 1e-3));
      },
    );

    test(
      'SceneManager.fadeTo animates alpha curve and swaps scene at midpoint',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        var sceneACreated = 0;
        var sceneBCreated = 0;

        engine.scenes.register('SceneA', () {
          sceneACreated++;
          final s = Scene();
          s.createGameObject('ObjectA');
          return s;
        });

        engine.scenes.register('SceneB', () {
          sceneBCreated++;
          final s = Scene();
          s.createGameObject('ObjectB');
          return s;
        });

        engine.scenes.load('SceneA');
        expect(sceneACreated, 1);
        expect(engine.scenes.activeSceneName, 'SceneA');
        expect(engine.scenes.isTransitioning, isFalse);

        // Trigger 1.0s fade transition to SceneB
        engine.scenes.fadeTo('SceneB', duration: 1.0);
        expect(engine.scenes.isTransitioning, isTrue);
        expect(engine.scenes.transitionAlpha, closeTo(0.0, 1e-4));

        // Step 5 frames of 0.05s = 0.25s: quarter-way through fade-out, alpha = 0.5, scene still SceneA
        for (var i = 0; i < 5; i++) {
          engine.step(0.05);
        }
        expect(engine.scenes.isTransitioning, isTrue);
        expect(engine.scenes.transitionAlpha, closeTo(0.5, 1e-4));
        expect(engine.scenes.activeSceneName, 'SceneA');

        // Step 6 more frames of 0.05s (total 0.55s): past midpoint -> scene swapped to SceneB, alpha fading in
        for (var i = 0; i < 6; i++) {
          engine.step(0.05);
        }
        expect(sceneBCreated, 1);
        expect(engine.scenes.activeSceneName, 'SceneB');
        expect(engine.scenes.isTransitioning, isTrue);
        expect(engine.scenes.transitionAlpha, closeTo(0.9, 1e-3));

        // Step 10 more frames of 0.05s (total 1.05s): transition finishes
        for (var i = 0; i < 10; i++) {
          engine.step(0.05);
        }
        expect(engine.scenes.isTransitioning, isFalse);
        expect(engine.scenes.transitionAlpha, closeTo(0.0, 1e-4));
      },
    );
  });

  group('E25 — AudioSource Fades, Constraints, and Scene.clone', () {
    test(
      'AudioSource fadeVolumeTo and crossFadeTo ramp volume and switch clips smoothly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final clipA = host.audio.clip('music_a.ogg');
        final clipB = host.audio.clip('music_b.ogg');

        final src = AudioSource(clip: clipA, volume: 1.0);
        engine.scene.createGameObject('MusicPlayer', components: [src]);
        src.play();

        var fadeFinished = false;
        src.fadeVolumeTo(
          0.2,
          duration: 0.2,
          onComplete: () => fadeFinished = true,
        );
        expect(src.isFading, isTrue);

        // Step 2 frames of 0.05s = 0.1s: half-way through fade
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.6, 1e-4));
        expect(fadeFinished, isFalse);

        // Step 2 more frames of 0.05s = 0.2s: finished
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.2, 1e-4));
        expect(fadeFinished, isTrue);
        expect(src.isFading, isFalse);

        // Cross fade from clipA to clipB over 0.2s
        var crossFinished = false;
        src.crossFadeTo(
          clipB,
          duration: 0.2,
          targetVolume: 0.8,
          onComplete: () => crossFinished = true,
        );
        expect(src.isFading, isTrue);

        // Step 2 frames of 0.05s = 0.1s: midpoint reached -> clip swapped to clipB
        engine.step(0.05);
        engine.step(0.05);
        expect(src.clip, clipB);

        // Step 2 more frames = 0.2s: cross-fade finishes at target volume 0.8
        engine.step(0.05);
        engine.step(0.05);
        expect(src.volume, closeTo(0.8, 1e-4));
        expect(crossFinished, isTrue);
        expect(src.isFading, isFalse);
      },
    );

    test(
      'LookAtConstraint and FollowConstraint update orientation and spatial position',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final target = engine.scene.createGameObject(
          'Target',
          position: const Vec3(10.0, 0, 0),
        );
        final turret = engine.scene.createGameObject(
          'Turret',
          position: Vec3.zero,
        );
        turret.addComponent(
          LookAtConstraint(target: target.transform, weight: 1.0),
        );

        engine.step(0.016);
        // Turret's forward (-Z) should now point towards Target (+X), so forward.x is ~ 1.0
        expect(turret.transform.forward.x, closeTo(1.0, 1e-3));
        expect(turret.transform.forward.y, closeTo(0.0, 1e-3));

        // Follower follows target with offset (0, 2, 0) and lockY: true
        final follower = engine.scene.createGameObject(
          'Follower',
          position: Vec3.zero,
        );
        follower.addComponent(
          FollowConstraint(
            target: target.transform,
            offset: const Vec3(0, 2, 0),
            smoothing: 0.0,
            lockY: true,
          ),
        );

        engine.step(0.016);
        expect(follower.transform.position.x, closeTo(10.0, 1e-4));
        expect(
          follower.transform.position.y,
          closeTo(0.0, 1e-4),
        ); // Y locked to 0
      },
    );

    test(
      'Scene.clone duplicates GameObjects, components, and hierarchies independently',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final original = engine.scene.createGameObject(
          'Hero',
          tag: 'Player',
          layer: 3,
          position: const Vec3(1, 2, 3),
          components: [
            MeshRenderer(
              meshData: Primitives.cube(),
              tintColor: LinearColor(1, 0, 0),
            ),
            BoxCollider(size: const Vec3(1, 1, 1)),
          ],
        );

        final sword = engine.scene.createGameObject('Sword', parent: original);
        sword.addComponent(
          Light.point(color: LinearColor(1, 1, 0), intensity: 5.0),
        );

        // Clone original to a new position
        final clone = original.clone(
          name: 'HeroClone',
          position: const Vec3(10, 20, 30),
        );

        expect(clone.name, 'HeroClone');
        expect(clone.tag, 'Player');
        expect(clone.layer, 3);
        expect(clone.transform.position, const Vec3(10, 20, 30));

        // Must have own independent MeshRenderer and BoxCollider
        final mr = clone.getComponent<MeshRenderer>();
        expect(mr, isNotNull);
        expect(mr!.tintColor?.r, closeTo(1.0, 1e-4));
        expect(clone.getComponent<BoxCollider>(), isNotNull);

        // Must have duplicated child hierarchy
        expect(clone.children.length, 1);
        final clonedSword = clone.children.first;
        expect(clonedSword.name, 'Sword');
        final light = clonedSword.getComponent<Light>();
        expect(light, isNotNull);
        expect(light!.intensity, 5.0);

        // Modifying clone does not mutate original
        clone.layer = 7;
        mr.tintColor = LinearColor(0, 1, 0);
        expect(original.layer, 3);
        expect(
          original.getComponent<MeshRenderer>()!.tintColor?.r,
          closeTo(1.0, 1e-4),
        );
      },
    );
  });

  group(
    'E26 — LinearColor Extensions, SpatialGrid2D, and UICanvas Focus Navigation',
    () {
      test(
        'LinearColor extensions lerp, convert to HSV/hex, and parse hex/hsv formats',
        () {
          final red = const LinearColor(1, 0, 0);
          final blue = const LinearColor(0, 0, 1);

          // lerp
          final purple = red.lerp(blue, 0.5);
          expect(purple.r, closeTo(0.5, 1e-4));
          expect(purple.g, closeTo(0.0, 1e-4));
          expect(purple.b, closeTo(0.5, 1e-4));

          // withIntensity
          final brightRed = red.withIntensity(2.0);
          expect(brightRed.r, closeTo(2.0, 1e-4));

          // toRgba & toHex
          expect(red.toHex(), '#FF0000');
          expect(red.toRgba(1.0), 0xFF0000FF);

          // toHsv
          final hsvRed = red.toHsv();
          expect(hsvRed.h, closeTo(0.0, 1e-3));
          expect(hsvRed.s, closeTo(1.0, 1e-3));
          expect(hsvRed.v, closeTo(1.0, 1e-3));

          final green = const LinearColor(0, 1, 0);
          final hsvGreen = green.toHsv();
          expect(hsvGreen.h, closeTo(120.0, 1e-3));

          // linearColorFromHex & linearColorFromHsv
          final parsed = linearColorFromHex('#00FF00');
          expect(parsed.r, closeTo(0.0, 1e-3));
          expect(parsed.g, closeTo(1.0, 1e-3));
          expect(parsed.b, closeTo(0.0, 1e-3));

          final hsvBlue = linearColorFromHsv(240.0, 1.0, 1.0);
          expect(hsvBlue.r, closeTo(0.0, 1e-3));
          expect(hsvBlue.g, closeTo(0.0, 1e-3));
          expect(hsvBlue.b, closeTo(1.0, 1e-3));
        },
      );

      test(
        'SpatialGrid2D indexes 2D entities and accelerates radius/aabb queries',
        () {
          final grid = SpatialGrid2D<String>(cellSize: 50.0);

          grid.insert('Bullet1', const Vec2(10, 10), 5.0);
          grid.insert('Bullet2', const Vec2(25, 25), 5.0);
          grid.insert('DistantEnemy', const Vec2(500, 500), 10.0);

          expect(grid.count, 3);

          // Query near (0, 0) within radius 50.0 -> should retrieve Bullet1 and Bullet2, NOT DistantEnemy
          final nearby = grid.querySphere(const Vec2(0, 0), 50.0);
          expect(nearby, containsAll(['Bullet1', 'Bullet2']));
          expect(nearby, isNot(contains('DistantEnemy')));

          // Remove Bullet1 -> query should no longer return it
          expect(grid.remove('Bullet1'), isTrue);
          expect(grid.count, 2);
          final afterRemove = grid.querySphere(const Vec2(0, 0), 50.0);
          expect(afterRemove, isNot(contains('Bullet1')));
          expect(afterRemove, contains('Bullet2'));

          // Clear grid
          grid.clear();
          expect(grid.count, 0);
          expect(grid.querySphere(const Vec2(0, 0), 1000.0), isEmpty);
        },
      );

      test('UICanvas manages focus navigation and keyboard traversal', () {
        final host = HeadlessHost();
        final engine = Engine(host);

        var btn1Clicks = 0;
        var btn2Clicks = 0;
        final btn1 = UIButton(
          label: 'Btn1',
          width: 100,
          height: 30,
          onPressed: () => btn1Clicks++,
        );
        final btn2 = UIButton(
          label: 'Btn2',
          x: 120,
          width: 100,
          height: 30,
          onPressed: () => btn2Clicks++,
        );

        final canvas = UICanvas();
        canvas.add(btn1);
        canvas.add(btn2);
        engine.scene.createGameObject('UI', components: [canvas]);

        expect(canvas.focusedElement, isNull);

        // Tab -> focus first element (btn1)
        canvas.focusNext();
        expect(canvas.focusedElement, btn1);
        expect(btn1.isFocused, isTrue);
        expect(btn2.isFocused, isFalse);

        // Submit focused -> clicks btn1
        canvas.submitFocused();
        expect(btn1Clicks, 1);
        expect(btn2Clicks, 0);

        // Tab again -> focus btn2
        canvas.focusNext();
        expect(canvas.focusedElement, btn2);
        expect(btn1.isFocused, isFalse);
        expect(btn2.isFocused, isTrue);

        // Submit focused -> clicks btn2
        canvas.submitFocused();
        expect(btn1Clicks, 1);
        expect(btn2Clicks, 1);

        // Tab wraps around back to btn1
        canvas.focusNext();
        expect(canvas.focusedElement, btn1);

        // Shift+Tab navigates backwards to btn2
        canvas.focusPrevious();
        expect(canvas.focusedElement, btn2);
      });
    },
  );

  group('E27 — Native Submodules Trilogy (voxlog, voxui, voxecs)', () {
    test(
      'voxlog ring buffer sink and pattern formatting integrate with engine logging',
      () {
        final ring = RingBufferSink(capacity: 3);
        final log = Logger(name: 'Engine', sinks: [ring], level: LogLevel.info);

        log.debug('Ignored debug');
        log.info('System initialized');
        log.warn('Dropped frame detected');
        log.error('Renderer context lost');
        log.info('Fallback to headless');

        expect(ring.length, 3);
        final entries = ring.records.toList();
        expect(entries[0].message, 'Dropped frame detected');
        expect(entries[1].message, 'Renderer context lost');
        expect(entries[2].message, 'Fallback to headless');
        expect(entries[0].level, LogLevel.warn);
        expect(entries[1].level, LogLevel.error);
      },
    );

    test('voxui immediate-mode layout, sliders, and draw commands', () {
      final ui = VoxUiContext();
      // Window at (10, 10). Title(26) + pad(10) + text(17) + sep(8) => checkbox at y ~ 83..103.
      final input = VoxInput(
        mouseX: 50,
        mouseY: 90,
        wasMouseClicked: true,
        isMouseDown: true,
      );

      ui.beginFrame(input);
      final opened = ui.beginWindow(
        'Performance Diagnostics',
        x: 10,
        y: 10,
        width: 240,
        height: 160,
      );
      expect(opened, isTrue);

      ui.text('Frame Budget: 16.6ms');
      ui.separator();
      final wireframe = ui.checkbox('Show Colliders', false);
      expect(wireframe, isTrue);

      ui.endWindow();
      final dl = ui.endFrame();
      expect(dl.commands, isNotEmpty);
      expect(dl.commands.any((cmd) => cmd.text == 'Show Colliders'), isTrue);
    });

    test(
      'voxecs sparse-set storage, optimal multi-joins, and swap-and-pop removal',
      () {
        final reg = Registry();

        final e1 = reg.create();
        final e2 = reg.create();
        final e3 = reg.create();

        reg.assign(e1, Vec3(1, 2, 3));
        reg.assign(e2, Vec3(4, 5, 6));
        reg.assign(e3, Vec3(7, 8, 9));

        reg.assign(e1, 'Player');
        reg.assign(e3, 'Boss');

        // view2 join: only e1 and e3 have both Vec3 and String
        final joined = reg.view2<Vec3, String>().toList();
        expect(joined.length, 2);
        expect(
          joined.map((t) => t.$3).toSet(),
          containsAll(['Player', 'Boss']),
        );

        // Swap-and-pop removal of e1
        reg.remove<Vec3>(e1);
        expect(reg.has<Vec3>(e1), isFalse);
        expect(reg.has<Vec3>(e2), isTrue);
        expect(reg.has<Vec3>(e3), isTrue);

        // Clean destruction recycles generational handle
        reg.destroy(e3);
        expect(reg.valid(e3), isFalse);
        final recycled = reg.create();
        expect(recycled.index, e3.index);
        expect(recycled.version, e3.version + 1);
      },
    );
  });

  group('E28 — Procedural Audio, AI Components, and Debug Console (voxsynth, voxai)', () {
    test(
      'AudioSource.playSynth and Scene.playSynthAt spawn procedural sound one-shots',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final go = engine.scene.createGameObject('Player');
        final src = go.addComponent(AudioSource());

        // Play procedural laser synth via AudioSource
        final laser = voxsynth.laser();
        src.playSynth(laser);

        // Play spatial procedural explosion synth via Scene
        final explosion = voxsynth.explosion();
        final oneShotGo = engine.scene.playSynthAt(
          explosion,
          const Vec3(10, 0, 5),
        );

        expect(oneShotGo, isNotNull);
        expect(oneShotGo!.name, contains('SpatialAudioOneShot_procedural://'));
        expect(oneShotGo.transform.position.x, closeTo(10.0, 1e-4));

        final oneShotSrc = oneShotGo.getComponent<AudioSource>();
        expect(oneShotSrc, isNotNull);
        expect(oneShotSrc!.clip, isA<ProceduralAudioClip>());
        expect(
          (oneShotSrc.clip as ProceduralAudioClip).wavBytes.length,
          greaterThan(44),
        );
      },
    );

    test(
      'BehaviorTreeComponent and AiFsmComponent advance AI states in engine loop',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        var attackTicked = false;
        final tree = BehaviorTree(
          root: SequenceNode([
            ConditionNode((bb) => bb.get<int>('targetDistance') <= 5),
            ActionNode((bb) {
              attackTicked = true;
              return NodeStatus.success;
            }),
          ]),
        );
        tree.blackboard.set('targetDistance', 10);

        final go = engine.scene.createGameObject('Enemy');
        final btComp = go.addComponent(BehaviorTreeComponent(tree: tree));

        // Step 1: Distance = 10 -> condition fails, attackTicked is false
        engine.step(0.016);
        expect(attackTicked, isFalse);
        expect(btComp.lastStatus, equals(NodeStatus.failure));

        // Step 2: Distance = 3 -> condition passes, attackTicked is true
        btComp.blackboard.set('targetDistance', 3);
        engine.step(0.016);
        expect(attackTicked, isTrue);
        expect(btComp.lastStatus, equals(NodeStatus.success));

        // FSM Component test
        var patrolEntered = false;
        var alertEntered = false;

        final fsmComp = go.addComponent(
          AiFsmComponent<String>(initialState: 'patrol'),
        );
        fsmComp.addState(
          'patrol',
          LambdaState(onEnter: (_) => patrolEntered = true),
        );
        fsmComp.addState(
          'alert',
          LambdaState(onEnter: (_) => alertEntered = true),
        );
        fsmComp.addTransition(
          'patrol',
          'alert',
          (targetGo) => targetGo.transform.position.x > 10.0,
        );

        engine.step(0.016);
        expect(fsmComp.currentStateId, equals('patrol'));
        expect(patrolEntered, isTrue);
        expect(alertEntered, isFalse);

        // Move enemy beyond x = 10 -> triggers transition to alert
        go.transform.position = const Vec3(15, 0, 0);
        engine.step(0.016);
        expect(fsmComp.currentStateId, equals('alert'));
        expect(alertEntered, isTrue);
      },
    );

    test(
      'DebugController renders immediate-mode UI with metrics and rolling voxlog logs',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final ring = RingBufferSink(capacity: 10);
        final testLog = Logger(
          name: 'Engine',
          sinks: [ring],
          level: LogLevel.info,
        );
        testLog.info('Boot sequence ready');
        testLog.warn('GPU pipeline initialized');

        final debugGo = engine.scene.createGameObject('Debug');
        final dbg = debugGo.addComponent(DebugController(isOpen: true));

        engine.step(0.016);

        final ui = VoxUiContext();
        final input = VoxInput();
        ui.beginFrame(input);

        dbg.renderDebugUi(ui, ring);

        final dl = ui.endFrame();
        expect(dl.commands, isNotEmpty);
        expect(dl.commands.any((c) => c.text == 'Engine Diagnostics'), isTrue);
        expect(
          dl.commands.any(
            (c) => c.text != null && c.text!.contains('Boot sequence ready'),
          ),
          isTrue,
        );
      },
    );

    test('E29: Transform and GameObject tweening with voxtween', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.maximumDeltaTime = 10.0;

      final go = engine.scene.createGameObject('Hero');
      go.transform.position = Vec3.zero;
      go.transform.localScale = 1.0;

      var posCompleted = false;
      var scaleCompleted = false;

      go.transform
          .tweenPosition(const Vec3(10, 0, 0), 1.0, ease: Ease.linear)
          .onComplete(() => posCompleted = true);

      go
          .tweenScale(2.0, 1.0, ease: Ease.linear)
          .onComplete(() => scaleCompleted = true);

      // Step half second (0.5s)
      engine.step(0.5);
      expect(go.transform.position.x, closeTo(5.0, 1e-3));
      expect(go.transform.localScale, closeTo(1.5, 1e-3));
      expect(posCompleted, isFalse);
      expect(scaleCompleted, isFalse);

      // Step remaining half second
      engine.step(0.5);
      expect(go.transform.position.x, closeTo(10.0, 1e-3));
      expect(go.transform.localScale, closeTo(2.0, 1e-3));
      expect(posCompleted, isTrue);
      expect(scaleCompleted, isTrue);

      // Destroying GameObject cleans up active tweens
      go.transform.tweenPosition(const Vec3(100, 0, 0), 1.0);
      go.destroy();
      engine.step(0.016);
      expect(TweenManager.instance.activeCount, equals(0));
    });

    test(
      'E29: Camera frustum extraction and visibility culling with voxgeom',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final camGo = engine.scene.createGameObject('MainCamera');
        camGo.transform.position = const Vec3(0, 0, 10);
        camGo.transform.lookAt(Vec3.zero);
        final cam = camGo.addComponent(
          Camera(fovYRadians: 1.0, near: 0.1, far: 50.0),
        );

        final visibleGo = engine.scene.createGameObject('VisibleCube');
        visibleGo.transform.position = const Vec3(0, 0, 0);
        final visibleMesh = visibleGo.addComponent(MeshRenderer());

        final behindGo = engine.scene.createGameObject('BehindCube');
        behindGo.transform.position = const Vec3(0, 0, 20);
        final behindMesh = behindGo.addComponent(MeshRenderer());

        final farAwayGo = engine.scene.createGameObject('FarAwayCube');
        farAwayGo.transform.position = const Vec3(100, 0, 0);
        final farMesh = farAwayGo.addComponent(MeshRenderer());

        engine.step(0.016);

        final frustum = cam.calculateFrustum();
        expect(frustum.planes, hasLength(6));

        expect(cam.isMeshVisible(visibleMesh), isTrue);
        expect(cam.isMeshVisible(behindMesh), isFalse);
        expect(cam.isMeshVisible(farMesh), isFalse);
      },
    );

    test(
      'E29: Scene.raycastMeshes hits closest active MeshRenderer bounding box',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final cubeA = engine.scene.createGameObject('CubeNear');
        cubeA.transform.position = const Vec3(0, 0, 5);
        final meshA = cubeA.addComponent(MeshRenderer());

        final cubeB = engine.scene.createGameObject('CubeFar');
        cubeB.transform.position = const Vec3(0, 0, 15);
        cubeB.addComponent(MeshRenderer());

        engine.step(0.016);

        final ray = Ray3(const GeomVec3(0, 0, 0), const GeomVec3(0, 0, 1));
        final hit = engine.scene.raycastMeshes(ray);

        expect(hit, isNotNull);
        expect(hit!.gameObject, equals(cubeA));
        expect(hit.renderer, equals(meshA));
        expect(hit.distance, closeTo(4.5, 1e-3));
      },
    );

    test(
      'E30: NavAgent2D pathfinding, waypoint tracking, and arrival events with voxpath',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.time.maximumDeltaTime = 10.0;

        final grid = NavGrid.fromAscii(['.....', '.###.', '.....']);

        final agentGo = engine.scene.createGameObject('Minion');
        agentGo.transform.position = const Vec3(0.5, 0, 0.5);

        final agent = agentGo.addComponent(NavAgent2D(speed: 4.0, grid: grid));
        var reachedDestination = false;
        final visited = <Vec2>[];

        agent.onWaypointReached = (idx, pt) => visited.add(pt);
        agent.onDestinationReached = () => reachedDestination = true;

        // Navigate from (0, 0) around wall to (4, 2)
        final success = agent.setDestination(
          const Vec2(4.5, 2.5),
          tileSize: 1.0,
        );
        expect(success, isTrue);
        expect(agent.isMoving, isTrue);

        // Step simulation
        for (var i = 0; i < 30 && !reachedDestination; i++) {
          engine.step(0.1);
        }

        expect(reachedDestination, isTrue);
        expect(visited, isNotEmpty);
        expect(agentGo.transform.position.x, closeTo(4.5, 0.2));
        expect(agentGo.transform.position.z, closeTo(2.5, 0.2));
      },
    );

    test('E30: FlowField2DComponent crowd vector field evaluation', () {
      final grid = NavGrid.fromAscii([
        '..........',
        '..######..',
        '..........',
      ]);

      final fieldComp = FlowField2DComponent(grid: grid, tileSize: 1.0);
      fieldComp.setTarget(const GridPoint(5, 2));

      // Test steering vector in world space: must steer around the obstacle horizontally
      final steer = fieldComp.getSteeringVector(const Vec3(5.5, 0, 0.5));
      expect(steer.length, closeTo(1.0, 1e-3));
      expect(steer.x.abs(), greaterThan(0.0));
    });

    test(
      'E31: ProceduralDungeonComponent generates BSP rooms, corridors, and NavGrid',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final dungeonGo = engine.scene.createGameObject('Dungeon');
        final layer = TileLayer(
          columns: 40,
          rows: 40,
          tileWidth: 16,
          tileHeight: 16,
          tileset: [SpriteRegion.white, SpriteRegion.white],
        );
        final tilemap = dungeonGo.addComponent(
          TilemapComponent(layer, solidTiles: [1]),
        );
        final dungeon = dungeonGo.addComponent(
          ProceduralDungeonComponent(
            width: 40,
            height: 40,
            minRoomSize: 4,
            maxRoomSize: 10,
            tileSize: 2.0,
          ),
        );

        final result = dungeon.generate(customSeed: 42, targetTilemap: tilemap);

        expect(result.rooms, isNotEmpty);
        expect(dungeon.rooms, equals(result.rooms));
        expect(dungeon.roomCenters, hasLength(dungeon.rooms.length));
        expect(dungeon.navGrid, isNotNull);

        // Verify player spawn is within bounds and on a walkable floor
        final spawn = dungeon.playerSpawn;
        expect(spawn.x, greaterThan(0.0));
        expect(spawn.z, greaterThan(0.0));

        final spawnTileX = (spawn.x / 2.0).floor();
        final spawnTileZ = (spawn.z / 2.0).floor();
        expect(dungeon.navGrid!.isWalkable(spawnTileX, spawnTileZ), isTrue);
        expect(tilemap.layer.tileAt(spawnTileX, spawnTileZ), equals(1));
      },
    );

    test(
      'E31: PoissonScatterComponent distributes non-overlapping prefabs',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final scatterGo = engine.scene.createGameObject('ScatterZone');
        final scatter = scatterGo.addComponent(
          PoissonScatterComponent(
            areaWidth: 50.0,
            areaHeight: 50.0,
            minDistance: 8.0,
            seed: 999,
          ),
        );

        final positions = scatter.sampleWorldPositions();
        expect(positions, isNotEmpty);

        // Verify minimum clearance between all sampled points
        for (var i = 0; i < positions.length; i++) {
          for (var j = i + 1; j < positions.length; j++) {
            final dx = positions[i].x - positions[j].x;
            final dz = positions[i].z - positions[j].z;
            final distSq = dx * dx + dz * dz;
            expect(distSq, greaterThanOrEqualTo(7.99 * 7.99));
          }
        }

        // Instantiate prefabs into scene
        final treePrefab = Prefab('TreePrefab', (root) {
          root.addComponent(MeshRenderer());
        });

        final spawned = scatter.spawnPrefabs(treePrefab);
        expect(spawned, hasLength(positions.length));
        expect(scatterGo.children, hasLength(positions.length));
      },
    );

    test(
      'E32: RigidBody2D and BoxCollider2D fall under gravity and rest on ground',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

        // Static ground at (0, 0), size (10, 1) -> top is at y = 0.5
        final groundGo = engine.scene.createGameObject(
          'Ground',
          position: Vec3.zero,
        );
        groundGo.addComponent(
          BoxCollider2D(
            size: const Vec2(10.0, 1.0),
            friction: 0.5,
            restitution: 0.0,
          ),
        );

        // Dynamic crate at (0, 3), size (1, 1) -> halfHeight = 0.5
        final crateGo = engine.scene.createGameObject(
          'Crate',
          position: const Vec3(0.0, 3.0, 0.0),
        );
        final rb = crateGo.addComponent(
          RigidBody2D(bodyType: BodyType.dynamicBody),
        );
        crateGo.addComponent(
          BoxCollider2D(
            size: const Vec2(1.0, 1.0),
            friction: 0.5,
            restitution: 0.0,
          ),
        );

        // Step engine 60 frames (1.0s)
        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }

        // Crate should come to rest on ground: y = 0.5 + 0.5 = 1.0
        expect(crateGo.transform.position.y, closeTo(1.0, 0.05));
        expect(rb.linearVelocity.y.abs(), lessThan(0.05));
      },
    );

    test('E32: 2D Collision and Trigger Behaviour callbacks', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

      final colSpy = _CollisionSpy2D();
      final trigSpy = _TriggerSpy2D();

      final groundGo = engine.scene.createGameObject(
        'Ground',
        position: Vec3.zero,
      );
      groundGo.addComponent(BoxCollider2D(size: const Vec2(10.0, 1.0)));
      groundGo.addComponent(colSpy);

      // Sensor zone at (0, 1.5)
      final sensorGo = engine.scene.createGameObject(
        'Sensor',
        position: const Vec3(0.0, 1.5, 0.0),
      );
      sensorGo.addComponent(
        BoxCollider2D(size: const Vec2(4.0, 2.0), isTrigger: true),
      );
      sensorGo.addComponent(trigSpy);

      // Dynamic crate at (0, 3)
      final crateGo = engine.scene.createGameObject(
        'Crate',
        position: const Vec3(0.0, 3.0, 0.0),
      );
      crateGo.addComponent(RigidBody2D(bodyType: BodyType.dynamicBody));
      crateGo.addComponent(CircleCollider2D(radius: 0.5));

      for (var i = 0; i < 60; i++) {
        engine.step(1.0 / 60.0);
      }

      expect(trigSpy.entered, isTrue);
      expect(colSpy.entered, isTrue);
      expect(colSpy.lastCollision, isNotNull);
      expect(colSpy.lastCollision!.otherGameObject, equals(crateGo));
    });

    test(
      'E32: DistanceJoint2D maintains distance constraint in engine scene',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.scene.physics2D.gravity = const Vec2(0.0, -10.0);

        final anchorGo = engine.scene.createGameObject(
          'Anchor',
          position: const Vec3(0.0, 5.0, 0.0),
        );
        final anchorRb = anchorGo.addComponent(
          RigidBody2D(bodyType: BodyType.staticBody),
        );

        final bobGo = engine.scene.createGameObject(
          'Bob',
          position: const Vec3(3.0, 5.0, 0.0),
        );
        bobGo.addComponent(RigidBody2D(bodyType: BodyType.dynamicBody));
        bobGo.addComponent(CircleCollider2D(radius: 0.3));

        bobGo.addComponent(
          DistanceJoint2D(connectedBody: anchorRb, length: 3.0),
        );

        for (var i = 0; i < 60; i++) {
          engine.step(1.0 / 60.0);
        }

        final dist =
            (bobGo.transform.position - anchorGo.transform.position).length;
        expect(dist, closeTo(3.0, 0.05));
      },
    );

    test('E32: Scene.raycast2D queries 2D colliders', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final targetGo = engine.scene.createGameObject(
        'Target',
        position: const Vec3(0.0, 4.0, 0.0),
      );
      targetGo.addComponent(CircleCollider2D(radius: 1.0));

      final hit = engine.scene.raycast2D(
        const Vec2(0.0, 10.0),
        const Vec2(0.0, -1.0),
      );
      expect(hit, isNotNull);
      expect(hit!.gameObject, equals(targetGo));
      expect(hit.point.y, closeTo(5.0, 1e-3));
      expect(hit.normal.y, closeTo(1.0, 1e-3));
    });

    test('E33: NetworkManager and NetworkTransform replicate state across loopback transport', () {
      final net = LoopbackNetwork();
      final serverTransport = net.createEndpoint(0);
      final clientTransport = net.createEndpoint(1);

      final serverHost = HeadlessHost();
      final serverEngine = Engine(serverHost);
      serverEngine.scene.network.startServer(serverTransport: serverTransport);

      final clientHost = HeadlessHost();
      final clientEngine = Engine(clientHost);
      clientEngine.scene.network.startClient(1, clientTransport: clientTransport);

      // Server entity
      final serverGo = serverEngine.scene.createGameObject('Player', position: const Vec3(0.0, 0.0, 0.0));
      serverGo.addComponent(NetworkIdentity(netId: 10, ownerPeerId: 0));
      serverGo.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

      // Client proxy entity
      final clientGo = clientEngine.scene.createGameObject('PlayerProxy', position: const Vec3(0.0, 0.0, 0.0));
      clientGo.addComponent(NetworkIdentity(netId: 10, ownerPeerId: 0));
      clientGo.addComponent(NetworkTransform(interpolationDelaySeconds: 0.0));

      // Move server entity
      serverGo.transform.position = const Vec3(15.0, 2.0, -5.0);

      // Step server (broadcasts snapshot)
      serverEngine.step(0.05);

      // Step client (receives snapshot and applies interpolation)
      clientEngine.step(0.05);

      expect(clientGo.transform.position.x, closeTo(15.0, 0.01));
      expect(clientGo.transform.position.y, closeTo(2.0, 0.01));
      expect(clientGo.transform.position.z, closeTo(-5.0, 0.01));
    });

    test('E33: NetworkManager sends and dispatches RPCs', () {
      final net = LoopbackNetwork();
      final serverTransport = net.createEndpoint(0);
      final clientTransport = net.createEndpoint(1);

      final serverEngine = Engine(HeadlessHost());
      serverEngine.scene.network.startServer(serverTransport: serverTransport);

      final clientEngine = Engine(HeadlessHost());
      clientEngine.scene.network.startClient(1, clientTransport: clientTransport);

      var rpcReceived = false;
      var receivedDamage = 0;

      clientEngine.scene.network.rpc.register('applyDamage', (senderId, payload) {
        rpcReceived = true;
        receivedDamage = ByteReader(payload).readInt32();
      });

      final payload = ByteWriter()..writeInt32(85);
      serverEngine.scene.network.sendRpc(1, 'applyDamage', payload.toBytes(), recipientId: 1);

      // Step client to process network messages
      clientEngine.step(0.05);

      expect(rpcReceived, isTrue);
      expect(receivedDamage, equals(85));
    });

    test('E34: TwoBoneIkComponent solves limb kinematics towards target position', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final upperLeg = engine.scene.createGameObject('UpperLeg', position: const Vec3(0.0, 2.0, 0.0));
      final lowerLeg = engine.scene.createGameObject('LowerLeg', position: const Vec3(0.0, -1.0, 0.0), parent: upperLeg);
      final foot = engine.scene.createGameObject('Foot', position: const Vec3(0.0, -1.0, 0.0), parent: lowerLeg);

      const targetPos = Vec3(0.4, 0.2, 0.0);
      const polePos = Vec3(0.0, 1.0, 1.0);

      upperLeg.addComponent(TwoBoneIkComponent(
        rootBone: upperLeg,
        midBone: lowerLeg,
        endEffector: foot,
        targetPosition: targetPos,
        polePosition: polePos,
      ));

      engine.step(0.05);

      // Foot world position should reach target
      expect((foot.transform.position - targetPos).length, lessThan(0.05));
      // Knee bent forward towards pole (+Z)
      expect(lowerLeg.transform.position.z, greaterThan(0.0));
    });

    test('E34: AimIkComponent directs forward vector towards 3D target', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final head = engine.scene.createGameObject('Head', position: const Vec3(0.0, 1.5, 0.0));
      const targetPos = Vec3(10.0, 1.5, -10.0); // 45 deg right/forward in -Z space

      head.addComponent(AimIkComponent(
        bone: head,
        targetPosition: targetPos,
      ));

      engine.step(0.05);

      final toTarget = (targetPos - head.transform.position).normalized;
      final aimDot = head.transform.forward.dot(toTarget);
      expect(aimDot, closeTo(1.0, 0.05));
    });

    test('E34: BlendTreeComponent evaluates 1D blend tree and updates bone transforms', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final character = engine.scene.createGameObject('Character');
      final arm = engine.scene.createGameObject('Arm', parent: character);

      final idlePose = Pose({'Arm': BoneTransform(position: const AnimVec3(0.0, 1.0, 0.0))});
      final runPose = Pose({'Arm': BoneTransform(position: const AnimVec3(0.0, 1.0, 4.0))});

      final blendTree = Blend1DNode(
        parameterName: 'speed',
        entries: [
          Blend1DEntry(threshold: 0.0, node: ClipNode(name: 'Idle', duration: 1.0, sampler: (_) => idlePose)),
          Blend1DEntry(threshold: 10.0, node: ClipNode(name: 'Run', duration: 1.0, sampler: (_) => runPose)),
        ],
      );

      character.addComponent(BlendTreeComponent(
        rootNode: blendTree,
        initialParameters: {'speed': 5.0}, // 50% blend
      ));

      engine.step(0.05);

      // Arm Z position should be halfway between 0.0 and 4.0 -> 2.0
      expect(arm.transform.localPosition.z, closeTo(2.0, 1e-4));
      expect(arm.transform.localPosition.y, closeTo(1.0, 1e-4));
    });

    test('E35: Light2DComponent and ShadowCaster2DComponent evaluate 2D lighting with shadow occlusion', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final lightGo = engine.scene.createGameObject('Torch', position: const Vec3(0.0, 0.0, 0.0));
      lightGo.addComponent(Light2DComponent(
        type: Light2DType.point,
        radius: 10.0,
        intensity: 2.0,
        color: const LinearColor(1.0, 0.5, 0.0),
      ));

      // Wall at y = 4 with shadow caster
      final wallGo = engine.scene.createGameObject('Wall', position: const Vec3(0.0, 4.0, 0.0));
      wallGo.addComponent(ShadowCaster2DComponent.box(const Vec2(2.0, 0.5)));

      engine.step(0.05);

      // Point before wall is brightly illuminated
      final beforeWall = engine.scene.evaluateLight2D(const Vec2(0.0, 2.0));
      expect(beforeWall.intensity, greaterThan(1.0));
      expect(beforeWall.r, greaterThan(beforeWall.g));

      // Point behind wall is occluded in shadow
      final behindWall = engine.scene.evaluateLight2D(const Vec2(0.0, 7.0));
      expect(behindWall.intensity, equals(0.0));
    });

    test('E35: Light2DComponent calculates 2D VisibilityPolygon', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final lightGo = engine.scene.createGameObject('PlayerLight', position: const Vec3(0.0, 0.0, 0.0));
      final lightComp = lightGo.addComponent(Light2DComponent(radius: 15.0));

      // Wall occluder
      final wall = engine.scene.createGameObject('Pillar', position: const Vec3(0.0, 5.0, 0.0));
      wall.addComponent(ShadowCaster2DComponent.box(const Vec2(1.5, 0.5)));

      engine.step(0.05);

      final poly = lightComp.computeVisibilityPolygon();
      expect(poly.vertices.length, greaterThanOrEqualTo(8));

      // Free space in front of pillar is visible
      expect(poly.contains(const LightVec2(0.0, 2.5)), isTrue);
      // Behind pillar is occluded
      expect(poly.contains(const LightVec2(0.0, 8.0)), isFalse);
    });

    test('E35: FogOfWar2DComponent reveals area and blocks exploration behind shadows', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final fogGo = engine.scene.createGameObject('FogManager');
      final fogComp = fogGo.addComponent(FogOfWar2DComponent(
        width: 30,
        height: 30,
        cellSize: 1.0,
        origin: const Vec2(-15.0, -15.0),
      ));

      // Wall occluder at y = 3
      final wall = engine.scene.createGameObject('WallOccluder', position: const Vec3(0.0, 3.0, 0.0));
      wall.addComponent(ShadowCaster2DComponent.box(const Vec2(3.0, 0.5)));

      engine.step(0.05);

      // Reveal from origin with radius 8
      fogComp.reveal(Vec2.zero, 8.0);

      // Area in front of wall is visible and explored
      expect(fogComp.isVisible(const Vec2(0.0, 1.5)), isTrue);
      expect(fogComp.isExplored(const Vec2(0.0, 1.5)), isTrue);

      // Area behind wall is blocked by occluder
      expect(fogComp.isVisible(const Vec2(0.0, 5.0)), isFalse);
    });

    test('E36: AudioLowPassFilterComponent processes audio buffer', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final audioGo = engine.scene.createGameObject('AudioEmitter');
      final lpf = audioGo.addComponent(AudioLowPassFilterComponent(cutoffFrequency: 400.0));

      final buffer = List<double>.generate(100, (i) => i.isEven ? 1.0 : -1.0); // High frequency alternations
      lpf.processBuffer(buffer);

      // Filtered high-frequency buffer should have significantly attenuated amplitude
      expect(buffer.last.abs(), lessThan(0.5));
    });

    test('E36: AudioReverbZone calculates proximity wet mix', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final zoneGo = engine.scene.createGameObject('CaveReverb', position: const Vec3(0.0, 0.0, 0.0));
      final zone = zoneGo.addComponent(AudioReverbZone(
        minDistance: 5.0,
        maxDistance: 15.0,
        wet: 0.8,
      ));

      // Close to center -> 100% wet (0.8)
      expect(zone.calculateReverbMix(const Vec3(2.0, 0.0, 0.0)), closeTo(0.8, 1e-4));

      // Midpoint between min and max (dist = 10.0) -> 50% of wet (0.4)
      expect(zone.calculateReverbMix(const Vec3(10.0, 0.0, 0.0)), closeTo(0.4, 0.05));

      // Far outside zone -> 0.0
      expect(zone.calculateReverbMix(const Vec3(20.0, 0.0, 0.0)), equals(0.0));
    });

    test('E36: AudioSource.calculateSpatialDsp evaluates 3D pan and doppler pitch', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final listenerGo = engine.scene.createGameObject('Listener', position: const Vec3(0.0, 0.0, 0.0));
      final listener = listenerGo.addComponent(AudioListener());

      final sourceGo = engine.scene.createGameObject('Siren', position: const Vec3(10.0, 0.0, 0.0));
      final source = sourceGo.addComponent(AudioSource(minDistance: 1.0, maxDistance: 50.0));

      engine.step(0.05);

      final res = source.calculateSpatialDsp(
        listener: listener,
        sourceVelocity: const Vec3(-20.0, 0.0, 0.0), // Moving towards listener
      );

      // Stereo pan right
      expect(res.pan, closeTo(1.0, 1e-4));
      expect(res.rightGain, greaterThan(res.leftGain));

      // Doppler pitch shift > 1.0
      expect(res.dopplerFactor, greaterThan(1.02));
    });

    test('E37: DialogueComponent advances conversation and handles player choices', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final graph = DialogueGraph(
        entryNodeId: 'intro',
        initialNodes: [
          const DialogueNode(
            id: 'intro',
            speaker: 'Captain',
            text: 'Ready for departure, Commander?',
            choices: [
              DialogueChoice(text: 'Launch now', targetNodeId: 'launch'),
              DialogueChoice(text: 'Hold on', targetNodeId: 'hold'),
            ],
          ),
          const DialogueNode(id: 'launch', speaker: 'Captain', text: 'Engines engaged!'),
          const DialogueNode(id: 'hold', speaker: 'Captain', text: 'Standing by.'),
        ],
      );

      final npc = engine.scene.createGameObject('CaptainGo');
      final dialogue = npc.addComponent(DialogueComponent(graph: graph, autoStart: true));

      engine.step(0.05);

      expect(dialogue.isRunning, isTrue);
      expect(dialogue.speaker, equals('Captain'));
      expect(dialogue.choices.length, equals(2));

      // Choose 'Launch now' (index 0)
      dialogue.selectChoice(0);
      expect(dialogue.runner.currentNode?.id, equals('launch'));

      // Advance to end
      dialogue.advance(); // finish typewriter
      dialogue.advance(); // completes dialogue
      expect(dialogue.isComplete, isTrue);
    });

    test('E37: QuestManagerComponent registers and advances quest objectives', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final questGo = engine.scene.createGameObject('QuestManagerGo');
      final questMgr = questGo.addComponent(QuestManagerComponent());

      final quest = Quest(
        id: 'repair_thrusters',
        title: 'Fix Thruster Assembly',
        description: 'Collect 2 titanium plates to patch the thruster.',
        objectives: [
          QuestObjective(id: 'plates', description: 'Titanium Plates', targetCount: 2),
        ],
      );

      questMgr.registerQuest(quest);
      questMgr.startQuest('repair_thrusters');

      expect(questMgr.activeQuests.length, equals(1));
      expect(questMgr.variables.getString('quest_repair_thrusters_status'), equals('active'));

      // Complete objective
      questMgr.advanceObjective('repair_thrusters', 'plates', 2);
      expect(quest.isCompleted, isTrue);
      expect(questMgr.completedQuests.length, equals(1));
      expect(questMgr.variables.getString('quest_repair_thrusters_status'), equals('completed'));
    });

    test('E37: DialogueUI renders immediate-mode dialogue box with choices', () {
      final graph = DialogueGraph(
        entryNodeId: 'talk',
        initialNodes: [
          const DialogueNode(
            id: 'talk',
            speaker: 'Navigator',
            text: 'Jump coordinates locked.',
            choices: [
              DialogueChoice(text: 'Engage hyperdrive', targetNodeId: 'jump'),
            ],
          ),
          const DialogueNode(id: 'jump', speaker: 'Navigator', text: 'Jumping now!'),
        ],
      );

      final runner = DialogueRunner(graph: graph, typewriterSpeed: 0.0);
      runner.start();

      final ui = VoxUiContext();
      final input = VoxInput();
      ui.beginFrame(input);

      DialogueUI.render(ui, runner);

      final dl = ui.endFrame();

      // Should have recorded dialogue window commands
      expect(dl.commands, isNotEmpty);
      final hasNavigator = dl.commands.any(
        (cmd) => cmd.type == DrawCmdType.text && cmd.text == 'Navigator',
      );
      expect(hasNavigator, isTrue);

      final hasChoiceText = dl.commands.any(
        (cmd) => cmd.type == DrawCmdType.text && cmd.text?.contains('Engage hyperdrive') == true,
      );
      expect(hasChoiceText, isTrue);
    });

    test('E38: VisualEffectComponent integrates voxvfx simulation with GameObject transform', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final fireVfx = VisualEffectComponent.fire(maxParticles: 100);
      final go = engine.scene.createGameObject('Torch', components: [fireVfx]);
      go.transform.position = const Vec3(10.0, 5.0, -2.0);

      expect(fireVfx.simulation.activeParticleCount, 0);

      // Step engine -> should update emitter position and spawn particles
      engine.step(0.1);

      expect(fireVfx.simulation.emitterPosition.x, closeTo(10.0, 1e-4));
      expect(fireVfx.simulation.emitterPosition.y, closeTo(5.0, 1e-4));
      expect(fireVfx.simulation.emitterPosition.z, closeTo(-2.0, 1e-4));
      expect(fireVfx.simulation.activeParticleCount, greaterThan(0));

      // Test manual burst and clear
      fireVfx.burst(15);
      final countAfterBurst = fireVfx.simulation.activeParticleCount;
      expect(countAfterBurst, greaterThanOrEqualTo(15));

      fireVfx.clear();
      expect(fireVfx.simulation.activeParticleCount, 0);
    });

    test('E38: VisualEffectComponent.explosion triggers burst forces', () {
      final explosion = VisualEffectComponent.explosion(particleCount: 50);
      expect(explosion.simulation.activeParticleCount, 0);

      // Advance simulation step -> burst triggered at time 0
      explosion.step(0.016);
      expect(explosion.simulation.activeParticleCount, 50);

      for (final p in explosion.simulation.activeParticles) {
        expect(p.velocity.length, greaterThan(0.0));
      }
    });

    test('E39: VoxelTerrainComponent builds terrain, performs 3D DDA raycasts, and carves cavities', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final terrain = VoxelTerrainComponent();
      final go = engine.scene.createGameObject('VoxelWorld', components: [terrain]);
      go.transform.position = const Vec3(0, 0, 0);

      // Fill a solid 4x4x4 block of stone
      terrain.fillBox(
        const VoxelCoord(0, 0, 0),
        const VoxelCoord(3, 3, 3),
        1, // Stone
      );

      // Verify voxel data
      expect(terrain.getVoxel(1, 1, 1), equals(1));
      expect(terrain.getVoxel(5, 5, 5), equals(0));

      // Raycast from (1.5, 10.0, 1.5) downward (0, -1, 0)
      final hit = terrain.raycastVoxel(
        const Vec3(1.5, 10.0, 1.5),
        const Vec3(0.0, -1.0, 0.0),
        maxDistance: 20.0,
      );

      expect(hit, isNotNull);
      expect(hit!.hitVoxel, equals(const VoxelCoord(1, 3, 1)));
      expect(hit.normal.y, closeTo(1.0, 1e-4)); // hit top face pointing +Y
      expect(hit.adjacentEmptyVoxel, equals(const VoxelCoord(1, 4, 1))); // block above

      // Rebuild greedy meshes
      final meshes = terrain.rebuildAllMeshes();
      expect(meshes, isNotEmpty);
      final mesh = meshes.values.first;
      // 4x4x4 cube faces merged into 6 quads
      expect(mesh.quadCount, equals(6));

      // Carve sphere at (1, 1, 1)
      final carved = terrain.carveSphere(const VoxelCoord(1, 1, 1), 1.5);
      expect(carved, greaterThan(0));
      expect(terrain.getVoxel(1, 1, 1), equals(0));
    });

    test('E40: InputManagerComponent processes WASD Vector2, chord combos, and ActionMap priorities', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final im = InputManagerComponent();
      final gameplay = im.actions.addMap('Gameplay', priority: 0);
      gameplay.addVector2('Move', [Vector2Binding.wasd]);
      gameplay.addButton('Jump', [const KeyBinding('Space')]);
      gameplay.addButton('QuickSave', [const ChordBinding(['ControlLeft', 'KeyS'])]);

      final pauseMenu = im.actions.addMap('Menu', priority: 10, enabled: false, blocksLowerMaps: true);
      pauseMenu.addButton('Confirm', [const KeyBinding('Space')]);

      engine.scene.createGameObject('InputSystem', components: [im]);

      // Press W + D for diagonal normalized movement
      host.input.press('KeyW');
      host.input.press('KeyD');
      engine.step(0.016);
      host.input.endFrame();

      final move = im.getVector2('Move');
      expect(move.length, closeTo(1.0, 1e-3));
      expect(move.x, closeTo(0.7071, 1e-3));
      expect(move.y, closeTo(0.7071, 1e-3));

      // QuickSave chord Ctrl+S
      host.input.press('ControlLeft');
      engine.step(0.016);
      expect(im.isPressed('QuickSave'), isFalse);

      host.input.press('KeyS');
      engine.step(0.016);
      expect(im.wasPressed('QuickSave'), isTrue);

      // Pause Menu active -> Space is consumed by Menu and blocked from Gameplay Jump
      pauseMenu.enabled = true;
      host.input.press('Space');
      engine.step(0.016);
      expect(im.isPressed('Menu/Confirm'), isTrue);
      expect(im.isPressed('Gameplay/Jump'), isFalse);
    });

    test('E40: InputManagerComponent interactive rebinding + storage profile persistence', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final im = InputManagerComponent();
      final gameplay = im.actions.addMap('Gameplay');
      final jump = gameplay.addButton('Jump', [const KeyBinding('Space')]);
      engine.scene.createGameObject('InputSystem', components: [im]);

      // Start rebinding Jump
      String? boundControl;
      im.rebinder.startListening(
        map: gameplay,
        action: jump,
        onCompleted: (ctrl) => boundControl = ctrl,
      );

      // Step frame where player presses KeyF
      host.input.press('KeyF');
      engine.step(0.016);
      host.input.endFrame();

      expect(boundControl, equals('KeyF'));
      expect(im.isPressed('Jump'), isTrue);

      // Save profile to host.storage
      im.saveProfile('player_controls');

      // Reload into a fresh engine & InputManagerComponent sharing host storage
      final engine2 = Engine(host);
      final im2 = InputManagerComponent();
      final gameplay2 = im2.actions.addMap('Gameplay');
      gameplay2.addButton('Jump', [const KeyBinding('Space')]);
      engine2.scene.createGameObject('InputSystem2', components: [im2]);

      expect(im2.loadProfile('player_controls'), isTrue);
      final loadedBinding = im2.action('Jump')!.bindings.first as KeyBinding;
      expect(loadedBinding.control, equals('KeyF'));
    });

    test('E40: VirtualGamepad drives InputManagerComponent actions and renders via VirtualGamepadUI', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final vpad = VirtualGamepad(
        sticks: [
          VirtualStick(
            centerX: 80,
            centerY: 280,
            radius: 40,
            axisXName: 'VirtualLeftX',
            axisYName: 'VirtualLeftY',
          ),
        ],
        buttons: [
          VirtualButton(
            centerX: 520,
            centerY: 280,
            radius: 30,
            controlName: 'GamepadA',
            label: 'A',
          ),
        ],
      );

      final im = InputManagerComponent(virtualGamepad: vpad);
      final mobile = im.actions.addMap('Mobile');
      mobile.addVector2('Move', [
        const Vector2Binding(analogX: 'VirtualLeftX', analogY: 'VirtualLeftY'),
      ]);
      mobile.addButton('Fire', [const KeyBinding('GamepadA')]);
      engine.scene.createGameObject('MobileInput', components: [im]);

      // Multi-touch: finger 1 pulls stick left-up, finger 2 holds Fire button
      im.feedVirtualPointers([
        const VirtualTouchPointer(id: 1, x: 80, y: 280, isDown: true),
        const VirtualTouchPointer(id: 2, x: 520, y: 280, isDown: true),
      ]);
      engine.step(0.016);
      expect(im.isPressed('Fire'), isTrue);

      // Move finger 1 right to edge (+40px -> +1.0 X)
      im.feedVirtualPointers([
        const VirtualTouchPointer(id: 1, x: 120, y: 280, isDown: true),
      ]);
      engine.step(0.016);
      expect(im.getVector2('Move').x, closeTo(1.0, 1e-4));
      expect(im.isPressed('Fire'), isFalse);

      // Verify VirtualGamepadUI renders circles and button label
      final ui = VoxUiContext();
      ui.beginFrame(VoxInput());
      VirtualGamepadUI.render(ui, vpad);
      final dl = ui.endFrame();
      expect(dl.commands.any((c) => c.type == DrawCmdType.circleFilled), isTrue);
      expect(dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'A'), isTrue);
    });

    test('E41: InventoryComponent & StatsComponent handle spatial equip swaps, stat buffs & storage persistence', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final greatsword = ItemDefinition(
        id: 'greatsword',
        name: 'Titanium Greatsword',
        gridWidth: 2,
        gridHeight: 3,
        rarity: ItemRarity.legendary,
        equipSlot: 'MainHand',
        equipModifiers: [
          StatModifier(statName: 'attack', value: 30.0),
          StatModifier(statName: 'attack', value: 0.2, type: StatModifierType.percentAdd),
        ],
      );
      const healingCell = ItemDefinition(
        id: 'medkit',
        name: 'Nano Medkit',
        maxStack: 5,
        rarity: ItemRarity.rare,
      );

      final reg = ItemRegistry()..registerAll([greatsword, healingCell]);

      final statsComp = StatsComponent({'attack': 10.0});
      final invComp = InventoryComponent(gridWidth: 5, gridHeight: 4);
      engine.scene.createGameObject('Player', components: [invComp, statsComp]);

      final swordStack = ItemStack(greatsword);
      final medStack = ItemStack(healingCell, quantity: 3);
      expect(invComp.addItem(swordStack), equals(0));
      expect(invComp.addItem(medStack), equals(0));

      // Equip greatsword from grid -> base 10 + 30 = 40, * 1.2 = 48.0 attack
      expect(invComp.equipFromInventory('MainHand', swordStack), isTrue);
      expect(statsComp.getValue('attack'), closeTo(48.0, 1e-4));
      expect(invComp.grid.countById('greatsword'), equals(0));

      // Unequip back to inventory -> returns to base 10.0
      expect(invComp.unequipToInventory('MainHand'), isTrue);
      expect(statsComp.getValue('attack'), closeTo(10.0, 1e-4));
      expect(invComp.grid.countById('greatsword'), equals(1));

      // Save & restore inventory grid via host.storage
      invComp.saveToStorage('hero_bag');
      invComp.grid.clear();
      expect(invComp.grid.countById('medkit'), equals(0));
      expect(invComp.loadFromStorage(reg, 'hero_bag'), isTrue);
      expect(invComp.grid.countById('medkit'), equals(3));

      // Render InventoryUI using voxui
      final ui = VoxUiContext();
      ui.beginFrame(VoxInput());
      InventoryUI.render(ui, invComp);
      final dl = ui.endFrame();
      expect(dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'Titanium Greatsword'), isTrue);
      expect(dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'x3'), isTrue);
    });

    test('E42: TimeRewindComponent records Transform & custom binary state and rewinds back cleanly', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.fixedDeltaTime = 0.1;

      var health = 100;
      final rewind = TimeRewindComponent(
        maxFrames: 100,
        onCaptureState: (w) => w.writeVarInt(health),
        onRestoreState: (r) => health = r.readVarInt(),
      );

      final player = engine.scene.createGameObject('ChronoHero', components: [rewind]);

      // Advance 5 fixed steps moving +2m per step while losing health
      for (int i = 1; i <= 5; i++) {
        player.transform.position = Vec3(i * 2.0, 0.0, 0.0);
        health = 100 - i * 10;
        engine.step(0.1);
      }

      expect(player.transform.position.x, closeTo(10.0, 1e-3));
      expect(health, equals(50));
      expect(rewind.recordedFrames, equals(5));

      // Rewind continuously for 0.3s back in time (3 steps backward from 0.5s -> 0.2s)
      rewind.beginRewind();
      for (int i = 0; i < 3; i++) {
        engine.step(0.1);
      }

      expect(player.transform.position.x, closeTo(4.0, 1e-2));
      expect(health, equals(80));

      // Resume live gameplay from rewound time and verify future timeline branched cleanly
      rewind.stopRewind();
      expect(rewind.recordedFrames, equals(2));
    });

    test('E42: GhostRecorderComponent exports binary GhostTrack and GhostPlaybackComponent replays smoothly', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final recorder = GhostRecorderComponent(sampleInterval: 0.1);
      final racer = engine.scene.createGameObject('Racer', components: [recorder]);

      for (int i = 0; i <= 10; i++) {
        racer.transform.position = Vec3(i * 1.0, 0.0, 0.0);
        engine.step(0.1);
      }

      final bytes = recorder.exportBinary();
      expect(bytes, isNotEmpty);

      // Replay in a fresh ghost object using binary decode
      final playback = GhostPlaybackComponent.fromBinary(bytes, loop: false);
      final ghost = engine.scene.createGameObject('GhostRacer', components: [playback]);

      // Advance 5 frames of 0.1s (= 0.5s elapsed, respecting Time.maximumDeltaTime clamp)
      for (int i = 0; i < 5; i++) {
        engine.step(0.1);
      }
      expect(ghost.transform.position.x, closeTo(5.0, 1.0));
    });

    test('E43: FlowGraphComponent drives GameObject transforms, delays & signals in scene loop', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final g = FlowGraph(name: 'MoverGraph', registry: EngineFlowNodes.createRegistry());
      final onUpdate = g.addNode('event.update');
      final mulSpeed = g.addNode('math.mul', inputs: {'b': 10.0});
      final makeDelta = g.addNode('vec.make3');
      final translate = g.addNode('engine.translate');

      g.connect(onUpdate.id, 'out', translate.id, 'in');
      g.connect(onUpdate.id, 'dt', mulSpeed.id, 'a');
      g.connect(mulSpeed.id, 'result', makeDelta.id, 'x');
      g.connect(makeDelta.id, 'vec', translate.id, 'delta');

      // Also test latent delay -> signal -> deactivate
      final onEvt = g.addNode('event.custom', properties: {'event': 'DeactivateSoon'});
      final delay = g.addNode('flow.delay', inputs: {'seconds': 0.2});
      final emit = g.addNode('signal.emit', inputs: {'payload': 42}, properties: {'signal': 'done'});
      final deactivate = g.addNode('engine.setActive', inputs: {'active': false});

      g.connect(onEvt.id, 'out', delay.id, 'in');
      g.connect(delay.id, 'completed', emit.id, 'in');
      g.connect(emit.id, 'out', deactivate.id, 'in');

      final signals = <(String, Object?)>[];
      final flowComp = FlowGraphComponent(
        g,
        onSignal: (sig, payload) => signals.add((sig, payload)),
      );
      final go = engine.scene.createGameObject('Bot', components: [flowComp]);

      // 4 frames * 0.05s * 10.0 speed = 2.0m along X
      for (int i = 0; i < 4; i++) {
        engine.step(0.05);
      }
      expect(go.transform.position.x, closeTo(2.0, 1e-4));

      // Trigger custom latent event
      flowComp.triggerEvent('DeactivateSoon');
      expect(go.activeSelf, isTrue);
      engine.step(0.1);
      expect(signals, isEmpty);
      engine.step(0.12);
      expect(signals, [('done', 42)]);
      expect(go.activeSelf, isFalse);
    });

    test('E43: FlowGraphUI renders node canvas, wire preview and interactive pin linking via voxui', () {
      final g = FlowGraph();
      final src = g.addNode('math.constFloat', x: 40.0, y: 40.0, properties: {'value': 7.0});
      final dst = g.addNode('math.add', x: 260.0, y: 40.0);

      final ui = VoxUiContext();
      final state = FlowGraphUiState();

      // Compute exact canvas offset matching FlowGraphUI.render(x: 20, y: 20)
      final canvasX = 20.0 + 6.0;
      final canvasY = 20.0 + ui.style.titleBarHeight + 4.0;
      final outPinX = canvasX + src.x + 170.0 - 10.0;
      final outPinY = canvasY + src.y + 22.0 + 12.0;
      final inPinX = canvasX + dst.x + 10.0;
      final inPinY = canvasY + dst.y + 22.0 + 12.0;

      // Frame 1: click output pin on src node
      ui.beginFrame(VoxInput(mouseX: outPinX, mouseY: outPinY, isMouseDown: true, wasMouseClicked: true));
      FlowGraphUI.render(ui, g, state: state, x: 20, y: 20, width: 620, height: 400);
      final cmds1 = ui.endFrame();
      expect(state.linkingFromNodeId, src.id);
      expect(cmds1.commands.where((c) => c.type == DrawCmdType.line), isNotEmpty);

      // Frame 2: drag across canvas
      ui.beginFrame(VoxInput(mouseX: (outPinX + inPinX) * 0.5, mouseY: outPinY, isMouseDown: true));
      FlowGraphUI.render(ui, g, state: state, x: 20, y: 20, width: 620, height: 400);
      ui.endFrame();

      // Frame 3: release over input pin on dst node -> connects link cleanly
      ui.beginFrame(VoxInput(mouseX: inPinX, mouseY: inPinY, wasMouseReleased: true));
      FlowGraphUI.render(ui, g, state: state, x: 20, y: 20, width: 620, height: 400);
      ui.endFrame();

      expect(g.links.length, 1);
      expect(g.links.first.fromNodeId, src.id);
      expect(g.links.first.toNodeId, dst.id);
      expect(DataflowEvaluator(g).evaluateOutput(dst.id, 'result'), closeTo(7.0, 1e-6));
    });

    test('E44: HexGridComponent projects world coords, runs WFC biomes, paths, reachability & FOV', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final grid = HexGridComponent.radial(radius: 3, hexSize: 2.0);
      engine.scene.createGameObject(
        'TacticalBoard',
        position: const Vec3(10, 0, -5),
        components: [grid],
      );

      const targetHex = HexCoord(1, -1);
      final worldPos = grid.hexToWorld(targetHex);
      expect(grid.worldToHex(worldPos), targetHex);

      final rules = WfcRuleSet<String>.hex()
        ..addTile('grass', weight: 4.0)
        ..addTile('hills', weight: 2.0)
        ..addTile('mountain', weight: 1.0);
      for (int d = 0; d < 6; d++) {
        rules.allow('grass', d, 'grass');
        rules.allow('grass', d, 'hills');
        rules.allow('hills', d, 'hills');
        rules.allow('hills', d, 'mountain');
        rules.allow('mountain', d, 'mountain');
      }

      final ok = grid.generateWfcBiomes(
        rules: rules,
        seed: 42,
        preplaced: {
          HexCoord.zero: 'hills',
          const HexCoord(1, 0): 'mountain',
        },
        terrainCatalog: const {
          'grass': (moveCost: 1.0, passable: true, blocksSight: false),
          'hills': (moveCost: 2.0, passable: true, blocksSight: false),
          'mountain': (moveCost: 99.0, passable: false, blocksSight: true),
        },
      );
      expect(ok, isTrue);
      expect(grid.map[HexCoord.zero]!.terrain, 'hills');
      expect(grid.map[const HexCoord(1, 0)]!.passable, isFalse);

      // Visibility blocked directly behind mountain at (1, 0)
      final visible = grid.computeVisible(HexCoord.zero, radius: 3);
      expect(visible.contains(const HexCoord(1, 0)), isTrue);
      expect(visible.contains(const HexCoord(2, 0)), isFalse);

      // Reachability respects movement budget and avoids mountain
      final reach = grid.reachableFrom(HexCoord.zero, 2.0);
      expect(reach.canReach(const HexCoord(1, 0)), isFalse);
      expect(reach.canReach(HexCoord.zero), isTrue);
    });

    test('E44: WfcTilemapGenerator populates TileLayer and HexGridUI renders & picks hovered hex', () {
      final layer = TileLayer(
        columns: 6,
        rows: 5,
        tileWidth: 16,
        tileHeight: 16,
        tileset: [SpriteRegion.white, SpriteRegion.white, SpriteRegion.white],
      );
      final rules = WfcRuleSet<int>.grid2d()
        ..addSocketTile(0, ['g', 'g', 'g', 'g'], weight: 3.0)
        ..addSocketTile(1, ['g', 'r', 'g', 'r'], weight: 1.0)
        ..addSocketTile(2, ['r', 'g', 'r', 'g'], weight: 1.0);

      final filled = WfcTilemapGenerator.populate(
        layer: layer,
        rules: rules,
        seed: 9,
        preplaced: {(2, 2): 1},
      );
      expect(filled, isTrue);
      expect(layer.tileAt(2, 2), 1);

      final grid = HexGridComponent.radial(radius: 2, hexSize: 1.0);
      grid.map[const HexCoord(1, 0)]!.passable = false;

      final ui = VoxUiContext();
      // Window at (20, 20, 360, 340) places center at (200, 20 + 26 + 314*0.5 = 203)
      final centerX = 20.0 + 360.0 * 0.5;
      final centerY = 20.0 + ui.style.titleBarHeight + (340.0 - ui.style.titleBarHeight) * 0.5;
      ui.beginFrame(VoxInput(mouseX: centerX, mouseY: centerY));
      final hovered = HexGridUI.render(
        ui,
        grid,
        x: 20,
        y: 20,
        width: 360,
        height: 340,
        selectedHex: HexCoord.zero,
        reachable: {const HexCoord(-1, 0), const HexCoord(0, -1)},
        path: const [HexCoord.zero, HexCoord(-1, 0)],
      );
      final cmds = ui.endFrame();

      expect(hovered, HexCoord.zero);
      expect(cmds.commands.where((c) => c.type == DrawCmdType.line).length, greaterThan(100));
    });

    test('E45: StatusEffectComponent syncs buffs with StatsComponent, ticks DoTs, absorbs damage & cooldowns', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final stats = StatsComponent({'attack': 20.0, 'armor': 20.0});
      final combat = StatusEffectComponent(maxHp: 100.0);
      engine.scene.createGameObject('Paladin', components: [stats, combat]);

      const warcry = StatusEffectDef(
        id: 'warcry',
        name: 'Warcry',
        duration: 2.0,
        maxStacks: 2,
        stackPolicy: StatusStackPolicy.stackIntensity,
        statBonuses: {
          'attack': StatBonusSpec(flat: 5.0),
          'armor': StatBonusSpec(flat: 40.0),
        },
        absorbShieldAmount: 15.0,
      );
      const burn = StatusEffectDef(
        id: 'burn',
        name: 'Burn',
        duration: 1.5,
        tickInterval: 0.5,
        damagePerTick: 10.0,
        damageType: DamageTypes.fire,
      );

      // Apply 2 stacks -> +10 attack (total 30), +80 armor (total 100), 30 shield
      combat.applyStatus(warcry);
      combat.applyStatus(warcry);
      expect(stats.getValue('attack'), closeTo(30.0, 1e-4));
      expect(stats.getValue('armor'), closeTo(100.0, 1e-4));
      expect(combat.statuses.totalShield, closeTo(30.0, 1e-4));

      // Take 40 physical damage: 100 armor gives 50% mitigation -> 20 dmg, fully absorbed by 30 shield!
      final hitRes = combat.takeDamage(
        const DamagePacket(baseAmount: 40.0),
        forceCrit: false,
        forceDodge: false,
        forceBlock: false,
      );
      expect(hitRes.absorbedByShield, closeTo(20.0, 1e-4));
      expect(hitRes.finalDamage, closeTo(0.0, 1e-4));
      expect(combat.statuses.totalShield, closeTo(10.0, 1e-4));

      // Cooldown tracking + DoT burn over 1.0s (2 ticks * 10 fire = 20 dmg -> 10 shield + 10 HP lost)
      combat.cooldowns.start('slash', 1.0);
      expect(combat.cooldowns.isReady('slash'), isFalse);

      combat.applyStatus(burn);
      for (int i = 0; i < 10; i++) {
        engine.step(0.1);
      }
      expect(combat.currentHp, closeTo(90.0, 1e-3));
      expect(combat.cooldowns.isReady('slash'), isTrue);

      // Advance remaining 1.1s so warcry (2.0s total) expires and cleans up StatsComponent modifiers
      for (int i = 0; i < 11; i++) {
        engine.step(0.1);
      }
      expect(combat.statuses.hasStatus('warcry'), isFalse);
      expect(stats.getValue('attack'), closeTo(20.0, 1e-4));
      expect(stats.getValue('armor'), closeTo(20.0, 1e-4));
    });

    test('E45: TurnEncounterComponent syncs stun state & CombatHudUI renders buffs/turn bar via voxui', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final heroStatus = StatusEffectComponent(maxHp: 120.0, currentHp: 85.0);
      final orcStatus = StatusEffectComponent(maxHp: 80.0);
      final encounter = TurnEncounterComponent(mode: TurnMode.speedGauge);

      engine.scene.createGameObject('Hero', components: [heroStatus]);
      engine.scene.createGameObject('Orc', components: [orcStatus]);
      engine.scene.createGameObject('Encounter', components: [encounter]);

      encounter.registerParticipant(
        CombatantSlot(id: 'hero', name: 'Hero', speed: 25.0),
        statusComponent: heroStatus,
      );
      encounter.registerParticipant(
        CombatantSlot(id: 'orc', name: 'Orc', speed: 20.0),
        statusComponent: orcStatus,
      );

      // Stun orc -> Hero gets back-to-back turns
      orcStatus.applyStatus(const StatusEffectDef(
        id: 'stun',
        name: 'Stunned',
        duration: 2.0,
        stopsTurnAction: true,
      ));
      expect(encounter.advanceTurn()!.id, 'hero');
      expect(encounter.advanceTurn()!.id, 'hero');

      heroStatus.cooldowns.start('Fireball', 4.0);
      final ui = VoxUiContext();
      ui.beginFrame(VoxInput());
      CombatHudUI.render(ui, heroStatus, encounter: encounter, abilities: const ['Fireball']);
      final drawList = ui.endFrame();
      expect(drawList.commands.where((c) => c.text != null && c.text!.contains('Next Turns')), isNotEmpty);
      expect(drawList.commands.where((c) => c.text != null && c.text!.contains('HP 85/120')), isNotEmpty);
    });

    test('E46: CutsceneDirectorComponent animates transforms, toggles active camera shots, subtitles & cues', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final hero = engine.scene.createGameObject('Hero');
      final wideCam = Camera();
      final closeCam = Camera();
      engine.scene.createGameObject('WideCam', components: [wideCam]);
      engine.scene.createGameObject('CloseCam', components: [closeCam]);

      final eventsFired = <String>[];
      final audioCuesFired = <String>[];
      var completed = false;

      final director = CutsceneDirectorComponent(
        duration: 2.0,
        onEvent: (m) => eventsFired.add(m.name),
        onCompleted: () => completed = true,
      );
      director.bindPosition('hero_pos', hero)
        ..addKey(0.0, const SeqVec3(0, 0, 0))
        ..addKey(2.0, const SeqVec3(10, 0, 0));
      director.bindCameras('cams', {'Wide': wideCam, 'Close': closeCam})
        ..addShot(0.0, 1.0, 'Wide')
        ..addShot(1.0, 2.0, 'Close');
      director.bindSubtitles('subs').addClip(0.5, 1.8, 'Captain', 'All units advance!');
      director.bindAudioCues('sfx', onTriggerCue: (cue) => audioCuesFired.add(cue.clipKey))
          .addCue(0.25, 'sfx/horn.wav', duration: 0.5);
      director.sequence.addTrack(EventTrack(id: 'cues')..addEvent(1.5, 'spawnWave'));

      engine.scene.createGameObject('CutsceneDirector', components: [director]);
      director.play(fromStart: true);

      // Step to t = 0.3
      for (int i = 0; i < 3; i++) {
        engine.step(0.1);
      }
      expect(hero.transform.position.x, closeTo(1.5, 1e-3));
      expect(wideCam.isActiveAndEnabled, isTrue);
      expect(closeCam.isActiveAndEnabled, isFalse);
      expect(audioCuesFired, ['sfx/horn.wav']);
      expect(director.activeSubtitle, isNull);

      // Step to t = 1.2
      for (int i = 0; i < 9; i++) {
        engine.step(0.1);
      }
      expect(hero.transform.position.x, closeTo(6.0, 1e-3));
      expect(wideCam.isActiveAndEnabled, isFalse);
      expect(closeCam.isActiveAndEnabled, isTrue);
      expect(director.activeSubtitle?.speaker, 'Captain');

      // Step to completion at t = 2.0+
      for (int i = 0; i < 9; i++) {
        engine.step(0.1);
      }
      expect(eventsFired, ['spawnWave']);
      expect(completed, isTrue);
      expect(director.isPlaying, isFalse);
      expect(hero.transform.position.x, closeTo(10.0, 1e-3));
    });

    test('E46: TimelineSequencerUI renders tracks, toggles transport Play & scrubs playhead via voxui', () {
      final posTrack = ValueTrack.vec3(id: 'pos')
        ..addKey(0.0, const SeqVec3(0, 0, 0))
        ..addKey(4.0, const SeqVec3(8, 0, 0));
      final camTrack = CameraCutTrack(id: 'cams')..addShot(0.0, 4.0, 'MainCam');

      final sequence = TimelineSequence(duration: 4.0)
        ..addTrack(posTrack)
        ..addTrack(camTrack);

      final ui = VoxUiContext();
      final state = TimelineSequencerUiState();

      // Compute exact button/ruler coordinates matching TimelineSequencerUI.render(x: 20, y: 20, width: 560)
      final playBtnX = 20.0 + ui.style.windowPadding + 20.0;
      final playBtnY = 20.0 + ui.style.titleBarHeight + ui.style.windowPadding + 10.0;

      // Press & release Play button
      ui.beginFrame(VoxInput(mouseX: playBtnX, mouseY: playBtnY, isMouseDown: true, wasMouseClicked: true));
      TimelineSequencerUI.render(ui, sequence, state: state, subtitlePreview: 'Ready!', x: 20, y: 20, width: 560, height: 280);
      ui.endFrame();

      ui.beginFrame(VoxInput(mouseX: playBtnX, mouseY: playBtnY, wasMouseReleased: true));
      TimelineSequencerUI.render(ui, sequence, state: state, subtitlePreview: 'Ready!', x: 20, y: 20, width: 560, height: 280);
      ui.endFrame();
      expect(sequence.isPlaying, isTrue);

      // Scrub to 50% of ruler (rulerX = 20 + 10 + 132 = 162, rulerW = 560 - 20 - 132 = 408)
      final rulerMidX = 162.0 + 408.0 * 0.5;
      final rulerMidY = 20.0 + ui.style.titleBarHeight + ui.style.windowPadding + 30.0 + 10.0;
      ui.beginFrame(VoxInput(mouseX: rulerMidX, mouseY: rulerMidY, isMouseDown: true, wasMouseClicked: true));
      TimelineSequencerUI.render(ui, sequence, state: state, subtitlePreview: 'Ready!', x: 20, y: 20, width: 560, height: 280);
      final dl = ui.endFrame();

      expect(sequence.currentTime, closeTo(2.0, 1e-3));
      expect(posTrack.evaluate(sequence.currentTime), const SeqVec3(4, 0, 0));
      expect(dl.commands.any((c) => c.type == DrawCmdType.circleFilled), isTrue);
      expect(dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'Ready!'), isTrue);
    });

    test('E47: ProgressionStatsComponent tracks combos, unlocks composable achievements & persists storage', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      final stats = ProgressionStatsComponent(
        comboDecayDuration: 1.0,
        comboMultiplierStep: 0.5,
        toastDisplayDuration: 2.0,
      );
      stats.registerAchievements([
        const AchievementDef(
          id: 'chain5',
          title: 'Combo Apprentice',
          description: 'Reach a 5-hit combo',
          points: 15,
          condition: MetricThresholdCondition('best_combo', 5),
        ),
        const AchievementDef(
          id: 'ace_pilot',
          title: 'Ace Pilot',
          description: 'Defeat 3 bosses and reach combo rank C',
          points: 40,
          condition: AllOfConditions([
            EventCountCondition('boss_down', requiredCount: 3),
            MetricThresholdCondition('best_combo', 5),
          ]),
        ),
      ]);
      engine.scene.createGameObject('GameStats', components: [stats]);

      // Hit 5 times -> hits best_combo == 5 -> unlocks 'chain5'
      for (int i = 0; i < 5; i++) {
        stats.registerComboHit(basePoints: 100.0);
      }
      expect(stats.combo.rank, ComboRank.c);
      expect(stats.combo.multiplier, closeTo(3.0, 1e-6));
      expect(stats.achievements.isUnlocked('chain5'), isTrue);
      expect(stats.achievements.isUnlocked('ace_pilot'), isFalse);

      // Step once so active toast dequeues, render HUD & submit leaderboard score
      engine.step(0.1);
      expect(stats.activeToast?.id, 'chain5');
      stats.submitScore('arcade', playerId: 'p1', displayName: 'Nova', score: stats.combo.totalScore);

      final ui = VoxUiContext();
      ui.beginFrame(VoxInput());
      AchievementsHudUI.render(ui, stats, leaderboardId: 'arcade');
      final drawList = ui.endFrame();
      expect(drawList.commands.any((c) => c.text != null && c.text!.contains('UNLOCKED: Combo Apprentice')), isTrue);
      expect(drawList.commands.any((c) => c.text != null && c.text!.contains('#1 Nova')), isTrue);

      // Emit 3 boss events -> unlocks 'ace_pilot'
      for (int i = 0; i < 3; i++) {
        stats.emitEvent('boss_down');
      }
      expect(stats.achievements.isUnlocked('ace_pilot'), isTrue);

      // Decay combo after 1.1s (Time.maximumDeltaTime clamps single steps to 0.1s)
      for (int i = 0; i < 10; i++) {
        engine.step(0.1);
      }
      expect(stats.combo.count, 0);

      // Persist & reload into fresh engine sharing host storage
      stats.saveToStorage('profile_e47');
      final engine2 = Engine(host);
      final stats2 = ProgressionStatsComponent();
      stats2.registerAchievements(stats.achievements.all.map((a) => a.def));
      engine2.scene.createGameObject('GameStats2', components: [stats2]);
      expect(stats2.loadFromStorage('profile_e47'), isTrue);
      expect(stats2.achievements.isUnlocked('ace_pilot'), isTrue);
      expect(stats2.leaderboards['arcade']!.top().single.displayName, 'Nova');
    });
  });
}

final class _PointerSpy extends Behaviour {
  final List<String> events = [];
  PointerRaycastHit? lastHit;

  @override
  void onPointerEnter(PointerRaycastHit hit) {
    events.add('enter');
    lastHit = hit;
  }

  @override
  void onPointerExit(PointerRaycastHit hit) {
    events.add('exit');
    lastHit = hit;
  }

  @override
  void onPointerDown(PointerRaycastHit hit) {
    events.add('down');
    lastHit = hit;
  }

  @override
  void onPointerUp(PointerRaycastHit hit) {
    events.add('up');
    lastHit = hit;
  }

  @override
  void onPointerClick(PointerRaycastHit hit) {
    events.add('click');
    lastHit = hit;
  }
}

final class _HeadlessResources implements ResourceLibrary {
  final HeadlessGraphics graphics;
  _HeadlessResources(this.graphics);

  @override
  MeshHandle registerMesh(MeshData data, {String? debugLabel}) =>
      graphics.createMesh(data, debugLabel: debugLabel);

  @override
  MaterialHandle registerMaterial(MaterialDefinition definition) =>
      graphics.createMaterial(definition);

  // `Invocation` is shadowed by the engine's invoke handle, so widen the
  // parameter to Object (a valid override) and forward dynamically.
  @override
  dynamic noSuchMethod(Object invocation) =>
      super.noSuchMethod(invocation as dynamic);
}

final class _CollisionSpy extends Behaviour {
  final void Function(Collision) onHit;
  _CollisionSpy(this.onHit);

  @override
  void onCollisionEnter(Collision collision) => onHit(collision);
}

final class _CollisionSpy2D extends Behaviour {
  bool entered = false;
  Collision2D? lastCollision;

  @override
  void onCollisionEnter2D(Collision2D collision) {
    entered = true;
    lastCollision = collision;
  }
}

final class _TriggerSpy2D extends Behaviour {
  bool entered = false;
  Collider2D? lastTrigger;

  @override
  void onTriggerEnter2D(Collider2D other) {
    entered = true;
    lastTrigger = other;
  }
}
