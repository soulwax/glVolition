part of '../engine.dart';

/// A named node in a [Scene] that owns a [TransformComponent] and any number
/// of other components. Create one with [Scene.createGameObject].
final class GameObject {
  final Scene scene;
  String name;
  String tag;

  /// 0..31, used by physics layer filtering and queries.
  int layer;

  /// The pixeldart scene node this object drives. Renderers hang their
  /// drawable nodes beneath it.
  final SceneNode node;

  late final TransformComponent transform;

  final List<Component> _components = [];
  GameObject? _parent;
  final List<GameObject> _children = [];
  bool _activeSelf = true;
  bool _destroyRequested = false;
  bool _destroyed = false;

  GameObject._(this.scene, this.name, {this.tag = 'Untagged', this.layer = 0})
      : node = SceneNode.group(name: name) {
    if (layer < 0 || layer > 31) throw RangeError.range(layer, 0, 31, 'layer');
    transform = TransformComponent._();
    transform._gameObject = this;
    _components.add(transform);
  }

  GameObject? get parent => _parent;
  List<GameObject> get children => List.unmodifiable(_children);
  List<Component> get components => List.unmodifiable(_components);

  bool get activeSelf => _activeSelf;
  bool get activeInHierarchy => !_destroyed && _activeSelf && (_parent?.activeInHierarchy ?? true);
  bool get isDestroyed => _destroyed;

  void setActive(bool value) {
    if (_activeSelf == value) return;
    _activeSelf = value;
    node.visible = value;
    _refreshTree();
  }

  void _refreshTree() {
    for (final c in List.of(_components)) {
      scene._refresh(c);
    }
    for (final child in List.of(_children)) {
      child._refreshTree();
    }
  }

  /// Re-parents this object. With [worldPositionStays] the object keeps its
  /// world position and rotation; otherwise it keeps its local values.
  void setParent(GameObject? newParent, {bool worldPositionStays = true}) {
    if (newParent == _parent) return;
    if (newParent != null) {
      if (newParent.scene != scene) throw ArgumentError('Cannot parent across scenes');
      for (GameObject? p = newParent; p != null; p = p._parent) {
        if (p == this) throw ArgumentError('Cannot parent $name under its own descendant');
      }
    }
    final worldPos = transform.position;
    final worldRot = transform.rotation;

    (_parent?._children ?? scene._roots).remove(this);
    _parent = newParent;
    (newParent?._children ?? scene._roots).add(this);
    (newParent?.node ?? scene.root).addChild(node);

    if (worldPositionStays) {
      transform
        ..position = worldPos
        ..rotation = worldRot;
    }
    _refreshTree();
  }

  /// Attaches [component] and runs its lifecycle up to where this object is.
  T addComponent<T extends Component>(T component) {
    if (_destroyed || _destroyRequested) throw StateError('GameObject $name is destroyed');
    if (component._gameObject != null) {
      throw StateError('$component is already attached to ${component._gameObject!.name}');
    }
    component._gameObject = this;
    _components.add(component);
    if (component is Behaviour) scene._registerBehaviour(component);
    component._onAttach();
    scene._refresh(component);
    return component;
  }

  T? getComponent<T>() {
    for (final c in _components) {
      if (c is T && !c._destroyRequested) return c as T;
    }
    return null;
  }

  T requireComponent<T>() =>
      getComponent<T>() ?? (throw StateError('GameObject $name has no $T'));

  Iterable<T> getComponents<T>() => _components.where((c) => !c._destroyRequested).whereType<T>();

  T? getComponentInChildren<T>({bool includeInactive = false}) {
    if (includeInactive || activeInHierarchy) {
      final own = getComponent<T>();
      if (own != null) return own;
    }
    for (final child in _children) {
      final found = child.getComponentInChildren<T>(includeInactive: includeInactive);
      if (found != null) return found;
    }
    return null;
  }

  T? getComponentInParent<T>() {
    for (GameObject? g = this; g != null; g = g._parent) {
      final found = g.getComponent<T>();
      if (found != null) return found;
    }
    return null;
  }

  /// The first direct child called [childName], or a nested path such as
  /// `'Pivot/Flame'`.
  GameObject? find(String childName) {
    GameObject? current = this;
    for (final part in childName.split('/')) {
      current = current?._children.where((c) => c.name == part && !c._destroyRequested).firstOrNull;
      if (current == null) return null;
    }
    return current;
  }

  /// Destroys this object, its children and their components at the end of
  /// the frame.
  void destroy() => scene.destroy(this);

  @override
  String toString() => 'GameObject($name)';
}
