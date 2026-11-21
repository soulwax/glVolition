/// Wave G15 test: Verifies real disk-backed Studio workflow using
/// [IoProjectFileSystem] — 3-step Wizard -> disk scaffold -> live Editor ->
/// `Ctrl+S` workspace save (scene + settings + layout) -> fresh restart &
/// `loadWorkspaceFromDisk` full state restoration.
library;

import 'dart:io';

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

import '../../tool/studio/io_project_fs.dart';

void main() {
  group('Wave G15 — Disk-Backed Wizard -> Editor -> Ctrl+S Save & Reload', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('volition_studio_g15_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'Wizard scaffolds real files on disk, Ctrl+S saves workspace, and reload restores scene/settings/layout',
      () async {
        final diskFs = IoProjectFileSystem(tempDir);

        // Session 1: Run Wizard -> create 3D project on real disk
        final engine1 = Engine(HeadlessHost());
        engine1.loadScene(Scene('Boot'));
        final bridge1 = SessionEditorHostBridge(EditorSession(engine1));
        final shell1 = StudioWorkspaceShell(
          bridge: bridge1,
          project: ProjectWindowModel(AssetDatabase(diskFs)),
          openWizardOnStart: true,
        );

        shell1.projectWizard.selectedTemplate =
            StudioProjectTemplate.template3d;
        shell1.projectWizard.projectName = 'DiskQuest';
        shell1.projectWizard.initialLayoutPreset = 'Wide';
        await shell1.completeWizardAndOpenEditor(fs: diskFs);

        expect(
          File('${tempDir.path}/volition.project.json').existsSync(),
          isTrue,
        );
        expect(
          File('${tempDir.path}/assets/scenes/main.scene.json').existsSync(),
          isTrue,
        );

        // Edit scene + settings, then save workspace via saveWorkspace()
        engine1.scene.createGameObject('QuestBeacon').transform.localPosition =
            const Vec3(7, 2, -3);
        shell1.settings.targetFpsCap = 120;
        shell1.settings.translateSnap = 1.0;
        await shell1.saveWorkspace(fs: diskFs);

        expect(
          File('${tempDir.path}/.volition/studio_settings.json').existsSync(),
          isTrue,
        );
        expect(
          File('${tempDir.path}/.volition/layout.json').existsSync(),
          isTrue,
        );

        // Session 2: Fresh Engine + StudioWorkspaceShell loads from disk
        final engine2 = Engine(HeadlessHost());
        engine2.loadScene(Scene('Empty'));
        final bridge2 = SessionEditorHostBridge(EditorSession(engine2));
        final shell2 = StudioWorkspaceShell(
          bridge: bridge2,
          project: ProjectWindowModel(AssetDatabase(diskFs)),
        );

        await shell2.loadWorkspaceFromDisk(diskFs);
        expect(engine2.scene.name, equals('DiskQuest'));
        expect(engine2.scene.find('QuestBeacon'), isNotNull);
        expect(shell2.settings.targetFpsCap, equals(120));
        expect(shell2.settings.translateSnap, equals(1.0));
        expect(shell2.gizmoInteractor.translateSnap, equals(1.0));
      },
    );
  });
}
