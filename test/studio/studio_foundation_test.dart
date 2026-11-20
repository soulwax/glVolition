/// S1-0 tests: Studio Protocol v2 codec/registry, pure-Dart ProjectFileSystem,
/// and extended tool/check_boundaries.dart rules for lib/src/studio/**.
library;

import 'dart:io';

import 'package:gl_volition/src/studio/studio.dart';
import 'package:pixeldart/rendering/api/capabilities.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:test/test.dart';

void main() {
  group('S1-0 — Studio Protocol v2', () {
    test('encodes and decodes requests, responses, and events cleanly', () {
      const codec = StudioProtocolCodec();

      const req = StudioRequest(
        id: 'req-1',
        method: 'assets.list',
        params: {'folder': 'assets/meshes'},
      );
      final decodedReq = codec.decode(codec.encode(req));
      expect(decodedReq, isA<StudioRequest>());
      final r = decodedReq as StudioRequest;
      expect(r.version, equals(studioProtocolVersion));
      expect(r.id, equals('req-1'));
      expect(r.method, equals('assets.list'));
      expect(r.params['folder'], equals('assets/meshes'));

      final okRes = StudioResponse.ok('req-1', {'count': 3});
      final decodedOk = codec.decode(codec.encode(okRes)) as StudioResponse;
      expect(decodedOk.ok, isTrue);
      expect(decodedOk.result?['count'], equals(3));

      final errRes = StudioResponse.err(
        'req-2',
        const StudioError(
          code: StudioErrorCode.assetNotFound,
          message: 'Missing hero.glb',
          details: {'path': 'assets/hero.glb'},
        ),
      );
      final decodedErr = codec.decode(codec.encode(errRes)) as StudioResponse;
      expect(decodedErr.ok, isFalse);
      expect(decodedErr.error?.code, equals(StudioErrorCode.assetNotFound));
      expect(decodedErr.error?.details?['path'], equals('assets/hero.glb'));

      const ev = StudioEvent(
        event: 'assets.changed',
        payload: {'path': 'assets/hero.glb'},
        timestampMs: 123456,
      );
      final decodedEv = codec.decode(codec.encode(ev)) as StudioEvent;
      expect(decodedEv.event, equals('assets.changed'));
      expect(decodedEv.timestampMs, equals(123456));
    });

    test(
      'StudioMethodRegistry enforces non-empty CLI mapping on every method',
      () {
        final registry = StudioMethodRegistry();
        expect(registry.all, isNotEmpty);
        for (final desc in registry.all) {
          expect(desc.cliCommand.trim(), isNotEmpty);
        }
        expect(registry.lookup('doctor.run')?.cliCommand, contains('doctor'));
        expect(
          () => registry.register(
            const StudioMethodDescriptor(
              method: 'bad.method',
              cliCommand: '   ',
              summary: 'Missing CLI parity',
            ),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('S1-0 — Pure-Dart ProjectFileSystem', () {
    test('supports write, read, list, stat, move, delete, and watch', () async {
      final fs = MemoryProjectFileSystem();
      final events = <ProjectFsEvent>[];
      final sub = fs.watch('assets').listen(events.add);

      await fs.writeString('assets/scenes/main.scene.json', '{"v":1}');
      expect(await fs.exists('assets/scenes/main.scene.json'), isTrue);
      expect(
        await fs.readString('assets/scenes/main.scene.json'),
        equals('{"v":1}'),
      );

      final st = await fs.stat('assets/scenes/main.scene.json');
      expect(st?.kind, equals(ProjectFsEntryKind.file));
      expect(st?.sizeBytes, equals(7));

      await fs.move(
        'assets/scenes/main.scene.json',
        'assets/scenes/level1.scene.json',
      );
      expect(await fs.exists('assets/scenes/main.scene.json'), isFalse);
      expect(await fs.exists('assets/scenes/level1.scene.json'), isTrue);

      final listed = await fs.list('assets', recursive: true);
      expect(
        listed.map((e) => e.path),
        contains('assets/scenes/level1.scene.json'),
      );

      await fs.delete('assets/scenes/level1.scene.json');
      expect(await fs.exists('assets/scenes/level1.scene.json'), isFalse);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await fs.close();

      expect(
        events.map((e) => e.kind),
        containsAll([
          ProjectFsEventKind.created,
          ProjectFsEventKind.moved,
          ProjectFsEventKind.deleted,
        ]),
      );
    });
  });

  group('S1-0 — GPU Device API v2 Descriptors & Capabilities', () {
    test('validates v2 descriptors and capability serialization', () {
      const caps = RenderCapabilities(
        maxTextureSize: 4096,
        maxTextureArrayLayers: 256,
        maxSamples: 4,
        maxVertexAttributes: 16,
        maxColorAttachments: 4,
        occlusionQueryConservative: true,
        maxUniformBlockSize: 65536,
        maxUniformBufferBindings: 36,
        maxDrawBuffers: 4,
        maxCubeMapTextureSize: 4096,
      );
      final roundTrip = RenderCapabilities.fromMap(caps.toMap());
      expect(roundTrip.maxUniformBlockSize, equals(65536));
      expect(roundTrip.maxDrawBuffers, equals(4));
      expect(roundTrip.occlusionQueryConservative, isTrue);

      const cube = GpuCubeTextureDescriptor(size: 512, hasMips: true);
      cube.validate();
      expect(cube.mipLevelCount, equals(10));

      const mrt = GpuMrtTargetDescriptor(
        width: 1280,
        height: 720,
        colorFormats: [
          GpuColorTargetFormat.rgba16f,
          GpuColorTargetFormat.rgba8,
        ],
      );
      mrt.validate();
    });
  });

  group('S1-0 — Boundary Checker Enforces lib/src/studio/** Rules', () {
    Directory createMinimalRepoFixture() {
      final dir = Directory.systemTemp.createTempSync('volition_boundary_');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      for (final rel in [
        'lib/gl_volition.dart',
        'lib/gl_volition_web.dart',
        'lib/gl_volition_native.dart',
        'lib/src/engine.dart',
        'lib/src/engine/core.dart',
        'lib/src/studio/studio.dart',
        'lib/src/web/web.dart',
        'lib/src/native/native.dart',
      ]) {
        final f = File('${dir.path}/$rel');
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('// ok\n');
      }
      return dir;
    }

    test(
      'rejects dart:io inside lib/src/studio/ and studio import inside lib/src/engine/',
      () {
        final dir = createMinimalRepoFixture();
        try {
          // 1. Clean fixture passes
          final okRes = Process.runSync(Platform.resolvedExecutable, [
            'run',
            'tool/check_boundaries.dart',
            '--root',
            dir.path,
          ]);
          expect(okRes.exitCode, equals(0), reason: '${okRes.stderr}');

          // 2. dart:io inside lib/src/studio/ fails
          final studioBad = File('${dir.path}/lib/src/studio/bad_io.dart');
          studioBad.writeAsStringSync("import 'dart:io';\n");
          final badStudioRes = Process.runSync(Platform.resolvedExecutable, [
            'run',
            'tool/check_boundaries.dart',
            '--root',
            dir.path,
          ]);
          expect(badStudioRes.exitCode, equals(1));
          expect(badStudioRes.stderr.toString(), contains('pure-dart-studio'));
          studioBad.deleteSync();

          // 3. lib/src/engine/ importing lib/src/studio/ fails
          final engineBad = File('${dir.path}/lib/src/engine/bad_studio.dart');
          engineBad.writeAsStringSync(
            "import 'package:gl_volition/src/studio/studio.dart';\n",
          );
          final badEngineRes = Process.runSync(Platform.resolvedExecutable, [
            'run',
            'tool/check_boundaries.dart',
            '--root',
            dir.path,
          ]);
          expect(badEngineRes.exitCode, equals(1));
          expect(badEngineRes.stderr.toString(), contains('pure-dart-core'));
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  });
}
