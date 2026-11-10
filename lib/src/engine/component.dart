part of '../engine.dart';

/// Anything attached to a [GameObject]. Lifecycle, in order:
///
/// `awake` (once, when the object is first active) → `onEnable` →
/// `start` (Behaviours, once, before their first update) →
/// `fixedUpdate`/`update`/`lateUpdate` → `onDisable` → `onDestroy`.
abstract class Component {
  static int _nextId = 1;

  /// Unique for the life of the process.
  final int instanceId = _nextId++;

  GameObject? _gameObject;
  bool _awoken = false;
  bool _active = false;
  bool _destroyed = false;
  bool _destroyRequested = false;

  GameObject get gameObject =>
      _gameObject ?? (throw StateError('$runtimeType is not attached to a GameObject'));
  bool get isAttached => _gameObject != null;

  TransformComponent get transform => gameObject.transform;
  Scene get scene => gameObject.scene;
  Engine get engine => scene.engine;
  Time get time => engine.time;
  InputActions get input => engine.input;

  /// True between `onEnable` and `onDisable`.
  bool get isActiveAndEnabled => _active;
  bool get isDestroyed => _destroyed;

  bool get _enabledSelf => true;

  void awake() {}
  void onEnable() {}
  void onDisable() {}
  void onDestroy() {}

  // Engine-internal hooks for built-in components. They run before the
  // matching public callback (after it for disable/destroy), so user
  // overrides never need to call super.
  void _onAttach() {}
  void _onEnableInternal() {}
  void _onDisableInternal() {}
  void _onDestroyInternal() {}

  T? getComponent<T>() => gameObject.getComponent<T>();
  T requireComponent<T>() => gameObject.requireComponent<T>();
  T addComponent<T extends Component>(T component) => gameObject.addComponent(component);

  /// Destroys this component at the end of the frame.
  void destroy() => scene._requestDestroyComponent(this);

  @override
  String toString() => '$runtimeType#$instanceId(${_gameObject?.name ?? 'detached'})';
}

/// A component that can be switched on and off and receives per-frame
/// callbacks: the engine's `MonoBehaviour`.
abstract class Behaviour extends Component {
  bool _enabled = true;
  bool _started = false;
  bool _startQueued = false;

  /// Lower runs first within each phase (Unity's script execution order).
  /// Read once, when the behaviour is attached.
  int get executionOrder => 0;

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_gameObject != null) scene._refresh(this);
  }

  @override
  bool get _enabledSelf => _enabled;

  void start() {}
  void fixedUpdate() {}
  void update() {}
  void lateUpdate() {}

  /// A collider on this object started overlapping [other].
  void onTriggerEnter(Collider other) {}

  /// Called every fixed step while the overlap continues.
  void onTriggerStay(Collider other) {}

  void onTriggerExit(Collider other) {}

  /// Runs [action] after [delaySeconds] of game time, then every
  /// [repeatEvery] seconds if given. Cancelled automatically when this
  /// behaviour is destroyed.
  Invocation invoke(double delaySeconds, void Function() action, {double? repeatEvery}) =>
      engine.invoke(delaySeconds, action, repeatEvery: repeatEvery, owner: this);
}
