/// Pure-Dart Unity-Style Modular Docking Layout Solver (`[Wave G2]`):
/// Maps `StudioDockLayout` (`DockSplitNode` / `DockTabsNode`) onto exact pixel
/// `VoxRect`s, handles splitter dragging, 5-zone tab drag-and-drop docking
/// (`Left / Right / Top / Bottom / Center`), `Shift+Space` maximize/restore,
/// and Unity workspace presets (`Default`, `Wide`, `Tall`, `2 by 3`).
library;

import 'package:voxui/voxui.dart';

import 'dock_layout.dart';

/// 5-zone Unity-style tab drop region inside a `DockArea`.
enum DockDropZone { centerTab, left, right, top, bottom }

/// Solved pixel geometry for a single draggable `SplitView` gutter.
final class SolvedSplitter {
  final String splitId;
  final DockSplitAxis axis;
  final VoxRect rect;
  final VoxRect parentRect;
  final double currentRatio;

  const SolvedSplitter({
    required this.splitId,
    required this.axis,
    required this.rect,
    required this.parentRect,
    required this.currentRatio,
  });
}

/// Solved pixel geometry for a single tabbed `DockArea` pane.
final class SolvedDockArea {
  final String areaId;
  final List<String> panelIds;
  final int activeIndex;
  final VoxRect bounds;
  final VoxRect tabBarRect;
  final VoxRect contentRect;
  final List<VoxRect> tabRects;

  const SolvedDockArea({
    required this.areaId,
    required this.panelIds,
    required this.activeIndex,
    required this.bounds,
    required this.tabBarRect,
    required this.contentRect,
    required this.tabRects,
  });

  String? get activePanelId => panelIds.isEmpty
      ? null
      : panelIds[activeIndex.clamp(0, panelIds.length - 1)];
}

/// Complete solved workspace layout for one frame.
final class SolvedDockWorkspace {
  final VoxRect workspaceRect;
  final List<SolvedDockArea> areas;
  final List<SolvedSplitter> splitters;

  const SolvedDockWorkspace({
    required this.workspaceRect,
    required this.areas,
    required this.splitters,
  });

  SolvedDockArea? areaById(String id) {
    for (final a in areas) {
      if (a.areaId == id) return a;
    }
    return null;
  }

  SolvedDockArea? areaAt(double x, double y) {
    for (final a in areas) {
      if (a.bounds.contains(x, y)) return a;
    }
    return null;
  }

  SolvedSplitter? splitterAt(double x, double y, {double hitPad = 3.0}) {
    for (final s in splitters) {
      final padded = VoxRect(
        s.rect.x - hitPad,
        s.rect.y - hitPad,
        s.rect.width + hitPad * 2,
        s.rect.height + hitPad * 2,
      );
      if (padded.contains(x, y)) return s;
    }
    return null;
  }
}

/// Pure-Dart Unity `SplitView` / `DockArea` layout solver & mutator (`[Wave G2]`).
abstract final class DockLayoutSolver {
  static const double defaultSplitterSize = 4.0;
  static const double defaultTabBarHeight = 24.0;

  /// Solves [layout] inside [workspaceRect]. If [maximizedAreaId] is set, that
  /// area fills the entire [workspaceRect] (`Shift+Space`).
  static SolvedDockWorkspace solve(
    StudioDockLayout layout,
    VoxRect workspaceRect, {
    String? maximizedAreaId,
    double splitterSize = defaultSplitterSize,
    double tabBarHeight = defaultTabBarHeight,
  }) {
    final areas = <SolvedDockArea>[];
    final splitters = <SolvedSplitter>[];

    if (maximizedAreaId != null) {
      final found = _findTabsNode(layout.root, maximizedAreaId);
      if (found != null) {
        areas.add(_buildArea(found, workspaceRect, tabBarHeight));
        return SolvedDockWorkspace(
          workspaceRect: workspaceRect,
          areas: areas,
          splitters: const [],
        );
      }
    }

    _solveNode(
      layout.root,
      workspaceRect,
      areas,
      splitters,
      splitterSize,
      tabBarHeight,
    );
    return SolvedDockWorkspace(
      workspaceRect: workspaceRect,
      areas: areas,
      splitters: splitters,
    );
  }

  static void _solveNode(
    DockNode node,
    VoxRect rect,
    List<SolvedDockArea> areas,
    List<SolvedSplitter> splitters,
    double splitterSize,
    double tabBarHeight,
  ) {
    switch (node) {
      case DockTabsNode():
        areas.add(_buildArea(node, rect, tabBarHeight));
      case DockSplitNode():
        final ratio = node.ratio.clamp(0.12, 0.88);
        if (node.axis == DockSplitAxis.horizontal) {
          final usableW = (rect.width - splitterSize).clamp(
            0.0,
            double.infinity,
          );
          final w1 = usableW * ratio;
          final w2 = usableW - w1;
          final r1 = VoxRect(rect.x, rect.y, w1, rect.height);
          final splitRect = VoxRect(
            rect.x + w1,
            rect.y,
            splitterSize,
            rect.height,
          );
          final r2 = VoxRect(
            rect.x + w1 + splitterSize,
            rect.y,
            w2,
            rect.height,
          );
          splitters.add(
            SolvedSplitter(
              splitId: node.id,
              axis: node.axis,
              rect: splitRect,
              parentRect: rect,
              currentRatio: ratio,
            ),
          );
          _solveNode(
            node.first,
            r1,
            areas,
            splitters,
            splitterSize,
            tabBarHeight,
          );
          _solveNode(
            node.second,
            r2,
            areas,
            splitters,
            splitterSize,
            tabBarHeight,
          );
        } else {
          final usableH = (rect.height - splitterSize).clamp(
            0.0,
            double.infinity,
          );
          final h1 = usableH * ratio;
          final h2 = usableH - h1;
          final r1 = VoxRect(rect.x, rect.y, rect.width, h1);
          final splitRect = VoxRect(
            rect.x,
            rect.y + h1,
            rect.width,
            splitterSize,
          );
          final r2 = VoxRect(
            rect.x,
            rect.y + h1 + splitterSize,
            rect.width,
            h2,
          );
          splitters.add(
            SolvedSplitter(
              splitId: node.id,
              axis: node.axis,
              rect: splitRect,
              parentRect: rect,
              currentRatio: ratio,
            ),
          );
          _solveNode(
            node.first,
            r1,
            areas,
            splitters,
            splitterSize,
            tabBarHeight,
          );
          _solveNode(
            node.second,
            r2,
            areas,
            splitters,
            splitterSize,
            tabBarHeight,
          );
        }
    }
  }

  static SolvedDockArea _buildArea(
    DockTabsNode node,
    VoxRect rect,
    double tabBarHeight,
  ) {
    final tbH = tabBarHeight.clamp(0.0, rect.height);
    final tabBarRect = VoxRect(rect.x, rect.y, rect.width, tbH);
    final contentRect = VoxRect(
      rect.x,
      rect.y + tbH,
      rect.width,
      (rect.height - tbH).clamp(0.0, double.infinity),
    );
    final tabRects = <VoxRect>[];
    if (node.panelIds.isNotEmpty) {
      final maxTabW = (rect.width / node.panelIds.length).clamp(48.0, 128.0);
      var x = rect.x + 2.0;
      for (var i = 0; i < node.panelIds.length; i++) {
        final w = maxTabW.clamp(36.0, (rect.right - x).clamp(0.0, maxTabW));
        tabRects.add(VoxRect(x, rect.y + 2.0, w, (tbH - 2.0).clamp(0.0, tbH)));
        x += w + 2.0;
      }
    }
    return SolvedDockArea(
      areaId: node.id,
      panelIds: node.panelIds,
      activeIndex: node.activeIndex,
      bounds: rect,
      tabBarRect: tabBarRect,
      contentRect: contentRect,
      tabRects: tabRects,
    );
  }

  static DockTabsNode? _findTabsNode(DockNode node, String areaId) {
    switch (node) {
      case DockTabsNode():
        return node.id == areaId ? node : null;
      case DockSplitNode():
        return _findTabsNode(node.first, areaId) ??
            _findTabsNode(node.second, areaId);
    }
  }

  /// Determines which of Unity's 5 drop zones `(left, right, top, bottom, centerTab)`
  /// pointer `(px, py)` falls into within [area], along with the preview rect.
  static (DockDropZone zone, VoxRect previewRect) resolveDropZone(
    SolvedDockArea area,
    double px,
    double py,
  ) {
    final r = area.contentRect;
    final relX = r.width > 0 ? ((px - r.x) / r.width).clamp(0.0, 1.0) : 0.5;
    final relY = r.height > 0 ? ((py - r.y) / r.height).clamp(0.0, 1.0) : 0.5;

    if (py < area.contentRect.y ||
        (relX > 0.25 && relX < 0.75 && relY > 0.25 && relY < 0.75)) {
      return (DockDropZone.centerTab, area.bounds);
    }
    final distLeft = relX;
    final distRight = 1.0 - relX;
    final distTop = relY;
    final distBottom = 1.0 - relY;
    final minDist = [
      distLeft,
      distRight,
      distTop,
      distBottom,
    ].reduce((a, b) => a < b ? a : b);

    if (minDist == distLeft) {
      return (DockDropZone.left, VoxRect(r.x, r.y, r.width * 0.5, r.height));
    }
    if (minDist == distRight) {
      return (
        DockDropZone.right,
        VoxRect(r.x + r.width * 0.5, r.y, r.width * 0.5, r.height),
      );
    }
    if (minDist == distTop) {
      return (DockDropZone.top, VoxRect(r.x, r.y, r.width, r.height * 0.5));
    }
    return (
      DockDropZone.bottom,
      VoxRect(r.x, r.y + r.height * 0.5, r.width, r.height * 0.5),
    );
  }

  /// Updates the split ratio for [splitId] immutably.
  static StudioDockLayout setSplitRatio(
    StudioDockLayout layout,
    String splitId,
    double ratio,
  ) => StudioDockLayout(
    version: layout.version,
    root: _updateSplit(layout.root, splitId, ratio.clamp(0.12, 0.88)),
  );

  static DockNode _updateSplit(DockNode node, String splitId, double ratio) {
    switch (node) {
      case DockTabsNode():
        return node;
      case DockSplitNode():
        if (node.id == splitId) {
          return node.copyWith(ratio: ratio);
        }
        return node.copyWith(
          first: _updateSplit(node.first, splitId, ratio),
          second: _updateSplit(node.second, splitId, ratio),
        );
    }
  }

  /// Selects [panelId] as active tab inside [areaId].
  static StudioDockLayout selectTab(
    StudioDockLayout layout,
    String areaId,
    String panelId,
  ) => StudioDockLayout(
    version: layout.version,
    root: _selectTabNode(layout.root, areaId, panelId),
  );

  static DockNode _selectTabNode(DockNode node, String areaId, String panelId) {
    switch (node) {
      case DockTabsNode():
        if (node.id != areaId) return node;
        final idx = node.panelIds.indexOf(panelId);
        if (idx < 0) return node;
        return node.copyWith(activeIndex: idx);
      case DockSplitNode():
        return node.copyWith(
          first: _selectTabNode(node.first, areaId, panelId),
          second: _selectTabNode(node.second, areaId, panelId),
        );
    }
  }

  /// Moves [panelId] from [sourceAreaId] into [targetAreaId] at [zone],
  /// pruning any emptied source `DockArea` cleanly.
  static StudioDockLayout dockPanel(
    StudioDockLayout layout, {
    required String panelId,
    required String sourceAreaId,
    required String targetAreaId,
    required DockDropZone zone,
  }) {
    if (sourceAreaId == targetAreaId && zone == DockDropZone.centerTab) {
      return selectTab(layout, targetAreaId, panelId);
    }
    final withoutSource = _removePanel(layout.root, sourceAreaId, panelId);
    if (withoutSource == null) return layout;
    final inserted = _insertPanel(withoutSource, targetAreaId, panelId, zone);
    return StudioDockLayout(version: layout.version, root: inserted);
  }

  static DockNode? _removePanel(
    DockNode node,
    String sourceAreaId,
    String panelId,
  ) {
    switch (node) {
      case DockTabsNode():
        if (node.id != sourceAreaId) return node;
        final nextIds = node.panelIds.where((id) => id != panelId).toList();
        if (nextIds.isEmpty) return null;
        return node.copyWith(
          panelIds: nextIds,
          activeIndex: node.activeIndex.clamp(0, nextIds.length - 1),
        );
      case DockSplitNode():
        final f = _removePanel(node.first, sourceAreaId, panelId);
        final s = _removePanel(node.second, sourceAreaId, panelId);
        if (f == null) return s;
        if (s == null) return f;
        return node.copyWith(first: f, second: s);
    }
  }

  static DockNode _insertPanel(
    DockNode node,
    String targetAreaId,
    String panelId,
    DockDropZone zone,
  ) {
    switch (node) {
      case DockTabsNode():
        if (node.id != targetAreaId) return node;
        if (zone == DockDropZone.centerTab) {
          final nextIds = [
            ...node.panelIds.where((id) => id != panelId),
            panelId,
          ];
          return node.copyWith(
            panelIds: nextIds,
            activeIndex: nextIds.length - 1,
          );
        }
        final newPane = DockTabsNode(
          id: 'dock_${panelId}_${zone.name}',
          panelIds: [panelId],
        );
        final axis = (zone == DockDropZone.left || zone == DockDropZone.right)
            ? DockSplitAxis.horizontal
            : DockSplitAxis.vertical;
        final newFirst =
            (zone == DockDropZone.left || zone == DockDropZone.top);
        return DockSplitNode(
          id: 'split_${targetAreaId}_$panelId',
          axis: axis,
          ratio: 0.5,
          first: newFirst ? newPane : node,
          second: newFirst ? node : newPane,
        );
      case DockSplitNode():
        return node.copyWith(
          first: _insertPanel(node.first, targetAreaId, panelId, zone),
          second: _insertPanel(node.second, targetAreaId, panelId, zone),
        );
    }
  }

  /// Unity-style "Wide" workspace preset (Scene/Game full top, Hierarchy +
  /// Project + Console across bottom, Inspector right).
  static StudioDockLayout wideLayout() => const StudioDockLayout(
    root: DockSplitNode(
      id: 'wide_h',
      axis: DockSplitAxis.horizontal,
      ratio: 0.78,
      first: DockSplitNode(
        id: 'wide_left_v',
        axis: DockSplitAxis.vertical,
        ratio: 0.68,
        first: DockTabsNode(id: 'center_dock', panelIds: ['scene', 'game']),
        second: DockSplitNode(
          id: 'wide_bottom_h',
          axis: DockSplitAxis.horizontal,
          ratio: 0.30,
          first: DockTabsNode(id: 'hierarchy_dock', panelIds: ['hierarchy']),
          second: DockTabsNode(
            id: 'bottom_dock',
            panelIds: ['project', 'console', 'profiler'],
          ),
        ),
      ),
      second: DockTabsNode(
        id: 'right_dock',
        panelIds: ['inspector', 'lighting', 'modules'],
      ),
    ),
  );

  /// Unity-style "2 by 3" workspace preset (Scene & Game stacked left,
  /// Hierarchy + Project middle, Inspector right).
  static StudioDockLayout twoByThreeLayout() => const StudioDockLayout(
    root: DockSplitNode(
      id: '2x3_h',
      axis: DockSplitAxis.horizontal,
      ratio: 0.52,
      first: DockSplitNode(
        id: '2x3_views_v',
        axis: DockSplitAxis.vertical,
        ratio: 0.5,
        first: DockTabsNode(id: 'scene_dock', panelIds: ['scene']),
        second: DockTabsNode(id: 'game_dock', panelIds: ['game']),
      ),
      second: DockSplitNode(
        id: '2x3_right_h',
        axis: DockSplitAxis.horizontal,
        ratio: 0.48,
        first: DockSplitNode(
          id: '2x3_mid_v',
          axis: DockSplitAxis.vertical,
          ratio: 0.5,
          first: DockTabsNode(id: 'hierarchy_dock', panelIds: ['hierarchy']),
          second: DockTabsNode(
            id: 'project_dock',
            panelIds: ['project', 'console'],
          ),
        ),
        second: DockTabsNode(
          id: 'inspector_dock',
          panelIds: ['inspector', 'lighting', 'modules'],
        ),
      ),
    ),
  );
}
