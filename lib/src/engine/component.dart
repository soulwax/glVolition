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

  /// Called when a solid (`isTrigger == false`) collider on this object first
  /// collides with another solid collider (E9-3).
  void onCollisionEnter(Collision collision) {}

  /// Called when a 2D solid collider on this object first collides with another 2D collider (E32).
  void onCollisionEnter2D(Collision2D collision) {}

  /// Called each fixed frame a 2D solid collision persists (E32).
  void onCollisionStay2D(Collision2D collision) {}

  /// Called when a 2D solid collision ceases (E32).
  void onCollisionExit2D(Collision2D collision) {}

  /// Called when a 2D trigger collider is entered (E32).
  void onTriggerEnter2D(Collider2D other) {}

  /// Called each fixed frame a 2D trigger overlap persists (E32).
  void onTriggerStay2D(Collider2D other) {}

  /// Called when a 2D trigger collider is exited (E32).
  void onTriggerExit2D(Collider2D other) {}

  /// Called when the pointer enters a collider attached to this GameObject (E16-1).
  void onPointerEnter(PointerRaycastHit hit) {}

  /// Called when the pointer exits a collider attached to this GameObject (E16-1).
  void onPointerExit(PointerRaycastHit hit) {}

  /// Called when the pointer is pressed down over a collider attached to this GameObject (E16-1).
  void onPointerDown(PointerRaycastHit hit) {}

  /// Called when the pointer is released over a collider attached to this GameObject (E16-1).
  void onPointerUp(PointerRaycastHit hit) {}

  /// Called when the pointer is pressed and released over the same collider (E16-1).
  void onPointerClick(PointerRaycastHit hit) {}

  /// Runs [action] after [delaySeconds] of game time, then every
  /// [repeatEvery] seconds if given. Cancelled automatically when this
  /// behaviour is destroyed.
  Invocation invoke(double delaySeconds, void Function() action, {double? repeatEvery}) =>
      engine.invoke(delaySeconds, action, repeatEvery: repeatEvery, owner: this);

  /// Starts a generator [Coroutine] (`Iterable<YieldInstruction?> Function()`)
  /// that steps each frame after `update()` and cancels automatically if this
  /// behaviour is destroyed (E8-1).
  Coroutine startCoroutine(Iterable<YieldInstruction?> Function() routine) {
    final co = Coroutine._(this, routine());
    scene._coroutines.add(co);
    // Execute up to the first yield immediately.
    if (!co._step(0, 0)) {
      scene._coroutines.remove(co);
    }
    return co;
  }

  /// Cancels all active [Coroutine]s owned by this behaviour.
  void stopAllCoroutines() {
    for (final co in scene._coroutines) {
      if (identical(co.owner, this)) {
        co.cancel();
      }
    }
  }

  /// Subscribes [handler] to scene events of type [E], automatically scoped to
  /// this behaviour's active/destroyed lifecycle (E8-1).
  EventSubscription listen<E>(void Function(E event) handler) =>
      scene.events.on<E>(handler, owner: this);
}
