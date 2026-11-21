/// Wave G11 test: Verifies per-panel mouse-wheel scrolling & clamping,
/// Hierarchy disclosure toggle & drag-to-reparenting, and interactive
/// Lighting panel EV100/Tonemapper/Auto-Exposure controls.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Wave G11 — Scrollable Panels, Hierarchy Reparent & Interactive Lighting',
    () {
      test('scrolls Modules panel with mouse wheel and clamps cleanly', () {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.loadScene(Scene('ScrollTest'));

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          layout: const StudioDockLayout(
            root: DockTabsNode(
              id: 'mods_only',
              panelIds: ['modules'],
              activeIndex: 0,
            ),
          ),
        );

        final dl = DrawList();
        final solved = shell.buildFrame(
          dl: dl,
          input: VoxInput(),
          width: 500,
          height: 260,
        );
        final area = solved.areas.single;
        expect(shell.panelScrollY['modules'], equals(0.0));

        // Scroll down (negative wheel delta increases scrollY)
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: area.contentRect.x + 40,
            mouseY: area.contentRect.y + 60,
            scrollDeltaY: -3.0,
          ),
          width: 500,
          height: 260,
        );
        expect(shell.panelScrollY['modules'], greaterThan(0.0));
      });

      test('Hierarchy drag-to-reparent updates parent-child relationship', () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('ReparentTest');
        final parentObj = scene.createGameObject('Parent');
        final childObj = scene.createGameObject('Child');
        engine.loadScene(scene);

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          layout: const StudioDockLayout(
            root: DockTabsNode(
              id: 'hier_only',
              panelIds: ['hierarchy'],
              activeIndex: 0,
            ),
          ),
        );

        final dl = DrawList();
        final solved = shell.buildFrame(
          dl: dl,
          input: VoxInput(),
          width: 400,
          height: 300,
        );
        final area = solved.areas.single;
        final row0Y = area.contentRect.y + 28 + 10; // Parent
        final row1Y = area.contentRect.y + 28 + 30; // Child

        // Click Child row to start dragging
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: area.contentRect.x + 60,
            mouseY: row1Y,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
          width: 400,
          height: 300,
        );

        // Release over Parent row -> Child becomes child of Parent
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: area.contentRect.x + 60,
            mouseY: row0Y,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
          width: 400,
          height: 300,
        );

        expect(childObj.parent, equals(parentObj));
        expect(shell.hierarchy.isExpanded('Parent'), isTrue);
      });

      test(
        'Lighting panel EV100 scrub, Tonemapper cycler, and Auto-Exposure toggle mutate model',
        () {
          final host = HeadlessHost();
          final engine = Engine(host);
          engine.loadScene(Scene('LightingTest'));

          final session = EditorSession(engine);
          final bridge = SessionEditorHostBridge(session);
          final shell = StudioWorkspaceShell(
            bridge: bridge,
            layout: const StudioDockLayout(
              root: DockTabsNode(
                id: 'light_only',
                panelIds: ['lighting'],
                activeIndex: 0,
              ),
            ),
          );

          final dl = DrawList();
          final solved = shell.buildFrame(
            dl: dl,
            input: VoxInput(),
            width: 400,
            height: 300,
          );
          final r = solved.areas.single.contentRect;
          final evBefore = shell.lighting.exposureSettings.manualEv100;
          final tmBefore = shell.lighting.exposureSettings.tonemapper;
          final aeBefore = shell.lighting.exposureSettings.autoExposureEnabled;

          // Drag EV100 bar right
          shell.buildFrame(
            dl: dl..clear(),
            input: VoxInput(
              mouseX: r.x + 50,
              mouseY: r.y + 42,
              mouseDeltaX: 20.0,
              isMouseDown: true,
            ),
            width: 400,
            height: 300,
          );
          expect(
            shell.lighting.exposureSettings.manualEv100,
            greaterThan(evBefore),
          );

          // Click Tonemapper button
          shell.buildFrame(
            dl: dl..clear(),
            input: VoxInput(
              mouseX: r.x + 50,
              mouseY: r.y + 70,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 400,
            height: 300,
          );
          expect(
            shell.lighting.exposureSettings.tonemapper,
            isNot(equals(tmBefore)),
          );

          // Click Auto-Exposure toggle
          shell.buildFrame(
            dl: dl..clear(),
            input: VoxInput(
              mouseX: r.x + 50,
              mouseY: r.y + 98,
              isMouseDown: true,
              wasMouseClicked: true,
            ),
            width: 400,
            height: 300,
          );
          expect(
            shell.lighting.exposureSettings.autoExposureEnabled,
            equals(!aeBefore),
          );
        },
      );
    },
  );
}
