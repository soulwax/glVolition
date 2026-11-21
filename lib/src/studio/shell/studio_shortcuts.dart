/// Pure-Dart Unity-Style Keyboard Shortcuts, Scene Authoring Commands & Layout
/// Persistence (`[Wave G8]`):
/// - `Ctrl+Z` Undo, `Ctrl+Y` / `Ctrl+Shift+Z` Redo
/// - `Ctrl+D` Duplicate, `Delete` Delete selected
/// - `F` Frame selected in Scene View
/// - `Q/W/E/R/T` Transform gizmo tool selection
/// - `Shift+Space` Maximize / Restore hovered `DockArea`
/// - `RMB + WASD / Q / E` Scene View fly camera
/// - `Escape` Close open menus & popups
/// - `.volition/layout.json` save/load via [ProjectFileSystem]
library;

import 'dart:convert';

import '../../../gl_volition.dart';
import '../project/project_fs.dart';
import 'dock_layout.dart';
import 'dock_layout_solver.dart';
import 'studio_workspace_ui.dart';

/// Per-frame keyboard & modifier snapshot passed to [StudioWorkspaceShell].
final class StudioKeyboardState {
  final Set<String> heldKeys;
  final Set<String> pressedKeys;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool isRightMouseDown;
  final String typedText;
  final bool backspace;

  const StudioKeyboardState({
    this.heldKeys = const {},
    this.pressedKeys = const {},
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.isRightMouseDown = false,
    this.typedText = '',
    this.backspace = false,
  });

  bool isHeld(String key) => heldKeys.contains(key);
  bool wasPressed(String key) => pressedKeys.contains(key);
}

/// Undoable GameObject creation command (`[Wave G8]`).
final class CreateGameObjectStudioCommand implements EditorCommand {
  @override
  final String name;
  final String objectName;
  final Vec3 position;
  final void Function(GameObject go)? configure;

  GameObject? _created;

  CreateGameObjectStudioCommand({
    required this.objectName,
    this.position = Vec3.zero,
    this.configure,
  }) : name = 'Create $objectName';

  GameObject? get createdObject => _created;

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.createGameObject(objectName);
    go.transform.localPosition = position;
    configure?.call(go);
    _created = go;
    session.selected = go;
  }

  @override
  void undo(EditorSession session) {
    final go = _created;
    if (go != null && !go.isDestroyed) {
      go.setActive(false);
      go.destroy();
      session.selected = null;
    }
  }
}

/// Undoable GameObject deactivation/removal command (`[Wave G8]`).
final class DeleteGameObjectStudioCommand implements EditorCommand {
  @override
  final String name;
  final GameObject target;
  bool _wasActive = true;

  DeleteGameObjectStudioCommand(this.target) : name = 'Delete ${target.name}';

  @override
  void execute(EditorSession session) {
    if (target.isDestroyed) return;
    _wasActive = target.activeSelf;
    target.setActive(false);
    if (session.selected == target) {
      session.selected = null;
    }
  }

  @override
  void undo(EditorSession session) {
    if (target.isDestroyed) return;
    target.setActive(_wasActive);
    session.selected = target;
  }
}

/// Dispatches Unity-standard keyboard shortcuts and fly-camera navigation
/// against [StudioWorkspaceShell] (`[Wave G8]`).
abstract final class StudioShortcutDispatcher {
  static void dispatch({
    required StudioWorkspaceShell shell,
    required StudioKeyboardState keyboard,
    required SolvedDockWorkspace? previousSolved,
    required double mouseX,
    required double mouseY,
    required double dtSeconds,
  }) {
    // Hold Ctrl for gizmo grid snapping
    shell.gizmoInteractor.snapEnabled = keyboard.ctrl;

    // Escape closes any open popup or top menu
    if (keyboard.wasPressed('escape')) {
      shell.openTopMenu = null;
      shell.hierarchyCreateMenuOpen = false;
      shell.addComponentPopupOpen = false;
      shell.hierarchySearchFocused = false;
      return;
    }

    // If Hierarchy search box is focused, route text input to search query
    if (shell.hierarchySearchFocused) {
      if (keyboard.backspace && shell.hierarchy.searchQuery.isNotEmpty) {
        shell.hierarchy.searchQuery = shell.hierarchy.searchQuery.substring(
          0,
          shell.hierarchy.searchQuery.length - 1,
        );
      }
      if (keyboard.typedText.isNotEmpty) {
        shell.hierarchy.searchQuery += keyboard.typedText;
      }
      return;
    }

    // Undo / Redo
    if (keyboard.ctrl && keyboard.wasPressed('z')) {
      if (keyboard.shift) {
        shell.bridge.session.redo();
      } else {
        shell.bridge.session.undo();
      }
      return;
    }
    if (keyboard.ctrl && keyboard.wasPressed('y')) {
      shell.bridge.session.redo();
      return;
    }

    // Duplicate selected (Ctrl+D)
    if (keyboard.ctrl && keyboard.wasPressed('d')) {
      duplicateSelected(shell);
      return;
    }

    // Delete selected (Delete)
    if (keyboard.wasPressed('delete')) {
      deleteSelected(shell);
      return;
    }

    // Maximize / Restore hovered DockArea (Shift+Space)
    if (keyboard.shift && keyboard.wasPressed('space')) {
      final hovered = previousSolved?.areaAt(mouseX, mouseY);
      if (hovered != null) {
        shell.toggleMaximizeArea(hovered.areaId);
      }
      return;
    }

    // RMB + WASD/QE Scene View fly camera
    if (keyboard.isRightMouseDown) {
      final fwd =
          (keyboard.isHeld('w') ? 1.0 : 0.0) -
          (keyboard.isHeld('s') ? 1.0 : 0.0);
      final right =
          (keyboard.isHeld('d') ? 1.0 : 0.0) -
          (keyboard.isHeld('a') ? 1.0 : 0.0);
      final up =
          (keyboard.isHeld('e') ? 1.0 : 0.0) -
          (keyboard.isHeld('q') ? 1.0 : 0.0);
      if (fwd != 0.0 || right != 0.0 || up != 0.0) {
        shell.sceneViewport.editorCamera.flyWasd(
          forwardInput: fwd,
          rightInput: right,
          upInput: up,
          dt: dtSeconds,
          boost: keyboard.shift,
        );
      }
      return;
    }

    // Frame selected object in Scene View (F)
    if (!keyboard.ctrl && keyboard.wasPressed('f')) {
      final sel = shell.bridge.session.selectedObjects;
      if (sel.isNotEmpty) {
        final cam = shell.sceneViewport.editorCamera;
        cam.target = sel.first.transform.position;
        cam.distance = 6.0;
      }
      return;
    }

    // Gizmo tool shortcuts (Q/W/E/R/T)
    if (!keyboard.ctrl && !keyboard.alt) {
      if (keyboard.wasPressed('q')) shell.activeGizmoTool = 'hand';
      if (keyboard.wasPressed('w')) shell.activeGizmoTool = 'move';
      if (keyboard.wasPressed('e')) shell.activeGizmoTool = 'rotate';
      if (keyboard.wasPressed('r')) shell.activeGizmoTool = 'scale';
      if (keyboard.wasPressed('t')) shell.activeGizmoTool = 'rect';
    }
  }

  static void duplicateSelected(StudioWorkspaceShell shell) {
    final sel = shell.bridge.session.selectedObjects;
    if (sel.isEmpty) return;
    final src = sel.first;
    final cmd = CreateGameObjectStudioCommand(
      objectName: '${src.name} (Copy)',
      position: src.transform.localPosition + const Vec3(1.0, 0.0, 0.0),
    );
    shell.bridge.session.executeCommand(cmd);
  }

  static void deleteSelected(StudioWorkspaceShell shell) {
    final sel = shell.bridge.session.selectedObjects;
    if (sel.isEmpty) return;
    shell.bridge.session.executeCommand(
      DeleteGameObjectStudioCommand(sel.first),
    );
  }
}

/// Persists and restores `.volition/layout.json` via [ProjectFileSystem].
abstract final class StudioLayoutPersistence {
  static const String defaultPath = '.volition/layout.json';

  static Future<void> saveLayout(
    ProjectFileSystem fs,
    StudioDockLayout layout, {
    String path = defaultPath,
  }) async {
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(layout.toJson());
    await fs.writeString(path, jsonText);
  }

  static Future<StudioDockLayout?> loadLayout(
    ProjectFileSystem fs, {
    String path = defaultPath,
  }) async {
    if (!await fs.exists(path)) return null;
    try {
      final raw = await fs.readString(path);
      final map = jsonDecode(raw) as Map<String, Object?>;
      return StudioDockLayout.fromJson(map);
    } on Object {
      return null;
    }
  }
}
