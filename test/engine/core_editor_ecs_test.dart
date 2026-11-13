/// Core engine lifecycle, DebugController, EditorSession, ECS, events, coroutines & profiler.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../support/subsystems_test_helpers.dart';

void main() {
  group('E2 — DebugController & Session Snapshot', () {
    test(
      'DebugController pauses, steps single fixed frames, scales time, and reports metrics',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.time.fixedDeltaTime = 0.02;

        final counter = FixedCounter();
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
        engine.registry.register(HealthBehaviour.spec);
        engine.storage.write('high_score', '4200');
        engine.time.timeScale = 0.5;

        engine.scene.createGameObject(
          'Hero',
          position: const Vec3(3, 4, 5),
          tag: 'Player',
          components: [HealthBehaviour(hp: 77, faction: 'allies', speed: 9.5)],
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
        final hb = hero.getComponent<HealthBehaviour>();
        expect(hb, isNotNull);
        expect(hb!.hp, 77);
        expect(hb.faction, 'allies');
        expect(hb.speed, 9.5);
      },
    );
  });

  group('E3 — ObjectPool Warmup & Reuse', () {
    test(
      'ObjectPool warms up, acquires, reuses without new allocations, and fires Poolable callbacks',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final prefab = Prefab('Bullet', (go) => go.addComponent(PoolTracker()));
        final pool = ObjectPool<PoolTracker>(
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
        final tracker = seen.first.getComponent<PoolTracker>()!;
        expect(tracker.spawnCount, greaterThan(0));
        expect(tracker.despawnCount, equals(tracker.spawnCount));
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
          engine.registry.register(HealthBehaviour.spec);

          final crate = engine.scene.createGameObject(
            'Crate',
            position: const Vec3(2, 0, -4),
            components: [HealthBehaviour(hp: 100)],
          );
          final enemy = engine.scene.createGameObject(
            'TempEnemy',
            position: const Vec3(5, 0, 0),
          );

          engine.editor.enterPlayMode();

          // Mutate crate and destroy TempEnemy during Play mode
          crate.transform.localPosition = const Vec3(99, 50, 12);
          crate.getComponent<HealthBehaviour>()!.hp = 10;
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
          expect(restoredCrate.getComponent<HealthBehaviour>()!.hp, 100);
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

  group('E8 — SceneEvents & Coroutines', () {
    test(
      'SceneEvents dispatches typed events and unsubscribes automatically when owner is disabled/destroyed',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final go = engine.scene.createGameObject(
          'ListenerObj',
          components: [HealthBehaviour(hp: 100)],
        );
        final health = go.getComponent<HealthBehaviour>()!;

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
          components: [HealthBehaviour(hp: 0)],
        );
        final beh = go.getComponent<HealthBehaviour>()!;

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
  });

  group('E11 — SceneManager & dontDestroyOnLoad', () {
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
  });

  group('E13 — EditorSession Undo & Redo', () {
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
        engine.scene.createGameObject('Barrel', position: const Vec3(-4, 0, 0));

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
  });

  group('E23 — Scene.createPrimitive', () {
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
  });

  group('E24 — SceneManager.fadeTo', () {
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

  group('E27 — voxlog & voxecs Native Submodules', () {
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

  group('E28 — DebugController Immediate-Mode UI', () {
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
  });

  group('E42 — TimeRewind & Ghost Playback', () {
    test(
      'E42: TimeRewindComponent records Transform & custom binary state and rewinds back cleanly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.time.fixedDeltaTime = 0.1;

        var health = 100;
        final rewind = TimeRewindComponent(
          maxFrames: 100,
          onCaptureState: (w) => w.writeVarInt(health),
          onRestoreState: (r) => health = r.readVarInt(),
        );

        final player = engine.scene.createGameObject(
          'ChronoHero',
          components: [rewind],
        );

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
      },
    );

    test(
      'E42: GhostRecorderComponent exports binary GhostTrack and GhostPlaybackComponent replays smoothly',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final recorder = GhostRecorderComponent(sampleInterval: 0.1);
        final racer = engine.scene.createGameObject(
          'Racer',
          components: [recorder],
        );

        for (int i = 0; i <= 10; i++) {
          racer.transform.position = Vec3(i * 1.0, 0.0, 0.0);
          engine.step(0.1);
        }

        final bytes = recorder.exportBinary();
        expect(bytes, isNotEmpty);

        // Replay in a fresh ghost object using binary decode
        final playback = GhostPlaybackComponent.fromBinary(bytes, loop: false);
        final ghost = engine.scene.createGameObject(
          'GhostRacer',
          components: [playback],
        );

        // Advance 5 frames of 0.1s (= 0.5s elapsed, respecting Time.maximumDeltaTime clamp)
        for (int i = 0; i < 5; i++) {
          engine.step(0.1);
        }
        expect(ghost.transform.position.x, closeTo(5.0, 1.0));
      },
    );
  });

  group('E87 — Frame Arena, Slab Pool & Telemetry Counters (voxalloc)', () {
    test(
      'FrameProfilerComponent manages arena resets, generational slabs, P99 telemetry & ProfilerTelemetryInspectorUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final profGo = engine.scene.createGameObject('Profiler');
        final prof = profGo.addComponent(
          FrameProfilerComponent(
            arenaCapacityBytes: 8192,
            slabCapacity: 8,
            autoResetArenaOnUpdate: true,
          ),
        );

        final alloc1 = prof.allocScratchBytes(512);
        expect(alloc1, isNotNull);
        expect(prof.frameArena.usedBytes, 512);

        final h0 = prof.allocateSlab('RenderTarget#0')!;
        expect(prof.resolveSlab(h0), 'RenderTarget#0');

        engine.step(0.016);
        // Auto-reset clears usedBytes after frame while preserving peakBytes
        expect(prof.frameArena.usedBytes, 0);
        expect(prof.frameArena.peakBytes, 512);
        expect(prof.telemetry.totalFramesRecorded, 1);

        // Test ProfilerTelemetryInspectorUI: click Alloc +1KB (x=154, y=159) -> click Reset Arena (x=254, y=159)
        final ui = VoxUiContext();
        final uiState = ProfilerTelemetryInspectorUiState();
        ui.beginFrame(
          VoxInput(
            mouseX: 154.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ProfilerTelemetryInspectorUI.render(ui, prof, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 154.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ProfilerTelemetryInspectorUI.render(ui, prof, state: uiState);
        ui.endFrame();
        expect(prof.frameArena.usedBytes, 1024);
        expect(prof.frameArena.peakBytes, 1024);

        ui.beginFrame(
          VoxInput(
            mouseX: 254.0,
            mouseY: 159.0,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        ProfilerTelemetryInspectorUI.render(ui, prof, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 254.0,
            mouseY: 159.0,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        ProfilerTelemetryInspectorUI.render(ui, prof, state: uiState);
        final dl = ui.endFrame();
        expect(prof.frameArena.usedBytes, 0);
        expect(dl.commands.any((c) => c.text == 'Frame Telemetry'), isTrue);

        // Verify ComponentRegistry serialization
        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('FrameProfilerComponent'), isNotNull);
        final json = reg.specFor(prof)!.toJson(prof);
        expect(json['arenaCapacityBytes'], 8192);
        expect(json['slabCapacity'], 8);
      },
    );
  });
}
