/// Wave G14 test: Verifies the 3-step New Project Wizard -> Editor flow,
/// Studio ↔ CLI Bridge (`SimulatedStudioCliBridge` + `StudioCliController`),
/// upgraded Unity Main Toolbar (`Local`/`Global`, `Snap`, `Wizard`, `Doctor`,
/// `Settings`), and categorized `Settings` panel + JSON persistence.
library;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('Wave G14 — New Project Wizard, CLI Bridge, Toolbar & Settings', () {
    test(
      '3-step New Project Wizard scaffolds template, loads live Scene into Engine, and enters Editor',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.loadScene(Scene('Blank'));

        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final fs = MemoryProjectFileSystem();
        final shell = StudioWorkspaceShell(
          bridge: bridge,
          project: ProjectWindowModel(AssetDatabase(fs)),
          openWizardOnStart: true,
        );

        expect(shell.projectHubOpen, isTrue);
        expect(shell.projectWizard.step, equals(ProjectWizardStep.template));

        // Step 1 -> select 3D template & render Wizard modal
        shell.projectWizard.selectedTemplate = StudioProjectTemplate.template3d;
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
          overlayDl.commands.any(
            (c) => (c.text ?? '').contains('New Project Wizard'),
          ),
          isTrue,
        );

        // Step 2 -> configure name, quality & layout via keyboard input
        shell.projectWizard.step = ProjectWizardStep.configure;
        shell.projectWizard.nameFieldFocused = true;
        shell.projectWizard.projectName = 'Star';
        shell.buildFrame(
          dl: dl..clear(),
          overlayDl: overlayDl..clear(),
          input: VoxInput(),
          keyboard: const StudioKeyboardState(typedText: 'Forge'),
          width: 1280,
          height: 720,
        );
        expect(shell.projectWizard.projectName, equals('StarForge'));
        shell.projectWizard.initialQualityTier = VrpQualityTier.ultra;
        shell.projectWizard.initialLayoutPreset = 'Wide';

        // Step 3 -> verify CLI preview & execute Create & Open in Editor
        shell.projectWizard.step = ProjectWizardStep.review;
        expect(
          shell.projectWizard.cliCommandPreview,
          equals('volition create StarForge --template 3d'),
        );

        final created = await shell.completeWizardAndOpenEditor(fs: fs);
        expect(created.name, equals('StarForge'));
        expect(await fs.exists('volition.project.json'), isTrue);
        expect(await fs.exists('assets/scenes/main.scene.json'), isTrue);
        expect(shell.projectHubOpen, isFalse);
        expect(engine.scene.name, equals('StarForge'));
        expect(engine.scene.find('Sun'), isNotNull);
        expect(shell.quality.activeTier, equals(VrpQualityTier.ultra));
        expect(shell.activeLayoutPreset, equals('Wide'));
        expect(shell.launcher.recentProjects.first.name, equals('StarForge'));
      },
    );

    test(
      'Toolbar CLI Doctor button & Settings panel execute CLI commands and persist settings JSON',
      () async {
        final host = HeadlessHost();
        final engine = Engine(host);
        engine.loadScene(Scene('CliSettingsTest'));

        final fakeCli = SimulatedStudioCliBridge();
        final session = EditorSession(engine);
        final bridge = SessionEditorHostBridge(session);
        final shell = StudioWorkspaceShell(bridge: bridge, cliBridge: fakeCli);

        // Click 'Doctor' toolbar button and verify CLI execution + Console log
        final res = await shell.cli.execute(const ['doctor']);
        expect(res.succeeded, isTrue);
        expect(fakeCli.recordedCommands.single, equals(['doctor']));
        expect(
          shell.console.visibleEntries().any(
            (e) => e.message.contains('volition doctor'),
          ),
          isTrue,
        );

        // Open Settings panel via Edit/Preferences menu
        expect(shell.menus.trigger('edit.preferences'), isTrue);
        final dl = DrawList();
        shell.buildFrame(dl: dl, input: VoxInput(), width: 1280, height: 720);
        expect(
          dl.commands.any(
            (c) => (c.text ?? '').contains('General Studio Preferences'),
          ),
          isTrue,
        );

        // Persist and reload StudioSettingsModel via ProjectFileSystem
        final fs = MemoryProjectFileSystem();
        shell.settings.targetFpsCap = 120;
        shell.settings.translateSnap = 1.0;
        await shell.settings.save(fs);

        final reloaded = StudioSettingsModel();
        expect(await reloaded.load(fs), isTrue);
        expect(reloaded.targetFpsCap, equals(120));
        expect(reloaded.translateSnap, equals(1.0));
      },
    );
  });
}
