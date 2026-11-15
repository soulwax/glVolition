import 'dart:collection';
import 'dart:ffi' as ffi;

import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/src/native/native_input.dart';
import 'package:gl_volition/src/native/sdl3_bindings.dart';
import 'package:test/test.dart';

final class _MockSdl3GamepadApi implements Sdl3GamepadApi {
  @override
  bool isAvailable = true;

  final List<String> callLog = <String>[];
  final List<int> connectedIds = <int>[];
  final Map<int, int> _idToHandle = <int, int>{};
  final Map<int, Map<int, int>> axesByHandle = <int, Map<int, int>>{};
  final Map<int, Set<int>> buttonsByHandle = <int, Set<int>>{};
  final Map<int, bool> relativeMouseMode = <int, bool>{};
  final Map<int, bool> textInputActive = <int, bool>{};
  final Set<int> closedHandles = <int>{};
  int _nextHandle = 1000;

  @override
  List<int> getGamepads() {
    callLog.add('SDL_GetGamepads');
    return List<int>.from(connectedIds);
  }

  @override
  int openGamepad(int instanceId) {
    callLog.add('SDL_OpenGamepad($instanceId)');
    final handle = _idToHandle.putIfAbsent(instanceId, () => _nextHandle++);
    closedHandles.remove(handle);
    return handle;
  }

  @override
  void closeGamepad(int gamepadHandle) {
    callLog.add('SDL_CloseGamepad($gamepadHandle)');
    closedHandles.add(gamepadHandle);
  }

  @override
  int getGamepadAxis(int gamepadHandle, int axis) =>
      axesByHandle[gamepadHandle]?[axis] ?? 0;

  @override
  bool getGamepadButton(int gamepadHandle, int button) =>
      buttonsByHandle[gamepadHandle]?.contains(button) ?? false;

  @override
  bool setWindowRelativeMouseMode(int windowHandle, bool enabled) {
    callLog.add('SDL_SetWindowRelativeMouseMode($windowHandle, $enabled)');
    relativeMouseMode[windowHandle] = enabled;
    return true;
  }

  @override
  bool getWindowRelativeMouseMode(int windowHandle) =>
      relativeMouseMode[windowHandle] ?? false;

  @override
  bool startTextInput(int windowHandle) {
    callLog.add('SDL_StartTextInput($windowHandle)');
    textInputActive[windowHandle] = true;
    return true;
  }

  @override
  bool stopTextInput(int windowHandle) {
    callLog.add('SDL_StopTextInput($windowHandle)');
    textInputActive[windowHandle] = false;
    return true;
  }
}

final class _FakeWindowSdl3Api implements Sdl3NativeApi {
  final ListQueue<Sdl3RawEvent> events = ListQueue<Sdl3RawEvent>();
  final int windowHandle;

  _FakeWindowSdl3Api({this.windowHandle = 0x5150});

  @override
  bool init(int flags) => true;

  @override
  int createWindow(String title, int width, int height, int flags) =>
      windowHandle;

  @override
  bool glSetAttribute(int attr, int value) => true;

  @override
  int glCreateContext(int windowHandle) => 0x6160;

  @override
  bool glMakeCurrent(int windowHandle, int contextHandle) => true;

  @override
  bool glSwapWindow(int windowHandle) => true;

  @override
  Sdl3RawEvent? pollEvent(ffi.Pointer<ffi.Uint8> eventBuffer) {
    if (events.isEmpty) return null;
    final next = events.removeFirst();
    if (eventBuffer != ffi.nullptr) {
      next.writeToPointer(eventBuffer);
      return Sdl3RawEvent.fromPointer(eventBuffer);
    }
    return next;
  }

  @override
  ({int width, int height})? getWindowSizeInPixels(int windowHandle) =>
      const (width: 1280, height: 720);

  @override
  ({int width, int height})? getWindowSize(int windowHandle) =>
      const (width: 1280, height: 720);

  @override
  void destroyWindow(int windowHandle) {}

  @override
  void glDestroyContext(int contextHandle) {}

  @override
  void quit() {}

  @override
  String getError() => '';

  @override
  String getKeyName(int keycode) => '';

  @override
  String getScancodeName(int scancode) => '';
}

InputManagerComponent _attachInputManager(
  Engine engine, {
  InputActionAsset? actions,
  VirtualGamepad? virtualGamepad,
}) {
  final mgr = InputManagerComponent(
    actions: actions,
    virtualGamepad: virtualGamepad,
  );
  engine.scene.createGameObject('InputManager', components: [mgr]);
  return mgr;
}

void main() {
  group('HeadlessHost / ScriptedInput + InputManagerComponent parity', () {
    test(
      'wheel deltas populate convenience getters & MouseWheelX/Y bindings and reset in endFrame',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final mgr = _attachInputManager(engine);
        final camMap = mgr.actions.addMap('Camera');
        camMap.addAxis1D('Zoom', [
          const Axis1DBinding(
            analogAxis: 'MouseWheelY',
            deadzone: DeadzoneProcessor(mode: DeadzoneMode.none),
          ),
        ]);
        camMap.addAxis1D('PanWheelX', [
          const Axis1DBinding(
            analogAxis: 'MouseWheelX',
            deadzone: DeadzoneProcessor(mode: DeadzoneMode.none),
          ),
        ]);
        camMap.addButton('WheelPulse', [const KeyBinding('MouseWheelY')]);

        host.input.scrollWheel(-0.5, 0.75);
        engine.step(0.016);

        expect(mgr.wheelDeltaX, closeTo(-0.5, 1e-6));
        expect(mgr.wheelDeltaY, closeTo(0.75, 1e-6));
        expect(mgr.wheelDelta.x, closeTo(-0.5, 1e-6));
        expect(mgr.wheelDelta.y, closeTo(0.75, 1e-6));
        expect(mgr.getAxis('Camera/PanWheelX'), closeTo(-0.5, 1e-6));
        expect(mgr.getAxis('Camera/Zoom'), closeTo(0.75, 1e-6));
        expect(mgr.isPressed('Camera/WheelPulse'), isTrue);
        expect(mgr.wasPressed('Camera/WheelPulse'), isTrue);

        host.input.endFrame();
        engine.step(0.016);

        expect(mgr.wheelDeltaX, 0.0);
        expect(mgr.wheelDeltaY, 0.0);
        expect(mgr.getAxis('Camera/PanWheelX'), 0.0);
        expect(mgr.getAxis('Camera/Zoom'), 0.0);
        expect(mgr.isPressed('Camera/WheelPulse'), isFalse);
        expect(mgr.wasReleased('Camera/WheelPulse'), isTrue);
      },
    );

    test(
      'live raw.touches drive multi-touch VirtualGamepad sticks & buttons with primary pointer fallback',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final vpad = VirtualGamepad.dualStick(
          viewportWidth: 1280,
          viewportHeight: 720,
        );
        final leftStick = vpad.sticks.first;
        final buttonA = vpad.buttons.first;

        final mgr = _attachInputManager(engine, virtualGamepad: vpad);
        final mobileMap = mgr.actions.addMap('Mobile');
        mobileMap.addVector2('Move', [
          Vector2Binding(
            analogX: leftStick.axisXName,
            analogY: leftStick.axisYName,
            deadzone: const DeadzoneProcessor(mode: DeadzoneMode.none),
          ),
        ]);
        mobileMap.addButton('Jump', [KeyBinding(buttonA.controlName)]);

        // Two simultaneous touches: left stick pulled right + Jump button A pressed.
        host.input.setTouches([
          TouchPoint(
            id: 1,
            x: leftStick.originX + leftStick.radius,
            y: leftStick.originY,
          ),
          TouchPoint(id: 2, x: buttonA.centerX, y: buttonA.centerY),
        ]);
        engine.step(0.016);

        expect(mgr.touches.length, 2);
        expect(mgr.getVector2('Move').x, closeTo(1.0, 1e-5));
        expect(mgr.getVector2('Move').y, closeTo(0.0, 1e-5));
        expect(mgr.isPressed('Jump'), isTrue);
        expect(mgr.wasPressed('Jump'), isTrue);

        // Lift finger 2 while keeping finger 1 engaged on stick.
        host.input.setTouches([
          TouchPoint(
            id: 1,
            x: leftStick.originX + leftStick.radius,
            y: leftStick.originY,
          ),
        ]);
        engine.step(0.016);

        expect(mgr.getVector2('Move').x, closeTo(1.0, 1e-5));
        expect(mgr.isPressed('Jump'), isFalse);
        expect(mgr.wasReleased('Jump'), isTrue);

        // Lift all touches and verify empty raw.touches falls back to primary pointer.
        host.input.clearTouches();
        host.input.pointerX = buttonA.centerX;
        host.input.pointerY = buttonA.centerY;
        host.input.pointerDown = true;
        engine.step(0.016);

        expect(mgr.touches, isEmpty);
        expect(mgr.getVector2('Move').x, closeTo(0.0, 1e-5));
        expect(mgr.isPressed('Jump'), isTrue);
        expect(mgr.wasPressed('Jump'), isTrue);

        host.input.pointerDown = false;
        engine.step(0.016);
        expect(mgr.isPressed('Jump'), isFalse);
      },
    );

    test(
      'pointer lock toggles persistently and PointerDeltaX/Y clear per frame',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final mgr = _attachInputManager(engine);
        final fpsMap = mgr.actions.addMap('FPS');
        fpsMap.addVector2('Look', [
          const Vector2Binding(
            analogX: 'PointerDeltaX',
            analogY: 'PointerDeltaY',
            deadzone: DeadzoneProcessor(mode: DeadzoneMode.none),
            normalize: false,
          ),
        ]);

        expect(mgr.pointerLocked, isFalse);
        mgr.requestPointerLock();
        expect(mgr.pointerLocked, isTrue);
        expect(host.input.pointerLocked, isTrue);

        host.input.addPointerDelta(0.45, -0.35);
        engine.step(0.016);

        expect(mgr.pointerDeltaX, closeTo(0.45, 1e-6));
        expect(mgr.pointerDeltaY, closeTo(-0.35, 1e-6));
        expect(mgr.pointerDelta.x, closeTo(0.45, 1e-6));
        expect(mgr.pointerDelta.y, closeTo(-0.35, 1e-6));
        expect(mgr.snapshot.getAxis('PointerDeltaX'), closeTo(0.45, 1e-6));
        expect(mgr.snapshot.getAxis('PointerDeltaY'), closeTo(-0.35, 1e-6));
        expect(mgr.getVector2('FPS/Look').x, closeTo(0.45, 1e-6));
        expect(mgr.getVector2('FPS/Look').y, closeTo(-0.35, 1e-6));

        host.input.endFrame();
        host.input.addPointerDelta(14.5, -9.25);
        engine.step(0.016);
        expect(mgr.pointerDeltaX, closeTo(14.5, 1e-6));
        expect(mgr.pointerDeltaY, closeTo(-9.25, 1e-6));
        expect(mgr.snapshot.getAxis('PointerDeltaX'), closeTo(14.5, 1e-6));
        expect(mgr.snapshot.getAxis('PointerDeltaY'), closeTo(-9.25, 1e-6));

        host.input.endFrame();
        engine.step(0.016);

        expect(mgr.pointerLocked, isTrue);
        expect(mgr.pointerDeltaX, 0.0);
        expect(mgr.pointerDeltaY, 0.0);
        expect(mgr.getVector2('FPS/Look'), Vec2.zero);

        mgr.exitPointerLock();
        expect(mgr.pointerLocked, isFalse);
        expect(host.input.pointerLocked, isFalse);
      },
    );

    test(
      'gamepad axes & buttons poll into InputManagerComponent and clear on disconnect',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final mgr = _attachInputManager(engine);
        final gpMap = mgr.actions.addMap('Gamepad');
        gpMap.addVector2('Stick', [
          const Vector2Binding(
            analogX: 'GamepadAxis0',
            analogY: 'GamepadAxis1',
            deadzone: DeadzoneProcessor(mode: DeadzoneMode.none),
            normalize: false,
          ),
        ]);
        gpMap.addButton('South', [const KeyBinding('GamepadButton0')]);
        gpMap.addButton('Misc', [const KeyBinding('GamepadButton15')]);
        gpMap.addAxis1D('Pad2Trigger', [
          const Axis1DBinding(
            analogAxis: 'Gamepad1Axis4',
            deadzone: DeadzoneProcessor(mode: DeadzoneMode.none),
          ),
        ]);
        gpMap.addButton('Pad2Button', [const KeyBinding('Gamepad1Button2')]);

        expect(mgr.gamepadCount, 0);
        expect(mgr.gamepadAxis(0, 0), 0.0);
        expect(mgr.gamepadButtonDown(0, 0), isFalse);

        host.input.setGamepadAxis(0, 0, 0.85);
        host.input.setGamepadAxis(0, 1, -0.45);
        host.input.setGamepadButton(0, 0, true);
        host.input.setGamepadButton(0, 15, true);
        host.input.setGamepadAxis(1, 4, 0.6);
        host.input.setGamepadButton(1, 2, true);
        engine.step(0.016);

        expect(mgr.gamepadCount, 2);
        expect(mgr.gamepadAxis(0, 0), closeTo(0.85, 1e-6));
        expect(mgr.gamepadButtonDown(0, 0), isTrue);
        expect(mgr.getVector2('Stick').x, closeTo(0.85, 1e-6));
        expect(mgr.getVector2('Stick').y, closeTo(-0.45, 1e-6));
        expect(mgr.isPressed('South'), isTrue);
        expect(mgr.isPressed('Misc'), isTrue);
        expect(mgr.getAxis('Pad2Trigger'), closeTo(0.6, 1e-6));
        expect(mgr.isPressed('Pad2Button'), isTrue);

        // Disconnect gamepad 0 while keeping gamepad 1 connected.
        host.input.setGamepadConnected(0, false);
        engine.step(0.016);

        expect(mgr.isPressed('South'), isFalse);
        expect(mgr.wasReleased('South'), isTrue);
        expect(mgr.isPressed('Misc'), isFalse);
        expect(mgr.getVector2('Stick'), Vec2.zero);
        expect(mgr.getAxis('Pad2Trigger'), closeTo(0.6, 1e-6));
        expect(mgr.isPressed('Pad2Button'), isTrue);
      },
    );

    test(
      'runtime rebinding captures keyboard & gamepad buttons and saveProfile/loadProfile persists across hosts',
      () {
        final host1 = HeadlessHost();
        final engine1 = Engine(host1);
        final mgr1 = _attachInputManager(engine1);
        final combatMap1 = mgr1.actions.addMap('Combat');
        final fire1 = combatMap1.addButton('Fire', [const KeyBinding('KeyF')]);

        // 1) Rebind interactively to GamepadButton2.
        String? bound1;
        mgr1.rebinder.startListening(
          map: combatMap1,
          action: fire1,
          bindingIndex: 0,
          onCompleted: (ctrl) => bound1 = ctrl,
        );
        host1.input.setGamepadButton(0, 2, true);
        engine1.step(0.016);

        expect(bound1, 'GamepadButton2');
        expect(mgr1.rebinder.isListening, isFalse);
        expect((fire1.bindings.first as KeyBinding).control, 'GamepadButton2');

        host1.input.setGamepadButton(0, 2, false);
        host1.input.endFrame();
        engine1.step(0.016);

        // 2) Rebind interactively to KeyK and persist profile.
        String? bound2;
        mgr1.rebinder.startListening(
          map: combatMap1,
          action: fire1,
          bindingIndex: 0,
          onCompleted: (ctrl) => bound2 = ctrl,
        );
        host1.input.press('KeyK');
        engine1.step(0.016);

        expect(bound2, 'KeyK');
        expect(mgr1.rebinder.isListening, isFalse);
        expect((fire1.bindings.first as KeyBinding).control, 'KeyK');
        mgr1.saveProfile('w10a_profile');

        // 3) Boot fresh Engine & Host sharing persisted JSON and restore profile.
        final host2 = HeadlessHost();
        host2.storage.write(
          'w10a_profile',
          host1.storage.read('w10a_profile')!,
        );
        final engine2 = Engine(host2);
        final mgr2 = _attachInputManager(engine2);
        final combatMap2 = mgr2.actions.addMap('Combat');
        combatMap2.addButton('Fire', [const KeyBinding('KeyF')]);

        expect(mgr2.loadProfile('w10a_profile'), isTrue);

        host2.input.press('KeyF');
        engine2.step(0.016);
        expect(mgr2.isPressed('Combat/Fire'), isFalse);

        host2.input.release('KeyF');
        host2.input.endFrame();
        host2.input.press('KeyK');
        engine2.step(0.016);
        expect(mgr2.isPressed('Combat/Fire'), isTrue);
        expect(mgr2.wasPressed('Combat/Fire'), isTrue);
      },
    );

    test(
      'textInputBuffer exposes typed text and resets cleanly every endFrame',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final mgr = _attachInputManager(engine);

        host.input.appendTextInput('Volition ');
        host.input.appendTextInput('3D');
        engine.step(0.016);

        expect(mgr.textInputBuffer, 'Volition 3D');
        expect(host.input.textInputBuffer, 'Volition 3D');

        host.input.endFrame();
        engine.step(0.016);

        expect(mgr.textInputBuffer, isEmpty);
        expect(host.input.textInputBuffer, isEmpty);
      },
    );
  });

  group('NativeInput + mock Sdl3GamepadApi + ScriptedInput parity', () {
    test(
      'missing SDL3 library fails safely with zero throws and full ScriptedInput fallback',
      () {
        final bindings = Sdl3GamepadBindings(
          candidateLibraries: const [
            'nonexistent_sdl3_w10a_win.dll',
            'nonexistent_sdl3_w10a_linux.so',
          ],
        );
        expect(bindings.isLoaded, isFalse);
        expect(bindings.api, isNull);
        expect(bindings.loadError, isNotNull);

        final nativeInput = NativeInput(gamepadBindings: bindings);
        expect(nativeInput.isHardwareInputAvailable, isFalse);
        expect(nativeInput.sdl3LoadError, isNotNull);
        expect(nativeInput.gamepadCount, 0);
        expect(nativeInput.gamepadAxis(0, 0), 0.0);
        expect(nativeInput.gamepadButtonDown(0, 0), isFalse);
        expect(nativeInput.startTextInput(), isFalse);
        expect(nativeInput.stopTextInput(), isFalse);

        nativeInput.requestPointerLock();
        expect(nativeInput.pointerLocked, isTrue);
        expect(nativeInput.scripted.pointerLocked, isTrue);
        nativeInput.exitPointerLock();
        expect(nativeInput.pointerLocked, isFalse);
        expect(nativeInput.scripted.pointerLocked, isFalse);

        nativeInput.pumpHardware();
        nativeInput.endFrame();
        nativeInput.dispose();
        nativeInput.dispose();

        // Explicit probeSdl3: false & default probing both stay safe regardless of host SDL3 install.
        final noProbeInput = NativeInput(probeSdl3: false);
        expect(noProbeInput.isHardwareInputAvailable, isFalse);
        noProbeInput.pumpHardware();
        noProbeInput.dispose();

        expect(() {
          final defaultProbed = NativeInput();
          defaultProbed.pumpHardware();
          defaultProbed.endFrame();
          defaultProbed.dispose();
        }, returnsNormally);
      },
    );

    test(
      'SDL3 Sint16 axis normalization, multi-gamepad polling, and hot-unplug sync NativeInput & ScriptedInput',
      () {
        expect(normalizeSdl3GamepadAxis(-32768), -1.0);
        expect(normalizeSdl3GamepadAxis(-16384), closeTo(-0.5, 1e-6));
        expect(normalizeSdl3GamepadAxis(0), 0.0);
        expect(normalizeSdl3GamepadAxis(16384), closeTo(16384 / 32767.0, 1e-6));
        expect(normalizeSdl3GamepadAxis(32767), 1.0);

        final api = _MockSdl3GamepadApi();
        api.connectedIds.addAll([101, 202]);

        final bindings = Sdl3GamepadBindings.forTest(api);
        final nativeInput = NativeInput(gamepadBindings: bindings);

        // Configure pad 101 (handle 1000) & pad 202 (handle 1001).
        api.axesByHandle[1000] = {0: -32768, 1: 32767, 4: 16384};
        api.buttonsByHandle[1000] = {0, 9};
        api.axesByHandle[1001] = {0: -16384};
        api.buttonsByHandle[1001] = {3};

        nativeInput.pumpHardware();

        expect(nativeInput.isHardwareInputAvailable, isTrue);
        expect(nativeInput.gamepadCount, 2);
        expect(nativeInput.scripted.gamepadCount, 2);
        expect(nativeInput.gamepadAxis(0, 0), -1.0);
        expect(nativeInput.scripted.gamepadAxis(0, 0), -1.0);
        expect(nativeInput.gamepadAxis(0, 1), 1.0);
        expect(nativeInput.gamepadAxis(0, 4), closeTo(16384 / 32767.0, 1e-6));
        expect(nativeInput.gamepadButtonDown(0, 0), isTrue);
        expect(nativeInput.scripted.gamepadButtonDown(0, 0), isTrue);
        expect(nativeInput.gamepadButtonDown(0, 9), isTrue);
        expect(nativeInput.gamepadButtonDown(0, 1), isFalse);
        expect(nativeInput.gamepadAxis(1, 0), closeTo(-0.5, 1e-6));
        expect(nativeInput.gamepadButtonDown(1, 3), isTrue);

        // Hot-unplug pad 101 -> handle 1000 closes, pad 202 shifts to slot 0 without re-opening.
        final openCountBefore = api.callLog
            .where((c) => c == 'SDL_OpenGamepad(202)')
            .length;
        expect(openCountBefore, 1);

        api.connectedIds.remove(101);
        nativeInput.pumpHardware();

        expect(api.closedHandles.contains(1000), isTrue);
        expect(api.callLog.where((c) => c == 'SDL_OpenGamepad(202)').length, 1);
        expect(nativeInput.gamepadCount, 1);
        expect(nativeInput.scripted.gamepadCount, 1);
        expect(nativeInput.gamepadAxis(0, 0), closeTo(-0.5, 1e-6));
        expect(nativeInput.gamepadButtonDown(0, 3), isTrue);

        // Hot-unplug remaining pad 202.
        api.connectedIds.clear();
        nativeInput.pumpHardware();

        expect(api.closedHandles.contains(1001), isTrue);
        expect(nativeInput.gamepadCount, 0);
        expect(nativeInput.scripted.gamepadCount, 0);

        nativeInput.dispose();
      },
    );

    test(
      'pointer lock toggles SDL3 relative mouse mode, start/stopTextInput, and dispose restores cleanly',
      () {
        final api = _MockSdl3GamepadApi();
        final nativeInput = NativeInput(gamepadApi: api, windowHandle: 777);

        nativeInput.requestPointerLock();
        expect(nativeInput.pointerLocked, isTrue);
        expect(nativeInput.scripted.pointerLocked, isTrue);
        expect(api.relativeMouseMode[777], isTrue);

        // External OS exit of relative mouse mode synchronizes on pumpHardware.
        api.relativeMouseMode[777] = false;
        nativeInput.pumpHardware();
        expect(nativeInput.pointerLocked, isFalse);
        expect(nativeInput.scripted.pointerLocked, isFalse);

        // Re-lock and verify text input toggle + cleanup on dispose.
        nativeInput.requestPointerLock();
        expect(nativeInput.startTextInput(), isTrue);
        expect(nativeInput.isTextInputActive, isTrue);
        expect(api.textInputActive[777], isTrue);

        expect(nativeInput.stopTextInput(), isTrue);
        expect(nativeInput.isTextInputActive, isFalse);
        expect(api.textInputActive[777], isFalse);

        expect(nativeInput.startTextInput(), isTrue);
        nativeInput.dispose();

        expect(nativeInput.pointerLocked, isFalse);
        expect(nativeInput.scripted.pointerLocked, isFalse);
        expect(api.relativeMouseMode[777], isFalse);
        expect(nativeInput.isTextInputActive, isFalse);
        expect(api.textInputActive[777], isFalse);
      },
    );

    test(
      'Sdl3WindowBackend wheel, pointer motion deltas, touches, and textInputBuffer forward cleanly into NativeInput & ScriptedInput',
      () {
        final fakeWindowApi = _FakeWindowSdl3Api(windowHandle: 0x9001);
        final windowBindings = Sdl3Bindings.forTest(fakeWindowApi);
        final windowBackend = Sdl3WindowBackend(bindings: windowBindings);
        expect(windowBackend.openWindow(title: 'W10A Parity'), isTrue);

        final gamepadApi = _MockSdl3GamepadApi();
        final nativeInput = NativeInput(
          windowBackend: windowBackend,
          gamepadApi: gamepadApi,
        );

        // Pointer lock should automatically route to windowBackend.windowHandle.
        nativeInput.requestPointerLock();
        expect(gamepadApi.relativeMouseMode[0x9001], isTrue);

        fakeWindowApi.events.addAll([
          const Sdl3RawEvent(type: SDL_EVENT_MOUSE_MOTION, x: 120.0, y: 80.0),
          const Sdl3RawEvent(type: SDL_EVENT_MOUSE_MOTION, x: 135.0, y: 74.0),
          const Sdl3RawEvent(
            type: SDL_EVENT_MOUSE_WHEEL,
            wheelX: 1.5,
            wheelY: -2.0,
            wheelDirection: SDL_MOUSEWHEEL_NORMAL,
          ),
          const Sdl3RawEvent(
            type: SDL_EVENT_MOUSE_WHEEL,
            wheelX: 0.0,
            wheelY: -1.0,
            wheelDirection: SDL_MOUSEWHEEL_FLIPPED,
          ),
        ]);
        nativeInput.setTouches([
          const TouchPoint(id: 3, x: 240.0, y: 320.0),
          const TouchPoint(id: 7, x: 960.0, y: 540.0, pressure: 0.6),
        ]);
        nativeInput.appendTextInput('abc');

        nativeInput.pumpHardware();

        expect(nativeInput.pointerX, closeTo(135.0, 1e-6));
        expect(nativeInput.pointerY, closeTo(74.0, 1e-6));
        expect(nativeInput.pointerDeltaX, closeTo(135.0, 1e-6));
        expect(nativeInput.pointerDeltaY, closeTo(74.0, 1e-6));
        expect(nativeInput.scripted.pointerDeltaX, closeTo(135.0, 1e-6));
        expect(nativeInput.scripted.pointerDeltaY, closeTo(74.0, 1e-6));
        expect(nativeInput.wheelDeltaX, closeTo(1.5, 1e-6));
        expect(nativeInput.wheelDeltaY, closeTo(-1.0, 1e-6));
        expect(nativeInput.scripted.wheelDeltaX, closeTo(1.5, 1e-6));
        expect(nativeInput.scripted.wheelDeltaY, closeTo(-1.0, 1e-6));
        expect(nativeInput.touches.length, 2);
        expect(nativeInput.scripted.touches.length, 2);
        expect(nativeInput.textInputBuffer, 'abc');
        expect(nativeInput.scripted.textInputBuffer, 'abc');

        nativeInput.endFrame();
        expect(nativeInput.wheelDeltaX, 0.0);
        expect(nativeInput.wheelDeltaY, 0.0);
        expect(nativeInput.pointerDeltaX, 0.0);
        expect(nativeInput.pointerDeltaY, 0.0);
        expect(nativeInput.textInputBuffer, isEmpty);
        expect(nativeInput.scripted.textInputBuffer, isEmpty);

        // Next frame incremental delta from (135, 74) to (140, 70).
        fakeWindowApi.events.add(
          const Sdl3RawEvent(type: SDL_EVENT_MOUSE_MOTION, x: 140.0, y: 70.0),
        );
        nativeInput.pumpHardware();

        expect(nativeInput.pointerDeltaX, closeTo(5.0, 1e-6));
        expect(nativeInput.pointerDeltaY, closeTo(-4.0, 1e-6));

        nativeInput.dispose();
        windowBackend.dispose();
      },
    );
  });
}
