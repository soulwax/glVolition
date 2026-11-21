/// Pure-Dart Hierarchy panel model (S2-C): tree flattening, expand/collapse,
/// search/filter, single/toggle/shift-range multi-select, and undoable
/// reparent, rename, create, duplicate, active-toggle, and delete commands.
library;

import '../../../gl_volition.dart';
import '../bridge/editor_host_bridge.dart';
import '../shell/dock_layout.dart';

/// Undoable rename command for a [GameObject].
final class RenameGameObjectCommand implements EditorCommand {
  @override
  final String name;
  final String oldName;
  final String newName;

  RenameGameObjectCommand({
    this.name = 'Rename GameObject',
    required this.oldName,
    required this.newName,
  });

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(oldName);
    if (go != null) go.name = newName;
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(newName);
    if (go != null) go.name = oldName;
  }
}

/// Flattened visible row in the Studio Hierarchy panel.
final class HierarchyRowView {
  final GameObject object;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isSelected;

  const HierarchyRowView({
    required this.object,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isSelected,
  });
}

/// Platform-neutral Hierarchy panel controller backed by [EditorHostBridge].
final class HierarchyPanelModel implements StudioPanel {
  final EditorHostBridge bridge;
  final Set<String> _expandedNames = {};
  String searchQuery = '';
  String? tagFilter;
  int? layerFilter;
  String? _anchorName;

  HierarchyPanelModel(this.bridge);

  @override
  String get id => 'hierarchy';

  @override
  String get title => 'Hierarchy';

  bool isExpanded(String objectName) => _expandedNames.contains(objectName);

  void setExpanded(String objectName, bool expanded) {
    if (expanded) {
      _expandedNames.add(objectName);
    } else {
      _expandedNames.remove(objectName);
    }
  }

  void toggleExpanded(String objectName) =>
      setExpanded(objectName, !isExpanded(objectName));

  /// Returns the flattened list of currently visible hierarchy rows.
  List<HierarchyRowView> visibleRows() {
    final session = bridge.session;
    final hasFilter =
        searchQuery.trim().isNotEmpty ||
        tagFilter != null ||
        layerFilter != null;

    if (hasFilter) {
      final matches = session.searchHierarchy(
        nameQuery: searchQuery.trim().isEmpty ? null : searchQuery,
        tag: tagFilter,
        layer: layerFilter,
      );
      return [
        for (final go in matches)
          HierarchyRowView(
            object: go,
            depth: 0,
            hasChildren: go.children.isNotEmpty,
            isExpanded: false,
            isSelected: session.isSelected(go),
          ),
      ];
    }

    final rows = <HierarchyRowView>[];
    void walk(GameObject go, int depth) {
      if (go.isDestroyed) return;
      final children = go.children.where((c) => !c.isDestroyed).toList();
      final expanded = _expandedNames.contains(go.name);
      rows.add(
        HierarchyRowView(
          object: go,
          depth: depth,
          hasChildren: children.isNotEmpty,
          isExpanded: expanded,
          isSelected: session.isSelected(go),
        ),
      );
      if (expanded) {
        for (final child in children) {
          walk(child, depth + 1);
        }
      }
    }

    for (final root in session.engine.scene.rootGameObjects) {
      walk(root, 0);
    }
    return rows;
  }

  void selectSingle(GameObject target) {
    _anchorName = target.name;
    bridge.selectObjects([target]);
  }

  void selectToggle(GameObject target) {
    _anchorName = target.name;
    bridge.session.select(target, toggle: true);
    bridge.selectObjects(bridge.session.selectedObjects);
  }

  /// Shift-click contiguous range selection across [visibleRows].
  void selectRangeTo(GameObject target) {
    final rows = visibleRows();
    final targetIdx = rows.indexWhere((r) => identical(r.object, target));
    if (targetIdx < 0) return;
    final anchorIdx = _anchorName == null
        ? targetIdx
        : rows.indexWhere((r) => r.object.name == _anchorName);
    final start = anchorIdx < 0
        ? targetIdx
        : (anchorIdx < targetIdx ? anchorIdx : targetIdx);
    final end = anchorIdx < 0
        ? targetIdx
        : (anchorIdx > targetIdx ? anchorIdx : targetIdx);
    bridge.selectObjects([for (var i = start; i <= end; i++) rows[i].object]);
  }

  /// Undoably reparents [child] under [newParent] (or scene root if `null`).
  void reparent(GameObject child, GameObject? newParent) {
    if (identical(child, newParent)) return;
    // Prevent reparenting into own descendant
    var cursor = newParent;
    while (cursor != null) {
      if (identical(cursor, child)) return;
      cursor = cursor.parent;
    }
    bridge.dispatchCommand(
      ReparentCommand(
        targetName: child.name,
        oldParentName: child.parent?.name,
        newParentName: newParent?.name,
      ),
    );
    if (newParent != null) {
      _expandedNames.add(newParent.name);
    }
  }

  /// Undoably renames [target] to [newName].
  void rename(GameObject target, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == target.name) return;
    final wasExpanded = _expandedNames.remove(target.name);
    bridge.dispatchCommand(
      RenameGameObjectCommand(oldName: target.name, newName: trimmed),
    );
    if (wasExpanded) _expandedNames.add(trimmed);
  }

  /// Undoably toggles activeSelf on all [targets].
  void setActive(List<GameObject> targets, bool active) {
    if (targets.isEmpty) return;
    bridge.dispatchCommand(
      BatchSetActiveCommand(
        targetNames: [for (final g in targets) g.name],
        active: active,
      ),
    );
  }

  /// Undoably creates a new child [GameObject] under [parent] (or root).
  GameObject createObject(String name, {GameObject? parent}) {
    final unique = _uniqueName(name);
    bridge.dispatchCommand(
      AddGameObjectCommand(objectName: unique, parentName: parent?.name),
    );
    if (parent != null) _expandedNames.add(parent.name);
    return bridge.session.engine.scene.find(unique)!;
  }

  /// Undoably deletes all currently selected [GameObject]s.
  void deleteSelected() {
    final selected = bridge.session.selectedObjects;
    if (selected.isEmpty) return;
    bridge.dispatchCommand(
      BatchDeleteCommand(targetNames: [for (final g in selected) g.name]),
    );
  }

  String _uniqueName(String base) {
    if (bridge.session.engine.scene.find(base) == null) return base;
    var suffix = 1;
    while (bridge.session.engine.scene.find('$base ($suffix)') != null) {
      suffix++;
    }
    return '$base ($suffix)';
  }

  @override
  Map<String, Object?> saveState() => {
    'expanded': _expandedNames.toList()..sort(),
    'searchQuery': searchQuery,
    if (tagFilter != null) 'tagFilter': tagFilter,
    if (layerFilter != null) 'layerFilter': layerFilter,
  };

  @override
  void restoreState(Map<String, Object?> state) {
    _expandedNames.clear();
    final expanded = state['expanded'];
    if (expanded is List) {
      _expandedNames.addAll(expanded.map((e) => e.toString()));
    }
    searchQuery = state['searchQuery'] as String? ?? '';
    tagFilter = state['tagFilter'] as String?;
    layerFilter = (state['layerFilter'] as num?)?.toInt();
  }
}
