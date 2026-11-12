import 'dart:math' as math;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../example/dungeon_2d/game.dart';
import '../example/island_3d/game.dart';
import '../example/pixel_rocket/game.dart';
import '../example/prism_pulse/game.dart';
import '../example/procession/game.dart';

List<GameObject> _collectAllGameObjects(Scene scene) {
  final result = <GameObject>[];
  void visit(GameObject go) {
    result.add(go);
    for (final child in go.children) {
      visit(child);
    }
  }

  for (final root in scene.rootGameObjects) {
    visit(root);
  }
  return result;
}

void _assertSceneHealthy(Scene scene) {
  expect(scene.root, isNotNull);
  expect(scene.rootGameObjects, isNotEmpty);
  final objects = _collectAllGameObjects(scene);
  expect(objects, isNotEmpty);
  for (final go in objects) {
    expect(go.isDestroyed, isFalse);
    final p = go.transform.position;
    expect(p.x.isFinite, isTrue, reason: '${go.name} position.x finite');
    expect(p.y.isFinite, isTrue, reason: '${go.name} position.y finite');
    expect(p.z.isFinite, isTrue, reason: '${go.name} position.z finite');
  }
}

void _assertFrameStatsValid(FrameStats stats, String label) {
  expect(stats.drawCalls, greaterThan(0), reason: '$label drawCalls > 0');
  expect(stats.drawCalls, lessThan(500), reason: '$label drawCalls < 500');
  expect(
    stats.liveGpuBytes,
    lessThan(64 * 1024 * 1024),
    reason: '$label liveGpuBytes < 64 MiB',
  );
  expect(stats.liveGpuBytes, greaterThanOrEqualTo(0));
  expect(stats.peakGpuBytes, greaterThanOrEqualTo(stats.liveGpuBytes));
  expect(stats.trianglesSubmitted, greaterThanOrEqualTo(0));
  expect(stats.trianglesCulled, greaterThanOrEqualTo(0));
  expect(stats.instancesSubmitted, greaterThanOrEqualTo(0));
  expect(stats.instancesCulled, greaterThanOrEqualTo(0));
  expect(stats.drawCalls.toDouble().isNaN, isFalse);
  expect(stats.trianglesSubmitted.toDouble().isNaN, isFalse);
  expect(stats.liveGpuBytes.toDouble().isNaN, isFalse);
  expect(stats.peakGpuBytes.toDouble().isNaN, isFalse);
}

void main() {
  group('E100 — Headless & Native Parity + Draw/VRAM Benchmark', () {
    test('Headless parity across all 5 example scenes (30 frames each)', () {
      final builders = <(String, void Function(ComponentRegistry), void Function(Engine))>[
        ('Dungeon2D', registerDungeon2DSpecs, (e) => e.loadScene(buildDungeon2DScene())),
        ('Procession', registerProcessionSpecs, (e) => e.loadScene(buildProcessionScene())),
        ('Island3D', registerIsland3DSpecs, (e) => e.loadScene(buildIsland3DScene())),
        ('PrismPulse', registerPrismPulseSpecs, (e) => e.loadScene(buildPrismPulseScene())),
        (
          'PixelRocket',
          registerPixelRocketSpecs,
          (e) {
            e.loadScene(Scene('PixelRocket'));
            buildPixelRocketScene(e, hud: NullRocketHud(), random: math.Random(7));
          },
        ),
      ];

      for (final (name, registerSpecs, setupScene) in builders) {
        final host = HeadlessHost();
        final registry = ComponentRegistry.defaults();
        registerSpecs(registry);

        final engine = Engine(host, registry: registry);
        setupScene(engine);

        for (var frame = 0; frame < 30; frame++) {
          engine.step(1 / 60);
          host.input.endFrame();
        }

        expect(host.errors, isEmpty, reason: '$name produced headless errors');
        _assertSceneHealthy(engine.scene);
        engine.dispose();
      }
    });

    test(
      'NativeEngineHost + GlesDevice parity, resize, draw/VRAM budget & zero-leak dispose',
      () async {
        const vramBudgetBytes = 64 * 1024 * 1024;
        final device = GlesDevice();
        final runner = await NativeEngineHost.boot(
          device: device,
          width: 1280,
          height: 720,
          requestedProfile: QualityProfile.clean,
          registerSpecs: (reg) {
            registerDungeon2DSpecs(reg);
            registerProcessionSpecs(reg);
            registerIsland3DSpecs(reg);
            registerPrismPulseSpecs(reg);
            registerPixelRocketSpecs(reg);
          },
          initialScene: buildDungeon2DScene(),
        );

        final summaries = <String>[];

        void runFrames(String label, int count) {
          late FrameStats lastStats;
          var maxDraws = 0;
          var maxVram = 0;
          for (var i = 0; i < count; i++) {
            lastStats = runner.renderFrame(1 / 60);
            _assertFrameStatsValid(lastStats, '$label frame $i');
            if (lastStats.drawCalls > maxDraws) maxDraws = lastStats.drawCalls;
            if (lastStats.liveGpuBytes > maxVram) maxVram = lastStats.liveGpuBytes;
          }
          expect(runner.host.errors, isEmpty, reason: '$label host errors');
          expect(device.programCompileCalls, greaterThan(0));
          expect(maxVram, lessThan(vramBudgetBytes));
          _assertSceneHealthy(runner.scene);
          summaries.add(
            '$label: draws=${lastStats.drawCalls} (max=$maxDraws), '
            'tris=${lastStats.trianglesSubmitted}, '
            'vram=${(lastStats.liveGpuBytes / 1024).toStringAsFixed(1)} KB',
          );
        }

        // 1. Dungeon2D (initial scene at 1280x720)
        runFrames('Dungeon2D', 6);

        // 2. Procession
        runner.engine.loadScene(buildProcessionScene());
        runFrames('Procession', 6);

        // 3. Island3D + viewport resize (1280x720 -> 800x600)
        runner.engine.loadScene(buildIsland3DScene());
        runFrames('Island3D (1280x720)', 6);
        await runner.resize(800, 600);
        expect(runner.host.graphics.viewportWidth, 800);
        expect(runner.host.graphics.viewportHeight, 600);
        runFrames('Island3D (800x600)', 6);

        // 4. PrismPulse
        runner.engine.loadScene(buildPrismPulseScene());
        runFrames('PrismPulse', 8);

        // 5. PixelRocket (built on clean empty scene)
        runner.engine.loadScene(Scene('PixelRocket'));
        final director = buildPixelRocketScene(
          runner.engine,
          hud: NullRocketHud(),
          random: math.Random(7),
        );
        expect(director.phase, GamePhase.title);
        runFrames('PixelRocket', 8);

        // Print benchmark summary
        for (final line in summaries) {
          // ignore: avoid_print
          print('[E100 benchmark] $line');
        }
        // ignore: avoid_print
        print(
          '[E100 programs] compiled=${device.programCompileCalls}, '
          'peakLiveObjects=${device.bufferCreateCalls + device.textureCreateCalls + device.targetCreateCalls + device.vaoCreateCalls + device.programCompileCalls}',
        );

        // Zero-leak GPU & timer verification
        runner.dispose();
        expect(device.liveObjectCount, 0);
        expect(device.liveTimerCount, 0);
      },
    );

    test(
      'ComponentRegistry.defaults() & example ComponentSpec coverage without duplicates',
      () {
        final reg = ComponentRegistry.defaults();

        // E94-E98 new built-in components
        const requiredBuiltIns = [
          'SoftBodyXpbdComponent',
          'GreedyVoxelBrickComponent',
          'EngineWorkbenchComponent',
          'ShaderOverrideComponent',
          'SceneStreamZone',
        ];
        for (final typeName in requiredBuiltIns) {
          final spec = reg.specByName(typeName);
          expect(spec, isNotNull, reason: 'Missing built-in spec $typeName');
          final instance = spec!.create();
          expect(reg.specFor(instance), same(spec));
        }

        // Register each example's specs and verify strictly additive count (no duplicates)
        var expectedCount = reg.registeredSpecs.length;

        registerDungeon2DSpecs(reg);
        expectedCount += 4;
        expect(reg.registeredSpecs.length, expectedCount);

        registerProcessionSpecs(reg);
        expectedCount += 3;
        expect(reg.registeredSpecs.length, expectedCount);

        registerIsland3DSpecs(reg);
        expectedCount += 4;
        expect(reg.registeredSpecs.length, expectedCount);

        registerPrismPulseSpecs(reg);
        expectedCount += 7;
        expect(reg.registeredSpecs.length, expectedCount);

        registerPixelRocketSpecs(reg);
        expectedCount += 3;
        expect(reg.registeredSpecs.length, expectedCount);

        const exampleSpecs = [
          'BrazierBehaviour',
          'MoteBehaviour',
          'ShadeBehaviour',
          'DungeonExplorer',
          'LeaderBehaviour',
          'VillagerBehaviour',
          'SwarmEnemyBehaviour',
          'LighthouseBehaviour',
          'FlareBehaviour',
          'ShipAgentBehaviour',
          'HarbourDirector',
          'PulseCraftBehaviour',
          'PulseBoltBehaviour',
          'PrismCoreBehaviour',
          'SentinelBehaviour',
          'BeaconSweepBehaviour',
          'PrismArenaDirector',
          'PrismHudController',
          'FieldBody',
          'ShipController',
          'RocketDirector',
        ];
        for (final name in exampleSpecs) {
          expect(reg.specByName(name), isNotNull, reason: 'Missing example spec $name');
        }
      },
    );
  });
}
