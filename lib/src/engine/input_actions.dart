part of '../engine.dart';

final class _ButtonBinding {
  final List<String> keys;
  final List<int> gamepadButtons;
  final int gamepadIndex;

  _ButtonBinding({
    required List<String> keys,
    List<int> gamepadButtons = const [],
    this.gamepadIndex = 0,
  }) : keys = List.unmodifiable(keys),
       gamepadButtons = List.unmodifiable(gamepadButtons);

  Map<String, Object?> toJson() => {
    'keys': keys,
    if (gamepadButtons.isNotEmpty) 'gamepadButtons': gamepadButtons,
    if (gamepadIndex != 0) 'gamepadIndex': gamepadIndex,
  };

  factory _ButtonBinding.fromJson(Map<String, Object?> json) => _ButtonBinding(
    keys: [
      for (final k in (json['keys'] as List<Object?>?) ?? const [])
        k.toString(),
    ],
    gamepadButtons: [
      for (final b in (json['gamepadButtons'] as List<Object?>?) ?? const [])
        if (b is num) b.toInt(),
    ],
    gamepadIndex: (json['gamepadIndex'] as num?)?.toInt() ?? 0,
  );
}

final class _AxisBinding {
  final List<String> negative;
  final List<String> positive;
  final int? gamepadAxis;
  final int gamepadIndex;
  final double deadzone;
  final bool invertGamepadAxis;

  _AxisBinding({
    required List<String> negative,
    required List<String> positive,
    this.gamepadAxis,
    this.gamepadIndex = 0,
    this.deadzone = 0.15,
    this.invertGamepadAxis = false,
  }) : negative = List.unmodifiable(negative),
       positive = List.unmodifiable(positive);

  Map<String, Object?> toJson() => {
    'negative': negative,
    'positive': positive,
    if (gamepadAxis != null) 'gamepadAxis': gamepadAxis,
    if (gamepadIndex != 0) 'gamepadIndex': gamepadIndex,
    'deadzone': deadzone,
    if (invertGamepadAxis) 'invertGamepadAxis': true,
  };

  factory _AxisBinding.fromJson(Map<String, Object?> json) => _AxisBinding(
    negative: [
      for (final k in (json['negative'] as List<Object?>?) ?? const [])
        k.toString(),
    ],
    positive: [
      for (final k in (json['positive'] as List<Object?>?) ?? const [])
        k.toString(),
    ],
    gamepadAxis: (json['gamepadAxis'] as num?)?.toInt(),
    gamepadIndex: (json['gamepadIndex'] as num?)?.toInt() ?? 0,
    deadzone: (json['deadzone'] as num?)?.toDouble() ?? 0.15,
    invertGamepadAxis: json['invertGamepadAxis'] == true,
  );
}

/// Named buttons and axes over raw [Input] supporting keyboard + gamepad
/// bindings, deadzones, runtime rebinding, and JSON profile persistence
/// (P11-W19-A). Ships with Unity's familiar defaults: `Horizontal`, `Vertical`,
/// `Submit`, `Cancel`.
final class InputActions {
  final Input raw;
  final Map<String, _ButtonBinding> _buttons = {};
  final Map<String, _AxisBinding> _axes = {};
  final Map<String, bool> _prevGamepadButtonDown = {};

  InputActions(this.raw) {
    axis(
      'Horizontal',
      negative: ['KeyA', 'ArrowLeft'],
      positive: ['KeyD', 'ArrowRight'],
      gamepadAxis: 0,
    );
    axis(
      'Vertical',
      negative: ['KeyS', 'ArrowDown'],
      positive: ['KeyW', 'ArrowUp'],
      gamepadAxis: 1,
      invertGamepadAxis: true,
    );
    button('Submit', ['Enter', 'Space'], gamepadButtons: const [0]);
    button('Cancel', ['Escape'], gamepadButtons: const [1]);
  }

  /// Defines or replaces a button bound to any of [keys] and optional
  /// [gamepadButtons] on [gamepadIndex].
  void button(
    String name,
    List<String> keys, {
    List<int> gamepadButtons = const [],
    int gamepadIndex = 0,
  }) => _buttons[name] = _ButtonBinding(
    keys: keys,
    gamepadButtons: gamepadButtons,
    gamepadIndex: gamepadIndex,
  );

  /// Updates an existing button binding (or creates one if absent).
  void rebindButton(
    String name,
    List<String> keys, {
    List<int>? gamepadButtons,
    int? gamepadIndex,
  }) {
    final prev = _buttons[name];
    _buttons[name] = _ButtonBinding(
      keys: keys,
      gamepadButtons: gamepadButtons ?? prev?.gamepadButtons ?? const [],
      gamepadIndex: gamepadIndex ?? prev?.gamepadIndex ?? 0,
    );
  }

  /// Defines or replaces an axis that reads -1 while any [negative] key is
  /// held, +1 for [positive], blended with an optional [gamepadAxis] with
  /// [deadzone] filtering.
  void axis(
    String name, {
    required List<String> negative,
    required List<String> positive,
    int? gamepadAxis,
    int gamepadIndex = 0,
    double deadzone = 0.15,
    bool invertGamepadAxis = false,
  }) => _axes[name] = _AxisBinding(
    negative: negative,
    positive: positive,
    gamepadAxis: gamepadAxis,
    gamepadIndex: gamepadIndex,
    deadzone: deadzone,
    invertGamepadAxis: invertGamepadAxis,
  );

  /// Updates an existing axis binding in place while keeping unspecified fields.
  void rebindAxis(
    String name, {
    List<String>? negative,
    List<String>? positive,
    int? gamepadAxis,
    int? gamepadIndex,
    double? deadzone,
    bool? invertGamepadAxis,
  }) {
    final prev = _axes[name];
    _axes[name] = _AxisBinding(
      negative: negative ?? prev?.negative ?? const [],
      positive: positive ?? prev?.positive ?? const [],
      gamepadAxis: gamepadAxis ?? prev?.gamepadAxis,
      gamepadIndex: gamepadIndex ?? prev?.gamepadIndex ?? 0,
      deadzone: deadzone ?? prev?.deadzone ?? 0.15,
      invertGamepadAxis: invertGamepadAxis ?? prev?.invertGamepadAxis ?? false,
    );
  }

  _ButtonBinding _button(String name) =>
      _buttons[name] ??
      (throw ArgumentError.value(name, 'name', 'no such input button'));

  bool _anyGamepadButtonDown(_ButtonBinding b) {
    if (b.gamepadButtons.isEmpty || raw.gamepadCount <= b.gamepadIndex) {
      return false;
    }
    for (final btn in b.gamepadButtons) {
      if (raw.gamepadButtonDown(b.gamepadIndex, btn)) return true;
    }
    return false;
  }

  /// Snapshots current gamepad button states for edge detection (`wasPressed` /
  /// `wasReleased`) across frames.
  void syncGamepadState() {
    for (final entry in _buttons.entries) {
      _prevGamepadButtonDown[entry.key] = _anyGamepadButtonDown(entry.value);
    }
  }

  bool isDown(String name) {
    final b = _button(name);
    return b.keys.any(raw.isDown) || _anyGamepadButtonDown(b);
  }

  /// Whether a button named [name] is registered.
  bool hasButton(String name) => _buttons.containsKey(name);

  /// Whether an axis named [name] is registered.
  bool hasAxis(String name) => _axes.containsKey(name);

  /// All registered button names.
  Iterable<String> get buttonNames => _buttons.keys;

  /// All registered axis names.
  Iterable<String> get axisNames => _axes.keys;

  /// Alias for [getAxis] matching Unity conventions.
  double getAxisRaw(String name) => getAxis(name);

  bool wasPressed(String name) {
    final b = _button(name);
    final keyPressed =
        b.keys.any(raw.wasPressed) &&
        !b.keys.any((k) => raw.isDown(k) && !raw.wasPressed(k));
    final gpNow = _anyGamepadButtonDown(b);
    final gpPrev = _prevGamepadButtonDown[name] ?? false;
    final gpPressed = gpNow && !gpPrev;
    return keyPressed || gpPressed;
  }

  bool wasReleased(String name) {
    final b = _button(name);
    final keyReleased = b.keys.any(raw.wasReleased) && !b.keys.any(raw.isDown);
    final gpNow = _anyGamepadButtonDown(b);
    final gpPrev = _prevGamepadButtonDown[name] ?? false;
    final gpReleased = !gpNow && gpPrev;
    return (keyReleased || gpReleased) && !isDown(name);
  }

  double getAxis(String name) {
    final binding =
        _axes[name] ??
        (throw ArgumentError.value(name, 'name', 'no such input axis'));
    var v = 0.0;
    if (binding.negative.any(raw.isDown)) v -= 1.0;
    if (binding.positive.any(raw.isDown)) v += 1.0;

    final gpAxis = binding.gamepadAxis;
    if (gpAxis != null && raw.gamepadCount > binding.gamepadIndex) {
      var axisVal = raw.gamepadAxis(binding.gamepadIndex, gpAxis);
      if (binding.invertGamepadAxis) axisVal = -axisVal;
      if (axisVal.abs() >= binding.deadzone) {
        v += axisVal;
      }
    }
    return v.clamp(-1.0, 1.0);
  }

  /// Evaluates 2D directional vector `(x, y)` composed of two named axes (default `Horizontal` and `Vertical`) (E23-3).
  ///
  /// When [normalize] is true and the length exceeds 1.0, scales the vector to unit length
  /// so diagonal movement does not exceed cardinal movement speed.
  Vec2 getVector2({
    String horizontalAxis = 'Horizontal',
    String verticalAxis = 'Vertical',
    bool normalize = true,
  }) {
    final vx = getAxis(horizontalAxis);
    final vy = getAxis(verticalAxis);
    if (!normalize) return Vec2(vx, vy);
    final lenSq = vx * vx + vy * vy;
    if (lenSq > 1.0) {
      final invLen = 1.0 / math.sqrt(lenSq);
      return Vec2(vx * invLen, vy * invLen);
    }
    return Vec2(vx, vy);
  }

  /// Serializes all button and axis bindings into a JSON-compatible map.
  Map<String, Object?> exportBindingsJson() => {
    'version': 1,
    'buttons': {for (final e in _buttons.entries) e.key: e.value.toJson()},
    'axes': {for (final e in _axes.entries) e.key: e.value.toJson()},
  };

  /// Loads button and axis bindings from [json] produced by [exportBindingsJson].
  void importBindingsJson(
    Map<String, Object?> json, {
    bool clearExisting = false,
  }) {
    if (clearExisting) {
      _buttons.clear();
      _axes.clear();
    }
    final rawButtons = json['buttons'];
    if (rawButtons is Map) {
      for (final e in rawButtons.entries) {
        if (e.value is Map) {
          _buttons[e.key.toString()] = _ButtonBinding.fromJson(
            Map<String, Object?>.from(e.value as Map),
          );
        }
      }
    }
    final rawAxes = json['axes'];
    if (rawAxes is Map) {
      for (final e in rawAxes.entries) {
        if (e.value is Map) {
          _axes[e.key.toString()] = _AxisBinding.fromJson(
            Map<String, Object?>.from(e.value as Map),
          );
        }
      }
    }
  }

  /// Persists the current binding profile to [store] under [key].
  void saveToStore(KeyValueStore store, {String key = 'volition.input'}) {
    store.write(key, jsonEncode(exportBindingsJson()));
  }

  /// Loads a binding profile from [store] under [key]. Returns `true` if found.
  bool loadFromStore(KeyValueStore store, {String key = 'volition.input'}) {
    final raw = store.read(key);
    if (raw == null || raw.isEmpty) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return false;
    importBindingsJson(Map<String, Object?>.from(decoded));
    return true;
  }
}
