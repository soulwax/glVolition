part of '../engine.dart';

/// Active scene transition state during fade transitions (E24-3).
final class SceneTransition {
  final String targetSceneName;
  final double duration;
  final int fadeColor;
  double elapsed = 0.0;
  bool _swapped = false;

  SceneTransition({
    required this.targetSceneName,
    this.duration = 0.6,
    this.fadeColor = 0xFF000000,
  });

  bool get isComplete => elapsed >= duration;
  double get progress => duration <= 0.0 ? 1.0 : (elapsed / duration).clamp(0.0, 1.0);

  /// Normalized opacity curve: `0.0 -> 1.0` during fade-out (first half),
  /// and `1.0 -> 0.0` during fade-in (second half).
  double get alpha {
    final p = progress;
    if (p <= 0.5) {
      return (p * 2.0).clamp(0.0, 1.0);
    } else {
      return ((1.0 - p) * 2.0).clamp(0.0, 1.0);
    }
  }
}

/// Multi-scene registry and transition manager owned by [Engine.scenes]
/// (E11-4, E24-3).
///
/// Supports named scene factories (`register`, `load`, `fadeTo`, `reloadCurrent`) and
/// Unity-style [dontDestroyOnLoad] root [GameObject]s that automatically
/// migrate into newly loaded scenes.
final class SceneManager {
  final Engine _engine;
  final Map<String, Scene Function()> _builders = {};
  final Set<GameObject> _persistentObjects = {};
  String? _activeSceneName;
  SceneTransition? _activeTransition;

  SceneManager._(this._engine);

  String? get activeSceneName => _activeSceneName;
  Iterable<String> get registeredSceneNames => _builders.keys;
  SceneTransition? get activeTransition => _activeTransition;
  bool get isTransitioning => _activeTransition != null && !_activeTransition!.isComplete;
  double get transitionAlpha => _activeTransition?.alpha ?? 0.0;

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

  /// Initiates a smooth fade transition to [targetSceneName] over [duration] seconds (E24-3).
  void fadeTo(
    String targetSceneName, {
    double duration = 0.6,
    int fadeColor = 0xFF000000,
  }) {
    if (!_builders.containsKey(targetSceneName)) {
      throw ArgumentError.value(
        targetSceneName,
        'targetSceneName',
        'No scene registered with name "$targetSceneName"',
      );
    }
    _activeTransition = SceneTransition(
      targetSceneName: targetSceneName,
      duration: duration,
      fadeColor: fadeColor,
    );
  }

  void _stepTransition(double dt) {
    final t = _activeTransition;
    if (t == null) return;
    t.elapsed += dt;

    if (!t._swapped && t.progress >= 0.5) {
      t._swapped = true;
      load(t.targetSceneName);
    }

    if (t.isComplete) {
      _activeTransition = null;
    }
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
