/// Volition Studio Extension Host & Edit-Mode Execution Runner (`[S5-C]`):
/// Discovers and dispatches custom inspectors, gizmo drawers, menu items,
/// context actions, and `@ExecuteInEditMode` ticks with an `isPlaying` guard.
library;

import 'package:pixeldart/rendering/api/editor_overlay.dart';

import '../../engine.dart';
import '../commands/menu_registry.dart';
import '../extensions/editor_extension.dart';

/// Optional mixin/interface for [Behaviour]s that execute in Edit Mode
/// (`[S5-C]`).
abstract interface class EditModeTickable {
  /// Called on edit-mode ticks with [isPlaying] (`false` in Edit Mode).
  void onEditModeUpdate(double dt, {required bool isPlaying});
}

/// Central registry hosting Studio editor extensions (`[S5-C]`).
final class StudioExtensionHost {
  final Map<Type, List<CustomInspector<Component>>> _inspectors = {};
  final Map<Type, List<GizmoDrawer<Component>>> _gizmoDrawers = {};
  final List<StudioMenuItemExtension> _menuItems = [];
  final List<StudioEditorWindow> _windows = [];
  final List<StudioContextAction> _contextActions = [];
  final List<StudioToolbarTool> _toolbarTools = [];

  void registerInspector<T extends Component>(CustomInspector<T> inspector) {
    final list = _inspectors.putIfAbsent(T, () => []);
    list.add(inspector);
    list.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void registerGizmoDrawer<T extends Component>(GizmoDrawer<T> drawer) {
    _gizmoDrawers.putIfAbsent(T, () => []).add(drawer);
  }

  void registerMenuItem(
    StudioMenuItemExtension item, {
    StudioMenuRegistry? menuRegistry,
  }) {
    _menuItems.add(item);
    menuRegistry?.register(
      StudioMenuItem(
        id: item.id,
        menuPath: item.menuPath,
        action: item.onExecute,
      ),
    );
  }

  void registerWindow(StudioEditorWindow window) => _windows.add(window);
  void registerContextAction(StudioContextAction action) =>
      _contextActions.add(action);
  void registerToolbarTool(StudioToolbarTool tool) => _toolbarTools.add(tool);

  /// Returns the highest-priority [CustomInspector] for [component], or `null`
  /// to fall back to the generic `ComponentSpec` inspector.
  CustomInspector<Component>? resolveInspector(Component component) {
    final list = _inspectors[component.runtimeType];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  /// Collects all gizmo lines emitted by registered [GizmoDrawer]s for
  /// [component].
  List<EditorGizmoLine> collectGizmos(
    Component component, {
    required bool isSelected,
  }) {
    final drawers = _gizmoDrawers[component.runtimeType];
    if (drawers == null || drawers.isEmpty) return const [];
    return [
      for (final d in drawers)
        ...d.drawGizmos(component, isSelected: isSelected),
    ];
  }

  List<StudioContextAction> contextActionsFor(GameObject go) {
    final types = {for (final c in go.components) c.runtimeType};
    return [
      for (final a in _contextActions)
        if (a.targetComponentType == null ||
            types.contains(a.targetComponentType))
          a,
    ];
  }

  List<StudioMenuItemExtension> get menuItems => List.unmodifiable(_menuItems);
  List<StudioEditorWindow> get windows => List.unmodifiable(_windows);
  List<StudioToolbarTool> get toolbarTools => List.unmodifiable(_toolbarTools);

  /// Ticks all [EditModeTickable] components in [scene] when not playing.
  int tickEditMode(Scene scene, double dt, {required bool isPlaying}) {
    if (isPlaying) return 0;
    var ticked = 0;
    void walk(GameObject go) {
      for (final c in go.components) {
        if (c is EditModeTickable && c is Behaviour && c.enabled) {
          (c as EditModeTickable).onEditModeUpdate(dt, isPlaying: false);
          ticked++;
        }
      }
      for (final child in go.children) {
        walk(child);
      }
    }

    for (final root in scene.rootGameObjects) {
      walk(root);
    }
    return ticked;
  }
}
