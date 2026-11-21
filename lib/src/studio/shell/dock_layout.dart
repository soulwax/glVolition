/// Pure-Dart Volition Studio panel & serializable docking layout tree (S2-0).
library;

/// Contract implemented by every dockable Studio panel (Hierarchy, Inspector,
/// Scene, Game, Project, Console, Build/Tools, etc.).
abstract interface class StudioPanel {
  String get id;
  String get title;

  Map<String, Object?> saveState();
  void restoreState(Map<String, Object?> state);
}

/// Split orientation for [DockSplitNode].
enum DockSplitAxis { horizontal, vertical }

/// Serializable node inside a [StudioDockLayout] binary split tree.
sealed class DockNode {
  const DockNode();

  Map<String, Object?> toJson();

  static DockNode fromJson(Map<String, Object?> json) {
    final kind = json['kind'] as String?;
    return switch (kind) {
      'split' => DockSplitNode.fromJson(json),
      'tabs' => DockTabsNode.fromJson(json),
      _ => throw FormatException('Unknown DockNode kind: $kind'),
    };
  }
}

/// Divides a region into [first] and [second] along [axis] with [ratio] in
/// `[0.1, 0.9]`.
final class DockSplitNode extends DockNode {
  final String id;
  final DockSplitAxis axis;
  final double ratio;
  final DockNode first;
  final DockNode second;

  const DockSplitNode({
    required this.id,
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  DockSplitNode copyWith({double? ratio, DockNode? first, DockNode? second}) =>
      DockSplitNode(
        id: id,
        axis: axis,
        ratio: (ratio ?? this.ratio).clamp(0.1, 0.9),
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'split',
    'id': id,
    'axis': axis.name,
    'ratio': ratio,
    'first': first.toJson(),
    'second': second.toJson(),
  };

  factory DockSplitNode.fromJson(Map<String, Object?> json) {
    final axisName = json['axis'] as String? ?? 'horizontal';
    final axis = DockSplitAxis.values.firstWhere(
      (a) => a.name == axisName,
      orElse: () => DockSplitAxis.horizontal,
    );
    return DockSplitNode(
      id: json['id'] as String? ?? 'split',
      axis: axis,
      ratio: ((json['ratio'] as num?)?.toDouble() ?? 0.5).clamp(0.1, 0.9),
      first: DockNode.fromJson((json['first'] as Map).cast<String, Object?>()),
      second: DockNode.fromJson(
        (json['second'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

/// Leaf tab group hosting one or more [StudioPanel] ids plus persisted
/// per-panel state maps.
final class DockTabsNode extends DockNode {
  final String id;
  final List<String> panelIds;
  final int activeIndex;
  final Map<String, Map<String, Object?>> panelStates;

  const DockTabsNode({
    required this.id,
    required this.panelIds,
    this.activeIndex = 0,
    this.panelStates = const {},
  });

  String? get activePanelId => panelIds.isEmpty
      ? null
      : panelIds[activeIndex.clamp(0, panelIds.length - 1)];

  DockTabsNode copyWith({
    List<String>? panelIds,
    int? activeIndex,
    Map<String, Map<String, Object?>>? panelStates,
  }) => DockTabsNode(
    id: id,
    panelIds: panelIds ?? this.panelIds,
    activeIndex: activeIndex ?? this.activeIndex,
    panelStates: panelStates ?? this.panelStates,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'tabs',
    'id': id,
    'panelIds': panelIds,
    'activeIndex': activeIndex,
    if (panelStates.isNotEmpty) 'panelStates': panelStates,
  };

  factory DockTabsNode.fromJson(Map<String, Object?> json) {
    final ids = ((json['panelIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final rawStates = json['panelStates'];
    final states = <String, Map<String, Object?>>{};
    if (rawStates is Map) {
      for (final entry in rawStates.entries) {
        if (entry.value is Map) {
          states[entry.key.toString()] = (entry.value as Map)
              .cast<String, Object?>();
        }
      }
    }
    return DockTabsNode(
      id: json['id'] as String? ?? 'tabs',
      panelIds: ids,
      activeIndex: (json['activeIndex'] as num?)?.toInt() ?? 0,
      panelStates: states,
    );
  }
}

/// Root serializable docking workspace layout for Volition Studio.
final class StudioDockLayout {
  static const int schemaVersion = 1;

  final int version;
  final DockNode root;

  const StudioDockLayout({this.version = schemaVersion, required this.root});

  /// Default Unity-style 4-region Studio layout:
  /// Hierarchy (left) | Scene & Game (center) | Inspector (right)
  /// with Project, Console, and Build/Tools docked across the bottom.
  factory StudioDockLayout.defaultLayout() => const StudioDockLayout(
    root: DockSplitNode(
      id: 'root_vertical',
      axis: DockSplitAxis.vertical,
      ratio: 0.72,
      first: DockSplitNode(
        id: 'top_left_right',
        axis: DockSplitAxis.horizontal,
        ratio: 0.2,
        first: DockTabsNode(id: 'left_dock', panelIds: ['hierarchy']),
        second: DockSplitNode(
          id: 'center_inspector',
          axis: DockSplitAxis.horizontal,
          ratio: 0.72,
          first: DockTabsNode(
            id: 'viewport_dock',
            panelIds: ['scene', 'game'],
            activeIndex: 0,
          ),
          second: DockTabsNode(id: 'right_dock', panelIds: ['inspector']),
        ),
      ),
      second: DockTabsNode(
        id: 'bottom_dock',
        panelIds: ['project', 'console', 'tools'],
        activeIndex: 0,
      ),
    ),
  );

  /// Lists all panel ids currently docked in this layout.
  List<String> get panelIds {
    final out = <String>[];
    void walk(DockNode node) {
      switch (node) {
        case DockSplitNode(:final first, :final second):
          walk(first);
          walk(second);
        case DockTabsNode(:final panelIds):
          out.addAll(panelIds);
      }
    }

    walk(root);
    return out;
  }

  /// Returns a new layout with [panelId] focused in its containing [DockTabsNode].
  StudioDockLayout focusPanel(String panelId) {
    DockNode update(DockNode node) => switch (node) {
      DockSplitNode() => node.copyWith(
        first: update(node.first),
        second: update(node.second),
      ),
      DockTabsNode(:final panelIds) =>
        panelIds.contains(panelId)
            ? node.copyWith(activeIndex: panelIds.indexOf(panelId))
            : node,
    };
    return StudioDockLayout(version: version, root: update(root));
  }

  /// Returns a new layout with split [splitId] resized to [ratio].
  StudioDockLayout resizeSplit(String splitId, double ratio) {
    DockNode update(DockNode node) => switch (node) {
      DockSplitNode(:final id) =>
        id == splitId
            ? node.copyWith(ratio: ratio)
            : node.copyWith(
                first: update(node.first),
                second: update(node.second),
              ),
      DockTabsNode() => node,
    };
    return StudioDockLayout(version: version, root: update(root));
  }

  Map<String, Object?> toJson() => {'version': version, 'root': root.toJson()};

  factory StudioDockLayout.fromJson(Map<String, Object?> json) =>
      StudioDockLayout(
        version: (json['version'] as num?)?.toInt() ?? schemaVersion,
        root: DockNode.fromJson((json['root'] as Map).cast<String, Object?>()),
      );
}
