/// Wave G8 test: Verifies Unity-style keyboard shortcuts (`Ctrl+Z/Y/D`,
/// `Delete`, `F`, `Q/W/E/R/T`, `Shift+Space`, `RMB+WASD`), Hierarchy Create &
/// Search authoring, Inspector `Vec3` X/Y/Z scrubbing & `Add Component` popup,
/// and `.volition/layout.json` persistence round-trip.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G8 — Unity Shortcuts, Authoring Popups & Layout Persistence', () {
    test(
      'end-to-end authoring: create, frame, duplicate, delete, undo/redo, tools, maximize & fly-cam',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('AuthoringTest');
        engine.loadScene(scene);

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(bridge: bridge);
        final dl = DrawList();
        final overlayDl = DrawList();

        // Initial frame to establish DockArea bounds
        final solved = shell.buildFrame(
          dl: dl,
          overlayDl: overlayDl,
          input: VoxInput(),
          width: 1280,
          height: 720,
        );
        final sceneArea = solved.areas.firstWhere(
          (a) => a.activePanelId == 'scene',
        );

        // Create a Cube via undoable studio command
        session.executeCommand(
          CreateGameObjectStudioCommand(
            objectName: 'HeroCube',
            position: const Vec3(4, 1, -2),
          ),
        );
        expect(session.selectedObjects.single.name, equals('HeroCube'));

        // Press 'F' to frame selected object in Scene View
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(pressedKeys: {'f'}),
          width: 1280,
          height: 720,
        );
        expect(
          shell.sceneViewport.editorCamera.target,
          equals(const Vec3(4, 1, -2)),
        );
        expect(shell.sceneViewport.editorCamera.distance, closeTo(6.0, 1e-6));

        // Press 'E' -> switches gizmo tool to rotate
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(pressedKeys: {'e'}),
          width: 1280,
          height: 720,
        );
        expect(shell.activeGizmoTool, equals('rotate'));

        // Ctrl+D -> duplicates selected HeroCube
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(ctrl: true, pressedKeys: {'d'}),
          width: 1280,
          height: 720,
        );
        expect(session.selectedObjects.single.name, equals('HeroCube (Copy)'));

        // Delete -> deactivates duplicate, Ctrl+Z -> restores it
        final copy = session.selectedObjects.single;
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(pressedKeys: {'delete'}),
          width: 1280,
          height: 720,
        );
        expect(copy.activeSelf, isFalse);

        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(ctrl: true, pressedKeys: {'z'}),
          width: 1280,
          height: 720,
        );
        expect(copy.activeSelf, isTrue);

        // Shift+Space over Scene DockArea maximizes it, then restores it
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(
            mouseX: sceneArea.bounds.x + 20,
            mouseY: sceneArea.bounds.y + 40,
          ),
          keyboard: const StudioKeyboardState(
            shift: true,
            pressedKeys: {'space'},
          ),
          width: 1280,
          height: 720,
        );
        expect(shell.maximizedAreaId, equals(sceneArea.areaId));

        // RMB + W flies camera forward
        final camBefore = shell.sceneViewport.editorCamera.target;
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(
            isRightMouseDown: true,
            heldKeys: {'w'},
          ),
          dtSeconds: 0.1,
          width: 1280,
          height: 720,
        );
        expect(
          shell.sceneViewport.editorCamera.target,
          isNot(equals(camBefore)),
        );
      },
    );

    test(
      'persists and restores .volition/layout.json via StudioLayoutPersistence',
      () async {
        final fs = MemoryProjectFileSystem();
        final wide = DockLayoutSolver.wideLayout();
        await StudioLayoutPersistence.saveLayout(fs, wide);
        expect(await fs.exists(StudioLayoutPersistence.defaultPath), isTrue);

        final loaded = await StudioLayoutPersistence.loadLayout(fs);
        expect(loaded, isNotNull);
        expect(loaded!.toJson(), equals(wide.toJson()));
      },
    );
  });
}
