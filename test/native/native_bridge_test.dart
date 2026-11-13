/// Native GPU/GLES host & desktop bridge subsystem tests (E6, E99).
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../../example/dungeon_2d/game.dart';
import '../../example/island_3d/game.dart';

void main() {
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

  group('E99 — NativeGlTransport, Sdl3EventPump & NativeDesktopBridge', () {
    test(
      'NativeGlTransport records GlesDevice commands and Sdl3EventPump drives NativeDesktopBridge',
      () async {
        final missingDynLoader = DynamicLibraryGlLoader(
          candidateLibraries: const ['definitely_nonexistent_gles_lib_e99.dll'],
        );
        expect(missingDynLoader.isAvailable, isFalse);
        expect(missingDynLoader.hasSymbol('glDrawElements'), isFalse);

        final stubLoader = StubGlProcLoader(
          supportedSymbols: const {
            'glDrawElements',
            'glUseProgram',
            'glCreateShader',
          },
          libraryName: 'mock-angle-gles3',
        );
        expect(stubLoader.isAvailable, isTrue);
        expect(stubLoader.hasSymbol('glDrawElements'), isTrue);
        expect(stubLoader.hasSymbol('glUnknownProc'), isFalse);

        final forwarded = <GlCommandRecord>[];
        final transport = NativeGlTransport(
          procLoader: stubLoader,
          onForward: forwarded.add,
          maxRecordedCommands: 2048,
        );
        final device = transport.createDevice();

        final runner = await NativeEngineHost.boot(
          device: device,
          width: 640,
          height: 360,
          initialScene: buildDungeon2DScene(),
        );
        final bridge = NativeDesktopBridge(
          runner: runner,
          transport: transport,
        );

        // Enqueue a raw packet (keyDown 'KeyD') and mouse movement + click.
        final packetBytes = ByteData(28)
          ..setUint32(0, Sdl3EventKind.keyDown.index, Endian.little)
          ..setInt32(4, 1, Endian.little)
          ..setFloat64(8, 120.0, Endian.little)
          ..setFloat64(16, 80.0, Endian.little)
          ..setUint8(24, 0x4B) // 'K'
          ..setUint8(25, 0x65) // 'e'
          ..setUint8(26, 0x79) // 'y'
          ..setUint8(27, 0x44); // 'D'
        final decoded = Sdl3EventPump.decodeRawEventPacket(packetBytes);
        expect(decoded, isNotNull);
        expect(decoded!.kind, Sdl3EventKind.keyDown);
        expect(decoded.keyCode, 'KeyD');

        bridge.eventPump.enqueueAll([
          decoded,
          const Sdl3InputEvent(kind: Sdl3EventKind.mouseDown, x: 160, y: 90),
        ]);

        final stats = bridge.stepAndRender(1 / 60);
        expect(stats, isNotNull);
        expect(stats!.drawCalls, greaterThan(0));
        expect(transport.totalDispatched, greaterThan(0));
        expect(transport.records.length, lessThanOrEqualTo(2048));
        expect(forwarded.length, transport.totalDispatched);
        expect(transport.commandCounts.isNotEmpty, isTrue);
        expect(runner.host.input.isDown('KeyD'), isTrue);
        expect(runner.host.input.pointerX, closeTo(160.0, 1e-4));
        expect(runner.host.input.pointerDown, isTrue);

        // Enqueue quit -> stepAndRender returns null.
        bridge.eventPump.enqueue(
          const Sdl3InputEvent(kind: Sdl3EventKind.quit),
        );
        expect(bridge.stepAndRender(1 / 60), isNull);
        expect(bridge.isQuitRequested, isTrue);

        bridge.dispose();
        expect(device.liveObjectCount, 0);
        expect(device.liveTimerCount, 0);
      },
    );
  });
}
