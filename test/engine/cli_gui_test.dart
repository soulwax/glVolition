import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

import '../../tool/cli_gui_server.dart';
import '../../tool/cli_service.dart';

void main() {
  group('P8-W16 — VolitionCliService & Studio GUI', () {
    test(
      'VolitionCliService.runDoctor returns structured toolchain checks',
      () async {
        final service = VolitionCliService();
        try {
          final report = await service.runDoctor();
          final ids = report.checks.map((c) => c.id).toSet();
          expect(
            ids,
            containsAll([
              'dart_sdk',
              'browser',
              'compiler',
              'native_libs',
              'shader_toolchain',
            ]),
          );

          final json = report.toJson();
          expect(json['checks'], isA<List<Object?>>());
          expect((json['checks'] as List).length, 5);
        } finally {
          await service.dispose();
        }
      },
    );

    test(
      'VolitionCliService.discoverEntries finds workspace example mains',
      () async {
        final service = VolitionCliService();
        try {
          final entries = service.discoverEntries();
          expect(entries, isNotEmpty);
          expect(entries.every((e) => e.endsWith('.dart')), isTrue);
        } finally {
          await service.dispose();
        }
      },
    );

    test(
      'VolitionGuiServer serves Studio HTML, /health, and WebSocket RPC',
      () async {
        final server = VolitionGuiServer();
        final url = await server.start(port: 0);
        final httpClient = HttpClient();

        try {
          // 1. Verify HTML root
          final rootReq = await httpClient.getUrl(url);
          final rootRes = await rootReq.close();
          expect(rootRes.statusCode, HttpStatus.ok);
          final html = await utf8.decodeStream(rootRes);
          expect(html, contains('glVolition Studio'));
          expect(html, contains('/ws'));

          // 2. Verify /health JSON
          final healthReq = await httpClient.getUrl(url.resolve('/health'));
          final healthRes = await healthReq.close();
          expect(healthRes.statusCode, HttpStatus.ok);
          final healthJson =
              jsonDecode(await utf8.decodeStream(healthRes))
                  as Map<String, dynamic>;
          expect(healthJson['status'], 'ok');

          // 3. Verify WebSocket JSON-RPC
          final wsUri = url.replace(scheme: 'ws', path: '/ws');
          final ws = await WebSocket.connect(wsUri.toString());
          final messages = <Map<String, dynamic>>[];
          final sub = ws.listen((data) {
            if (data is String) {
              messages.add(jsonDecode(data) as Map<String, dynamic>);
            }
          });

          Future<Map<String, dynamic>> waitForType(String type) async {
            final deadline = DateTime.now().add(const Duration(seconds: 20));
            while (DateTime.now().isBefore(deadline)) {
              for (final m in messages) {
                if (m['type'] == type) return m;
              }
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            fail('Timed out waiting for WebSocket message type "$type"');
          }

          ws.add(jsonEncode({'id': 1, 'method': 'init', 'params': {}}));
          final initMsg = await waitForType('init');
          expect(initMsg['workingDirectory'], isNotEmpty);

          ws.add(jsonEncode({'id': 2, 'method': 'doctor.run', 'params': {}}));
          final docMsg = await waitForType('doctor.result');
          expect(
            ((docMsg['report'] as Map)['checks'] as List).length,
            greaterThanOrEqualTo(5),
          );

          ws.add(jsonEncode({'id': 3, 'method': 'entries.list', 'params': {}}));
          final entriesMsg = await waitForType('entries.result');
          expect(entriesMsg['entries'], isNotEmpty);

          // 4. Verify streaming task execution via gate.run (check_boundaries)
          ws.add(
            jsonEncode({
              'id': 4,
              'method': 'gate.run',
              'params': {'gate': 'boundaries'},
            }),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          Map<String, dynamic>? finishedTask;
          while (DateTime.now().isBefore(deadline)) {
            for (final m in messages) {
              if (m['type'] == 'task.update') {
                final task = m['task'] as Map<String, dynamic>;
                if (task['state'] == 'completed' || task['state'] == 'failed') {
                  finishedTask = task;
                  break;
                }
              }
            }
            if (finishedTask != null) break;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(finishedTask, isNotNull);
          expect(finishedTask!['state'], 'completed');
          expect(finishedTask['exitCode'], 0);
          expect(messages.any((m) => m['type'] == 'task.log'), isTrue);

          await sub.cancel();
          await ws.close();
        } finally {
          httpClient.close(force: true);
          await server.stop();
        }
      },
    );

    test('volition gui --help prints usage and exits 0', () async {
      final res = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/volition.dart',
        'gui',
        '--help',
      ]);
      expect(res.exitCode, 0);
      expect(res.stdout.toString(), contains('volition gui'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'VolitionCliService & WebSocket RPC inspect .pak archives and scene JSON artifacts',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'volition_inspect_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final builder = PakBuilder();
        builder.addBytes(
          'textures/albedo.bin',
          Uint8List.fromList(List.filled(64, 7)),
        );
        builder.addBytes(
          'config/level.txt',
          Uint8List.fromList(utf8.encode('level=1')),
        );
        final pakFile = File('${tempDir.path}/bundle.pak');
        pakFile.writeAsBytesSync(builder.build());

        final engine = Engine(HeadlessHost());
        final sun = engine.scene.createGameObject('Sun');
        sun.addComponent(Light.directional());
        final sceneFile = File('${tempDir.path}/test_scene.json');
        sceneFile.writeAsStringSync(SceneSerializer.toJsonString(engine.scene));

        final service = VolitionCliService(workingDirectory: tempDir.path);
        final server = VolitionGuiServer(service: service);
        final url = await server.start(port: 0);

        try {
          final discovered = service.discoverInspectableFiles();
          expect(discovered['paks'], contains('bundle.pak'));
          expect(discovered['scenes'], contains('test_scene.json'));

          final pakReport = service.inspectArtifact('bundle.pak');
          expect(pakReport['kind'], 'pak');
          expect(pakReport['entryCount'], 2);

          final sceneReport = service.inspectArtifact('test_scene.json');
          expect(sceneReport['kind'], 'scene');
          expect(sceneReport['totalObjectCount'], 1);
          expect((sceneReport['componentCounts'] as Map)['Light'], equals(1));

          final wsUri = url.replace(scheme: 'ws', path: '/ws');
          final ws = await WebSocket.connect(wsUri.toString());
          final messages = <Map<String, dynamic>>[];
          final sub = ws.listen((data) {
            if (data is String) {
              messages.add(jsonDecode(data) as Map<String, dynamic>);
            }
          });

          Future<Map<String, dynamic>> waitForType(String type) async {
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (DateTime.now().isBefore(deadline)) {
              for (final m in messages) {
                if (m['type'] == type) return m;
              }
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            fail('Timed out waiting for WebSocket message type "$type"');
          }

          ws.add(
            jsonEncode({'id': 1, 'method': 'inspector.list', 'params': {}}),
          );
          final listMsg = await waitForType('inspector.list.result');
          expect((listMsg['files'] as Map)['paks'], contains('bundle.pak'));

          ws.add(
            jsonEncode({
              'id': 2,
              'method': 'inspector.inspect',
              'params': {'path': 'bundle.pak'},
            }),
          );
          final inspectMsg = await waitForType('inspector.inspect.result');
          expect((inspectMsg['report'] as Map)['entryCount'], equals(2));

          await sub.cancel();
          await ws.close();
        } finally {
          await server.stop();
        }
      },
    );

    test(
      'VolitionCliService, WebSocket RPC tape.verify, and CLI volition replay verify InputTapes',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('volition_tape_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        // Record a deterministic 15-frame tape with a falling RigidBody
        final liveInput = ScriptedInput();
        final recorder = InputTapeRecorder(liveInput);
        final recHost = HeadlessHost();
        final recEngine = Engine(recHost);
        final bodyObj = recEngine.scene.createGameObject(
          'Ball',
          position: const Vec3(0, 5, 0),
        );
        bodyObj.addComponent(RigidBody(mass: 1.0));
        final initialScene = SceneSerializer.toJson(recEngine.scene);

        const dt = 0.02;
        for (var f = 0; f < 15; f++) {
          if (f == 2) liveInput.press('KeyW');
          if (f == 5) liveInput.release('KeyW');
          recEngine.step(dt);
          recorder.recordFrame(
            dt,
            checkpointScene: (f == 0 || f == 14) ? recEngine.scene : null,
          );
          liveInput.endFrame();
        }

        final tape = recorder.toTape(
          name: 'gravity_smoke',
          initialSceneJson: initialScene,
        );
        final tapeFile = File('${tempDir.path}/gravity_tape.json');
        tapeFile.writeAsStringSync(tape.toJsonString());

        // Create a tampered copy with an altered checkpoint hash
        final tamperedMap = Map<String, Object?>.from(tape.toJson());
        tamperedMap['checkpoints'] = {'14': 123456789};
        final tamperedFile = File('${tempDir.path}/tampered_tape.json');
        tamperedFile.writeAsStringSync(jsonEncode(tamperedMap));

        final service = VolitionCliService(workingDirectory: tempDir.path);
        final server = VolitionGuiServer(service: service);
        final url = await server.start(port: 0);

        try {
          final discovered = service.discoverInspectableFiles();
          expect(discovered['tapes'], contains('gravity_tape.json'));

          final inspect = service.inspectArtifact('gravity_tape.json');
          expect(inspect['kind'], 'tape');
          expect(inspect['frameCount'], 15);
          expect(inspect['checkpointCount'], 2);
          expect(inspect['distinctKeysUsed'], contains('KeyW'));

          final passResult = service.verifyInputTapeFile('gravity_tape.json');
          expect(passResult['passed'], isTrue);
          expect(passResult['framesExecuted'], 15);

          final failResult = service.verifyInputTapeFile('tampered_tape.json');
          expect(failResult['passed'], isFalse);
          expect(failResult['mismatches'], isNotEmpty);

          // Verify WebSocket RPC tape.verify
          final wsUri = url.replace(scheme: 'ws', path: '/ws');
          final ws = await WebSocket.connect(wsUri.toString());
          final messages = <Map<String, dynamic>>[];
          final sub = ws.listen((data) {
            if (data is String) {
              messages.add(jsonDecode(data) as Map<String, dynamic>);
            }
          });

          ws.add(
            jsonEncode({
              'id': 10,
              'method': 'tape.verify',
              'params': {'path': 'gravity_tape.json'},
            }),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          Map<String, dynamic>? verifyMsg;
          while (DateTime.now().isBefore(deadline)) {
            for (final m in messages) {
              if (m['type'] == 'tape.verify.result') {
                verifyMsg = m;
                break;
              }
            }
            if (verifyMsg != null) break;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(verifyMsg, isNotNull);
          expect((verifyMsg!['result'] as Map)['passed'], isTrue);

          await sub.cancel();
          await ws.close();

          // Verify CLI `volition replay <tape> --json`
          final cliPass = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/volition.dart',
            'replay',
            tapeFile.path,
            '--json',
          ]);
          expect(cliPass.exitCode, 0);
          final cliPassJson =
              jsonDecode(cliPass.stdout.toString()) as Map<String, dynamic>;
          expect(cliPassJson['passed'], isTrue);

          final cliFail = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/volition.dart',
            'replay',
            tamperedFile.path,
            '--json',
          ]);
          expect(cliFail.exitCode, 1);
        } finally {
          await server.stop();
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
