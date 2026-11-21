/// Wave G1 / G3 test: Verifies [VoxUiGlRenderer], [StudioBitmapFontAtlas],
/// [ViewportFboHost] (offscreen FBO creation, auto-resize, compositing), and
/// [NativeStudioApp] on [RecordingGlesDevice] with zero GPU object leaks.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G1 / G3 — Native AOT VoxUiGlRenderer, Font Atlas & Viewport FBOs', () {
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
        expect(app.uiRenderer.lastClipBatchCount, greaterThan(1));
        expect(app.lastOverlayCommandCount, greaterThan(0));
        expect(app.viewport3dRenderer.lastSceneDrawCalls, equals(1));
        expect(app.viewport3dRenderer.lastSceneVertices, greaterThan(36));
        expect(renderedViewportIds, contains('scene'));
        expect(app.viewportHost.entryFor('scene')?.resizeCount, equals(1));

        // Select Sun so 3D gizmo axes are emitted in Scene View, and switch
        // to 2x3 layout (both Scene and Game visible simultaneously) & resize window
        bridge.selectObjects([scene.rootGameObjects.first]);
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
        expect(app.viewport3dRenderer.lastSceneDrawCalls, equals(1));
        expect(app.viewport3dRenderer.lastGameDrawCalls, equals(1));
        expect(
          app.viewport3dRenderer.lastGameVertices,
          greaterThanOrEqualTo(36),
        );
        expect(app.viewportHost.entryFor('scene')?.resizeCount, equals(2));
        expect(app.viewportHost.entryFor('game')?.resizeCount, equals(1));

        // Verify mixed-case font atlas produces distinct bitmaps for 'A' vs 'a'
        final atlas = StudioBitmapFontAtlas.buildRgba8Atlas();
        expect(
          atlas.length,
          equals(
            StudioBitmapFontAtlas.atlasWidth *
                StudioBitmapFontAtlas.atlasHeight *
                4,
          ),
        );
        expect(
          StudioBitmapFontAtlas.uvForChar(65),
          isNot(equals(StudioBitmapFontAtlas.uvForChar(97))),
        );

        app.dispose();
        expect(device.bufferDeleteCalls, equals(device.bufferCreateCalls));
        expect(device.textureDeleteCalls, equals(device.textureCreateCalls));
        expect(device.targetDeleteCalls, equals(device.targetCreateCalls));
        expect(device.vaoDeleteCalls, equals(device.vaoCreateCalls));
        expect(device.programDeleteCalls, equals(device.programCompileCalls));
      },
    );
  });
}
