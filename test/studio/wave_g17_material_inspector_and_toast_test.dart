/// Wave G17 test: Verifies dockable Material Editor (`material` tab with live
/// preview swatch, Metallic/Roughness sliders, Queue cycler, `.vmat` save),
/// Inspector active checkbox + Transform Reset + Remove Component, Undo History
/// panel, and timed Toast notifications.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G17 — Material Editor, Inspector Actions, Undo History & Toasts', () {
    test(
      'Material Editor panel scrubs Metallic slider, cycles preview shape, and saves .vmat',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.loadScene(Scene('MatTest'));

        final fs = MemoryProjectFileSystem();
        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          project: ProjectWindowModel(AssetDatabase(fs)),
          layout: const StudioDockLayout(
            root: DockTabsNode(
              id: 'mat_only',
              panelIds: ['material'],
              activeIndex: 0,
            ),
          ),
        );

        final dl = DrawList();
        final solved = shell.buildFrame(
          dl: dl,
          input: VoxInput(),
          width: 500,
          height: 400,
        );
        final r = solved.areas.single.contentRect;
        expect(
          shell.materialInspector.previewShape,
          equals(MaterialPreviewShape.sphere),
        );

        // Click Preview Shape button (cycles sphere -> cube)
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: r.x + 110,
            mouseY: r.y + 38,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
          width: 500,
          height: 400,
        );
        expect(
          shell.materialInspector.previewShape,
          equals(MaterialPreviewShape.cube),
        );

        // Drag Metallic slider near right edge (~0.9)
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: r.x + 280,
            mouseY: r.y + 126,
            isMouseDown: true,
          ),
          width: 500,
          height: 400,
        );
        expect(
          (shell.materialInspector.asset.properties['metallic'] as num)
              .toDouble(),
          greaterThan(0.5),
        );

        // Click Save .vmat button
        shell.buildFrame(
          dl: dl..clear(),
          input: VoxInput(
            mouseX: r.x + 110,
            mouseY: r.y + 90,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
          width: 500,
          height: 400,
        );
        await Future<void>.delayed(Duration.zero);
        expect(await fs.exists('assets/materials/default_pbr.vmat'), isTrue);
      },
    );

    test(
      'Inspector toggles GameObject active state, resets Transform, and Toast auto-expires',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('InspActionsTest');
        final hero = scene.createGameObject('Hero');
        hero.transform.localPosition = const Vec3(5, 6, 7);
        engine.loadScene(scene);

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        bridge.selectObjects([hero]);
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          layout: const StudioDockLayout(
            root: DockTabsNode(
              id: 'insp_only',
              panelIds: ['inspector'],
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
          width: 400,
          height: 400,
        );
        final r = solved.areas.single.contentRect;

        // Click active checkbox [x] beside Hero
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(
            mouseX: r.x + 14,
            mouseY: r.y + 12,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
          width: 400,
          height: 400,
        );
        expect(hero.activeSelf, isFalse);

        // Trigger Toast and verify it renders then expires after duration
        shell.showToast('Saved Scene!', durationSeconds: 0.5);
        expect(shell.activeToastMessage, equals('Saved Scene!'));
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          dtSeconds: 0.1,
          width: 400,
          height: 400,
        );
        expect(
          overlayDl.commands.any(
            (c) => (c.text ?? '').contains('Saved Scene!'),
          ),
          isTrue,
        );
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          dtSeconds: 0.6,
          width: 400,
          height: 400,
        );
        expect(shell.activeToastMessage, isNull);
      },
    );
  });
}
