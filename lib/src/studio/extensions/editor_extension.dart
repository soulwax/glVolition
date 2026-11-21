/// Volition Studio Editor Extension Contracts (`[S5-0]`):
/// Pure-Dart extension points for CustomInspector, GizmoDrawer, MenuItem,
/// EditorWindow, AssetImporter, ContextAction, and ToolbarTool.
library;

import 'package:pixeldart/rendering/api/editor_overlay.dart';

import '../../engine.dart';

/// Custom inspector descriptor overriding or augmenting the generic inspector
/// for component type [T] (`[S5-0]`).
abstract class CustomInspector<T extends Component> {
  Type get targetType => T;
  int get priority => 0;

  /// Builds custom inspector widget rows for [component].
  List<Map<String, Object?>> buildRows(T component);
}

/// Custom 3D gizmo drawer for component type [T] (`[S5-0]`).
abstract class GizmoDrawer<T extends Component> {
  Type get targetType => T;

  /// Emits `EditorGizmoLine` segments for [component].
  List<EditorGizmoLine> drawGizmos(T component, {required bool isSelected});
}

/// Declarative Studio menu item extension (`[S5-0]`).
final class StudioMenuItemExtension {
  final String id;
  final String menuPath;
  final String? shortcut;
  final void Function() onExecute;

  const StudioMenuItemExtension({
    required this.id,
    required this.menuPath,
    required this.onExecute,
    this.shortcut,
  });
}

/// Declarative Studio dockable editor window extension (`[S5-0]`).
final class StudioEditorWindow {
  final String id;
  final String title;
  final String menuPath;

  const StudioEditorWindow({
    required this.id,
    required this.title,
    required this.menuPath,
  });
}

/// Declarative Studio asset importer extension (`[S5-0]`).
final class StudioAssetImporter {
  final String id;
  final List<String> extensions;
  final Map<String, Object?> Function(String path, String content) importAsset;

  const StudioAssetImporter({
    required this.id,
    required this.extensions,
    required this.importAsset,
  });
}

/// Context-menu action extension (e.g. "Generate / Regenerate with seed").
final class StudioContextAction {
  final String id;
  final String label;
  final Type? targetComponentType;
  final void Function(GameObject target) onExecute;

  const StudioContextAction({
    required this.id,
    required this.label,
    required this.onExecute,
    this.targetComponentType,
  });
}

/// Viewport toolbar tool extension (`[S5-0]`).
final class StudioToolbarTool {
  final String id;
  final String label;
  final String iconId;

  const StudioToolbarTool({
    required this.id,
    required this.label,
    required this.iconId,
  });
}
