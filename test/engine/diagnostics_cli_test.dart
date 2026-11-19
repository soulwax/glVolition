/// Engine diagnostics, telemetry snapshots, transient stress, and CLI tests (P7-W15-C).
library;

import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P7-W15-C — EngineTelemetrySnapshot & Diagnostics', () {
    test('captures complete runtime metrics and serializes to JSON', () {
      final engine = Engine(HeadlessHost());
      final go1 = engine.scene.createGameObject(
        'Hero',
        position: const Vec3(1, 2, 3),
      );
      go1.addComponent(BoxCollider(size: const Vec3(1, 1, 1)));
      go1.addComponent(RigidBody());

      final go2 = engine.scene.createGameObject(
        'Enemy',
        position: const Vec3(5, 0, 5),
      );
      go2.addComponent(SphereCollider(radius: 1.0));

      // Advance frames
      engine.step(0.016);
      engine.step(0.016);

      final snapshot = EngineTelemetrySnapshot.capture(
        engine,
        frameTimeSamplesMs: [15.5, 16.0, 16.2, 17.1, 22.0],
        transientMetrics: {'spawnedDecals': 10, 'spawnedParticles': 200},
      );

      expect(snapshot.totalEntityCount, greaterThanOrEqualTo(2));
      expect(snapshot.activeColliders, equals(2));
      expect(snapshot.activeRigidBodies, equals(1));
      expect(snapshot.p50FrameTimeMs, closeTo(16.2, 0.1));
      expect(snapshot.p95FrameTimeMs, closeTo(22.0, 0.1));
      expect(snapshot.fps, greaterThan(30.0));
      expect(snapshot.transientMetrics['spawnedDecals'], equals(10));

      final jsonMap = snapshot.toJson();
      final jsonStr = jsonEncode(jsonMap);
      expect(jsonStr, contains('"totalEntityCount":'));
      expect(jsonStr, contains('"activeColliders":2'));
    });

    test(
      'uncaught crash telemetry hook invokes callback with diagnostics snapshot',
      () {
        final engine = Engine(HeadlessHost());
        Object? capturedError;
        EngineTelemetrySnapshot? capturedSnapshot;

        EngineTelemetry.onUncaughtCrash = (error, stack, snap) {
          capturedError = error;
          capturedSnapshot = snap;
        };

        try {
          EngineTelemetry.handleUncaught(
            StateError('Simulated critical crash'),
            StackTrace.current,
            engine,
          );

          expect(capturedError, isA<StateError>());
          expect(capturedSnapshot, isNotNull);
          expect(capturedSnapshot!.totalEntityCount, greaterThanOrEqualTo(0));
        } finally {
          EngineTelemetry.onUncaughtCrash = null;
          EngineTelemetry.clearErrorLog();
        }
      },
    );

    test(
      'transient particle and decal stress suite runs smoothly without leaks',
      () {
        final engine = Engine(HeadlessHost());

        // Spawn 100 transient decal entities
        final decals = <GameObject>[];
        for (var i = 0; i < 100; i++) {
          final go = engine.scene.createGameObject(
            'Decal_$i',
            position: Vec3(i.toDouble(), 0, 0),
          );
          go.addComponent(DecalProjectorComponent(size: const Vec3(1, 1, 1)));
          decals.add(go);
        }

        // Step engine
        for (var frame = 0; frame < 20; frame++) {
          engine.step(0.016);
        }

        final midSnap = EngineTelemetrySnapshot.capture(engine);
        expect(midSnap.activeDecals, equals(100));

        // Destroy all transient decals and step engine to flush
        for (final d in decals) {
          d.destroy();
        }
        engine.step(0.016);

        final postSnap = EngineTelemetrySnapshot.capture(engine);
        expect(postSnap.activeDecals, equals(0));
      },
    );
  });

  group('P7-W15-C — DedicatedServerHost Multiplayer Runner', () {
    test(
      'DedicatedServerHost executes tick loop without GPU or window dependencies',
      () async {
        final server = DedicatedServerHost(tickRateHz: 50, port: 0);

        for (var i = 0; i < 15; i++) {
          server.stepTick(0.02);
        }

        expect(server.ticksExecuted, equals(15));
        expect(server.engine.time.frameCount, greaterThanOrEqualTo(15));

        server.stop();
        expect(server.isRunning, isFalse);
      },
    );
  });

  group('P7-W15-C — CLI Commands (doctor, create)', () {
    test(
      'volition doctor command exits cleanly with environment table',
      () async {
        final res = await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/volition.dart',
          'doctor',
        ]);

        expect(res.exitCode, equals(0));
        final out = res.stdout.toString();
        expect(out, contains('glVolition Doctor'));
        expect(out, contains('Dart SDK:'));
        expect(out, contains('Shader Toolchain:'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'volition doctor --json emits valid JSON diagnostics report',
      () async {
        final res = await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/volition.dart',
          'doctor',
          '--json',
        ]);

        expect(res.exitCode, equals(0));
        final decoded =
            jsonDecode(res.stdout.toString()) as Map<String, dynamic>;
        expect(decoded['checks'], isA<List<Object?>>());
        expect((decoded['checks'] as List).length, greaterThanOrEqualTo(5));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('volition create generates template project files', () async {
      const tempProjectName = 'test_cli_project';
      final tempDir = Directory(tempProjectName);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }

      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final res = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/volition.dart',
        'create',
        tempProjectName,
        '--template',
        'multiplayer',
      ]);

      expect(res.exitCode, equals(0));
      expect(File('$tempProjectName/pubspec.yaml').existsSync(), isTrue);
      expect(File('$tempProjectName/lib/main.dart').existsSync(), isTrue);
      expect(File('$tempProjectName/bin/server.dart').existsSync(), isTrue);
      expect(File('$tempProjectName/index.html').existsSync(), isTrue);

      final pubspec = File('$tempProjectName/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: $tempProjectName'));
      final indexHtml = File('$tempProjectName/index.html').readAsStringSync();
      expect(indexHtml, contains('<canvas id="game-canvas">'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
