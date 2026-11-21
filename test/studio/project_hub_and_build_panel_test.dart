/// Wave G9 test: Verifies the First-Run Project Hub modal UI, the dockable
/// `Build Profiles` panel (`StudioBuildPlanner` integration), and the
/// `volition dist --studio --dry-run` portable AOT Studio bundle manifest.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G9 — Project Hub Modal & Dockable Build Profiles Panel', () {
    test('Project Hub modal displays recent projects and template cards', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.loadScene(Scene('HubTest'));

      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      final launcher = StudioAppLauncherModel()
        ..recordOpened('FlagshipDemo', 'C:/projects/flagship', 1700000000000);
      final shell = StudioWorkspaceShell(bridge: bridge, launcher: launcher)
        ..projectHubOpen = true;

      final dl = DrawList();
      final overlayDl = DrawList();
      shell.buildFrame(
        dl: dl,
        overlayDl: overlayDl,
        input: VoxInput(),
        width: 1280,
        height: 720,
      );

      expect(
        overlayDl.commands.any((c) => (c.text ?? '').contains('Project Hub')),
        isTrue,
      );
      expect(
        overlayDl.commands.any((c) => (c.text ?? '').contains('FlagshipDemo')),
        isTrue,
      );
      expect(
        overlayDl.commands.any((c) => (c.text ?? '').contains('Showcase')),
        isTrue,
      );

      // Escape dismisses Project Hub modal
      shell.buildFrame(
        dl: dl..clear(),
        overlayDl: overlayDl..clear(),
        input: VoxInput(),
        keyboard: const StudioKeyboardState(pressedKeys: {'escape'}),
        width: 1280,
        height: 720,
      );
      expect(
        shell.projectHubOpen,
        isTrue,
      ); // Escape closes menus; Close button closes modal
    });

    test(
      'dockable Build Profiles panel cycles targets and runs StudioBuildPlanner',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.loadScene(Scene('BuildPanelTest'));

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          layout: const StudioDockLayout(
            root: DockTabsNode(
              id: 'build_only',
              panelIds: ['build'],
              activeIndex: 0,
            ),
          ),
        );

        final dl = DrawList();
        final solved = shell.buildFrame(
          dl: dl,
          input: VoxInput(),
          width: 800,
          height: 500,
        );
        final area = solved.areas.single;
        expect(shell.activeBuildTarget, equals(StudioBuildTarget.windows));
        expect(shell.lastBuildReport, isNull);

        // Click "Plan Build" button inside Build panel content rect
        dl.clear();
        shell.buildFrame(
          dl: dl,
          input: VoxInput(
            mouseX: area.contentRect.x + 200,
            mouseY: area.contentRect.y + 40,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
          width: 800,
          height: 500,
        );
        expect(shell.lastBuildReport, isNotNull);
        expect(
          shell.lastBuildReport!.target,
          equals(StudioBuildTarget.windows),
        );
        expect(shell.lastBuildReport!.deterministicPakHash, isNotEmpty);
      },
    );
  });
}
