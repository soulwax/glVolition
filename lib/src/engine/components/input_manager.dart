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

  /// Registers additional physical control names (e.g. `'MouseLeft'`, `'GamepadA'`) to poll from raw [Input].
  void watchControls(Iterable<String> controls) =>
      _watchedControls.addAll(controls);

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

  void _syncRawControls(Input raw) {
    final controlsToPoll = <String>{..._watchedControls};
    for (final map in actions.maps) {
      for (final act in map.actions) {
        for (final binding in act.bindings) {
          controlsToPoll.addAll(binding.referencedControls);
        }
      }
    }

    if (rebinder.isListening) {
      controlsToPoll.addAll(_kRebindScanControls);
    }

    // Track virtual button control names separately so virtual gamepad buttons aren't clobbered by missing physical presses
    final virtualControlNames = <String>{};
    if (virtualGamepad != null && virtualGamepad!.enabled) {
      for (final btn in virtualGamepad!.buttons) {
        virtualControlNames.add(btn.controlName);
      }
    }

    for (final code in controlsToPoll) {
      if (virtualControlNames.contains(code) && raw.isDown(code) == false) {
        // Leave virtual button handling to VirtualGamepad below
        continue;
      }
      snapshot.setDown(code, raw.isDown(code));
    }

    // Poll pointer buttons too if bound
    if (controlsToPoll.contains('MouseLeft')) {
      snapshot.setDown('MouseLeft', raw.pointerDown);
    }
  }

  @override
  void update() {
    final dt = time.deltaTime;
    final raw = engine.input.raw;

    _syncRawControls(raw);

    final vpad = virtualGamepad;
    if (vpad != null && vpad.enabled) {
      final ptrs =
          _queuedVirtualPointers ??
          [
            pad.VirtualTouchPointer(
              id: 0,
              x: raw.pointerX,
              y: raw.pointerY,
              isDown: raw.pointerDown,
            ),
          ];
      vpad.update(ptrs, snapshot);
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
