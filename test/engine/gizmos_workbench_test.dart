/// 3D Viewport Gizmos, Workbench/Inspector integration & Prefab Variant UI tests (P7-W15-B).
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('P7-W15-B — ViewportGizmos Axis Hit-Testing & Snapped Dragging', () {
    test(
      'hit-testing identifies X, Y, and Z axis handles accurately from raycasts',
      () {
        final engine = Engine(HeadlessHost());
        final gizmos = engine.scene.viewportGizmos;
        gizmos.gizmoSize = 2.0;
        gizmos.hitThreshold = 0.3;

        const origin = Vec3(0.0, 0.0, 0.0);

        // Ray aimed at X axis (x = 1.0, y = 0.05, z = 0.0) from z = -5 looking towards +z
        final rayX = Ray(
          origin: const Vec3(1.0, 0.05, -5.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        final hitX = gizmos.hitTest(rayX, origin);
        expect(hitX, isNotNull);
        expect(hitX!.axis, equals(ViewportGizmoAxis.x));

        // Ray aimed at Y axis (x = 0.05, y = 1.0, z = 0.0) from z = -5 looking towards +z
        final rayY = Ray(
          origin: const Vec3(0.05, 1.0, -5.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        final hitY = gizmos.hitTest(rayY, origin);
        expect(hitY, isNotNull);
        expect(hitY!.axis, equals(ViewportGizmoAxis.y));

        // Ray aimed at Z axis (x = 0.05, y = 0.0, z = 1.0) from x = -5 looking towards +x
        final rayZ = Ray(
          origin: const Vec3(-5.0, 0.05, 1.0),
          direction: const Vec3(1.0, 0.0, 0.0),
        );
        final hitZ = gizmos.hitTest(rayZ, origin);
        expect(hitZ, isNotNull);
        expect(hitZ!.axis, equals(ViewportGizmoAxis.z));

        // Ray that completely misses the handles
        final rayMiss = Ray(
          origin: const Vec3(10.0, 10.0, -5.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        final hitMiss = gizmos.hitTest(rayMiss, origin);
        expect(hitMiss, isNull);
      },
    );

    test(
      'snapped translation drag applies stepped increments and commits to undo stack',
      () {
        final engine = Engine(HeadlessHost());
        final gizmos = engine.scene.viewportGizmos;
        gizmos.mode = ViewportGizmoMode.translate;
        gizmos.snapEnabled = true;
        gizmos.translateSnap = 0.5;

        final go = engine.scene.createGameObject('Crate', position: Vec3.zero);

        final startRay = Ray(
          origin: const Vec3(0.0, 0.0, -10.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        gizmos.beginDrag(ViewportGizmoAxis.x, startRay, go);

        // Drag along X by 0.65 units -> snaps to 0.5
        final curRay1 = Ray(
          origin: const Vec3(0.65, 0.0, -10.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        gizmos.updateDrag(curRay1, go);
        expect(go.transform.position.x, closeTo(0.5, 1e-4));

        // Drag further along X to 1.15 units -> snaps to 1.0
        final curRay2 = Ray(
          origin: const Vec3(1.15, 0.0, -10.0),
          direction: const Vec3(0.0, 0.0, 1.0),
        );
        gizmos.updateDrag(curRay2, go);
        expect(go.transform.position.x, closeTo(1.0, 1e-4));

        // End drag and commit reversible command
        final cmd = gizmos.endDrag(go);
        expect(cmd, isNotNull);
        engine.editor.executeCommand(cmd!);

        expect(go.transform.position.x, closeTo(1.0, 1e-4));

        // Undo restores to 0.0
        expect(engine.editor.undo(), isTrue);
        expect(go.transform.position.x, closeTo(0.0, 1e-4));

        // Redo restores to 1.0
        expect(engine.editor.redo(), isTrue);
        expect(go.transform.position.x, closeTo(1.0, 1e-4));
      },
    );

    test('snapped scale drag adjusts uniform scale factor cleanly', () {
      final engine = Engine(HeadlessHost());
      final gizmos = engine.scene.viewportGizmos;
      gizmos.mode = ViewportGizmoMode.scale;
      gizmos.snapEnabled = true;
      gizmos.scaleSnap = 0.25;

      final go = engine.scene.createGameObject('Tower', position: Vec3.zero);
      go.transform.localScale = 1.0;

      final startRay = Ray(
        origin: const Vec3(0.0, 0.0, -10.0),
        direction: const Vec3(0.0, 0.0, 1.0),
      );
      gizmos.beginDrag(ViewportGizmoAxis.y, startRay, go);

      // Scale up by ~0.6 -> snaps to 1.5 or 1.75
      final curRay = Ray(
        origin: const Vec3(0.0, 2.5, -10.0),
        direction: const Vec3(0.0, 0.0, 1.0),
      );
      gizmos.updateDrag(curRay, go);
      expect(go.transform.localScale, greaterThan(1.0));
      // Verify scale is snapped to a multiple of 0.25
      final remainder = (go.transform.localScale * 100).round() % 25;
      expect(remainder, equals(0));

      final cmd = gizmos.endDrag(go);
      expect(cmd, isNotNull);
    });

    test(
      'gizmos.render populates line batch with colored axis arrows and shapes',
      () {
        final engine = Engine(HeadlessHost());
        engine.scene.gizmos.enabled = true;
        engine.scene.gizmos.clear();

        engine.scene.viewportGizmos.render(const Vec3(5.0, 2.0, -3.0));
        expect(engine.scene.gizmos.lineCount, greaterThan(0));

        // Test wire disc in rotate mode
        engine.scene.viewportGizmos.mode = ViewportGizmoMode.rotate;
        engine.scene.gizmos.clear();
        engine.scene.viewportGizmos.render(Vec3.zero);
        expect(engine.scene.gizmos.lineCount, greaterThan(0));
      },
    );
  });

  group('P7-W15-B — PrefabInstanceComponent Variant Overrides & Revert', () {
    test(
      'tracks individual property overrides and reverts per-property or in bulk',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject(
          'Tree_Variant',
          position: const Vec3(10.0, 0.0, 0.0),
        );
        final inst = go.addComponent(
          PrefabInstanceComponent(prefabName: 'PineTree'),
        );

        inst.addOrUpdateOverride(
          'position',
          const Vec3(0.0, 0.0, 0.0),
          const Vec3(10.0, 0.0, 0.0),
        );
        inst.addOrUpdateOverride('scale', 1.0, 2.5);

        expect(inst.hasOverride('position'), isTrue);
        expect(inst.hasOverride('scale'), isTrue);
        expect(inst.hasOverride('color'), isFalse);
        expect(inst.overrides.length, equals(2));

        // Revert position override
        expect(inst.revertOverride('position'), isTrue);
        expect(inst.hasOverride('position'), isFalse);
        expect(go.transform.position.x, closeTo(0.0, 1e-4));
        expect(inst.overrides.length, equals(1));

        // Revert all remaining overrides
        inst.revertAll();
        expect(inst.overrides, isEmpty);
        expect(go.transform.localScale, closeTo(1.0, 1e-4));
      },
    );

    test(
      'EngineWorkbenchComponent renders inspector with prefab overrides and gizmo controls',
      () {
        final engine = Engine(HeadlessHost());
        final go = engine.scene.createGameObject(
          'Building_Instance',
          position: const Vec3(2.0, 0.0, 0.0),
        );
        final inst = go.addComponent(
          PrefabInstanceComponent(prefabName: 'TowerBlock'),
        );
        inst.addOrUpdateOverride(
          'position',
          Vec3.zero,
          const Vec3(2.0, 0.0, 0.0),
        );

        final wbGo = engine.scene.createGameObject('Workbench');
        final wb = wbGo.addComponent(
          EngineWorkbenchComponent(
            activeTab: WorkbenchTab.inspector,
            selectedObject: go,
          ),
        );

        // Render a frame
        final drawList = wb.renderFrame(VoxInput());
        expect(drawList, isNotNull);
        expect(wb.selectedObject, equals(go));
      },
    );
  });
}
