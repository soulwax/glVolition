/// Pure-Dart Unity-Style Studio Workspace UI (`[Wave G2]`):
/// Renders the full modular Studio shell (Top Menu Bar, Play/Pause/Step Toolbar
/// with Play Mode chrome tinting, recursive `SplitView`/`DockArea` panels,
/// Scene View floating Overlays, Hierarchy, Inspector, Project, Console,
/// Lighting, Profiler, Modules, and Bottom Status Bar) into a `voxui`
/// [DrawList] — 100% platform-agnostic and unit-testable headlessly.
library;

import 'package:pixeldart/rendering/api/settings.dart';
import 'package:voxui/voxui.dart';

import '../assets/asset_database.dart';
import '../bridge/editor_host_bridge.dart';
import '../commands/menu_registry.dart';
import '../console/console_model.dart';
import '../hierarchy/hierarchy_model.dart';
import '../inspector/inspector_model.dart';
import '../modules/module_inventory.g.dart';
import '../modules/module_registry.dart';
import '../project/project_fs.dart';
import '../project_window/project_window_model.dart';
import '../viewport/scene_viewport_model.dart';
import '../windows/lighting_window.dart';
import '../windows/modules_window.dart';
import '../windows/profiler/profiler_window_model.dart';
import '../windows/quality_window.dart';
import 'dock_layout.dart';
import 'dock_layout_solver.dart';

/// Unity dark-theme color palette for Volition Studio (`[Wave G2]`).
abstract final class UnityDarkTheme {
  static const VoxColor bgRoot = VoxColor(32, 32, 32, 255);
  static const VoxColor bgToolbar = VoxColor(42, 42, 42, 255);
  static const VoxColor bgToolbarPlayTint = VoxColor(34, 52, 74, 255);
  static const VoxColor bgPanel = VoxColor(56, 56, 56, 255);
  static const VoxColor bgTabBar = VoxColor(40, 40, 40, 255);
  static const VoxColor bgTabActive = VoxColor(56, 56, 56, 255);
  static const VoxColor bgTabHover = VoxColor(50, 50, 50, 255);
  static const VoxColor bgRowAlt = VoxColor(51, 51, 51, 255);
  static const VoxColor bgRowSelected = VoxColor(44, 93, 135, 255);
  static const VoxColor bgOverlay = VoxColor(30, 32, 38, 215);
  static const VoxColor border = VoxColor(26, 26, 26, 255);
  static const VoxColor splitter = VoxColor(28, 28, 28, 255);
  static const VoxColor splitterHover = VoxColor(70, 140, 240, 255);
  static const VoxColor accentBlue = VoxColor(58, 121, 187, 255);
  static const VoxColor dropPreview = VoxColor(58, 121, 187, 96);
  static const VoxColor textPrimary = VoxColor(218, 218, 218, 255);
  static const VoxColor textMuted = VoxColor(150, 150, 150, 255);
  static const VoxColor statusError = VoxColor(235, 85, 85, 255);
  static const VoxColor statusWarn = VoxColor(235, 195, 65, 255);
}

/// Active viewport FBO rectangle emitted by [StudioWorkspaceShell.buildFrame]
/// so the native GLES3 host knows exactly where to render & composite the
/// live 3D Scene View and Game View FBOs.
final class StudioViewportSlot {
  final String panelId; // 'scene' or 'game'
  final VoxRect rect;

  const StudioViewportSlot({required this.panelId, required this.rect});
}

/// Complete Unity-style AOT Studio workspace controller & UI renderer (`[Wave G2]`).
final class StudioWorkspaceShell {
  static const double menuBarHeight = 24.0;
  static const double toolbarHeight = 34.0;
  static const double statusBarHeight = 22.0;

  final EditorHostBridge bridge;
  final StudioMenuRegistry menus;
  final HierarchyPanelModel hierarchy;
  final InspectorPanelModel inspector;
  final ProjectWindowModel project;
  final ConsolePanelModel console;
  final SceneViewportModel sceneViewport;
  final GameViewportModel gameViewport;
  final LightingWindowModel lighting;
  final QualityWindowModel quality;
  final ModulesWindowModel modules;
  final ProfilerWindowModel profiler;

  StudioDockLayout layout;
  String activeLayoutPreset = 'Default';
  String? maximizedAreaId;
  String activeGizmoTool = 'move'; // hand | move | rotate | scale | rect
  String sceneShadingMode = 'Lit'; // Lit | Wire | Albedo | Normals | Heatmap
  bool sceneGridVisible = true;
  bool sceneGizmosVisible = true;
  String? openTopMenu;

  // Interactive drag state
  String? _draggingSplitterId;
  ({String areaId, String panelId})? _draggingTab;

  // Per-frame telemetry displayed in status bar
  double lastFps = 60.0;
  double lastFrameMs = 16.6;

  /// Viewport FBO slots emitted on the most recent [buildFrame] call.
  final List<StudioViewportSlot> activeViewportSlots = [];

  StudioWorkspaceShell({
    required this.bridge,
    StudioMenuRegistry? menus,
    HierarchyPanelModel? hierarchy,
    InspectorPanelModel? inspector,
    ProjectWindowModel? project,
    ConsolePanelModel? console,
    SceneViewportModel? sceneViewport,
    GameViewportModel? gameViewport,
    LightingWindowModel? lighting,
    QualityWindowModel? quality,
    ModulesWindowModel? modules,
    ProfilerWindowModel? profiler,
    StudioDockLayout? layout,
  }) : menus = menus ?? StudioMenuRegistry(registerDefaults: true),
       hierarchy = hierarchy ?? HierarchyPanelModel(bridge),
       inspector = inspector ?? InspectorPanelModel(bridge),
       project =
           project ??
           ProjectWindowModel(AssetDatabase(MemoryProjectFileSystem())),
       console = console ?? ConsolePanelModel(),
       sceneViewport = sceneViewport ?? SceneViewportModel(bridge),
       gameViewport = gameViewport ?? GameViewportModel(),
       lighting = lighting ?? LightingWindowModel(),
       quality = quality ?? QualityWindowModel(),
       modules =
           modules ??
           ModulesWindowModel(StudioModuleRegistry(kStudioModuleInventory)),
       profiler = profiler ?? ProfilerWindowModel(),
       layout = layout ?? StudioDockLayout.defaultLayout();

  bool get isPlaying => bridge.playState == StudioPlayState.playing;

  void applyLayoutPreset(String preset) {
    activeLayoutPreset = preset;
    maximizedAreaId = null;
    layout = switch (preset) {
      'Wide' => DockLayoutSolver.wideLayout(),
      '2 by 3' => DockLayoutSolver.twoByThreeLayout(),
      _ => StudioDockLayout.defaultLayout(),
    };
  }

  void toggleMaximizeArea(String areaId) {
    maximizedAreaId = maximizedAreaId == areaId ? null : areaId;
  }

  /// Renders one complete Studio frame into [dl] for a native window of
  /// `[width x height]` pixels and processes mouse/keyboard interactions from
  /// [input]. When [overlayDl] is provided, floating Scene/Game viewport
  /// overlays, tab drag-drop previews, and menu dropdowns are emitted into
  /// [overlayDl] so the native 3-pass compositor can draw them *on top* of the
  /// live offscreen 3D viewport FBOs.
  SolvedDockWorkspace buildFrame({
    required DrawList dl,
    DrawList? overlayDl,
    required VoxInput input,
    required double width,
    required double height,
  }) {
    final topDl = overlayDl ?? dl;
    activeViewportSlots.clear();

    // 1. Background
    dl.addRectFilled(0, 0, width, height, UnityDarkTheme.bgRoot);

    // 2. Top Menu Bar
    _renderMenuBar(dl, input, width);

    // 3. Main Play / Gizmo / Quality / Layout Toolbar
    _renderMainToolbar(dl, input, width);

    // 4. Recursive SplitView + DockArea Workspace
    final workspaceRect = VoxRect(
      0,
      menuBarHeight + toolbarHeight,
      width,
      (height - menuBarHeight - toolbarHeight - statusBarHeight).clamp(
        0.0,
        double.infinity,
      ),
    );
    final solved = DockLayoutSolver.solve(
      layout,
      workspaceRect,
      maximizedAreaId: maximizedAreaId,
    );

    _handleSplitterDrag(input, solved);

    for (final area in solved.areas) {
      _renderDockArea(dl, topDl, input, area);
    }

    for (final s in solved.splitters) {
      final hovered =
          _draggingSplitterId == s.splitId ||
          s.rect.contains(input.mouseX, input.mouseY);
      dl.addRectFilled(
        s.rect.x,
        s.rect.y,
        s.rect.width,
        s.rect.height,
        hovered ? UnityDarkTheme.splitterHover : UnityDarkTheme.splitter,
      );
    }

    // Tab drag-and-drop 5-zone preview & commit (always on top of FBOs)
    _handleTabDragDrop(topDl, input, solved);

    // 5. Bottom Status Bar
    _renderStatusBar(dl, input, width, height);

    // 6. Active top-level menu dropdown overlay (always on top of FBOs)
    if (openTopMenu != null) {
      _renderMenuDropdown(topDl, input);
    }

    return solved;
  }

  void _renderMenuBar(DrawList dl, VoxInput input, double width) {
    dl.addRectFilled(0, 0, width, menuBarHeight, UnityDarkTheme.bgTabBar);
    dl.addLine(
      0,
      menuBarHeight - 1,
      width,
      menuBarHeight - 1,
      UnityDarkTheme.border,
    );

    const topMenus = [
      'File',
      'Edit',
      'Assets',
      'GameObject',
      'Component',
      'Window',
      'Help',
    ];
    var x = 8.0;
    for (final label in topMenus) {
      final w = label.length * 7.5 + 16.0;
      final r = VoxRect(x, 2, w, menuBarHeight - 4);
      final hovered = r.contains(input.mouseX, input.mouseY);
      final isOpen = openTopMenu == label;
      if (hovered || isOpen) {
        dl.addRectFilled(
          r.x,
          r.y,
          r.width,
          r.height,
          isOpen ? UnityDarkTheme.accentBlue : UnityDarkTheme.bgTabHover,
          cornerRadius: 3,
        );
      }
      dl.addText(
        label,
        r.x + 8,
        r.y + 4,
        color: UnityDarkTheme.textPrimary,
        size: 12,
      );
      if (hovered && input.wasMouseClicked) {
        openTopMenu = isOpen ? null : label;
      }
      x += w + 2;
    }
  }

  void _renderMenuDropdown(DrawList dl, VoxInput input) {
    final prefix = '$openTopMenu/';
    final items = menus.all
        .where((m) => m.menuPath.startsWith(prefix))
        .take(12)
        .toList();
    if (items.isEmpty) {
      if (input.wasMouseClicked) openTopMenu = null;
      return;
    }
    const dropX = 12.0;
    const dropY = menuBarHeight;
    const dropW = 220.0;
    const rowH = 22.0;
    final dropH = items.length * rowH + 8.0;
    final dropRect = VoxRect(dropX, dropY, dropW, dropH);
    dl.addRectFilled(
      dropX,
      dropY,
      dropW,
      dropH,
      UnityDarkTheme.bgOverlay,
      cornerRadius: 4,
    );
    dl.addRectOutline(dropX, dropY, dropW, dropH, UnityDarkTheme.border);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final rr = VoxRect(dropX + 4, dropY + 4 + i * rowH, dropW - 8, rowH);
      final hov = rr.contains(input.mouseX, input.mouseY);
      if (hov) {
        dl.addRectFilled(
          rr.x,
          rr.y,
          rr.width,
          rr.height,
          UnityDarkTheme.accentBlue,
          cornerRadius: 2,
        );
      }
      dl.addText(
        item.label,
        rr.x + 8,
        rr.y + 4,
        color: UnityDarkTheme.textPrimary,
        size: 12,
      );
      if (hov && input.wasMouseClicked) {
        menus.trigger(item.id);
        openTopMenu = null;
        return;
      }
    }
    if (input.wasMouseClicked &&
        !dropRect.contains(input.mouseX, input.mouseY)) {
      openTopMenu = null;
    }
  }

  void _renderMainToolbar(DrawList dl, VoxInput input, double width) {
    final y = menuBarHeight;
    final bg = isPlaying
        ? UnityDarkTheme.bgToolbarPlayTint
        : UnityDarkTheme.bgToolbar;
    dl.addRectFilled(0, y, width, toolbarHeight, bg);
    dl.addLine(
      0,
      y + toolbarHeight - 1,
      width,
      y + toolbarHeight - 1,
      UnityDarkTheme.border,
    );

    // Left: Transform tools (Q/W/E/R/T)
    const tools = [
      ('hand', 'Q'),
      ('move', 'W'),
      ('rotate', 'E'),
      ('scale', 'R'),
      ('rect', 'T'),
    ];
    var tx = 10.0;
    for (final (id, key) in tools) {
      final r = VoxRect(tx, y + 5, 28, 24);
      final active = activeGizmoTool == id;
      final hov = r.contains(input.mouseX, input.mouseY);
      dl.addRectFilled(
        r.x,
        r.y,
        r.width,
        r.height,
        active
            ? UnityDarkTheme.accentBlue
            : (hov ? UnityDarkTheme.bgTabHover : UnityDarkTheme.bgPanel),
        cornerRadius: 3,
      );
      dl.addText(
        key,
        r.x + 10,
        r.y + 6,
        color: UnityDarkTheme.textPrimary,
        size: 12,
      );
      if (hov && input.wasMouseClicked) {
        activeGizmoTool = id;
      }
      tx += 30;
    }

    // Center: Unity Play / Pause / Step transport controls
    final centerX = (width * 0.5) - 54;
    final playRect = VoxRect(centerX, y + 5, 36, 24);
    final pauseRect = VoxRect(centerX + 38, y + 5, 36, 24);
    final stepRect = VoxRect(centerX + 76, y + 5, 36, 24);

    _toolbarButton(
      dl,
      input,
      playRect,
      isPlaying ? '■' : '▶',
      active: isPlaying,
      onClick: () {
        if (isPlaying) {
          bridge.exitPlayMode();
        } else {
          bridge.enterPlayMode();
        }
      },
    );
    _toolbarButton(dl, input, pauseRect, '❚❚', active: false, onClick: () {});
    _toolbarButton(dl, input, stepRect, '▶|', active: false, onClick: () {});

    // Right: Quality Tier & Layout preset buttons
    final tierLabel = 'VRP: ${quality.activeTier.name.toUpperCase()}';
    final tierRect = VoxRect(width - 210, y + 5, 102, 24);
    _toolbarButton(
      dl,
      input,
      tierRect,
      tierLabel,
      onClick: () {
        const tiers = VrpQualityTier.values;
        final next = tiers[(quality.activeTier.index + 1) % tiers.length];
        quality.selectTier(next);
      },
    );

    final layoutRect = VoxRect(width - 100, y + 5, 90, 24);
    _toolbarButton(
      dl,
      input,
      layoutRect,
      activeLayoutPreset,
      onClick: () {
        const presets = ['Default', 'Wide', '2 by 3'];
        final idx = presets.indexOf(activeLayoutPreset);
        applyLayoutPreset(presets[(idx + 1) % presets.length]);
      },
    );
  }

  void _toolbarButton(
    DrawList dl,
    VoxInput input,
    VoxRect r,
    String label, {
    bool active = false,
    required void Function() onClick,
  }) {
    final hov = r.contains(input.mouseX, input.mouseY);
    dl.addRectFilled(
      r.x,
      r.y,
      r.width,
      r.height,
      active
          ? UnityDarkTheme.accentBlue
          : (hov ? UnityDarkTheme.bgTabHover : UnityDarkTheme.bgPanel),
      cornerRadius: 3,
    );
    dl.addRectOutline(r.x, r.y, r.width, r.height, UnityDarkTheme.border);
    dl.addText(
      label,
      r.x + 8,
      r.y + 6,
      color: UnityDarkTheme.textPrimary,
      size: 11,
    );
    if (hov && input.wasMouseClicked) {
      onClick();
    }
  }

  void _renderDockArea(
    DrawList dl,
    DrawList overlayDl,
    VoxInput input,
    SolvedDockArea area,
  ) {
    final r = area.bounds;
    dl.addRectFilled(r.x, r.y, r.width, r.height, UnityDarkTheme.bgPanel);
    dl.addRectFilled(
      area.tabBarRect.x,
      area.tabBarRect.y,
      area.tabBarRect.width,
      area.tabBarRect.height,
      UnityDarkTheme.bgTabBar,
    );

    for (var i = 0; i < area.panelIds.length; i++) {
      final pid = area.panelIds[i];
      final tr = area.tabRects[i];
      final active = i == area.activeIndex;
      final hov = tr.contains(input.mouseX, input.mouseY);
      dl.addRectFilled(
        tr.x,
        tr.y,
        tr.width,
        tr.height,
        active
            ? UnityDarkTheme.bgTabActive
            : (hov ? UnityDarkTheme.bgTabHover : UnityDarkTheme.bgTabBar),
        cornerRadius: 3,
      );
      if (active) {
        dl.addRectFilled(tr.x, tr.y, tr.width, 2, UnityDarkTheme.accentBlue);
      }
      dl.addText(
        _panelTitle(pid),
        tr.x + 8,
        tr.y + 5,
        color: active ? UnityDarkTheme.textPrimary : UnityDarkTheme.textMuted,
        size: 11,
      );
      if (hov && input.wasMouseClicked) {
        layout = DockLayoutSolver.selectTab(layout, area.areaId, pid);
        _draggingTab = (areaId: area.areaId, panelId: pid);
      }
    }

    dl.addRectOutline(r.x, r.y, r.width, r.height, UnityDarkTheme.border);

    final activePid = area.activePanelId;
    if (activePid == null) return;

    dl.pushClip(area.contentRect);
    _renderPanelBody(dl, overlayDl, input, activePid, area.contentRect);
    dl.popClip();
  }

  void _renderPanelBody(
    DrawList dl,
    DrawList overlayDl,
    VoxInput input,
    String panelId,
    VoxRect r,
  ) {
    switch (panelId) {
      case 'scene':
      case 'game':
        // Record FBO viewport slot for native GPU compositing
        activeViewportSlots.add(StudioViewportSlot(panelId: panelId, rect: r));
        dl.addRectFilled(
          r.x,
          r.y,
          r.width,
          r.height,
          const VoxColor(20, 22, 26, 255),
        );
        // Interactive Scene View camera controls (wheel zoom / drag orbit)
        if (panelId == 'scene' && r.contains(input.mouseX, input.mouseY)) {
          if (input.scrollDeltaY != 0.0) {
            sceneViewport.editorCamera.zoom(input.scrollDeltaY * 0.5);
          }
          if (input.isMouseDown &&
              (input.mouseDeltaX != 0.0 || input.mouseDeltaY != 0.0) &&
              _draggingSplitterId == null &&
              _draggingTab == null) {
            sceneViewport.editorCamera.orbit(
              input.mouseDeltaX * 0.01,
              input.mouseDeltaY * 0.01,
            );
          }
        }
        // Floating Unity Scene/Game View Overlay bar emitted to overlayDl
        // so it renders crisply on top of the composited 3D FBO texture.
        overlayDl.pushClip(r);
        if (panelId == 'scene') {
          const shadingModes = ['Lit', 'Wire', 'Albedo', 'Normals', 'Heatmap'];
          final shadeRect = VoxRect(r.x + 8, r.y + 8, 76, 22);
          _toolbarButton(
            overlayDl,
            input,
            shadeRect,
            sceneShadingMode,
            onClick: () {
              final idx = shadingModes.indexOf(sceneShadingMode);
              sceneShadingMode = shadingModes[(idx + 1) % shadingModes.length];
            },
          );
          final gridRect = VoxRect(r.x + 88, r.y + 8, 68, 22);
          _toolbarButton(
            overlayDl,
            input,
            gridRect,
            sceneGridVisible ? 'Grid:On' : 'Grid:Off',
            active: sceneGridVisible,
            onClick: () => sceneGridVisible = !sceneGridVisible,
          );
          final gizmoRect = VoxRect(r.x + 160, r.y + 8, 76, 22);
          _toolbarButton(
            overlayDl,
            input,
            gizmoRect,
            sceneGizmosVisible ? 'Gizmo:On' : 'Gizmo:Off',
            active: sceneGizmosVisible,
            onClick: () => sceneGizmosVisible = !sceneGizmosVisible,
          );
        } else {
          final aspectRect = VoxRect(r.x + 8, r.y + 8, 124, 22);
          _toolbarButton(
            overlayDl,
            input,
            aspectRect,
            'Aspect: ${gameViewport.aspectPreset.name}',
            onClick: () {
              const presets = GameViewAspectPreset.values;
              final next =
                  presets[(gameViewport.aspectPreset.index + 1) %
                      presets.length];
              gameViewport.aspectPreset = next;
            },
          );
          final modeRect = VoxRect(r.x + 136, r.y + 8, 72, 22);
          overlayDl.addRectFilled(
            modeRect.x,
            modeRect.y,
            modeRect.width,
            modeRect.height,
            isPlaying ? UnityDarkTheme.accentBlue : UnityDarkTheme.bgOverlay,
            cornerRadius: 3,
          );
          overlayDl.addText(
            isPlaying ? 'PLAYING' : 'Edit',
            modeRect.x + 8,
            modeRect.y + 5,
            color: UnityDarkTheme.textPrimary,
            size: 11,
          );
        }
        overlayDl.popClip();
      case 'hierarchy':
        final rows = hierarchy.visibleRows();
        var y = r.y + 4;
        for (var i = 0; i < rows.length && y < r.bottom; i++) {
          final row = rows[i];
          final rr = VoxRect(r.x + 2, y, r.width - 4, 20);
          dl.addRectFilled(
            rr.x,
            rr.y,
            rr.width,
            rr.height,
            row.isSelected
                ? UnityDarkTheme.bgRowSelected
                : (i.isEven ? UnityDarkTheme.bgPanel : UnityDarkTheme.bgRowAlt),
          );
          dl.addText(
            '${'  ' * row.depth}${row.object.name}',
            rr.x + 8,
            rr.y + 4,
            color: UnityDarkTheme.textPrimary,
            size: 11,
          );
          if (rr.contains(input.mouseX, input.mouseY) &&
              input.wasMouseClicked) {
            bridge.selectObjects([row.object]);
          }
          y += 20;
        }
      case 'inspector':
        final selected = bridge.session.selectedObjects;
        if (selected.isEmpty) {
          dl.addText(
            'No GameObject selected',
            r.x + 12,
            r.y + 12,
            color: UnityDarkTheme.textMuted,
            size: 11,
          );
          return;
        }
        final sections = inspector.buildSections();
        var y = r.y + 8;
        dl.addText(
          '${selected.first.name} (${sections.length} components)',
          r.x + 10,
          y,
          color: UnityDarkTheme.textPrimary,
          size: 12,
        );
        y += 22;
        for (final comp in sections) {
          if (y > r.bottom) break;
          dl.addRectFilled(
            r.x + 4,
            y,
            r.width - 8,
            20,
            UnityDarkTheme.bgTabBar,
            cornerRadius: 2,
          );
          dl.addText(
            comp.typeName,
            r.x + 10,
            y + 4,
            color: UnityDarkTheme.textPrimary,
            size: 11,
          );
          y += 22;
          for (final f in comp.fields.take(6)) {
            if (y > r.bottom) break;
            final fr = VoxRect(r.x + 12, y, r.width - 20, 18);
            final hov = fr.contains(input.mouseX, input.mouseY);
            if (hov) {
              dl.addRectFilled(
                fr.x,
                fr.y,
                fr.width,
                fr.height,
                UnityDarkTheme.bgTabHover,
                cornerRadius: 2,
              );
            }
            dl.addText(
              '${f.field.name}: ${f.isMixed ? '—' : f.jsonValue}',
              fr.x + 4,
              fr.y + 2,
              color: hov
                  ? UnityDarkTheme.textPrimary
                  : UnityDarkTheme.textMuted,
              size: 11,
            );
            // Interactive bool toggle or Unity-style numeric drag-scrubbing
            if (hov && input.wasMouseClicked && f.jsonValue is bool) {
              inspector.setFieldValue(
                comp.typeName,
                f.field.name,
                !(f.jsonValue as bool),
              );
            } else if (hov &&
                input.isMouseDown &&
                input.mouseDeltaX != 0.0 &&
                f.jsonValue is num) {
              final cur = f.jsonValue as num;
              final nextVal = cur is int
                  ? (cur + input.mouseDeltaX.round())
                  : double.parse(
                      (cur.toDouble() + input.mouseDeltaX * 0.05)
                          .toStringAsFixed(3),
                    );
              if (nextVal != cur) {
                inspector.setFieldValue(comp.typeName, f.field.name, nextVal);
              }
            }
            y += 18;
          }
        }
      case 'console':
        // Console filter bar: Clear + Info/Warn/Error counts
        final clearRect = VoxRect(r.x + 6, r.y + 4, 48, 18);
        _toolbarButton(dl, input, clearRect, 'Clear', onClick: console.clear);
        final infoRect = VoxRect(r.x + 60, r.y + 4, 64, 18);
        _toolbarButton(
          dl,
          input,
          infoRect,
          'I:${console.infoCount}',
          active: console.showInfo,
          onClick: () => console.showInfo = !console.showInfo,
        );
        final warnRect = VoxRect(r.x + 128, r.y + 4, 64, 18);
        _toolbarButton(
          dl,
          input,
          warnRect,
          'W:${console.warningCount}',
          active: console.showWarning,
          onClick: () => console.showWarning = !console.showWarning,
        );
        final errRect = VoxRect(r.x + 196, r.y + 4, 64, 18);
        _toolbarButton(
          dl,
          input,
          errRect,
          'E:${console.errorCount}',
          active: console.showError,
          onClick: () => console.showError = !console.showError,
        );
        final entries = console.visibleEntries();
        var y = r.y + 28;
        if (entries.isEmpty) {
          dl.addText(
            'Console is clear.',
            r.x + 10,
            y,
            color: UnityDarkTheme.textMuted,
            size: 11,
          );
        } else {
          for (final e in entries.reversed.take(20)) {
            if (y > r.bottom) break;
            final col = switch (e.level) {
              ConsoleLogLevel.error => UnityDarkTheme.statusError,
              ConsoleLogLevel.warning => UnityDarkTheme.statusWarn,
              ConsoleLogLevel.info => UnityDarkTheme.textPrimary,
            };
            dl.addText(
              '[${e.level.name.toUpperCase()}] ${e.message}',
              r.x + 8,
              y,
              color: col,
              size: 11,
            );
            y += 18;
          }
        }
      case 'project':
        final assets = project.visibleAssets();
        dl.addText(
          'Assets / ${project.currentFolder} (${assets.length} items)',
          r.x + 10,
          r.y + 8,
          color: UnityDarkTheme.textPrimary,
          size: 11,
        );
        var py = r.y + 28;
        for (final asset in assets.take(20)) {
          if (py > r.bottom) break;
          dl.addText(
            '[${asset.importerId}] ${asset.path}',
            r.x + 12,
            py,
            color: UnityDarkTheme.textMuted,
            size: 11,
          );
          py += 18;
        }
      case 'lighting':
        dl.addText(
          'EV100: ${lighting.exposureSettings.manualEv100.toStringAsFixed(2)} | '
          'Tonemap: ${lighting.exposureSettings.tonemapper.name}',
          r.x + 10,
          r.y + 10,
          color: UnityDarkTheme.textPrimary,
          size: 11,
        );
      case 'profiler':
        dl.addText(
          'Avg Frame: ${profiler.averageFrameTimeMs.toStringAsFixed(2)}ms | '
          'GPU: ${profiler.averageGpuTimeMs.toStringAsFixed(2)}ms | '
          'Samples: ${profiler.frames.length}',
          r.x + 10,
          r.y + 8,
          color: UnityDarkTheme.textPrimary,
          size: 11,
        );
        // Rolling frame-time bar chart (0..50ms scale with 16.6ms 60fps line)
        final chartX = r.x + 10;
        final chartY = r.y + 28;
        final chartW = (r.width - 20).clamp(40.0, double.infinity);
        final chartH = (r.height - 38).clamp(24.0, 140.0);
        dl.addRectFilled(
          chartX,
          chartY,
          chartW,
          chartH,
          const VoxColor(26, 28, 32, 255),
          cornerRadius: 3,
        );
        final line60Y = chartY + chartH * (1.0 - (16.6 / 50.0));
        dl.addLine(
          chartX,
          line60Y,
          chartX + chartW,
          line60Y,
          UnityDarkTheme.accentBlue,
        );
        final recent = profiler.frames.length > 60
            ? profiler.frames.sublist(profiler.frames.length - 60)
            : profiler.frames;
        if (recent.isNotEmpty) {
          final barW = (chartW / recent.length).clamp(2.0, 14.0);
          for (var i = 0; i < recent.length; i++) {
            final ms = recent[i].frameTimeMs;
            final frac = (ms / 50.0).clamp(0.02, 1.0);
            final bh = chartH * frac;
            final col = ms < 16.6
                ? const VoxColor(76, 185, 110, 255)
                : (ms < 33.3
                      ? UnityDarkTheme.statusWarn
                      : UnityDarkTheme.statusError);
            dl.addRectFilled(
              chartX + i * barW,
              chartY + chartH - bh,
              (barW - 1.0).clamp(1.0, barW),
              bh,
              col,
            );
          }
        }
      case 'modules':
        final list = modules.filteredModules;
        dl.addText(
          'Volition Modules: ${list.length}/74 registered',
          r.x + 10,
          r.y + 8,
          color: UnityDarkTheme.textPrimary,
          size: 11,
        );
        var my = r.y + 28;
        for (final m in list.take(24)) {
          if (my > r.bottom) break;
          dl.addText(
            '${m.package}  [${m.maturity.cliName}]',
            r.x + 12,
            my,
            color: UnityDarkTheme.textMuted,
            size: 11,
          );
          my += 18;
        }
      default:
        dl.addText(
          _panelTitle(panelId),
          r.x + 10,
          r.y + 10,
          color: UnityDarkTheme.textMuted,
          size: 11,
        );
    }
  }

  void _handleSplitterDrag(VoxInput input, SolvedDockWorkspace solved) {
    if (input.wasMouseClicked && _draggingSplitterId == null) {
      final hit = solved.splitterAt(input.mouseX, input.mouseY);
      if (hit != null) {
        _draggingSplitterId = hit.splitId;
      }
    }
    if (_draggingSplitterId != null && input.isMouseDown) {
      for (final s in solved.splitters) {
        if (s.splitId == _draggingSplitterId) {
          final ratio = s.axis == DockSplitAxis.horizontal
              ? (input.mouseX - s.parentRect.x) /
                    (s.parentRect.width > 1 ? s.parentRect.width : 1)
              : (input.mouseY - s.parentRect.y) /
                    (s.parentRect.height > 1 ? s.parentRect.height : 1);
          layout = DockLayoutSolver.setSplitRatio(layout, s.splitId, ratio);
          break;
        }
      }
    }
    if (input.wasMouseReleased) {
      _draggingSplitterId = null;
    }
  }

  void _handleTabDragDrop(
    DrawList dl,
    VoxInput input,
    SolvedDockWorkspace solved,
  ) {
    final drag = _draggingTab;
    if (drag == null) return;
    final targetArea = solved.areaAt(input.mouseX, input.mouseY);
    if (input.isMouseDown && targetArea != null) {
      final (_, preview) = DockLayoutSolver.resolveDropZone(
        targetArea,
        input.mouseX,
        input.mouseY,
      );
      dl.addRectFilled(
        preview.x,
        preview.y,
        preview.width,
        preview.height,
        UnityDarkTheme.dropPreview,
      );
      dl.addRectOutline(
        preview.x,
        preview.y,
        preview.width,
        preview.height,
        UnityDarkTheme.accentBlue,
        thickness: 2,
      );
    }
    if (input.wasMouseReleased) {
      if (targetArea != null) {
        final (zone, _) = DockLayoutSolver.resolveDropZone(
          targetArea,
          input.mouseX,
          input.mouseY,
        );
        layout = DockLayoutSolver.dockPanel(
          layout,
          panelId: drag.panelId,
          sourceAreaId: drag.areaId,
          targetAreaId: targetArea.areaId,
          zone: zone,
        );
      }
      _draggingTab = null;
    }
  }

  void _renderStatusBar(
    DrawList dl,
    VoxInput input,
    double width,
    double height,
  ) {
    final y = height - statusBarHeight;
    dl.addRectFilled(0, y, width, statusBarHeight, UnityDarkTheme.bgTabBar);
    dl.addLine(0, y, width, y, UnityDarkTheme.border);

    final visibleConsole = console.visibleEntries();
    final lastMsg = visibleConsole.isEmpty
        ? 'Ready'
        : visibleConsole.last.message;
    dl.addText(lastMsg, 10, y + 5, color: UnityDarkTheme.textMuted, size: 11);
    final rightInfo =
        'Sel: ${bridge.session.selectedObjects.length} | '
        '${quality.activeTier.name.toUpperCase()} | '
        '${lastFps.toStringAsFixed(0)} FPS (${lastFrameMs.toStringAsFixed(1)}ms)';
    dl.addText(
      rightInfo,
      (width - rightInfo.length * 6.5 - 12).clamp(160.0, width),
      y + 5,
      color: UnityDarkTheme.textMuted,
      size: 11,
    );
  }

  static String _panelTitle(String id) => switch (id) {
    'scene' => 'Scene',
    'game' => 'Game',
    'hierarchy' => 'Hierarchy',
    'inspector' => 'Inspector',
    'project' => 'Project',
    'console' => 'Console',
    'lighting' => 'Lighting',
    'profiler' => 'Profiler',
    'modules' => 'Modules',
    'build' => 'Build',
    _ => id,
  };
}
