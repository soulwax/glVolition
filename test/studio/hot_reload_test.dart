/// S5-B test: Verifies [StudioReloadSnapshot] round-trips scene (including
/// unsaved changes), selection, camera pose, active tool, and dock layout
/// byte-equally across hot reloads.
library;

import 'dart:convert';

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S5-B — State-Preserving Hot-Reload Snapshot', () {
    test(
      'captures and restores scene, selection, camera, and layout byte-equally',
      () {
        final scene = Scene('ReloadLevel');
        final hero = scene.createGameObject('Hero');
        hero.transform.position = const Vec3(4.5, 2.0, -7.25);

        final camera = EditorCameraController()
          ..target = const Vec3(4.5, 2.0, -7.25)
          ..yawRadians = 1.15
          ..pitchRadians = -0.35
          ..distance = 14.0;

        final layout = StudioDockLayout.defaultLayout();

        final snap1 = StudioReloadSnapshot.capture(
          scene: scene,
          selectedIds: [hero.transform.instanceId],
          camera: camera,
          dockLayout: layout,
          activeTool: 'rotate',
        );

        final wire1 = snap1.toCanonicalJson();
        final decoded = StudioReloadSnapshot.fromJson(
          jsonDecode(wire1) as Map<String, Object?>,
        );
        expect(decoded.toCanonicalJson(), equals(wire1));

        final restoredCamera = EditorCameraController();
        final restoredLayout = decoded.restoreInto(camera: restoredCamera);
        final restoredScene = decoded.restoreScene();

        expect(restoredCamera.target, equals(const Vec3(4.5, 2.0, -7.25)));
        expect(restoredCamera.yawRadians, closeTo(1.15, 1e-6));
        expect(restoredCamera.pitchRadians, closeTo(-0.35, 1e-6));
        expect(restoredCamera.distance, closeTo(14.0, 1e-6));
        expect(decoded.activeTool, equals('rotate'));
        expect(decoded.selectedIds, equals([hero.transform.instanceId]));
        expect(restoredLayout.toJson(), equals(layout.toJson()));
        expect(
          restoredScene.find('Hero')!.transform.position.x,
          closeTo(4.5, 1e-6),
        );
      },
    );
  });
}
