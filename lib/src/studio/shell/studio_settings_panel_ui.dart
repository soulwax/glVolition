/// Pure-Dart Studio Preferences & Project Settings Model + UI (`[Wave G14]`):
/// Categorized Unity-style Settings panel (`General`, `Editor & Gizmos`,
/// `Graphics & Quality`, `CLI & Toolchain`) persisted to
/// `.volition/studio_settings.json`.
library;

import 'dart:convert';

import 'package:pixeldart/rendering/passes/exposure.dart';

import '../../../gl_volition.dart';
import '../project/project_fs.dart';
import '../viewport/scene_gizmo_interactor.dart';
import '../viewport/scene_viewport_model.dart';
import '../windows/lighting_window.dart';
import '../windows/quality_window.dart';
import 'studio_cli_bridge.dart';

/// Categories displayed in the left sidebar of the Studio Settings panel.
enum StudioSettingsCategory { general, editor, graphics, cli }

/// Persistent Studio & Editor user preferences (`[Wave G14]`).
final class StudioSettingsModel {
  static const String defaultPath = '.volition/studio_settings.json';

  bool showWizardOnStartup;
  bool autoSaveLayout;
  int targetFpsCap; // 60 | 120 | 0 (unlimited)
  bool gizmoLocalSpace;
  bool gizmoPivotCenter;
  double translateSnap;
  double rotateSnapDegrees;
  double cameraFlySpeed;

  StudioSettingsModel({
    this.showWizardOnStartup = true,
    this.autoSaveLayout = true,
    this.targetFpsCap = 60,
    this.gizmoLocalSpace = false,
    this.gizmoPivotCenter = false,
    this.translateSnap = 0.5,
    this.rotateSnapDegrees = 15.0,
    this.cameraFlySpeed = 8.0,
  });

  Map<String, Object?> toJson() => {
    'showWizardOnStartup': showWizardOnStartup,
    'autoSaveLayout': autoSaveLayout,
    'targetFpsCap': targetFpsCap,
    'gizmoLocalSpace': gizmoLocalSpace,
    'gizmoPivotCenter': gizmoPivotCenter,
    'translateSnap': translateSnap,
    'rotateSnapDegrees': rotateSnapDegrees,
    'cameraFlySpeed': cameraFlySpeed,
  };

  void applyFromJson(Map<String, Object?> json) {
    showWizardOnStartup = json['showWizardOnStartup'] as bool? ?? true;
    autoSaveLayout = json['autoSaveLayout'] as bool? ?? true;
    targetFpsCap = (json['targetFpsCap'] as num?)?.toInt() ?? 60;
    gizmoLocalSpace = json['gizmoLocalSpace'] as bool? ?? false;
    gizmoPivotCenter = json['gizmoPivotCenter'] as bool? ?? false;
    translateSnap = (json['translateSnap'] as num?)?.toDouble() ?? 0.5;
    rotateSnapDegrees = (json['rotateSnapDegrees'] as num?)?.toDouble() ?? 15.0;
    cameraFlySpeed = (json['cameraFlySpeed'] as num?)?.toDouble() ?? 8.0;
  }

  Future<void> save(ProjectFileSystem fs, {String path = defaultPath}) async {
    await fs.writeString(
      path,
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  Future<bool> load(ProjectFileSystem fs, {String path = defaultPath}) async {
    if (!await fs.exists(path)) return false;
    try {
      final raw = await fs.readString(path);
      applyFromJson(jsonDecode(raw) as Map<String, Object?>);
      return true;
    } on Object {
      return false;
    }
  }
}

/// Interactive renderer for the dockable `'settings'` panel (`[Wave G14]`).
final class StudioSettingsPanelRenderer {
  StudioSettingsCategory activeCategory = StudioSettingsCategory.general;

  void render({
    required StudioSettingsModel settings,
    required SceneGizmoInteractor gizmoInteractor,
    required SceneViewportModel sceneViewport,
    required LightingWindowModel lighting,
    required QualityWindowModel quality,
    required StudioCliController cli,
    required DrawList dl,
    required VoxInput input,
    required VoxRect bounds,
  }) {
    final navW = (bounds.width * 0.28).clamp(110.0, 180.0);
    dl.addRectFilled(
      bounds.x,
      bounds.y,
      navW,
      bounds.height,
      const VoxColor(44, 46, 50, 255),
    );
    dl.addLine(
      bounds.x + navW,
      bounds.y,
      bounds.x + navW,
      bounds.bottom,
      const VoxColor(26, 26, 26, 255),
    );

    const categories = [
      (StudioSettingsCategory.general, 'General'),
      (StudioSettingsCategory.editor, 'Editor & Gizmos'),
      (StudioSettingsCategory.graphics, 'Graphics & VRP'),
      (StudioSettingsCategory.cli, 'CLI & Toolchain'),
    ];
    for (var i = 0; i < categories.length; i++) {
      final (cat, label) = categories[i];
      final cr = VoxRect(bounds.x + 6, bounds.y + 8 + i * 26, navW - 12, 22);
      final active = activeCategory == cat;
      final hov = cr.contains(input.mouseX, input.mouseY);
      if (active || hov) {
        dl.addRectFilled(
          cr.x,
          cr.y,
          cr.width,
          cr.height,
          active
              ? const VoxColor(58, 121, 187, 255)
              : const VoxColor(58, 60, 66, 255),
          cornerRadius: 3,
        );
      }
      dl.addText(
        label,
        cr.x + 8,
        cr.y + 5,
        color: const VoxColor(224, 224, 228, 255),
        size: 11,
      );
      if (hov && input.wasMouseClicked) {
        activeCategory = cat;
      }
    }

    final rx = bounds.x + navW + 14;
    final rw = (bounds.right - rx - 12).clamp(120.0, 420.0);
    var y = bounds.y + 12;

    switch (activeCategory) {
      case StudioSettingsCategory.general:
        dl.addText(
          'General Studio Preferences',
          rx,
          y,
          color: const VoxColor(232, 232, 238, 255),
          size: 12,
        );
        y += 26;
        _toggleRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Show New Project Wizard on Startup',
          settings.showWizardOnStartup,
          () => settings.showWizardOnStartup = !settings.showWizardOnStartup,
        );
        y += 28;
        _toggleRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Auto-Save Docking Layout',
          settings.autoSaveLayout,
          () => settings.autoSaveLayout = !settings.autoSaveLayout,
        );
        y += 28;
        final fpsLabel = settings.targetFpsCap == 0
            ? 'Unlimited'
            : '${settings.targetFpsCap} FPS';
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Target Frame Rate Cap: $fpsLabel',
          () {
            const caps = [60, 120, 0];
            final idx = caps.indexOf(settings.targetFpsCap);
            settings.targetFpsCap = caps[(idx + 1) % caps.length];
          },
        );
      case StudioSettingsCategory.editor:
        dl.addText(
          'Editor Camera & Gizmo Snapping',
          rx,
          y,
          color: const VoxColor(232, 232, 238, 255),
          size: 12,
        );
        y += 26;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Translate Grid Snap: ${settings.translateSnap.toStringAsFixed(2)} m',
          () {
            const snaps = [0.25, 0.5, 1.0, 2.0];
            final idx = snaps.indexWhere(
              (s) => (s - settings.translateSnap).abs() < 0.01,
            );
            settings.translateSnap = snaps[(idx + 1) % snaps.length];
            gizmoInteractor.translateSnap = settings.translateSnap;
          },
        );
        y += 28;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Rotate Angle Snap: ${settings.rotateSnapDegrees.toStringAsFixed(0)} deg',
          () {
            const snaps = [5.0, 15.0, 45.0];
            final idx = snaps.indexWhere(
              (s) => (s - settings.rotateSnapDegrees).abs() < 0.1,
            );
            settings.rotateSnapDegrees = snaps[(idx + 1) % snaps.length];
            gizmoInteractor.rotateSnapDegrees = settings.rotateSnapDegrees;
          },
        );
        y += 28;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Scene Fly Speed: ${settings.cameraFlySpeed.toStringAsFixed(1)} m/s',
          () {
            const speeds = [4.0, 8.0, 16.0, 32.0];
            final idx = speeds.indexWhere(
              (s) => (s - settings.cameraFlySpeed).abs() < 0.1,
            );
            settings.cameraFlySpeed = speeds[(idx + 1) % speeds.length];
            sceneViewport.editorCamera.flySpeed = settings.cameraFlySpeed;
          },
        );
      case StudioSettingsCategory.graphics:
        dl.addText(
          'Graphics & Volition Render Pipeline (VRP)',
          rx,
          y,
          color: const VoxColor(232, 232, 238, 255),
          size: 12,
        );
        y += 26;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Active Quality Tier: ${quality.activeTier.name.toUpperCase()}',
          () {
            const tiers = VrpQualityTier.values;
            quality.selectTier(
              tiers[(quality.activeTier.index + 1) % tiers.length],
            );
          },
        );
        y += 28;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'HDR Tonemapper: ${lighting.exposureSettings.tonemapper.name}',
          () {
            const vals = VrpTonemapper.values;
            lighting.setExposure(
              tonemapper:
                  vals[(lighting.exposureSettings.tonemapper.index + 1) %
                      vals.length],
            );
          },
        );
      case StudioSettingsCategory.cli:
        dl.addText(
          'Connected Volition CLI Actions',
          rx,
          y,
          color: const VoxColor(232, 232, 238, 255),
          size: 12,
        );
        y += 26;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Run: volition doctor',
          () => cli.execute(const ['doctor']),
        );
        y += 28;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Run: volition codegen --check',
          () => cli.execute(const ['codegen', '--check']),
        );
        y += 28;
        _actionRow(
          dl,
          input,
          VoxRect(rx, y, rw, 22),
          'Run: volition dist --studio --dry-run',
          () => cli.execute(const ['dist', '--studio', '--dry-run']),
        );
        y += 32;
        final last = cli.lastResult;
        dl.addText(
          last == null
              ? 'Last CLI result: (none yet)'
              : 'Last: ${last.commandLine} -> exit ${last.exitCode}',
          rx,
          y,
          color: last == null || last.succeeded
              ? const VoxColor(150, 195, 150, 255)
              : const VoxColor(235, 95, 95, 255),
          size: 11,
        );
    }
  }

  void _toggleRow(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label,
    bool value,
    void Function() onToggle,
  ) {
    _actionRow(
      dl,
      input,
      r,
      '$label: ${value ? 'ON' : 'OFF'}',
      onToggle,
      active: value,
    );
  }

  void _actionRow(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label,
    void Function() onClick, {
    bool active = false,
  }) {
    final hov = r.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      r.x,
      r.y,
      r.width,
      r.height,
      active
          ? const VoxColor(46, 98, 152, 255)
          : (hov
                ? const VoxColor(66, 68, 74, 255)
                : const VoxColor(46, 48, 52, 255)),
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
      r.x + 8,
      r.y + 5,
      color: const VoxColor(228, 228, 232, 255),
      size: 11,
    );
    if (hov && input.wasMouseClicked) {
      onClick();
    }
  }
}
