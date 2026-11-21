/// Wave G5 test: Verifies [Sdl3StudioRunner] & [NativeStudioInputMapper] drive
/// the full AOT native Studio loop (window open -> event pump -> UI/FBO render
/// -> swapBuffers -> clean GPU dispose).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

final class _FakeStudioWindow implements NativeWindowBackend {
  bool opened = false;
  bool disposed = false;
  int swapCount = 0;
  int pumpCount = 0;

  @override
  bool get isInitialized => opened && !disposed;

  @override
  bool get isHardwareAvailable => false;

  @override
  int get pixelWidth => 1280;

  @override
  int get pixelHeight => 720;

  @override
  double get devicePixelRatio => 1.0;

  @override
  bool quitRequested = false;

  @override
  bool openWindow({
    required String title,
    int width = 1280,
    int height = 720,
    bool resizable = true,
    bool gles3 = true,
  }) {
    opened = true;
    return true;
  }

  @override
  void makeCurrent() {}

  @override
  void swapBuffers() => swapCount++;

  @override
  ({int width, int height}) pollSize() => (width: 1280, height: 720);

  @override
  void pumpEvents(
    ScriptedInput input, {
    void Function(int width, int height)? onResize,
  }) {
    pumpCount++;
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  group('Wave G5 — Sdl3StudioRunner & Native Studio Desktop Loop', () {
    test('runs multi-frame native Studio loop with zero GPU leaks', () async {
      final device = RecordingGlesDevice();
      final window = _FakeStudioWindow();
      final engine = Engine(HeadlessHost());
      final scene = Scene('DesktopStudio');
      scene.createGameObject('MainCamera').addComponent(Camera());
      scene.createGameObject('Sun').addComponent(Light.directional());
      engine.loadScene(scene);

      final bridge = SessionEditorHostBridge(EditorSession(engine));
      final shell = StudioWorkspaceShell(bridge: bridge);
      final runner = Sdl3StudioRunner(
        shell: shell,
        windowBackend: window,
        device: device,
      );

      final result = await runner.run(maxFrames: 3);
      expect(result.launched, isTrue);
      expect(result.framesRendered, equals(3));
      expect(window.opened, isTrue);
      expect(window.disposed, isTrue);
      expect(window.swapCount, equals(3));
      expect(window.pumpCount, equals(3));

      // Zero GPU leaks after exit
      expect(device.bufferDeleteCalls, equals(device.bufferCreateCalls));
      expect(device.textureDeleteCalls, equals(device.textureCreateCalls));
      expect(device.targetDeleteCalls, equals(device.targetCreateCalls));
      expect(device.vaoDeleteCalls, equals(device.vaoCreateCalls));
      expect(device.programDeleteCalls, equals(device.programCompileCalls));
    });

    test(
      'NativeStudioInputMapper tracks pointer deltas and click/release edges',
      () {
        final mapper = NativeStudioInputMapper();

        final f1 = mapper.sampleRaw(
          mouseX: 100,
          mouseY: 200,
          isLeftDown: true,
          scrollDeltaY: 1.5,
        );
        expect(f1.mouseX, equals(100));
        expect(f1.mouseY, equals(200));
        expect(f1.isMouseDown, isTrue);
        expect(f1.wasMouseClicked, isTrue);
        expect(f1.wasMouseReleased, isFalse);
        expect(f1.scrollDeltaY, equals(1.5));

        final f2 = mapper.sampleRaw(
          mouseX: 112,
          mouseY: 205,
          isLeftDown: false,
        );
        expect(f2.mouseDeltaX, equals(12));
        expect(f2.mouseDeltaY, equals(5));
        expect(f2.wasMouseClicked, isFalse);
        expect(f2.wasMouseReleased, isTrue);
      },
    );
  });
}
