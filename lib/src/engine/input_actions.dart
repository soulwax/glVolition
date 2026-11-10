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
}
