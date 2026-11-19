part of '../../engine.dart';

/// Per-frame snapshot of platform [Input] state for deterministic recording
/// and replay (`InputTape`, P9-W17-B).
final class InputFrameSample {
  final int frameIndex;
  final double dt;
  final List<String> keysDown;
  final List<String> keysPressed;
  final List<String> keysReleased;
  final double pointerX;
  final double pointerY;
  final bool pointerDown;
  final bool pointerPressed;
  final bool pointerReleased;
  final double wheelDeltaX;
  final double wheelDeltaY;
  final double pointerDeltaX;
  final double pointerDeltaY;
  final bool pointerLocked;
  final List<TouchPoint> touches;
  final Map<int, Map<int, double>> gamepadAxes;
  final Map<int, List<int>> gamepadButtons;
  final String textInputBuffer;

  InputFrameSample({
    required this.frameIndex,
    required this.dt,
    List<String> keysDown = const [],
    List<String> keysPressed = const [],
    List<String> keysReleased = const [],
    this.pointerX = 0.0,
    this.pointerY = 0.0,
    this.pointerDown = false,
    this.pointerPressed = false,
    this.pointerReleased = false,
    this.wheelDeltaX = 0.0,
    this.wheelDeltaY = 0.0,
    this.pointerDeltaX = 0.0,
    this.pointerDeltaY = 0.0,
    this.pointerLocked = false,
    List<TouchPoint> touches = const [],
    Map<int, Map<int, double>> gamepadAxes = const {},
    Map<int, List<int>> gamepadButtons = const {},
    this.textInputBuffer = '',
  }) : keysDown = List.unmodifiable(keysDown),
       keysPressed = List.unmodifiable(keysPressed),
       keysReleased = List.unmodifiable(keysReleased),
       touches = List.unmodifiable(touches),
       gamepadAxes = Map.unmodifiable({
         for (final e in gamepadAxes.entries)
           e.key: Map<int, double>.unmodifiable(e.value),
       }),
       gamepadButtons = Map.unmodifiable({
         for (final e in gamepadButtons.entries)
           e.key: List<int>.unmodifiable(e.value),
       });

  static final empty = InputFrameSample(frameIndex: 0, dt: 0.0);

  Map<String, Object?> toJson() => {
    'frameIndex': frameIndex,
    'dt': dt,
    'keysDown': keysDown,
    'keysPressed': keysPressed,
    'keysReleased': keysReleased,
    'pointerX': pointerX,
    'pointerY': pointerY,
    'pointerDown': pointerDown,
    'pointerPressed': pointerPressed,
    'pointerReleased': pointerReleased,
    'wheelDeltaX': wheelDeltaX,
    'wheelDeltaY': wheelDeltaY,
    'pointerDeltaX': pointerDeltaX,
    'pointerDeltaY': pointerDeltaY,
    'pointerLocked': pointerLocked,
    'touches': [
      for (final t in touches)
        {'id': t.id, 'x': t.x, 'y': t.y, 'pressure': t.pressure},
    ],
    'gamepadAxes': {
      for (final e in gamepadAxes.entries)
        '${e.key}': {for (final ax in e.value.entries) '${ax.key}': ax.value},
    },
    'gamepadButtons': {
      for (final e in gamepadButtons.entries) '${e.key}': e.value,
    },
    'textInputBuffer': textInputBuffer,
  };

  factory InputFrameSample.fromJson(Map<String, Object?> json) {
    final rawTouches = (json['touches'] as List<Object?>?) ?? const [];
    final parsedTouches = <TouchPoint>[
      for (final raw in rawTouches)
        if (raw is Map)
          TouchPoint(
            id: (raw['id'] as num?)?.toInt() ?? 0,
            x: (raw['x'] as num?)?.toDouble() ?? 0.0,
            y: (raw['y'] as num?)?.toDouble() ?? 0.0,
            pressure: (raw['pressure'] as num?)?.toDouble() ?? 1.0,
          ),
    ];

    final parsedAxes = <int, Map<int, double>>{};
    final rawAxes = json['gamepadAxes'];
    if (rawAxes is Map) {
      for (final gpEntry in rawAxes.entries) {
        final gpIdx = int.tryParse(gpEntry.key.toString());
        if (gpIdx == null || gpEntry.value is! Map) continue;
        final axMap = <int, double>{};
        for (final axEntry in (gpEntry.value as Map).entries) {
          final axIdx = int.tryParse(axEntry.key.toString());
          if (axIdx != null && axEntry.value is num) {
            axMap[axIdx] = (axEntry.value as num).toDouble();
          }
        }
        parsedAxes[gpIdx] = axMap;
      }
    }

    final parsedButtons = <int, List<int>>{};
    final rawButtons = json['gamepadButtons'];
    if (rawButtons is Map) {
      for (final gpEntry in rawButtons.entries) {
        final gpIdx = int.tryParse(gpEntry.key.toString());
        if (gpIdx == null || gpEntry.value is! List) continue;
        parsedButtons[gpIdx] = [
          for (final b in (gpEntry.value as List))
            if (b is num) b.toInt(),
        ];
      }
    }

    List<String> stringList(Object? raw) {
      if (raw is! List) return const [];
      return [for (final s in raw) s.toString()];
    }

    return InputFrameSample(
      frameIndex: (json['frameIndex'] as num?)?.toInt() ?? 0,
      dt: (json['dt'] as num?)?.toDouble() ?? 0.0,
      keysDown: stringList(json['keysDown']),
      keysPressed: stringList(json['keysPressed']),
      keysReleased: stringList(json['keysReleased']),
      pointerX: (json['pointerX'] as num?)?.toDouble() ?? 0.0,
      pointerY: (json['pointerY'] as num?)?.toDouble() ?? 0.0,
      pointerDown: json['pointerDown'] == true,
      pointerPressed: json['pointerPressed'] == true,
      pointerReleased: json['pointerReleased'] == true,
      wheelDeltaX: (json['wheelDeltaX'] as num?)?.toDouble() ?? 0.0,
      wheelDeltaY: (json['wheelDeltaY'] as num?)?.toDouble() ?? 0.0,
      pointerDeltaX: (json['pointerDeltaX'] as num?)?.toDouble() ?? 0.0,
      pointerDeltaY: (json['pointerDeltaY'] as num?)?.toDouble() ?? 0.0,
      pointerLocked: json['pointerLocked'] == true,
      touches: parsedTouches,
      gamepadAxes: parsedAxes,
      gamepadButtons: parsedButtons,
      textInputBuffer: (json['textInputBuffer'] as String?) ?? '',
    );
  }
}

/// Recorded input timeline + optional scene baseline and frame checksums
/// supporting deterministic replay verification (P9-W17-B).
final class InputTape {
  static const int currentSchemaVersion = 1;

  final String name;
  final int schemaVersion;
  final Map<String, Object?>? initialSceneJson;
  final List<InputFrameSample> frames;
  final Map<int, int> checkpoints;

  InputTape({
    this.name = 'input_tape',
    this.schemaVersion = currentSchemaVersion,
    Map<String, Object?>? initialSceneJson,
    List<InputFrameSample> frames = const [],
    Map<int, int> checkpoints = const {},
  }) : initialSceneJson = initialSceneJson == null
           ? null
           : Map<String, Object?>.unmodifiable(initialSceneJson),
       frames = List<InputFrameSample>.unmodifiable(frames),
       checkpoints = Map<int, int>.unmodifiable(checkpoints);

  Map<String, Object?> toJson() => {
    'name': name,
    'schemaVersion': schemaVersion,
    if (initialSceneJson != null) 'initialSceneJson': initialSceneJson,
    'frames': [for (final f in frames) f.toJson()],
    'checkpoints': {for (final e in checkpoints.entries) '${e.key}': e.value},
  };

  String toJsonString() => jsonEncode(toJson());

  factory InputTape.fromJson(Map<String, Object?> json) {
    final rawFrames = (json['frames'] as List<Object?>?) ?? const [];
    final frames = <InputFrameSample>[
      for (final raw in rawFrames)
        if (raw is Map<String, Object?>)
          InputFrameSample.fromJson(raw)
        else if (raw is Map)
          InputFrameSample.fromJson(Map<String, Object?>.from(raw)),
    ];

    final checkpoints = <int, int>{};
    final rawCheckpoints = json['checkpoints'];
    if (rawCheckpoints is Map) {
      for (final e in rawCheckpoints.entries) {
        final frameIdx = int.tryParse(e.key.toString());
        if (frameIdx != null && e.value is num) {
          checkpoints[frameIdx] = (e.value as num).toInt();
        }
      }
    }

    final rawScene = json['initialSceneJson'];
    Map<String, Object?>? sceneJson;
    if (rawScene is Map<String, Object?>) {
      sceneJson = rawScene;
    } else if (rawScene is Map) {
      sceneJson = Map<String, Object?>.from(rawScene);
    }

    return InputTape(
      name: (json['name'] as String?) ?? 'input_tape',
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      initialSceneJson: sceneJson,
      frames: frames,
      checkpoints: checkpoints,
    );
  }

  factory InputTape.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      if (decoded is Map) {
        return InputTape.fromJson(Map<String, Object?>.from(decoded));
      }
      throw const FormatException(
        'Expected top-level JSON object for InputTape',
      );
    }
    return InputTape.fromJson(decoded);
  }
}

/// Computes a cross-platform 53-bit deterministic checksum over a [Scene]'s
/// hierarchy, quantized transforms, and rigidbody state (P9-W17-B).
abstract final class SceneStateHasher {
  static const int _mask53 = 0x1FFFFFFFFFFFFF;
  static const int _fnvPrime27 = 0x01000193;

  /// Computes a 53-bit masked hash identical on Dart VM and JS/Wasm.
  static int computeHash(Scene scene) {
    var lo = 0x011C9DC5; // 27-bit lane
    var hi = 0x024D5A37; // 26-bit lane

    void feedByte(int b) {
      final v = b & 0xFF;
      lo = ((lo ^ v) * _fnvPrime27) & 0x7FFFFFF;
      hi = ((hi ^ v ^ ((lo >> 19) & 0xFF)) * _fnvPrime27) & 0x3FFFFFF;
    }

    void feedInt(int v) {
      feedByte(v);
      feedByte(v >> 8);
      feedByte(v >> 16);
      feedByte(v >> 24);
    }

    void feedQuantized(double value) {
      final q = value.isFinite ? (value * 10000.0).round() : 0;
      feedInt(q);
    }

    void feedString(String s) {
      feedInt(s.length);
      for (var i = 0; i < s.length; i++) {
        feedInt(s.codeUnitAt(i));
      }
    }

    void feedVec3(Vec3 v) {
      feedQuantized(v.x);
      feedQuantized(v.y);
      feedQuantized(v.z);
    }

    void feedQuat(Quat q) {
      feedQuantized(q.x);
      feedQuantized(q.y);
      feedQuantized(q.z);
      feedQuantized(q.w);
    }

    void visit(GameObject go) {
      if (go._destroyRequested || go._destroyed) return;
      feedString(go.name);
      feedString(go.tag);
      feedInt(go.layer);
      feedByte(go.activeSelf ? 1 : 0);
      feedVec3(go.transform.localPosition);
      feedQuat(go.transform.localRotation);
      feedQuantized(go.transform.localScale);
      feedInt(go.components.length);

      final rb = go.getComponent<RigidBody>();
      if (rb != null) {
        feedByte(1);
        feedVec3(rb.velocity);
        feedVec3(rb.angularVelocity);
      } else {
        feedByte(0);
      }

      for (final child in go._children) {
        visit(child);
      }
    }

    for (final root in scene._roots) {
      visit(root);
    }

    return ((hi * 0x8000000) + lo) & _mask53;
  }
}

/// Transparent [Input] proxy that captures per-frame input snapshots into an
/// [InputTape] alongside optional [SceneStateHasher] checkpoints (P9-W17-B).
final class InputTapeRecorder implements Input {
  final Input delegate;
  final Set<String> _watchedKeys = {
    'KeyW',
    'KeyA',
    'KeyS',
    'KeyD',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
    'Space',
    'Enter',
    'Escape',
    'ShiftLeft',
    'ControlLeft',
  };
  final int maxGamepadButtonsToPoll;
  final int maxGamepadAxesToPoll;

  final List<InputFrameSample> _frames = [];
  final Map<int, int> _checkpoints = {};
  int _frameIndex = 0;

  InputTapeRecorder(
    this.delegate, {
    Iterable<String> extraWatchedKeys = const [],
    this.maxGamepadButtonsToPoll = 16,
    this.maxGamepadAxesToPoll = 8,
  }) {
    _watchedKeys.addAll(extraWatchedKeys);
  }

  /// Registers an additional key code to capture during [recordFrame].
  void watchKey(String code) => _watchedKeys.add(code);

  List<InputFrameSample> get recordedFrames => List.unmodifiable(_frames);
  Map<int, int> get recordedCheckpoints => Map.unmodifiable(_checkpoints);

  /// Captures the current [delegate] input state for frame `dt` and optionally
  /// records a deterministic [SceneStateHasher] checkpoint.
  void recordFrame(double dt, {Scene? checkpointScene}) {
    final sortedKeys = _watchedKeys.toList()..sort();
    final down = <String>[];
    final pressed = <String>[];
    final released = <String>[];
    for (final k in sortedKeys) {
      if (delegate.isDown(k)) down.add(k);
      if (delegate.wasPressed(k)) pressed.add(k);
      if (delegate.wasReleased(k)) released.add(k);
    }

    final axes = <int, Map<int, double>>{};
    final buttons = <int, List<int>>{};
    final gpCount = delegate.gamepadCount;
    for (var gp = 0; gp < gpCount; gp++) {
      final gpAxes = <int, double>{};
      for (var ax = 0; ax < maxGamepadAxesToPoll; ax++) {
        final v = delegate.gamepadAxis(gp, ax);
        if (v != 0.0) {
          gpAxes[ax] = v;
        }
      }
      if (gpAxes.isNotEmpty) {
        axes[gp] = gpAxes;
      }

      final gpButtons = <int>[];
      for (var btn = 0; btn < maxGamepadButtonsToPoll; btn++) {
        if (delegate.gamepadButtonDown(gp, btn)) {
          gpButtons.add(btn);
        }
      }
      if (gpButtons.isNotEmpty) {
        buttons[gp] = gpButtons;
      }
    }

    final idx = _frameIndex++;
    _frames.add(
      InputFrameSample(
        frameIndex: idx,
        dt: dt,
        keysDown: down,
        keysPressed: pressed,
        keysReleased: released,
        pointerX: delegate.pointerX,
        pointerY: delegate.pointerY,
        pointerDown: delegate.pointerDown,
        pointerPressed: delegate.pointerPressed,
        pointerReleased: delegate.pointerReleased,
        wheelDeltaX: delegate.wheelDeltaX,
        wheelDeltaY: delegate.wheelDeltaY,
        pointerDeltaX: delegate.pointerDeltaX,
        pointerDeltaY: delegate.pointerDeltaY,
        pointerLocked: delegate.pointerLocked,
        touches: List<TouchPoint>.of(delegate.touches),
        gamepadAxes: axes,
        gamepadButtons: buttons,
        textInputBuffer: delegate.textInputBuffer,
      ),
    );

    if (checkpointScene != null) {
      _checkpoints[idx] = SceneStateHasher.computeHash(checkpointScene);
    }
  }

  /// Packages all recorded frames and checkpoints into an immutable [InputTape].
  InputTape toTape({
    String name = 'input_tape',
    Map<String, Object?>? initialSceneJson,
  }) => InputTape(
    name: name,
    initialSceneJson: initialSceneJson,
    frames: _frames,
    checkpoints: _checkpoints,
  );

  void clear() {
    _frames.clear();
    _checkpoints.clear();
    _frameIndex = 0;
  }

  @override
  bool isDown(String code) {
    _watchedKeys.add(code);
    return delegate.isDown(code);
  }

  @override
  bool wasPressed(String code) {
    _watchedKeys.add(code);
    return delegate.wasPressed(code);
  }

  @override
  bool wasReleased(String code) {
    _watchedKeys.add(code);
    return delegate.wasReleased(code);
  }

  @override
  double get pointerX => delegate.pointerX;

  @override
  double get pointerY => delegate.pointerY;

  @override
  bool get pointerDown => delegate.pointerDown;

  @override
  bool get pointerPressed => delegate.pointerPressed;

  @override
  bool get pointerReleased => delegate.pointerReleased;

  @override
  double get wheelDeltaX => delegate.wheelDeltaX;

  @override
  double get wheelDeltaY => delegate.wheelDeltaY;

  @override
  double get pointerDeltaX => delegate.pointerDeltaX;

  @override
  double get pointerDeltaY => delegate.pointerDeltaY;

  @override
  bool get pointerLocked => delegate.pointerLocked;

  @override
  void requestPointerLock() => delegate.requestPointerLock();

  @override
  void exitPointerLock() => delegate.exitPointerLock();

  @override
  List<TouchPoint> get touches => delegate.touches;

  @override
  int get gamepadCount => delegate.gamepadCount;

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) =>
      delegate.gamepadAxis(gamepadIndex, axisIndex);

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) =>
      delegate.gamepadButtonDown(gamepadIndex, buttonIndex);

  @override
  String get textInputBuffer => delegate.textInputBuffer;
}

/// Deterministic [Input] driver fed frame-by-frame from an [InputTape]
/// during automated replay verification (P9-W17-B).
final class ReplayInputDriver implements Input {
  InputFrameSample _current = InputFrameSample.empty;
  Set<String> _down = const {};
  Set<String> _pressed = const {};
  Set<String> _released = const {};
  bool _pointerLockRequested = false;

  void applySample(InputFrameSample sample) {
    _current = sample;
    _down = sample.keysDown.toSet();
    _pressed = sample.keysPressed.toSet();
    _released = sample.keysReleased.toSet();
  }

  bool get pointerLockRequested => _pointerLockRequested;

  @override
  bool isDown(String code) => _down.contains(code);

  @override
  bool wasPressed(String code) => _pressed.contains(code);

  @override
  bool wasReleased(String code) => _released.contains(code);

  @override
  double get pointerX => _current.pointerX;

  @override
  double get pointerY => _current.pointerY;

  @override
  bool get pointerDown => _current.pointerDown;

  @override
  bool get pointerPressed => _current.pointerPressed;

  @override
  bool get pointerReleased => _current.pointerReleased;

  @override
  double get wheelDeltaX => _current.wheelDeltaX;

  @override
  double get wheelDeltaY => _current.wheelDeltaY;

  @override
  double get pointerDeltaX => _current.pointerDeltaX;

  @override
  double get pointerDeltaY => _current.pointerDeltaY;

  @override
  bool get pointerLocked => _current.pointerLocked || _pointerLockRequested;

  @override
  void requestPointerLock() {
    _pointerLockRequested = true;
  }

  @override
  void exitPointerLock() {
    _pointerLockRequested = false;
  }

  @override
  List<TouchPoint> get touches => _current.touches;

  @override
  int get gamepadCount {
    var maxIdx = -1;
    for (final k in _current.gamepadAxes.keys) {
      if (k > maxIdx) maxIdx = k;
    }
    for (final k in _current.gamepadButtons.keys) {
      if (k > maxIdx) maxIdx = k;
    }
    return maxIdx + 1;
  }

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) =>
      _current.gamepadAxes[gamepadIndex]?[axisIndex] ?? 0.0;

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) =>
      _current.gamepadButtons[gamepadIndex]?.contains(buttonIndex) ?? false;

  @override
  String get textInputBuffer => _current.textInputBuffer;
}

/// Summary report returned by [EngineReplayHarness.run] (P9-W17-B).
final class ReplayVerificationResult {
  final bool passed;
  final int framesExecuted;
  final int finalSceneHash;
  final List<String> mismatches;

  const ReplayVerificationResult({
    required this.passed,
    required this.framesExecuted,
    required this.finalSceneHash,
    this.mismatches = const [],
  });
}

/// Executes an [InputTape] against a target [Engine] and asserts scene
/// checksums at recorded checkpoints (P9-W17-B).
abstract final class EngineReplayHarness {
  static ReplayVerificationResult run(
    Engine engine,
    InputTape tape, {
    required ReplayInputDriver driver,
  }) {
    if (tape.initialSceneJson != null) {
      final restored = SceneSerializer.fromJson(
        tape.initialSceneJson!,
        registry: engine.registry,
      );
      engine.loadScene(restored);
    }

    final mismatches = <String>[];
    var executed = 0;

    for (final sample in tape.frames) {
      driver.applySample(sample);
      engine.step(sample.dt);
      executed++;

      final expectedHash = tape.checkpoints[sample.frameIndex];
      if (expectedHash != null) {
        final actualHash = SceneStateHasher.computeHash(engine.scene);
        if (actualHash != expectedHash) {
          mismatches.add(
            'Frame ${sample.frameIndex}: expected scene hash $expectedHash, '
            'got $actualHash',
          );
        }
      }
    }

    final finalHash = SceneStateHasher.computeHash(engine.scene);
    return ReplayVerificationResult(
      passed: mismatches.isEmpty,
      framesExecuted: executed,
      finalSceneHash: finalHash,
      mismatches: List.unmodifiable(mismatches),
    );
  }
}
