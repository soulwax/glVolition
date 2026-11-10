part of '../engine.dart';

/// Handle returned by [Engine.invoke] and [Behaviour.invoke].
final class Invocation {
  final Object? _owner;
  final void Function() _action;
  final double? _repeatEvery;
  double _dueAt;
  bool _cancelled = false;

  Invocation._(this._dueAt, this._action, this._repeatEvery, this._owner);

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// The runtime: owns [Time], [InputActions], the active [Scene], and the
/// frame schedule.
///
/// Each [step] runs:
/// 1. `Time` advance
/// 2. Due [invoke] callbacks
/// 3. Zero or more fixed steps (`fixedUpdate` → trigger physics)
/// 4. Variable step (`start` → `update` → `lateUpdate`)
/// 5. Deferred `destroy()` calls
/// 6. Scene → renderer sync (transforms, camera, lights, particles, post)
final class Engine {
  final EngineHost host;
  final Time time = Time();
  late final InputActions input = InputActions(host.input);
  late final AssetCatalog catalog = AssetCatalog._(this);
  late final EditorSession editor = EditorSession(this);
  final ComponentRegistry registry;

  Scene _scene;
  Scene? _pendingScene;
  final List<Invocation> _invocations = [];

  Engine(
    this.host, {
    Scene? initialScene,
    ComponentRegistry? registry,
  })  : _scene = initialScene ?? Scene(),
        registry = registry ?? ComponentRegistry.defaults() {
    _scene._attach(this);
  }

  Scene get scene => _scene;
  Graphics get graphics => host.graphics;
  AssetLoader get assets => host.assets;
  AudioDevice get audio => host.audio;
  KeyValueStore get storage => host.storage;
  RenderSettings get renderSettings => _scene.renderSettings;
  PhysicsWorld get physics => _scene.physics;

  /// Replaces the active scene. When called mid-frame the swap happens before
  /// the next frame starts; otherwise it happens immediately.
  bool _stepping = false;

  void loadScene(Scene next) {
    if (_stepping) {
      _pendingScene = next;
    } else {
      _swapScene(next);
    }
  }

  void _swapScene(Scene next) {
    if (identical(next, _scene)) return;
    _scene._detach();
    _invocations.clear();
    _scene = next;
    _scene._attach(this);
  }

  /// Schedules [action] to run after [delaySeconds] of scaled game time.
  Invocation invoke(
    double delaySeconds,
    void Function() action, {
    double? repeatEvery,
    Object? owner,
  }) {
    final inv = Invocation._(time._time + math.max(0, delaySeconds), action, repeatEvery, owner);
    _invocations.add(inv);
    return inv;
  }

  void _cancelOwnedBy(Object owner) {
    for (final inv in _invocations) {
      if (identical(inv._owner, owner)) inv._cancelled = true;
    }
  }

  void _runInvocations() {
    for (final inv in List.of(_invocations)) {
      if (inv._cancelled) {
        _invocations.remove(inv);
        continue;
      }
      if (time._time >= inv._dueAt) {
        _scene._guard(inv._action);
        final repeat = inv._repeatEvery;
        if (inv._cancelled || repeat == null || repeat <= 0) {
          _invocations.remove(inv);
        } else {
          inv._dueAt += repeat;
        }
      }
    }
  }

  /// Advances the engine by one frame of [rawDeltaSeconds] wall time.
  void step(double rawDeltaSeconds) {
    final pending = _pendingScene;
    if (pending != null) {
      _pendingScene = null;
      _swapScene(pending);
    }

    _stepping = true;
    try {
      time._beginFrame(rawDeltaSeconds);
      _runInvocations();

      time._inFixedStep = true;
      var steps = 0;
      while (time._accumulator >= time._fixedDeltaTime && steps < time.maxFixedStepsPerFrame) {
        time._accumulator -= time._fixedDeltaTime;
        time._fixedTime += time._fixedDeltaTime;
        _scene._fixedStep();
        steps++;
      }
      if (time._accumulator >= time._fixedDeltaTime) {
        time._accumulator = 0;
      }
      time._fixedStepsLastFrame = steps;
      time._inFixedStep = false;

      _scene._updateStep();
      _scene._flushDestroyed();
      _scene._syncToRenderer(host.graphics);
    } finally {
      time._inFixedStep = false;
      _stepping = false;
    }
  }

  /// Submits 2D tilemaps, world sprites, atmospheric particle fields, and
  /// screen-space UI overlays to [encoder] during the active render pass.
  void encodeFrame(RenderEncoder encoder, [FrameInput? frame]) {
    _scene._encode(encoder, frame);
  }

  /// Captures a JSON-compatible snapshot of the current session (timeScale,
  /// scene hierarchy/components, and [MemoryStore] entries if applicable) for
  /// hot-restart state preservation.
  Map<String, Object?> captureSessionSnapshot() {
    final store = host.storage;
    return <String, Object?>{
      'timeScale': time.timeScale,
      'fixedDeltaTime': time.fixedDeltaTime,
      if (store is MemoryStore) 'storage': Map<String, String>.of(store.values),
      'scene': SceneSerializer.toJson(_scene, registry: registry),
    };
  }

  /// Restores a snapshot previously captured by [captureSessionSnapshot].
  void restoreSessionSnapshot(Map<String, Object?> snapshot) {
    final ts = snapshot['timeScale'];
    if (ts is num) time.timeScale = ts.toDouble();
    final fdt = snapshot['fixedDeltaTime'];
    if (fdt is num) time.fixedDeltaTime = fdt.toDouble();
    final store = host.storage;
    final savedStore = snapshot['storage'];
    if (store is MemoryStore && savedStore is Map) {
      for (final e in savedStore.entries) {
        store.write(e.key.toString(), e.value.toString());
      }
    }
    final sceneJson = snapshot['scene'];
    if (sceneJson is Map<String, Object?>) {
      final restored = SceneSerializer.fromJson(sceneJson, registry: registry);
      loadScene(restored);
    }
  }

  void dispose() {
    _scene._detach();
    _invocations.clear();
  }
}
