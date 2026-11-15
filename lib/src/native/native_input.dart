import '../../gl_volition.dart';
import 'native_bindings.dart';

/// Native desktop [Input] adapter bridging [ScriptedInput] and optional SDL3
/// hardware polling (gamepad axes/buttons, scroll wheel, relative mouse lock,
/// multi-touch, and text input).
final class NativeInput implements Input {
  final ScriptedInput scripted;
  NativeWindowBackend? windowBackend;

  NativeInput({ScriptedInput? scripted, this.windowBackend})
    : scripted = scripted ?? ScriptedInput();

  @override
  bool isDown(String code) => scripted.isDown(code);

  @override
  bool wasPressed(String code) => scripted.wasPressed(code);

  @override
  bool wasReleased(String code) => scripted.wasReleased(code);

  @override
  double get pointerX => scripted.pointerX;

  @override
  double get pointerY => scripted.pointerY;

  @override
  bool get pointerDown => scripted.pointerDown;

  @override
  bool get pointerPressed => scripted.pointerPressed;

  @override
  bool get pointerReleased => scripted.pointerReleased;

  @override
  double get wheelDeltaX => scripted.wheelDeltaX;

  @override
  double get wheelDeltaY => scripted.wheelDeltaY;

  @override
  double get pointerDeltaX => scripted.pointerDeltaX;

  @override
  double get pointerDeltaY => scripted.pointerDeltaY;

  @override
  bool get pointerLocked => scripted.pointerLocked;

  @override
  void requestPointerLock() => scripted.requestPointerLock();

  @override
  void exitPointerLock() => scripted.exitPointerLock();

  @override
  List<TouchPoint> get touches => scripted.touches;

  @override
  int get gamepadCount => scripted.gamepadCount;

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) =>
      scripted.gamepadAxis(gamepadIndex, axisIndex);

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) =>
      scripted.gamepadButtonDown(gamepadIndex, buttonIndex);

  @override
  String get textInputBuffer => scripted.textInputBuffer;

  void pumpHardware() {
    windowBackend?.pumpEvents(scripted);
  }

  void endFrame() => scripted.endFrame();
}
