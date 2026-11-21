/// Wave G18 test: Verifies Scene View Orientation Compass (`Persp`/`2D`,
/// `Top`, `Front`, `Right`), Game View `Stats` HUD overlay, and dockable
/// `Animator` State Machine panel (`AnimatorControllerModel`).
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Wave G18 — Scene View Compass, Game View Stats HUD & Animator Panel',
    () {
      test(
        'Scene View Orientation Compass snaps camera to Top/Front/Right/2D',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          engine.loadScene(Scene('CompassTest'));

          final session = EditorSession(engine);
          final bridge = SessionEditorHostBridge(session);
          final shell = StudioWorkspaceShell(bridge: bridge);
          final dl = DrawList();
          final overlayDl = DrawList();

          shell.buildFrame(
            dl: dl,
            overlayDl: overlayDl,
            input: VoxInput(),
            width: 1280,
            height: 720,
          );
          final sceneSlot = shell.activeViewportSlots.firstWhere(
            (s) => s.panelId == 'scene',
          );

          // Click 'Top' preset pill in top-right of Scene View
          shell.buildFrame(
            dl: dl..clear(),
            overlayDl: overlayDl..clear(),
            input: VoxInput(
              mouseX: sceneSlot.rect.right - 120,
              mouseY: sceneSlot.rect.y + 16,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 1280,
            height: 720,
          );
          expect(
            shell.sceneViewport.editorCamera.pitchRadians,
            closeTo(1.50, 1e-4),
          );

          // Click 'Persp'/'2D' toggle pill
          shell.buildFrame(
            dl: dl..clear(),
            overlayDl: overlayDl..clear(),
            input: VoxInput(
              mouseX: sceneSlot.rect.right - 170,
              mouseY: sceneSlot.rect.y + 16,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 1280,
            height: 720,
          );
          expect(shell.sceneViewport.editorCamera.isOrthographic2D, isTrue);
        },
      );

      test(
        'Game View Stats toggle renders live FPS/Scene Stats HUD overlay',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          final scene = Scene('StatsTest');
          scene.createGameObject('MainCamera').addComponent(Camera());
          engine.loadScene(scene);

          final session = EditorSession(engine);
          final bridge = SessionEditorHostBridge(session);
          final shell = StudioWorkspaceShell(
            bridge: bridge,
            layout: const StudioDockLayout(
              root: DockTabsNode(
                id: 'game_only',
                panelIds: ['game'],
                activeIndex: 0,
              ),
            ),
          );
          final dl = DrawList();
          final overlayDl = DrawList();
          final solved = shell.buildFrame(
            dl: dl,
            overlayDl: overlayDl,
            input: VoxInput(),
            width: 800,
            height: 500,
          );
          final r = solved.areas.single.contentRect;
          expect(shell.gameViewport.showStats, isFalse);

          // Click 'Stats' pill in Game View overlay
          shell.buildFrame(
            dl: dl..clear(),
            overlayDl: overlayDl..clear(),
            input: VoxInput(
              mouseX: r.x + 156,
              mouseY: r.y + 16,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 800,
            height: 500,
          );
          expect(shell.gameViewport.showStats, isTrue);
          expect(
            overlayDl.commands.any(
              (c) => (c.text ?? '').contains('Game Stats'),
            ),
            isTrue,
          );
        },
      );

      test(
        'dockable Animator panel scrubs speed parameter and steps Idle -> Run',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          engine.loadScene(Scene('AnimTest'));

          final session = EditorSession(engine);
          final bridge = SessionEditorHostBridge(session);
          final shell = StudioWorkspaceShell(
            bridge: bridge,
            layout: const StudioDockLayout(
              root: DockTabsNode(
                id: 'anim_only',
                panelIds: ['animator'],
                activeIndex: 0,
              ),
            ),
          );
          final dl = DrawList();
          final solved = shell.buildFrame(
            dl: dl,
            input: VoxInput(),
            width: 800,
            height: 400,
          );
          final r = solved.areas.single.contentRect;
          expect(shell.animatorController.activeState, equals('Idle'));

          // Scrub 'speed' parameter right (+50px -> +1.0 > 0.5 threshold)
          shell.buildFrame(
            dl: dl..clear(),
            input: VoxInput(
              mouseX: r.x + 40,
              mouseY: r.y + 38,
              mouseDeltaX: 50.0,
              isMouseDown: true,
            ),
            width: 800,
            height: 400,
          );
          expect(
            shell.animatorController.parameters['speed'],
            greaterThan(0.5),
          );

          // Click 'Step Eval' -> transitions Idle -> Run!
          shell.buildFrame(
            dl: dl..clear(),
            input: VoxInput(
              mouseX: r.x + 40,
              mouseY: r.y + 92,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 800,
            height: 400,
          );
          expect(shell.animatorController.activeState, equals('Run'));
        },
      );
    },
  );
}
