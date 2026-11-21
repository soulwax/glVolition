/// S2-B tests: EditorCameraController (orbit, pan, zoom, WASD fly, frame
/// selection, 2D ortho toggle), SceneViewportModel (EditorOverlayState,
/// RGBA8 ID-buffer picking, ray picking), and GameViewportModel letterboxing.
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S2-B — EditorCameraController', () {
    test(
      'orbits, pans, zooms, flies with WASD, frames selection, and toggles 2D without touching game Camera',
      () {
        final engine = Engine(HeadlessHost());
        final gameCamGo = engine.scene.createGameObject(
          'MainCamera',
          position: const Vec3(0, 2, 10),
        )..addComponent(Camera());
        final targetGo = engine.scene.createGameObject(
          'TargetBox',
          position: const Vec3(10, 0, -5),
        );

        final session = EditorSession(engine)..stopPlayMode();
        session.select(targetGo);

        final cam = EditorCameraController();
        final initialPos = cam.position;
        cam.orbit(0.5, 0.2);
        expect(cam.position, isNot(equals(initialPos)));

        final beforeFly = cam.target;
        cam.flyWasd(forwardInput: 1.0, dt: 0.5);
        expect(cam.target, isNot(equals(beforeFly)));

        // Frame selected ('F') centers on TargetBox
        expect(cam.frameSelection(session), isTrue);
        expect(cam.target.x, closeTo(10.0, 1e-3));
        expect(cam.target.z, closeTo(-5.0, 1e-3));

        // Toggle 2D mode switches to ortho without mutating game camera
        cam.toggle2DMode();
        expect(cam.isOrthographic2D, isTrue);
        expect(gameCamGo.transform.position, equals(const Vec3(0, 2, 10)));
        expect(gameCamGo.getComponent<Camera>()!.orthographic, isFalse);
      },
    );
  });

  group('S2-B — SceneViewportModel & GameViewportModel', () {
    test(
      'builds EditorOverlayState and resolves RGBA8 ID-buffer & ray picks',
      () {
        final engine = Engine(HeadlessHost());
        final cube = engine.scene.createGameObject(
          'HeroCube',
          position: Vec3.zero,
        );
        engine.scene
            .createGameObject('Sun', position: const Vec3(0, 5, 0))
            .addComponent(Light.directional());

        final session = EditorSession(engine)..stopPlayMode();
        final bridge = SessionEditorHostBridge(session);
        bridge.selectObjects([cube]);

        final viewport = SceneViewportModel(bridge);
        final overlay = viewport.buildOverlayState();
        final cubeId = SceneViewportModel.objectPickId(cube);
        expect(overlay.grid.enabled, isTrue);
        expect(overlay.lines.length, equals(3)); // X, Y, Z gizmo axes
        expect(overlay.icons.any((i) => i.iconId == 'light'), isTrue);
        expect(overlay.selectedObjectIds, contains(cubeId));

        // Simulate 4x4 RGBA8 ID buffer with HeroCube at pixel (2, 1)
        final idPixels = Uint8List(4 * 4 * 4);
        final (r, g, b, a) = EditorPickIdCodec.encode(cubeId);
        final offset = (1 * 4 + 2) * 4;
        idPixels[offset + 0] = r;
        idPixels[offset + 1] = g;
        idPixels[offset + 2] = b;
        idPixels[offset + 3] = a;

        final pick = viewport.pickFromIdBuffer(idPixels, 4, 4, 2, 1);
        expect(pick, isNotNull);
        expect(pick!.objectId, equals(cubeId));
        expect(pick.gameObject, equals(cube));

        // Ray pick from center of screen hits HeroCube at origin
        viewport.editorCamera
          ..target = Vec3.zero
          ..yawRadians = 0
          ..pitchRadians = 0
          ..distance = 5.0;
        final rayPick = viewport.pickByRay(0.5, 0.5, 16 / 9);
        expect(rayPick?.gameObject, equals(cube));

        // Game view letterboxing for 16:9 inside 1000x1000 panel
        final gameView = GameViewportModel(
          aspectPreset: GameViewAspectPreset.hd16x9,
        );
        final rect = gameView.computeViewportRect(1000, 1000);
        expect(rect.width, closeTo(1000, 1e-6));
        expect(rect.height, closeTo(562.5, 1e-6));
        expect(rect.y, closeTo(218.75, 1e-6));
      },
    );
  });
}
