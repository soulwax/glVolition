part of '../engine.dart';

/// Optional mixin for components managed by an [ObjectPool].
mixin Poolable on Component {
  void onSpawned() {}
  void onDespawned() {}
}

/// Reusable template for spawning [GameObject] hierarchies (`Scene.instantiate`).
final class Prefab {
  final String name;
  final void Function(GameObject root) _build;

  const Prefab(this.name, this._build);
  const Prefab.builder(this.name, this._build);

  /// Creates a prefab from a serialized GameObject JSON map and a
  /// [ComponentRegistry].
  factory Prefab.fromJson(
    Map<String, Object?> json, {
    ComponentRegistry? registry,
  }) {
    final name = (json['name'] as String?) ?? 'Prefab';
    final reg = registry ?? ComponentRegistry.defaults();
    return Prefab.builder(name, (root) {
      SceneSerializer._populateGameObjectFromJson(root, json, reg, const {});
    });
  }

  /// Instantiates this prefab in [scene].
  GameObject instantiate(
    Scene scene, {
    GameObject? parent,
    Vec3? position,
    Quat? rotation,
    double? scale,
    String? name,
    bool active = true,
  }) {
    // Build while inactive if requested, otherwise build and refresh.
    final root = scene.createGameObject(
      name ?? this.name,
      parent: parent,
      position: position,
      rotation: rotation,
      scale: scale ?? 1.0,
      active: false,
    );
    _build(root);
    if (position != null) root.transform.localPosition = position;
    if (rotation != null) root.transform.localRotation = rotation;
    if (scale != null) root.transform.localScale = scale;
    if (active) root.setActive(true);
    return root;
  }
}

/// Pre-allocates and recycles [GameObject]s carrying a principal component [T]
/// so high-frequency spawns (bullets, meteors, pickups, VFX) do not allocate
/// or churn the scene graph at runtime.
final class ObjectPool<T extends Component> {
  final Scene scene;
  final Prefab prefab;
  final GameObject? parent;

  final List<T> _available = [];
  final Set<T> _active = {};

  ObjectPool({
    required this.scene,
    required this.prefab,
    this.parent,
    int initialCapacity = 0,
  }) {
    if (initialCapacity > 0) warmUp(initialCapacity);
  }

  int get activeCount => _active.length;
  int get availableCount => _available.length;
  int get totalCount => _active.length + _available.length;
  Iterable<T> get activeItems => List.unmodifiable(_active);

  void warmUp(int count) {
    for (var i = 0; i < count; i++) {
      final item = _createInactive();
      _available.add(item);
    }
  }

  T _createInactive() {
    final go = prefab.instantiate(scene, parent: parent, active: false);
    final comp = go.getComponent<T>();
    if (comp == null) {
      throw StateError('Prefab "${prefab.name}" did not attach a $T component');
    }
    return comp;
  }

  /// Acquires an instance from the pool (or instantiates a new one if empty),
  /// activates its [GameObject], and invokes [Poolable.onSpawned].
  T acquire({Vec3? position, Quat? rotation, double? scale}) {
    final item = _available.isNotEmpty ? _available.removeLast() : _createInactive();
    final go = item.gameObject;
    if (position != null) go.transform.localPosition = position;
    if (rotation != null) go.transform.localRotation = rotation;
    if (scale != null) go.transform.localScale = scale;
    _active.add(item);
    go.setActive(true);
    for (final c in go.components) {
      if (c is Poolable) c.onSpawned();
    }
    return item;
  }

  /// Deactivates [item]'s [GameObject], invokes [Poolable.onDespawned], and
  /// returns it to the available list.
  void release(T item) {
    if (!_active.remove(item)) return;
    final go = item.gameObject;
    for (final c in go.components) {
      if (c is Poolable) c.onDespawned();
    }
    go.setActive(false);
    _available.add(item);
  }

  void releaseAll() {
    for (final item in List.of(_active)) {
      release(item);
    }
  }
}
