part of '../engine.dart';

/// Named buttons and axes over raw [Input], so game code asks for "Boost"
/// rather than for two specific shift keys. Ships with Unity's familiar
/// defaults: `Horizontal`, `Vertical`, `Submit`, `Cancel`.
final class InputActions {
  final Input raw;
  final Map<String, List<String>> _buttons = {};
  final Map<String, (List<String>, List<String>)> _axes = {};

  InputActions(this.raw) {
    axis('Horizontal', negative: ['KeyA', 'ArrowLeft'], positive: ['KeyD', 'ArrowRight']);
    axis('Vertical', negative: ['KeyS', 'ArrowDown'], positive: ['KeyW', 'ArrowUp']);
    button('Submit', ['Enter', 'Space']);
    button('Cancel', ['Escape']);
  }

  /// Defines or replaces a button bound to any of [keys].
  void button(String name, List<String> keys) => _buttons[name] = List.unmodifiable(keys);

  /// Defines or replaces an axis that reads -1 while any [negative] key is
  /// held, +1 for [positive], 0 for both or neither.
  void axis(String name, {required List<String> negative, required List<String> positive}) =>
      _axes[name] = (List.unmodifiable(negative), List.unmodifiable(positive));

  List<String> _keys(String name) =>
      _buttons[name] ?? (throw ArgumentError.value(name, 'name', 'no such input button'));

  bool isDown(String name) => _keys(name).any(raw.isDown);

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
    final keys = _keys(name);
    // Pressed this frame, and not already held through another binding.
    return keys.any(raw.wasPressed) && !keys.any((k) => raw.isDown(k) && !raw.wasPressed(k));
  }

  bool wasReleased(String name) {
    final keys = _keys(name);
    return keys.any(raw.wasReleased) && !keys.any(raw.isDown);
  }

  double getAxis(String name) {
    final binding = _axes[name] ?? (throw ArgumentError.value(name, 'name', 'no such input axis'));
    var v = 0.0;
    if (binding.$1.any(raw.isDown)) v -= 1;
    if (binding.$2.any(raw.isDown)) v += 1;
    return v;
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
}
