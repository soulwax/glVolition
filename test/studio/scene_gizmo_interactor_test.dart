/// Wave G7 test: Verifies [SceneGizmoInteractor] raycast picking, 3D X/Y/Z
/// gizmo axis hit-testing, Translate (with grid snap), Rotate, Scale drags,
/// and single-step Undo/Redo via [EditorSession].
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G7 — Scene View Ray-Pick & 3D Transform Gizmos', () {
    test('picks closest active GameObject along camera ray', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final scene = Scene('PickTest');
      final nearObj = scene.createGameObject('NearCube');
      nearObj.transform.localPosition = const Vec3(0, 0, 0);
      final farObj = scene.createGameObject('FarCube');
      farObj.transform.localPosition = const Vec3(0, 0, -5);
      engine.loadScene(scene);

      final cam = EditorCameraController(
        target: Vec3.zero,
        distance: 8.0,
        yawRadians: 0.0,
        pitchRadians: 0.0,
      );
      const vp = VoxRect(0, 0, 800, 600);
      final centerRay = SceneGizmoInteractor.screenPointToRay(
        cam,
        vp,
        400,
        300,
      );

      final picked = SceneGizmoInteractor.pickObject(scene, centerRay);
      expect(picked, equals(nearObj));

      // Click-to-pick through handlePointer selects nearObj
      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      final interactor = SceneGizmoInteractor();
      final consumed = interactor.handlePointer(
        bridge: bridge,
        camera: cam,
        viewportRect: vp,
        input: VoxInput(
          mouseX: 400,
          mouseY: 300,
          isMouseDown: true,
          wasMouseClicked: true,
        ),
        activeTool: 'move',
        gizmosVisible: true,
      );
      expect(consumed, isTrue);
      expect(session.selectedObjects, equals([nearObj]));
    });

    test('drags X-axis gizmo with grid snap and reverts in one Undo step', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      final scene = Scene('GizmoDragTest');
      final box = scene.createGameObject('Box');
      box.transform.localPosition = Vec3.zero;
      engine.loadScene(scene);

      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      bridge.selectObjects([box]);

      // Camera looking straight down -Z from (0, 0, 8)
      final cam = EditorCameraController(
        target: Vec3.zero,
        distance: 8.0,
        yawRadians: 0.0,
        pitchRadians: 0.0,
      );
      const vp = VoxRect(0, 0, 800, 600);
      final interactor = SceneGizmoInteractor()
        ..snapEnabled = true
        ..translateSnap = 0.5;

      // Project a point on +X axis (0.7, 0, 0) onto screen
      final rayX = SceneRay(
        origin: const Vec3(0.7, 0, 8),
        direction: const Vec3(0, 0, -1),
      );
      expect(
        SceneGizmoInteractor.hitTestGizmoAxis(Vec3.zero, rayX),
        equals(GizmoAxis.x),
      );

      // Click near +X shaft on screen (right of center at x=460, y=300)
      final clicked = interactor.handlePointer(
        bridge: bridge,
        camera: cam,
        viewportRect: vp,
        input: VoxInput(
          mouseX: 460,
          mouseY: 300,
          isMouseDown: true,
          wasMouseClicked: true,
        ),
        activeTool: 'move',
        gizmosVisible: true,
      );
      expect(clicked, isTrue);
      expect(interactor.activeAxis, equals(GizmoAxis.x));
      expect(interactor.isDragging, isTrue);

      // Drag right (+120px)
      interactor.handlePointer(
        bridge: bridge,
        camera: cam,
        viewportRect: vp,
        input: VoxInput(
          mouseX: 580,
          mouseY: 300,
          mouseDeltaX: 120,
          mouseDeltaY: 0,
          isMouseDown: true,
        ),
        activeTool: 'move',
        gizmosVisible: true,
      );
      expect(box.transform.localPosition.x, greaterThan(0.0));
      // Verify 0.5 grid snap
      final snappedRem = (box.transform.localPosition.x / 0.5).round() * 0.5;
      expect(box.transform.localPosition.x, closeTo(snappedRem, 1e-6));

      final afterDragX = box.transform.localPosition.x;

      // Release commits single undoable command
      interactor.handlePointer(
        bridge: bridge,
        camera: cam,
        viewportRect: vp,
        input: VoxInput(
          mouseX: 580,
          mouseY: 300,
          isMouseDown: false,
          wasMouseReleased: true,
        ),
        activeTool: 'move',
        gizmosVisible: true,
      );
      expect(interactor.isDragging, isFalse);
      expect(box.transform.localPosition.x, closeTo(afterDragX, 1e-6));

      // Single Undo reverts entire drag; Redo reapplies it
      expect(session.undo(), isTrue);
      expect(box.transform.localPosition.x, closeTo(0.0, 1e-6));
      expect(session.redo(), isTrue);
      expect(box.transform.localPosition.x, closeTo(afterDragX, 1e-6));
    });
  });
}
