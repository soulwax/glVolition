/// Wave G1 / G3 test: Verifies [VoxUiGlRenderer], [StudioBitmapFontAtlas],
/// [ViewportFboHost] (offscreen FBO creation, auto-resize, compositing), and
/// [NativeStudioApp] on [RecordingGlesDevice] with zero GPU object leaks.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Wave G1 / G3 — Native AOT VoxUiGlRenderer, Font Atlas & Viewport FBOs',
    () {
      test(
        'batches UI + bitmap font atlas + offscreen Scene/Game FBOs with zero leaks',
        () {
          final device = RecordingGlesDevice();
          final host = HeadlessHost();
          final engine = Engine(host);
          final scene = Scene('NativeStudioTest');
          scene.createGameObject('Sun').addComponent(Light.directional());
          engine.loadScene(scene);

          final session = EditorSession(engine);
          final bridge = SessionEditorHostBridge(session);
          final shell = StudioWorkspaceShell(bridge: bridge);
          final app = NativeStudioApp(shell: shell, device: device);

          var renderedViewportIds = <String>[];
          final solved = app.stepFrame(
            input: VoxInput(),
            pixelWidth: 1280,
            pixelHeight: 720,
            onRenderViewport: (slot, fbo) =>
                renderedViewportIds.add(slot.panelId),
          );

          expect(app.frameCount, equals(1));
          expect(solved.areas.length, greaterThanOrEqualTo(4));
          expect(app.uiRenderer.lastSubmittedVertices, greaterThan(60));
          expect(app.uiRenderer.lastTextVertices, greaterThan(0));
          expect(renderedViewportIds, contains('scene'));
          expect(app.viewportHost.entryFor('scene')?.resizeCount, equals(1));

          // Switch to 2x3 layout (both Scene and Game visible simultaneously) & resize window
          shell.applyLayoutPreset('2 by 3');
          renderedViewportIds = [];
          app.stepFrame(
            input: VoxInput(),
            pixelWidth: 1600,
            pixelHeight: 900,
            onRenderViewport: (slot, fbo) =>
                renderedViewportIds.add(slot.panelId),
          );
          expect(renderedViewportIds, containsAll(['scene', 'game']));
          expect(app.viewportHost.entryFor('scene')?.resizeCount, equals(2));
          expect(app.viewportHost.entryFor('game')?.resizeCount, equals(1));

          app.dispose();
          expect(device.bufferDeleteCalls, equals(device.bufferCreateCalls));
          expect(device.textureDeleteCalls, equals(device.textureCreateCalls));
          expect(device.targetDeleteCalls, equals(device.targetCreateCalls));
          expect(device.vaoDeleteCalls, equals(device.vaoCreateCalls));
          expect(device.programDeleteCalls, equals(device.programCompileCalls));
        },
      );
    },
  );
}
