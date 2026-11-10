part of '../engine.dart';

/// Multi-scene registry and transition manager owned by [Engine.scenes]
/// (E11-4).
///
/// Supports named scene factories (`register`, `load`, `reloadCurrent`) and
/// Unity-style [dontDestroyOnLoad] root [GameObject]s that automatically
/// migrate into newly loaded scenes.
final class SceneManager {
  final Engine _engine;
  final Map<String, Scene Function()> _builders = {};
  final Set<GameObject> _persistentObjects = {};
  String? _activeSceneName;

  SceneManager._(this._engine);

  String? get activeSceneName => _activeSceneName;
  Iterable<String> get registeredSceneNames => _builders.keys;

  /// Registers a named scene factory [builder] under [name].
  void register(String name, Scene Function() builder) {
    _builders[name] = builder;
  }

  /// Marks a root [GameObject] so it survives [Engine.loadScene] and
  /// [SceneManager.load] transitions.
  void dontDestroyOnLoad(GameObject object) {
    if (object.parent != null) {
      object.setParent(null);
    }
    _persistentObjects.add(object);
  }

  bool isPersistent(GameObject object) => _persistentObjects.contains(object);

  /// Builds and loads the scene registered under [name].
  Scene load(String name) {
    final builder = _builders[name] ??
        (throw ArgumentError.value(name, 'name', 'No scene registered with name "$name"'));
    _activeSceneName = name;
    final next = builder();
    _engine.loadScene(next);
    return next;
  }

  /// Rebuilds and reloads the currently active named scene.
  Scene reloadCurrent() {
    final name = _activeSceneName ??
        (throw StateError('No named scene is currently active in SceneManager'));
    return load(name);
  }

  List<GameObject> _extractPersistentFrom(Scene outgoing) {
    final migrated = <GameObject>[];
    for (final go in List.of(_persistentObjects)) {
      if (go._destroyed || go._destroyRequested) {
        _persistentObjects.remove(go);
        continue;
      }
      if (identical(go.scene, outgoing)) {
        go._detachFromSceneForMigration(outgoing);
        outgoing._roots.remove(go);
        go.node.removeFromParent();
        migrated.add(go);
      }
    }
    return migrated;
  }

  void _attachPersistentTo(Scene incoming, List<GameObject> migrated) {
    for (final go in migrated) {
      go._attachToSceneAfterMigration(incoming);
      incoming._roots.add(go);
      incoming.root.addChild(go.node);
      go._refreshTree();
    }
  }
}
