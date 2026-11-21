/// Pure-Dart 3-Step New Project Wizard → Editor Flow (`[Wave G14]`):
/// Guides the user cleanly from launching Volition Studio to a live editable
/// scene:
/// - **Step 1**: Choose Template (`Empty`, `2D`, `3D`, `Multiplayer`, `Showcase`)
///   or quick-open a Recent Project.
/// - **Step 2**: Configure Project Name (keyboard input), Location, VRP Quality
///   Tier, and Workspace Layout Preset (`Default`, `Wide`, `2 by 3`).
/// - **Step 3**: Review generated manifest & CLI equivalent, then click
///   **Create & Open in Editor** to scaffold via [StudioProjectTemplateGenerator],
///   load the scene directly into the running [Engine], and enter the Editor.
library;

import 'dart:convert';

import '../../../gl_volition.dart';
import '../project/project_fs.dart';
import '../project/project_templates.dart';
import 'app_launcher_model.dart';
import 'studio_shortcuts.dart';

/// Current step in the New Project Wizard.
enum ProjectWizardStep { template, configure, review }

/// Result callback payload emitted when the user finishes the wizard.
final class CreatedStudioProject {
  final String name;
  final String location;
  final StudioProjectTemplate template;
  final VrpQualityTier qualityTier;
  final String layoutPreset;
  final Scene initialScene;
  final ProjectFileSystem fileSystem;

  const CreatedStudioProject({
    required this.name,
    required this.location,
    required this.template,
    required this.qualityTier,
    required this.layoutPreset,
    required this.initialScene,
    required this.fileSystem,
  });
}

/// Interactive 3-step New Project Wizard controller & renderer (`[Wave G14]`).
final class StudioProjectWizardController {
  ProjectWizardStep step = ProjectWizardStep.template;
  StudioProjectTemplate selectedTemplate = StudioProjectTemplate.template3d;
  String projectName = 'MyVolitionGame';
  String locationPath = './projects/MyVolitionGame';
  VrpQualityTier initialQualityTier = VrpQualityTier.high;
  String initialLayoutPreset = 'Default';
  bool nameFieldFocused = false;
  bool isCreating = false;
  String? statusMessage;

  static const List<(StudioProjectTemplate, String, String)> templates = [
    (StudioProjectTemplate.empty, 'Empty', 'Blank scene with MainCamera'),
    (StudioProjectTemplate.template2d, '2D', '2D camera + starter Player2D'),
    (StudioProjectTemplate.template3d, '3D', 'Lit 3D scene + Sun + Ground'),
    (
      StudioProjectTemplate.multiplayer,
      'Multiplayer',
      'NetworkIdentity + Sun starter',
    ),
    (
      StudioProjectTemplate.showcase,
      'Showcase',
      'Full VRP + 6-family flagship',
    ),
  ];

  String get cliTemplateFlag => switch (selectedTemplate) {
    StudioProjectTemplate.empty => 'empty',
    StudioProjectTemplate.template2d => '2d',
    StudioProjectTemplate.template3d => '3d',
    StudioProjectTemplate.multiplayer => 'multiplayer',
    StudioProjectTemplate.showcase => 'showcase',
  };

  String get cliCommandPreview =>
      'volition create $projectName --template $cliTemplateFlag';

  void reset() {
    step = ProjectWizardStep.template;
    nameFieldFocused = false;
    statusMessage = null;
  }

  /// Generates the starter project in [fs], loads its generated `main.scene.json`
  /// into a live [Scene], and returns [CreatedStudioProject].
  Future<CreatedStudioProject> createProject({
    required ProjectFileSystem fs,
    required ComponentRegistry registry,
  }) async {
    isCreating = true;
    try {
      final safeName = projectName.trim().isEmpty
          ? 'MyVolitionGame'
          : projectName.trim();
      await StudioProjectTemplateGenerator.generate(
        fs: fs,
        projectName: safeName,
        template: selectedTemplate,
      );
      final rawScene = await fs.readString('assets/scenes/main.scene.json');
      final scene = SceneSerializer.fromJson(
        jsonDecode(rawScene) as Map<String, Object?>,
        registry: registry,
      );
      return CreatedStudioProject(
        name: safeName,
        location: locationPath,
        template: selectedTemplate,
        qualityTier: initialQualityTier,
        layoutPreset: initialLayoutPreset,
        initialScene: scene,
        fileSystem: fs,
      );
    } finally {
      isCreating = false;
    }
  }

  /// Renders the 3-step Wizard modal into [dl] (overlay layer) and invokes
  /// [onFinishCreate] when the user clicks **Create & Open in Editor**,
  /// [onOpenRecent] when clicking a recent project, or [onClose] on Close.
  void render({
    required DrawList dl,
    required VoxInput input,
    StudioKeyboardState? keyboard,
    required StudioAppLauncherModel launcher,
    required double width,
    required double height,
    required void Function() onFinishCreate,
    required void Function(RecentProjectEntry entry) onOpenRecent,
    required void Function() onClose,
  }) {
    // Handle keyboard editing for project name on Step 2
    if (step == ProjectWizardStep.configure &&
        nameFieldFocused &&
        keyboard != null) {
      if (keyboard.backspace && projectName.isNotEmpty) {
        projectName = projectName.substring(0, projectName.length - 1);
        locationPath = './projects/$projectName';
      }
      if (keyboard.typedText.isNotEmpty) {
        projectName += keyboard.typedText;
        locationPath = './projects/$projectName';
      }
    }

    // Dimmed modal backdrop
    dl.addRectFilled(0, 0, width, height, const VoxColor(10, 12, 16, 200));
    final mw = (width * 0.68).clamp(500.0, 820.0);
    final mh = (height * 0.68).clamp(340.0, 520.0);
    final mx = (width - mw) * 0.5;
    final my = (height - mh) * 0.5;

    dl.addRectFilled(
      mx,
      my,
      mw,
      mh,
      const VoxColor(46, 48, 52, 255),
      cornerRadius: 6,
    );
    dl.addRectOutline(
      mx,
      my,
      mw,
      mh,
      const VoxColor(58, 121, 187, 255),
      thickness: 2,
    );

    // Header + Step indicator pills
    dl.addText(
      'Volition Studio — New Project Wizard',
      mx + 16,
      my + 14,
      color: const VoxColor(235, 238, 244, 255),
      size: 14,
    );
    _button(
      dl,
      input,
      VoxRect(mx + mw - 72, my + 10, 58, 22),
      'Close',
      onClick: onClose,
    );

    const stepLabels = ['1. Template', '2. Configure', '3. Create'];
    for (var i = 0; i < stepLabels.length; i++) {
      final sr = VoxRect(mx + 16 + i * 116, my + 40, 108, 22);
      final isCurrent = step.index == i;
      dl.addRectFilled(
        sr.x,
        sr.y,
        sr.width,
        sr.height,
        isCurrent
            ? const VoxColor(58, 121, 187, 255)
            : const VoxColor(36, 38, 42, 255),
        cornerRadius: 3,
      );
      dl.addText(
        stepLabels[i],
        sr.x + 10,
        sr.y + 5,
        color: isCurrent
            ? const VoxColor(245, 245, 250, 255)
            : const VoxColor(150, 155, 165, 255),
        size: 11,
      );
    }

    final bodyY = my + 74;
    switch (step) {
      case ProjectWizardStep.template:
        dl.addText(
          'Choose a Starter Template:',
          mx + 16,
          bodyY,
          color: const VoxColor(190, 196, 206, 255),
          size: 11,
        );
        final cardW =
            ((mw - 32 - (templates.length - 1) * 8) / templates.length).clamp(
              76.0,
              150.0,
            );
        for (var i = 0; i < templates.length; i++) {
          final (tmpl, label, desc) = templates[i];
          final cr = VoxRect(mx + 16 + i * (cardW + 8), bodyY + 20, cardW, 74);
          final selected = selectedTemplate == tmpl;
          final hov = cr.contains(input.mouseX, input.mouseY);
          dl.addRectFilled(
            cr.x,
            cr.y,
            cr.width,
            cr.height,
            selected
                ? const VoxColor(46, 98, 152, 255)
                : (hov
                      ? const VoxColor(60, 64, 70, 255)
                      : const VoxColor(38, 40, 44, 255)),
            cornerRadius: 4,
          );
          dl.addRectOutline(
            cr.x,
            cr.y,
            cr.width,
            cr.height,
            selected
                ? const VoxColor(96, 175, 245, 255)
                : const VoxColor(26, 26, 26, 255),
          );
          dl.addText(
            label,
            cr.x + 8,
            cr.y + 10,
            color: const VoxColor(238, 240, 245, 255),
            size: 12,
          );
          dl.addText(
            desc,
            cr.x + 8,
            cr.y + 32,
            color: const VoxColor(175, 180, 190, 255),
            size: 10,
          );
          if (hov && input.wasMouseClicked) {
            selectedTemplate = tmpl;
          }
        }

        // Recent projects quick-open list
        final recY = bodyY + 112;
        dl.addText(
          'Or Open Recent Project (${launcher.recentProjects.length}):',
          mx + 16,
          recY,
          color: const VoxColor(175, 180, 190, 255),
          size: 11,
        );
        var ry = recY + 20;
        for (final entry in launcher.recentProjects.take(4)) {
          final rr = VoxRect(mx + 16, ry, mw - 32, 24);
          final hov = rr.contains(input.mouseX, input.mouseY);
          dl.addRectFilled(
            rr.x,
            rr.y,
            rr.width,
            rr.height,
            hov
                ? const VoxColor(58, 121, 187, 255)
                : const VoxColor(38, 40, 44, 255),
            cornerRadius: 3,
          );
          dl.addText(
            '${entry.name}  —  ${entry.path}',
            rr.x + 8,
            rr.y + 6,
            color: const VoxColor(224, 226, 232, 255),
            size: 11,
          );
          if (hov && input.wasMouseClicked) {
            onOpenRecent(entry);
            return;
          }
          ry += 28;
        }

      case ProjectWizardStep.configure:
        dl.addText(
          'Project Name (click & type):',
          mx + 16,
          bodyY,
          color: const VoxColor(185, 190, 200, 255),
          size: 11,
        );
        final nameRect = VoxRect(mx + 16, bodyY + 20, mw - 32, 26);
        final nameHov = nameRect.contains(input.mouseX, input.mouseY);
        dl.addRectFilled(
          nameRect.x,
          nameRect.y,
          nameRect.width,
          nameRect.height,
          const VoxColor(30, 32, 36, 255),
          cornerRadius: 3,
        );
        dl.addRectOutline(
          nameRect.x,
          nameRect.y,
          nameRect.width,
          nameRect.height,
          nameFieldFocused
              ? const VoxColor(96, 175, 245, 255)
              : const VoxColor(26, 26, 26, 255),
        );
        dl.addText(
          projectName,
          nameRect.x + 8,
          nameRect.y + 6,
          color: const VoxColor(240, 242, 246, 255),
          size: 12,
        );
        if (input.wasMouseClicked) {
          nameFieldFocused = nameHov;
        }

        dl.addText(
          'Location: $locationPath',
          mx + 16,
          bodyY + 58,
          color: const VoxColor(165, 170, 180, 255),
          size: 11,
        );

        _button(
          dl,
          input,
          VoxRect(mx + 16, bodyY + 86, 240, 24),
          'Default Quality: ${initialQualityTier.name.toUpperCase()}',
          onClick: () {
            const tiers = VrpQualityTier.values;
            initialQualityTier =
                tiers[(initialQualityTier.index + 1) % tiers.length];
          },
        );
        _button(
          dl,
          input,
          VoxRect(mx + 16, bodyY + 118, 240, 24),
          'Editor Layout: $initialLayoutPreset',
          onClick: () {
            const presets = ['Default', 'Wide', '2 by 3'];
            final idx = presets.indexOf(initialLayoutPreset);
            initialLayoutPreset = presets[(idx + 1) % presets.length];
          },
        );

      case ProjectWizardStep.review:
        dl.addText(
          'Ready to Scaffold & Launch Editor:',
          mx + 16,
          bodyY,
          color: const VoxColor(235, 238, 244, 255),
          size: 12,
        );
        dl.addText(
          'Project: $projectName  ($locationPath)',
          mx + 16,
          bodyY + 28,
          color: const VoxColor(200, 205, 214, 255),
          size: 11,
        );
        dl.addText(
          'Template: $cliTemplateFlag  |  Quality: ${initialQualityTier.name.toUpperCase()}  |  Layout: $initialLayoutPreset',
          mx + 16,
          bodyY + 50,
          color: const VoxColor(200, 205, 214, 255),
          size: 11,
        );
        dl.addText(
          'CLI Equivalent: $cliCommandPreview',
          mx + 16,
          bodyY + 76,
          color: const VoxColor(135, 195, 245, 255),
          size: 11,
        );
        dl.addText(
          'Files: volition.project.json, assets/scenes/main.scene.json (+ .vmeta GUIDs)',
          mx + 16,
          bodyY + 100,
          color: const VoxColor(160, 166, 176, 255),
          size: 11,
        );
    }

    // Bottom navigation bar (Back / Next / Create & Open in Editor)
    final footerY = my + mh - 38;
    if (step != ProjectWizardStep.template) {
      _button(
        dl,
        input,
        VoxRect(mx + 16, footerY, 84, 26),
        '< Back',
        onClick: () {
          step = ProjectWizardStep.values[step.index - 1];
        },
      );
    }
    if (step != ProjectWizardStep.review) {
      _button(
        dl,
        input,
        VoxRect(mx + mw - 116, footerY, 100, 26),
        'Next >',
        primary: true,
        onClick: () {
          step = ProjectWizardStep.values[step.index + 1];
        },
      );
    } else {
      _button(
        dl,
        input,
        VoxRect(mx + mw - 196, footerY, 180, 26),
        'Create & Open in Editor',
        primary: true,
        onClick: onFinishCreate,
      );
    }
  }

  void _button(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label, {
    bool primary = false,
    required void Function() onClick,
  }) {
    final hov = r.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      r.x,
      r.y,
      r.width,
      r.height,
      primary
          ? const VoxColor(58, 121, 187, 255)
          : (hov
                ? const VoxColor(68, 72, 78, 255)
                : const VoxColor(56, 58, 64, 255)),
      cornerRadius: 3,
    );
    dl.addRectOutline(
      r.x,
      r.y,
      r.width,
      r.height,
      const VoxColor(26, 26, 26, 255),
    );
    dl.addText(
      label,
      r.x + 10,
      r.y + 6,
      color: const VoxColor(240, 242, 246, 255),
      size: 11,
    );
    if (hov && input.wasMouseClicked) {
      onClick();
    }
  }
}
