/// Wave G1 test: Verifies [VoxUiGlRenderer] and [NativeStudioApp] compile
/// the GLES3 2D UI shader, batch `voxui` DrawLists, composite viewport FBO
/// textures, and release all GPU objects cleanly on [RecordingGlesDevice].
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G1 — Native AOT VoxUiGlRenderer & NativeStudioApp', () {
    test(
      'batches Studio workspace DrawList to RecordingGlesDevice with zero GPU leaks',
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

        final solved = app.stepFrame(
          input: VoxInput(),
          pixelWidth: 1280,
          pixelHeight: 720,
        );

        expect(app.frameCount, equals(1));
        expect(solved.areas.length, greaterThanOrEqualTo(4));
        expect(app.uiRenderer.lastSubmittedVertices, greaterThan(60));
        expect(app.uiRenderer.lastDrawCalls, equals(1));
        expect(device.programCompileCalls, equals(1));

        app.dispose();
        expect(device.bufferDeleteCalls, equals(device.bufferCreateCalls));
        expect(device.vaoDeleteCalls, equals(device.vaoCreateCalls));
        expect(device.programDeleteCalls, equals(device.programCompileCalls));
      },
    );
  });
}
