// ignore_for_file: prefer_initializing_formals
part of '../engine.dart';

/// Base contract for reversible undo/redo operations in [EditorSession] (P7-W15-A).
abstract class EditorCommand {
  String get name;
  void execute(EditorSession session);
  void undo(EditorSession session);
}

/// Legacy snapshot command for whole-scene checkpoints when delta commands
/// are not applicable.
class _LegacySnapshotCommand implements EditorCommand {
  @override
  final String name;
  final Map<String, Object?> sceneJson;
  final String? selectedName;
  Map<String, Object?>? _afterSceneJson;
  String? _afterSelectedName;

  _LegacySnapshotCommand({
    required this.name,
    required this.sceneJson,
    this.selectedName,
  });

  @override
  void execute(EditorSession session) {
    if (_afterSceneJson != null) {
      final restored = SceneSerializer.fromJson(
        _afterSceneJson!,
        registry: session.engine.registry,
        prefabs: session.prefabs,
      );
      session.engine.loadScene(restored);
      session.selected = _afterSelectedName != null
          ? session.engine.scene.find(_afterSelectedName!)
          : null;
    }
  }

  @override
  void undo(EditorSession session) {
    _afterSceneJson = SceneSerializer.toJson(
      session.engine.scene,
      registry: session.engine.registry,
    );
    _afterSelectedName = session.selected?.name;

    final restored = SceneSerializer.fromJson(
      sceneJson,
      registry: session.engine.registry,
      prefabs: session.prefabs,
    );
    session.engine.loadScene(restored);
    session.selected = selectedName != null
        ? session.engine.scene.find(selectedName!)
        : null;
  }
}

/// Fine-grained delta command for GameObject translation, rotation, and scale mutations.
/// Operates in O(1) time and memory without full-scene JSON serialization.
class TransformMoveCommand implements EditorCommand {
  @override
  final String name;
  final String targetName;
  final Vec3 oldPosition;
  final Vec3 newPosition;
  final Quat? oldRotation;
  final Quat? newRotation;
  final double? oldScale;
  final double? newScale;

  TransformMoveCommand({
    this.name = 'Move Transform',
    required this.targetName,
    required this.oldPosition,
    required this.newPosition,
    this.oldRotation,
    this.newRotation,
    this.oldScale,
    this.newScale,
  });

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    if (go != null) {
      go.transform.localPosition = newPosition;
      if (newRotation != null) go.transform.localRotation = newRotation!;
      if (newScale != null) go.transform.localScale = newScale!;
    }
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    if (go != null) {
      go.transform.localPosition = oldPosition;
      if (oldRotation != null) go.transform.localRotation = oldRotation!;
      if (oldScale != null) go.transform.localScale = oldScale!;
    }
  }
}

/// Fine-grained delta command for property mutation on an attached component.
class SetPropertyCommand<T> implements EditorCommand {
  @override
  final String name;
  final String targetName;
  final Type componentType;
  final String propertyKey;
  final T oldValue;
  final T newValue;
  final void Function(Component component, T value)? _applier;

  SetPropertyCommand({
    this.name = 'Set Property',
    required this.targetName,
    required this.componentType,
    required this.propertyKey,
    required this.oldValue,
    required this.newValue,
    void Function(Component component, T value)? applier,
  }) : _applier = applier;

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    if (go == null) return;
    for (final comp in go.components) {
      if (comp.runtimeType == componentType) {
        _applier?.call(comp, newValue);
        break;
      }
    }
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    if (go == null) return;
    for (final comp in go.components) {
      if (comp.runtimeType == componentType) {
        _applier?.call(comp, oldValue);
        break;
      }
    }
  }
}

/// Fine-grained delta command for spawning a GameObject into the scene.
class AddGameObjectCommand implements EditorCommand {
  @override
  final String name;
  final String objectName;
  final Vec3 position;
  final Quat? rotation;
  final double scale;
  final String? parentName;

  AddGameObjectCommand({
    this.name = 'Add GameObject',
    required this.objectName,
    this.position = Vec3.zero,
    this.rotation,
    this.scale = 1.0,
    this.parentName,
  });

  @override
  void execute(EditorSession session) {
    if (session.engine.scene.find(objectName) != null) return;
    final parent = parentName != null
        ? session.engine.scene.find(parentName!)
        : null;
    final go = session.engine.scene.createGameObject(
      objectName,
      parent: parent,
      position: position,
      rotation: rotation,
      scale: scale,
    );
    session.selected = go;
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(objectName);
    if (go != null) {
      go.destroy();
      session.engine.scene._flushDestroyed();
      if (session.selected == go) {
        session.selected = null;
      }
    }
  }
}

/// Fine-grained delta command for removing a GameObject and storing its subtree for undo.
class RemoveGameObjectCommand implements EditorCommand {
  @override
  final String name;
  final String objectName;
  String? _serializedJson;
  String? _parentName;

  RemoveGameObjectCommand({
    this.name = 'Remove GameObject',
    required this.objectName,
  });

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(objectName);
    if (go != null) {
      _parentName = go.parent?.name;
      _serializedJson = jsonEncode(
        SceneSerializer._objectToJson(go, session.engine.registry),
      );
      go.destroy();
      session.engine.scene._flushDestroyed();
      if (session.selected == go) {
        session.selected = null;
      }
    }
  }

  @override
  void undo(EditorSession session) {
    if (_serializedJson == null) return;
    final data = jsonDecode(_serializedJson!) as Map<String, Object?>;
    final parent = _parentName != null
        ? session.engine.scene.find(_parentName!)
        : null;
    final restored = SceneSerializer._buildObjectFromJson(
      session.engine.scene,
      parent,
      data,
      session.engine.registry,
      session.prefabs,
    );
    session.selected = restored;
  }
}

/// Fine-grained delta command for changing GameObject parent hierarchy.
class ReparentCommand implements EditorCommand {
  @override
  final String name;
  final String targetName;
  final String? oldParentName;
  final String? newParentName;

  ReparentCommand({
    this.name = 'Reparent GameObject',
    required this.targetName,
    this.oldParentName,
    this.newParentName,
  });

  @override
  void execute(EditorSession session) {
    final target = session.engine.scene.find(targetName);
    if (target == null) return;
    final newParent = newParentName != null
        ? session.engine.scene.find(newParentName!)
        : null;
    target.setParent(newParent);
  }

  @override
  void undo(EditorSession session) {
    final target = session.engine.scene.find(targetName);
    if (target == null) return;
    final oldParent = oldParentName != null
        ? session.engine.scene.find(oldParentName!)
        : null;
    target.setParent(oldParent);
  }
}

/// Composable compound batch command executing and undoing an ordered list of commands.
class CompoundCommand implements EditorCommand {
  @override
  final String name;
  final List<EditorCommand> commands;

  CompoundCommand({
    this.name = 'Compound Command',
    required List<EditorCommand> commands,
  }) : commands = List.unmodifiable(commands);

  @override
  void execute(EditorSession session) {
    for (final cmd in commands) {
      cmd.execute(session);
    }
  }

  @override
  void undo(EditorSession session) {
    for (var i = commands.length - 1; i >= 0; i--) {
      commands[i].undo(session);
    }
  }
}
