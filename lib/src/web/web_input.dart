import 'dart:async';
import 'dart:js_interop';

import 'package:pixeldart/rendering/webgl/pixeldart_app.dart';
import 'package:web/web.dart' as web;

import '../../rocket.dart';

extension _PointerLockElementJs on web.Element {
  external JSAny? requestPointerLock();
}

extension _PointerLockDocumentJs on web.Document {
  external web.Element? get pointerLockElement;
  external void exitPointerLock();
}

extension _MouseEventMovementJs on web.MouseEvent {
  external num? get movementX;
  external num? get movementY;
}

/// Browser [Input] backend backed by [InputState] plus DOM wheel,
/// multi-touch, PointerLock, Gamepad, and text input listeners.
final class WebInput implements Input {
  final InputState _state;
  final web.HTMLCanvasElement? canvas;

  late final web.HTMLCanvasElement _targetCanvas = canvas ?? _state.canvas;

  double _wheelDeltaX = 0.0;
  double _wheelDeltaY = 0.0;
  double _pointerDeltaX = 0.0;
  double _pointerDeltaY = 0.0;
  bool _pointerLocked = false;
  double _lastClientX = 0.0;
  double _lastClientY = 0.0;
  bool _hasLastClientPos = false;

  final Map<int, TouchPoint> _activeTouches = {};
  List<TouchPoint> _cachedTouches = const [];
  bool _touchesDirty = false;

  final StringBuffer _textInputBuffer = StringBuffer();
  String? _pendingKeyText;
  String? _pendingBeforeInputText;
  bool _dedupClearScheduled = false;
  bool _disposed = false;

  late final JSFunction _onWheel = _handleWheel.toJS;
  late final JSFunction _onTouchStart = _handleTouchStart.toJS;
  late final JSFunction _onTouchMove = _handleTouchMove.toJS;
  late final JSFunction _onTouchEnd = _handleTouchEnd.toJS;
  late final JSFunction _onPointerLockChange = _handlePointerLockChange.toJS;
  late final JSFunction _onMouseMove = _handleMouseMove.toJS;
  late final JSFunction _onKeyDown = _handleKeyDown.toJS;
  late final JSFunction _onBeforeInput = _handleBeforeInput.toJS;
  late final JSFunction _onInput = _handleInput.toJS;
  late final JSFunction _onBlur = _handleBlur.toJS;

  WebInput(this._state, {this.canvas}) {
    _attachListeners();
  }

  void _attachListeners() {
    _targetCanvas.addEventListener('wheel', _onWheel);
    _targetCanvas.addEventListener('touchstart', _onTouchStart);
    _targetCanvas.addEventListener('touchmove', _onTouchMove);
    _targetCanvas.addEventListener('touchend', _onTouchEnd);
    _targetCanvas.addEventListener('touchcancel', _onTouchEnd);
    _targetCanvas.addEventListener('beforeinput', _onBeforeInput);
    _targetCanvas.addEventListener('input', _onInput);
    web.document.addEventListener('pointerlockchange', _onPointerLockChange);
    web.document.addEventListener('pointerlockerror', _onPointerLockChange);
    web.window.addEventListener('mousemove', _onMouseMove);
    web.window.addEventListener('keydown', _onKeyDown);
    web.window.addEventListener('blur', _onBlur);
    _syncPointerLockState();
  }

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
  double get wheelDeltaX => _wheelDeltaX;

  @override
  double get wheelDeltaY => _wheelDeltaY;

  @override
  double get pointerDeltaX => _pointerDeltaX;

  @override
  double get pointerDeltaY => _pointerDeltaY;

  @override
  bool get pointerLocked {
    _syncPointerLockState();
    return _pointerLocked;
  }

  @override
  void requestPointerLock() {
    if (_disposed) return;
    try {
      final result = _targetCanvas.requestPointerLock();
      if (result != null && result.isA<JSPromise>()) {
        (result as JSPromise).toDart.then((_) {}, onError: (Object _) {});
      }
    } catch (_) {}
  }

  @override
  void exitPointerLock() {
    if (_disposed) return;
    try {
      if (web.document.pointerLockElement != null) {
        web.document.exitPointerLock();
      }
    } catch (_) {}
    _pointerLocked = false;
  }

  @override
  List<TouchPoint> get touches {
    if (_touchesDirty) {
      final sorted = _activeTouches.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      _cachedTouches = List<TouchPoint>.unmodifiable(sorted);
      _touchesDirty = false;
    }
    return _cachedTouches;
  }

  @override
  int get gamepadCount => _connectedGamepads().length;

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) {
    if (gamepadIndex < 0 || axisIndex < 0) return 0.0;
    final pads = _connectedGamepads();
    if (gamepadIndex >= pads.length) return 0.0;
    try {
      final axes = pads[gamepadIndex].axes.toDart;
      if (axisIndex >= axes.length) return 0.0;
      final value = axes[axisIndex].toDartDouble;
      return value.isFinite ? value.clamp(-1.0, 1.0) : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) {
    if (gamepadIndex < 0 || buttonIndex < 0) return false;
    final pads = _connectedGamepads();
    if (gamepadIndex >= pads.length) return false;
    try {
      final buttons = pads[gamepadIndex].buttons.toDart;
      if (buttonIndex >= buttons.length) return false;
      return buttons[buttonIndex].pressed;
    } catch (_) {
      return false;
    }
  }

  @override
  String get textInputBuffer => _textInputBuffer.toString();

  void endFrame() {
    _wheelDeltaX = 0.0;
    _wheelDeltaY = 0.0;
    _pointerDeltaX = 0.0;
    _pointerDeltaY = 0.0;
    _textInputBuffer.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _targetCanvas.removeEventListener('wheel', _onWheel);
    _targetCanvas.removeEventListener('touchstart', _onTouchStart);
    _targetCanvas.removeEventListener('touchmove', _onTouchMove);
    _targetCanvas.removeEventListener('touchend', _onTouchEnd);
    _targetCanvas.removeEventListener('touchcancel', _onTouchEnd);
    _targetCanvas.removeEventListener('beforeinput', _onBeforeInput);
    _targetCanvas.removeEventListener('input', _onInput);
    web.document.removeEventListener('pointerlockchange', _onPointerLockChange);
    web.document.removeEventListener('pointerlockerror', _onPointerLockChange);
    web.window.removeEventListener('mousemove', _onMouseMove);
    web.window.removeEventListener('keydown', _onKeyDown);
    web.window.removeEventListener('blur', _onBlur);
    _activeTouches.clear();
    _cachedTouches = const [];
    _touchesDirty = false;
    _pointerLocked = false;
    endFrame();
  }

  List<web.Gamepad> _connectedGamepads() {
    try {
      final raw = web.window.navigator.getGamepads().toDart;
      final connected = <web.Gamepad>[];
      for (final pad in raw) {
        if (pad != null && pad.connected) {
          connected.add(pad);
        }
      }
      return connected;
    } catch (_) {
      return const [];
    }
  }

  void _syncPointerLockState() {
    try {
      _pointerLocked = web.document.pointerLockElement == _targetCanvas;
    } catch (_) {
      _pointerLocked = false;
    }
  }

  void _handleWheel(web.Event event) {
    if (!event.isA<web.WheelEvent>()) return;
    final e = event as web.WheelEvent;
    if (e.cancelable) e.preventDefault();
    final dx = e.deltaX.toDouble();
    final dy = e.deltaY.toDouble();
    if (dx.isFinite) _wheelDeltaX += dx;
    if (dy.isFinite) _wheelDeltaY += dy;
  }

  void _handleTouchStart(web.Event event) {
    if (!event.isA<web.TouchEvent>()) return;
    _upsertTouches((event as web.TouchEvent).changedTouches);
  }

  void _handleTouchMove(web.Event event) {
    if (!event.isA<web.TouchEvent>()) return;
    _upsertTouches((event as web.TouchEvent).changedTouches);
  }

  void _handleTouchEnd(web.Event event) {
    if (!event.isA<web.TouchEvent>()) return;
    final changed = (event as web.TouchEvent).changedTouches;
    for (var i = 0; i < changed.length; i++) {
      final touch = changed.item(i);
      if (touch == null) continue;
      if (_activeTouches.remove(touch.identifier) != null) {
        _touchesDirty = true;
      }
    }
  }

  void _upsertTouches(web.TouchList changed) {
    final rect = _targetCanvas.getBoundingClientRect();
    final hasRect = rect.width > 0 && rect.height > 0;
    final scaleX = hasRect ? _targetCanvas.width / rect.width : 1.0;
    final scaleY = hasRect ? _targetCanvas.height / rect.height : 1.0;
    final left = hasRect ? rect.left : 0.0;
    final top = hasRect ? rect.top : 0.0;

    for (var i = 0; i < changed.length; i++) {
      final touch = changed.item(i);
      if (touch == null) continue;
      final force = touch.force.toDouble();
      final pressure = force > 0.0 && force.isFinite ? force : 1.0;
      _activeTouches[touch.identifier] = TouchPoint(
        id: touch.identifier,
        x: (touch.clientX.toDouble() - left) * scaleX,
        y: (touch.clientY.toDouble() - top) * scaleY,
        pressure: pressure,
      );
      _touchesDirty = true;
    }
  }

  void _handlePointerLockChange(web.Event _) {
    _syncPointerLockState();
  }

  void _handleMouseMove(web.Event event) {
    if (!event.isA<web.MouseEvent>()) return;
    final e = event as web.MouseEvent;
    final mx = e.movementX?.toDouble();
    final my = e.movementY?.toDouble();
    final cx = e.clientX.toDouble();
    final cy = e.clientY.toDouble();
    if (mx != null && my != null && mx.isFinite && my.isFinite) {
      _pointerDeltaX += mx;
      _pointerDeltaY += my;
    } else if (_hasLastClientPos) {
      _pointerDeltaX += cx - _lastClientX;
      _pointerDeltaY += cy - _lastClientY;
    }
    _lastClientX = cx;
    _lastClientY = cy;
    _hasLastClientPos = true;
  }

  void _handleKeyDown(web.Event event) {
    if (!event.isA<web.KeyboardEvent>()) return;
    final e = event as web.KeyboardEvent;
    if (e.ctrlKey || e.metaKey || e.altKey || e.isComposing) return;
    final key = e.key;
    if (!_isPrintableSingleChar(key)) return;
    _textInputBuffer.write(key);
    _pendingKeyText = key;
    _scheduleDedupClear();
  }

  void _handleBeforeInput(web.Event event) {
    if (!event.isA<web.InputEvent>()) return;
    final e = event as web.InputEvent;
    if (e.isComposing) return;
    final data = e.data;
    if (data == null || data.isEmpty) return;
    if (_pendingKeyText == data) {
      _pendingKeyText = null;
      _pendingBeforeInputText = data;
      _scheduleDedupClear();
      return;
    }
    _textInputBuffer.write(data);
    _pendingBeforeInputText = data;
    _scheduleDedupClear();
  }

  void _handleInput(web.Event event) {
    if (!event.isA<web.InputEvent>()) return;
    final e = event as web.InputEvent;
    if (e.isComposing) return;
    final data = e.data;
    if (data == null || data.isEmpty) return;
    if (_pendingBeforeInputText == data) {
      _pendingBeforeInputText = null;
      return;
    }
    if (_pendingKeyText == data) {
      _pendingKeyText = null;
      return;
    }
    _textInputBuffer.write(data);
  }

  void _handleBlur(web.Event _) {
    _hasLastClientPos = false;
    _pendingKeyText = null;
    _pendingBeforeInputText = null;
    if (_activeTouches.isNotEmpty) {
      _activeTouches.clear();
      _cachedTouches = const [];
      _touchesDirty = false;
    }
  }

  void _scheduleDedupClear() {
    if (_dedupClearScheduled) return;
    _dedupClearScheduled = true;
    scheduleMicrotask(() {
      _dedupClearScheduled = false;
      _pendingKeyText = null;
      _pendingBeforeInputText = null;
    });
  }

  static bool _isPrintableSingleChar(String key) {
    if (key.isEmpty || key.runes.length != 1) return false;
    final codePoint = key.runes.first;
    return codePoint >= 0x20 && codePoint != 0x7F;
  }
}
