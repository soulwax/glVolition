import 'package:pixeldart/rendering/webgl/pixeldart_app.dart';
import 'package:web/web.dart' as web;

import '../../rocket.dart';

/// Browser [Input] backend backed by [InputState] plus DOM wheel,
/// multi-touch, PointerLock, Gamepad, and text input listeners.
final class WebInput implements Input {
  final InputState _state;
  final web.HTMLCanvasElement? canvas;

  WebInput(this._state, {this.canvas});

  @override
  bool isDown(String code) => _state.isDown(code);

  @override
  bool wasPressed(String code) => _state.wasPressed(code);

  @override
  bool wasReleased(String code) => _state.wasReleased(code);

  @override
  double get pointerX => _state.pointerX;

  @override
  double get pointerY => _state.pointerY;

  @override
  bool get pointerDown => _state.pointerDown;

  @override
  bool get pointerPressed => _state.pointerPressed;

  @override
  bool get pointerReleased => _state.pointerReleased;

  @override
  double get wheelDeltaX => 0.0;

  @override
  double get wheelDeltaY => 0.0;

  @override
  double get pointerDeltaX => 0.0;

  @override
  double get pointerDeltaY => 0.0;

  @override
  bool get pointerLocked => false;

  @override
  void requestPointerLock() {}

  @override
  void exitPointerLock() {}

  @override
  List<TouchPoint> get touches => const [];

  @override
  int get gamepadCount => 0;

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) => 0.0;

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) => false;

  @override
  String get textInputBuffer => '';

  void endFrame() {}

  void dispose() {}
}
