part of '../../engine.dart';

/// Standard set of keyboard & mouse control codes scanned during interactive rebinding.
const List<String> _kRebindScanControls = [
  'Space',
  'Enter',
  'Escape',
  'Tab',
  'Backspace',
  'ShiftLeft',
  'ShiftRight',
  'ControlLeft',
  'ControlRight',
  'AltLeft',
  'AltRight',
  'ArrowUp',
  'ArrowDown',
  'ArrowLeft',
  'ArrowRight',
  'KeyA',
  'KeyB',
  'KeyC',
  'KeyD',
  'KeyE',
  'KeyF',
  'KeyG',
  'KeyH',
  'KeyI',
  'KeyJ',
  'KeyK',
  'KeyL',
  'KeyM',
  'KeyN',
  'KeyO',
  'KeyP',
  'KeyQ',
  'KeyR',
  'KeyS',
  'KeyT',
  'KeyU',
  'KeyV',
  'KeyW',
  'KeyX',
  'KeyY',
  'KeyZ',
  'Digit0',
  'Digit1',
  'Digit2',
  'Digit3',
  'Digit4',
  'Digit5',
  'Digit6',
  'Digit7',
  'Digit8',
  'Digit9',
  'MouseLeft',
  'GamepadButton0',
  'GamepadButton1',
  'GamepadButton2',
  'GamepadButton3',
  'GamepadButton4',
  'GamepadButton5',
  'GamepadButton6',
  'GamepadButton7',
  'GamepadButton8',
  'GamepadButton9',
  'GamepadButton10',
  'GamepadButton11',
  'GamepadButton12',
  'GamepadButton13',
  'GamepadButton14',
  'GamepadButton15',
];

/// Component hosting contextual [pad.InputActionAsset] maps, deadzone pipelines,
/// chords, interactive key rebinding, persistent JSON profiles, and optional on-screen [pad.VirtualGamepad].
final class InputManagerComponent extends Behaviour {
  final pad.InputActionAsset actions;
  final pad.InputStateSnapshot snapshot;
  final pad.InputRebinder rebinder;

  pad.VirtualGamepad? virtualGamepad;
  final Set<String> _watchedControls = {};

  /// Controls driven by virtual touch gamepad so keyboard release checks don't overwrite them.
  List<pad.VirtualTouchPointer>? _queuedVirtualPointers;

  InputManagerComponent({
    pad.InputActionAsset? actions,
    pad.InputStateSnapshot? snapshot,
    pad.InputRebinder? rebinder,
    this.virtualGamepad,
  }) : actions = actions ?? pad.InputActionAsset(),
       snapshot = snapshot ?? pad.InputStateSnapshot(),
       rebinder = rebinder ?? pad.InputRebinder();

  /// Evaluates input actions before regular gameplay scripts run.
  @override
  int get executionOrder => -1000;

  /// Looks up an action by `"ActionName"` or `"MapName/ActionName"`.
  pad.InputAction? action(String query) => actions.findAction(query);

  /// True while the action is continuously held past its threshold.
  bool isPressed(String query) => action(query)?.isPressed ?? false;

  /// True on the exact frame the action transitioned to active.
  bool wasPressed(String query) => action(query)?.wasPressedThisFrame ?? false;

  /// True on the exact frame the action transitioned to inactive.
  bool wasReleased(String query) =>
      action(query)?.wasReleasedThisFrame ?? false;

  /// Returns 1D axis value in [-1.0, 1.0].
  double getAxis(String query) => action(query)?.value ?? 0.0;

  /// Returns 2D directional vector mapped from digital composite keys and/or analog sticks.
  Vec2 getVector2(String query) {
    final v = action(query)?.vector2 ?? pad.PadVec2.zero;
    return Vec2(v.x, v.y);
  }

  /// Registers additional physical control names (e.g. `'MouseLeft'`, `'GamepadButton0'`) to poll from raw [Input].
  void watchControls(Iterable<String> controls) =>
      _watchedControls.addAll(controls);

  Input? get _rawOrNull => isAttached ? engine.input.raw : null;

  /// Horizontal scroll wheel delta accumulated for the current frame.
  double get wheelDeltaX => _rawOrNull?.wheelDeltaX ?? 0.0;

  /// Vertical scroll wheel delta accumulated for the current frame.
  double get wheelDeltaY => _rawOrNull?.wheelDeltaY ?? 0.0;

  /// Scroll wheel delta vector (`wheelDeltaX`, `wheelDeltaY`) for the current frame.
  Vec2 get wheelDelta => Vec2(wheelDeltaX, wheelDeltaY);

  /// Horizontal relative pointer motion delta accumulated for the current frame.
  double get pointerDeltaX => _rawOrNull?.pointerDeltaX ?? 0.0;

  /// Vertical relative pointer motion delta accumulated for the current frame.
  double get pointerDeltaY => _rawOrNull?.pointerDeltaY ?? 0.0;

  /// Relative pointer delta vector (`pointerDeltaX`, `pointerDeltaY`) for the current frame.
  Vec2 get pointerDelta => Vec2(pointerDeltaX, pointerDeltaY);

  /// Whether pointer lock / relative mouse mode is currently engaged.
  bool get pointerLocked => _rawOrNull?.pointerLocked ?? false;

  /// Requests OS/browser pointer lock (relative mouse mode).
  void requestPointerLock() => _rawOrNull?.requestPointerLock();

  /// Exits OS/browser pointer lock (relative mouse mode).
  void exitPointerLock() => _rawOrNull?.exitPointerLock();

  /// Active multi-touch contacts in drawing-buffer pixel coordinates.
  List<TouchPoint> get touches => _rawOrNull?.touches ?? const <TouchPoint>[];

  /// Number of currently connected hardware/scripted gamepads.
  int get gamepadCount => _rawOrNull?.gamepadCount ?? 0;

  /// Normalized axis value in `[-1.0, 1.0]` for [gamepadIndex] and [axisIndex].
  double gamepadAxis(int gamepadIndex, int axisIndex) =>
      _rawOrNull?.gamepadAxis(gamepadIndex, axisIndex) ?? 0.0;

  /// True while [buttonIndex] on [gamepadIndex] is pressed.
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) =>
      _rawOrNull?.gamepadButtonDown(gamepadIndex, buttonIndex) ?? false;

  /// Printable characters entered during the current frame.
  String get textInputBuffer => _rawOrNull?.textInputBuffer ?? '';

  /// Queues multi-touch pointers for [virtualGamepad] to evaluate during the next frame update.
  void feedVirtualPointers(List<pad.VirtualTouchPointer> pointers) {
    _queuedVirtualPointers = List<pad.VirtualTouchPointer>.from(pointers);
  }

  /// Persists current custom bindings into the host [KeyValueStore].
  void saveProfile([String storageKey = 'voxpad_bindings']) {
    if (!isAttached) return;
    final jsonStr = pad.InputProfileSerializer.exportJson(actions);
    engine.host.storage.write(storageKey, jsonStr);
  }

  /// Restores previously saved custom bindings from the host [KeyValueStore].
  bool loadProfile([String storageKey = 'voxpad_bindings']) {
    if (!isAttached) return false;
    final jsonStr = engine.host.storage.read(storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return false;
    pad.InputProfileSerializer.importJson(actions, jsonStr);
    return true;
  }

  static const int _standardGamepadAxisCount = 6;
  static const int _standardGamepadButtonCount = 16;

  static ({int gamepadIndex, int index})? _parseGamepadControl(
    String code,
    String token,
  ) {
    if (!code.startsWith('Gamepad')) return null;
    final rest = code.substring('Gamepad'.length);
    final tokenPos = rest.indexOf(token);
    if (tokenPos < 0) return null;
    final padPart = rest.substring(0, tokenPos);
    final idxPart = rest.substring(tokenPos + token.length);
    final gamepadIndex = padPart.isEmpty ? 0 : int.tryParse(padPart);
    final itemIndex = int.tryParse(idxPart);
    if (gamepadIndex == null ||
        gamepadIndex < 0 ||
        itemIndex == null ||
        itemIndex < 0) {
      return null;
    }
    return (gamepadIndex: gamepadIndex, index: itemIndex);
  }

  static bool _readPhysicalControlDown(Input raw, String code) {
    if (code == 'MouseLeft') return raw.pointerDown;
    if (code == 'MouseWheelX') return raw.wheelDeltaX != 0.0;
    if (code == 'MouseWheelY') return raw.wheelDeltaY != 0.0;

    final gamepadBtn = _parseGamepadControl(code, 'Button');
    if (gamepadBtn != null) {
      if (gamepadBtn.gamepadIndex >= raw.gamepadCount) return false;
      return raw.gamepadButtonDown(gamepadBtn.gamepadIndex, gamepadBtn.index);
    }

    return raw.isDown(code);
  }

  void _syncPhysicalAxes(
    Input raw,
    Set<String> axesToPoll,
    Set<String> virtualAxisNames,
  ) {
    for (final axisName in axesToPoll) {
      if (virtualAxisNames.contains(axisName)) continue;
      if (axisName == 'MouseWheelX') {
        snapshot.setAxis(axisName, raw.wheelDeltaX);
        continue;
      }
      if (axisName == 'MouseWheelY') {
        snapshot.setAxis(axisName, raw.wheelDeltaY);
        continue;
      }
      if (axisName == 'PointerDeltaX') {
        snapshot.setAxis(axisName, raw.pointerDeltaX);
        continue;
      }
      if (axisName == 'PointerDeltaY') {
        snapshot.setAxis(axisName, raw.pointerDeltaY);
        continue;
      }

      final gamepadAxisRef = _parseGamepadControl(axisName, 'Axis');
      if (gamepadAxisRef != null) {
        final value = gamepadAxisRef.gamepadIndex < raw.gamepadCount
            ? raw.gamepadAxis(gamepadAxisRef.gamepadIndex, gamepadAxisRef.index)
            : 0.0;
        snapshot.setAxis(axisName, value);
      }
    }
  }

  void _syncRawControls(Input raw) {
    final controlsToPoll = <String>{..._watchedControls};
    final axesToPoll = <String>{
      'MouseWheelX',
      'MouseWheelY',
      'PointerDeltaX',
      'PointerDeltaY',
      for (var i = 0; i < _standardGamepadAxisCount; i++) 'GamepadAxis$i',
    };

    for (var i = 0; i < _standardGamepadButtonCount; i++) {
      controlsToPoll.add('GamepadButton$i');
    }

    for (final map in actions.maps) {
      for (final act in map.actions) {
        for (final binding in act.bindings) {
          controlsToPoll.addAll(binding.referencedControls);
          if (binding is pad.Axis1DBinding && binding.analogAxis != null) {
            axesToPoll.add(binding.analogAxis!);
          } else if (binding is pad.Vector2Binding) {
            if (binding.analogX != null) axesToPoll.add(binding.analogX!);
            if (binding.analogY != null) axesToPoll.add(binding.analogY!);
          }
        }
      }
    }

    if (rebinder.isListening) {
      controlsToPoll.addAll(_kRebindScanControls);
    }

    // Track virtual gamepad control/axis names so inactive physical inputs do not clobber virtual touch values.
    final virtualControlNames = <String>{};
    final virtualAxisNames = <String>{};
    final vpad = virtualGamepad;
    if (vpad != null && vpad.enabled) {
      for (final btn in vpad.buttons) {
        virtualControlNames.add(btn.controlName);
      }
      for (final stick in vpad.sticks) {
        virtualAxisNames
          ..add(stick.axisXName)
          ..add(stick.axisYName);
      }
    }

    for (final code in controlsToPoll) {
      final physicalDown = _readPhysicalControlDown(raw, code);
      if (virtualControlNames.contains(code) && !physicalDown) {
        continue;
      }
      snapshot.setDown(code, physicalDown);
    }

    _syncPhysicalAxes(raw, axesToPoll, virtualAxisNames);
  }

  @override
  void update() {
    final dt = time.deltaTime;
    final raw = engine.input.raw;

    _syncRawControls(raw);

    final vpad = virtualGamepad;
    if (vpad != null && vpad.enabled) {
      final List<pad.VirtualTouchPointer> ptrs;
      if (_queuedVirtualPointers != null) {
        ptrs = _queuedVirtualPointers!;
        _queuedVirtualPointers = null;
      } else {
        final rawTouches = raw.touches;
        if (rawTouches.isNotEmpty) {
          ptrs = [
            for (final t in rawTouches)
              pad.VirtualTouchPointer(id: t.id, x: t.x, y: t.y, isDown: true),
          ];
        } else {
          ptrs = [
            pad.VirtualTouchPointer(
              id: 0,
              x: raw.pointerX,
              y: raw.pointerY,
              isDown: raw.pointerDown,
            ),
          ];
        }
      }
      vpad.update(ptrs, snapshot);
    } else {
      _queuedVirtualPointers = null;
    }

    if (rebinder.isListening) {
      rebinder.poll(snapshot);
    }

    actions.evaluate(snapshot, dt, commitFrame: true);
  }
}

/// Immediate-mode renderer displaying on-screen [pad.VirtualGamepad] analog sticks & touch buttons using `voxui`.
final class VirtualGamepadUI {
  static void render(VoxUiContext ui, pad.VirtualGamepad gamepad) {
    if (!gamepad.enabled) return;

    final dl = ui.drawList;
    for (final stick in gamepad.sticks) {
      final baseColor = stick.isActive
          ? const VoxColor(255, 255, 255, 65)
          : const VoxColor(255, 255, 255, 35);
      final knobColor = stick.isActive
          ? const VoxColor(100, 190, 255, 190)
          : const VoxColor(220, 230, 245, 120);

      dl.addCircleFilled(stick.originX, stick.originY, stick.radius, baseColor);
      dl.addCircleFilled(
        stick.knobX,
        stick.knobY,
        stick.radius * 0.42,
        knobColor,
      );
    }

    for (final btn in gamepad.buttons) {
      final bg = btn.isPressed
          ? const VoxColor(90, 180, 255, 190)
          : const VoxColor(55, 65, 85, 120);
      dl.addCircleFilled(btn.centerX, btn.centerY, btn.radius, bg);
      dl.addText(
        btn.label,
        btn.centerX - 4.0 * btn.label.length,
        btn.centerY - 7.0,
        color: VoxColor.white,
        size: 14.0,
      );
    }
  }
}
