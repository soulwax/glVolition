/// Wave G13 test: Verifies `Window > ...` dynamic tab focus/spawning
/// (`openOrFocusPanel`), `windowTitle` dirty-state indicator, and
/// `saveActiveScene` / `newScene` JSON persistence.
library;

import 'dart:convert';

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G13 — Window Menu Spawning, Dirty Title & Scene Save/Load', () {
    test('Window menu triggers openOrFocusPanel for Graph & Timeline tabs', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.loadScene(Scene('Level01'));

      final session = EditorSession(engine);
      final bridge = SessionEditorHostBridge(session);
      final shell = StudioWorkspaceShell(bridge: bridge);

      expect(shell.windowTitle, contains('Level01'));

      // Trigger Window/Node Graph menu item -> spawns & focuses 'graph' tab
      expect(shell.menus.trigger('window.open.graph'), isTrue);
      final solvedGraph = DockLayoutSolver.solve(
        shell.layout,
        const VoxRect(0, 0, 1280, 720),
      );
      expect(solvedGraph.areas.any((a) => a.activePanelId == 'graph'), isTrue);

      // Trigger Window/Timeline menu item -> spawns & focuses 'timeline' tab
      expect(shell.menus.trigger('window.open.timeline'), isTrue);
      final solvedTimeline = DockLayoutSolver.solve(
        shell.layout,
        const VoxRect(0, 0, 1280, 720),
      );
      expect(
        solvedTimeline.areas.any((a) => a.activePanelId == 'timeline'),
        isTrue,
      );

      // Trigger File/Project Hub opens modal
      expect(shell.projectHubOpen, isFalse);
      expect(shell.menus.trigger('file.project_hub'), isTrue);
      expect(shell.projectHubOpen, isTrue);
    });

    test(
      'saveActiveScene writes valid scene JSON and newScene resets active scene',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = Scene('MainHall');
        scene.createGameObject('Torch').transform.localPosition = const Vec3(
          1,
          2,
          3,
        );
        engine.loadScene(scene);

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(bridge: bridge);
        final fs = MemoryProjectFileSystem();

        final savedPath = await shell.saveActiveScene(fs);
        expect(savedPath, equals('Assets/Scenes/MainHall.scene.json'));
        expect(await fs.exists(savedPath), isTrue);

        final decoded =
            jsonDecode(await fs.readString(savedPath)) as Map<String, Object?>;
        expect(decoded['name'], equals('MainHall'));

        shell.newScene(name: 'FreshScene');
        expect(engine.scene.name, equals('FreshScene'));
        expect(engine.scene.rootGameObjects, isEmpty);
        expect(shell.windowTitle, contains('FreshScene'));
      },
    );
  });
}
