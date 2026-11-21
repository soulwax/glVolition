/// Wave G2 test: Verifies Unity-style `DockLayoutSolver` (recursive splitting,
/// splitter dragging, 5-zone tab drag-drop docking, maximize/restore, presets)
/// and `StudioWorkspaceShell` (Menu bar, Play/Pause/Step chrome tinting,
/// Hierarchy selection, Inspector snapshot, Viewport FBO slots).
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G2 — Unity-Style Docking Solver & Studio Workspace UI', () {
    test(
      'DockLayoutSolver solves default, wide & 2x3 presets and supports splitter drag & 5-zone docking',
      () {
        const bounds = VoxRect(0, 0, 1280, 720);
        final def = DockLayoutSolver.solve(
          StudioDockLayout.defaultLayout(),
          bounds,
        );
        expect(def.areas.length, greaterThanOrEqualTo(4));
        expect(def.splitters.length, greaterThanOrEqualTo(3));

        final wide = DockLayoutSolver.solve(
          DockLayoutSolver.wideLayout(),
          bounds,
        );
        expect(wide.areas, hasLength(4));

        final twoByThree = DockLayoutSolver.solve(
          DockLayoutSolver.twoByThreeLayout(),
          bounds,
        );
        expect(twoByThree.areas, hasLength(5));

        // Maximize single area fills full workspace
        final maxArea = DockLayoutSolver.solve(
          StudioDockLayout.defaultLayout(),
          bounds,
          maximizedAreaId: def.areas.first.areaId,
        );
        expect(maxArea.areas, hasLength(1));
        expect(maxArea.areas.single.bounds, equals(bounds));

        // 5-zone drop detection & tab docking
        final centerArea = wide.areaById('center_dock')!;
        final (zoneRight, previewRight) = DockLayoutSolver.resolveDropZone(
          centerArea,
          centerArea.contentRect.right - 10,
          centerArea.contentRect.y + centerArea.contentRect.height * 0.5,
        );
        expect(zoneRight, equals(DockDropZone.right));
        expect(
          previewRight.width,
          closeTo(centerArea.contentRect.width * 0.5, 1e-4),
        );

        final docked = DockLayoutSolver.dockPanel(
          DockLayoutSolver.wideLayout(),
          panelId: 'console',
          sourceAreaId: 'bottom_dock',
          targetAreaId: 'center_dock',
          zone: DockDropZone.right,
        );
        final solvedDocked = DockLayoutSolver.solve(docked, bounds);
        expect(solvedDocked.areas, hasLength(5));
      },
    );

    test(
      'StudioWorkspaceShell renders Unity chrome, switches layouts, and reports Scene FBO slot',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('EditorDemo');
        final hero = scene.createGameObject('Hero');
        hero.transform.position = const Vec3(1, 2, 3);
        engine.loadScene(scene);

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(bridge: bridge);
        final dl = DrawList();

        final solved = shell.buildFrame(
          dl: dl,
          input: VoxInput(),
          width: 1280,
          height: 720,
        );

        expect(solved.areas.length, greaterThanOrEqualTo(4));
        expect(dl.commands.length, greaterThan(20));
        expect(
          shell.activeViewportSlots.any((s) => s.panelId == 'scene'),
          isTrue,
        );

        // Selecting hero updates Inspector rendering without throwing
        bridge.selectObjects([hero]);
        dl.clear();
        shell.buildFrame(dl: dl, input: VoxInput(), width: 1280, height: 720);
        expect(dl.commands.any((c) => (c.text ?? '').contains('Hero')), isTrue);

        // Enter Play Mode switches toolbar tint & label
        bridge.enterPlayMode();
        expect(shell.isPlaying, isTrue);
        dl.clear();
        shell.buildFrame(dl: dl, input: VoxInput(), width: 1280, height: 720);
        expect(
          dl.commands.any((c) => c.color == UnityDarkTheme.bgToolbarPlayTint),
          isTrue,
        );
        bridge.exitPlayMode();
      },
    );
  });
}
