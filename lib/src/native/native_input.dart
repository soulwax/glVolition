import 'dart:ffi' as ffi;

import '../../gl_volition.dart';
import 'native_bindings.dart';
import 'native_ffi_transport.dart';
import 'sdl3_bindings.dart';

typedef _SdlGetGamepadsNative =
    ffi.Pointer<ffi.Uint32> Function(ffi.Pointer<ffi.Int>);
typedef _SdlGetGamepadsDart =
    ffi.Pointer<ffi.Uint32> Function(ffi.Pointer<ffi.Int>);

typedef _SdlOpenGamepadNative = ffi.Pointer<ffi.Void> Function(ffi.Uint32);
typedef _SdlOpenGamepadDart = ffi.Pointer<ffi.Void> Function(int);

typedef _SdlCloseGamepadNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _SdlCloseGamepadDart = void Function(ffi.Pointer<ffi.Void>);

typedef _SdlGetGamepadAxisNative =
    ffi.Int16 Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SdlGetGamepadAxisDart = int Function(ffi.Pointer<ffi.Void>, int);

typedef _SdlGetGamepadButtonNative =
    ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SdlGetGamepadButtonDart = bool Function(ffi.Pointer<ffi.Void>, int);

typedef _SdlSetWindowRelativeMouseModeNative =
    ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Bool);
typedef _SdlSetWindowRelativeMouseModeDart =
    bool Function(ffi.Pointer<ffi.Void>, bool);

typedef _SdlWindowBoolQueryNative = ffi.Bool Function(ffi.Pointer<ffi.Void>);
typedef _SdlWindowBoolQueryDart = bool Function(ffi.Pointer<ffi.Void>);

typedef _SdlFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _SdlFreeDart = void Function(ffi.Pointer<ffi.Void>);

/// Normalizes a signed 16-bit SDL3 gamepad axis reading (`-32768..32767`) into
/// `[-1.0, 1.0]`.
double normalizeSdl3GamepadAxis(int rawValue) {
  if (rawValue <= -32768) return -1.0;
  if (rawValue >= 32767) return 1.0;
  if (rawValue == 0) return 0.0;
  return rawValue < 0 ? rawValue / 32768.0 : rawValue / 32767.0;
}

/// Injectable SDL3 hardware input interface covering gamepad enumeration &
/// polling, window relative mouse mode (pointer lock), and text input events.
abstract interface class Sdl3GamepadApi {
  /// Whether the underlying SDL3 symbols are loaded and safe to call.
  bool get isAvailable;

  /// Returns SDL3 joystick/gamepad instance IDs for currently attached gamepads
  /// (`SDL_GetGamepads`).
  List<int> getGamepads();

  /// Opens an attached gamepad by [instanceId] (`SDL_OpenGamepad`), returning a
  /// non-zero opaque handle or `0` on failure.
  int openGamepad(int instanceId);

  /// Closes a previously opened [gamepadHandle] (`SDL_CloseGamepad`).
  void closeGamepad(int gamepadHandle);

  /// Reads raw `Sint16` axis state (`-32768..32767`) for [axis] on
  /// [gamepadHandle] (`SDL_GetGamepadAxis`).
  int getGamepadAxis(int gamepadHandle, int axis);

  /// Reads pressed state for [button] on [gamepadHandle]
  /// (`SDL_GetGamepadButton`).
  bool getGamepadButton(int gamepadHandle, int button);

  /// Enables or disables relative mouse mode (`SDL_SetWindowRelativeMouseMode`)
  /// on [windowHandle].
  bool setWindowRelativeMouseMode(int windowHandle, bool enabled);

  /// Queries whether relative mouse mode is active on [windowHandle]
  /// (`SDL_GetWindowRelativeMouseMode`).
  bool getWindowRelativeMouseMode(int windowHandle);

  /// Starts OS text input event delivery on [windowHandle]
  /// (`SDL_StartTextInput`).
  bool startTextInput(int windowHandle);

  /// Stops OS text input event delivery on [windowHandle]
  /// (`SDL_StopTextInput`).
  bool stopTextInput(int windowHandle);
}

final class _FfiSdl3GamepadApi implements Sdl3GamepadApi {
  final NativeCAllocator allocator;
  final _SdlGetGamepadsDart? getGamepadsFn;
  final _SdlOpenGamepadDart? openGamepadFn;
  final _SdlCloseGamepadDart? closeGamepadFn;
  final _SdlGetGamepadAxisDart? getGamepadAxisFn;
  final _SdlGetGamepadButtonDart? getGamepadButtonFn;
  final _SdlSetWindowRelativeMouseModeDart? setWindowRelativeMouseModeFn;
  final _SdlWindowBoolQueryDart? getWindowRelativeMouseModeFn;
  final _SdlWindowBoolQueryDart? startTextInputFn;
  final _SdlWindowBoolQueryDart? stopTextInputFn;
  final _SdlFreeDart? sdlFreeFn;

  _FfiSdl3GamepadApi({
    required this.allocator,
    this.getGamepadsFn,
    this.openGamepadFn,
    this.closeGamepadFn,
    this.getGamepadAxisFn,
    this.getGamepadButtonFn,
    this.setWindowRelativeMouseModeFn,
    this.getWindowRelativeMouseModeFn,
    this.startTextInputFn,
    this.stopTextInputFn,
    this.sdlFreeFn,
  });

  factory _FfiSdl3GamepadApi.fromLibrary(
    ffi.DynamicLibrary library, {
    required NativeCAllocator allocator,
  }) {
    return _FfiSdl3GamepadApi(
      allocator: allocator,
      getGamepadsFn: library.providesSymbol('SDL_GetGamepads')
          ? library.lookupFunction<_SdlGetGamepadsNative, _SdlGetGamepadsDart>(
              'SDL_GetGamepads',
            )
          : null,
      openGamepadFn: library.providesSymbol('SDL_OpenGamepad')
          ? library.lookupFunction<_SdlOpenGamepadNative, _SdlOpenGamepadDart>(
              'SDL_OpenGamepad',
            )
          : null,
      closeGamepadFn: library.providesSymbol('SDL_CloseGamepad')
          ? library
                .lookupFunction<_SdlCloseGamepadNative, _SdlCloseGamepadDart>(
                  'SDL_CloseGamepad',
                )
          : null,
      getGamepadAxisFn: library.providesSymbol('SDL_GetGamepadAxis')
          ? library.lookupFunction<
              _SdlGetGamepadAxisNative,
              _SdlGetGamepadAxisDart
            >('SDL_GetGamepadAxis')
          : null,
      getGamepadButtonFn: library.providesSymbol('SDL_GetGamepadButton')
          ? library.lookupFunction<
              _SdlGetGamepadButtonNative,
              _SdlGetGamepadButtonDart
            >('SDL_GetGamepadButton')
          : null,
      setWindowRelativeMouseModeFn:
          library.providesSymbol('SDL_SetWindowRelativeMouseMode')
          ? library.lookupFunction<
              _SdlSetWindowRelativeMouseModeNative,
              _SdlSetWindowRelativeMouseModeDart
            >('SDL_SetWindowRelativeMouseMode')
          : null,
      getWindowRelativeMouseModeFn:
          library.providesSymbol('SDL_GetWindowRelativeMouseMode')
          ? library.lookupFunction<
              _SdlWindowBoolQueryNative,
              _SdlWindowBoolQueryDart
            >('SDL_GetWindowRelativeMouseMode')
          : null,
      startTextInputFn: library.providesSymbol('SDL_StartTextInput')
          ? library.lookupFunction<
              _SdlWindowBoolQueryNative,
              _SdlWindowBoolQueryDart
            >('SDL_StartTextInput')
          : null,
      stopTextInputFn: library.providesSymbol('SDL_StopTextInput')
          ? library.lookupFunction<
              _SdlWindowBoolQueryNative,
              _SdlWindowBoolQueryDart
            >('SDL_StopTextInput')
          : null,
      sdlFreeFn: library.providesSymbol('SDL_free')
          ? library.lookupFunction<_SdlFreeNative, _SdlFreeDart>('SDL_free')
          : null,
    );
  }

  @override
  bool get isAvailable =>
      getGamepadsFn != null ||
      setWindowRelativeMouseModeFn != null ||
      startTextInputFn != null;

  @override
  List<int> getGamepads() {
    final fn = getGamepadsFn;
    if (fn == null || !allocator.isAvailable) return const [];
    final countBuffer = allocator.allocateBytes(ffi.sizeOf<ffi.Int>());
    if (countBuffer == ffi.nullptr) return const [];

    ffi.Pointer<ffi.Uint32> idsPtr = ffi.nullptr;
    try {
      final countPtr = countBuffer.cast<ffi.Int>()..value = 0;
      idsPtr = fn(countPtr);
      if (idsPtr == ffi.nullptr) return const [];
      final count = countPtr.value;
      if (count <= 0) return const [];
      return List<int>.generate(count, (i) => idsPtr[i], growable: false);
    } finally {
      if (idsPtr != ffi.nullptr) {
        sdlFreeFn?.call(idsPtr.cast<ffi.Void>());
      }
      allocator.free(countBuffer);
    }
  }

  @override
  int openGamepad(int instanceId) {
    final fn = openGamepadFn;
    if (fn == null || instanceId == 0) return 0;
    return fn(instanceId).address;
  }

  @override
  void closeGamepad(int gamepadHandle) {
    final fn = closeGamepadFn;
    if (fn == null || gamepadHandle == 0) return;
    fn(ffi.Pointer<ffi.Void>.fromAddress(gamepadHandle));
  }

  @override
  int getGamepadAxis(int gamepadHandle, int axis) {
    final fn = getGamepadAxisFn;
    if (fn == null || gamepadHandle == 0) return 0;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(gamepadHandle), axis);
  }

  @override
  bool getGamepadButton(int gamepadHandle, int button) {
    final fn = getGamepadButtonFn;
    if (fn == null || gamepadHandle == 0) return false;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(gamepadHandle), button);
  }

  @override
  bool setWindowRelativeMouseMode(int windowHandle, bool enabled) {
    final fn = setWindowRelativeMouseModeFn;
    if (fn == null || windowHandle == 0) return false;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle), enabled);
  }

  @override
  bool getWindowRelativeMouseMode(int windowHandle) {
    final fn = getWindowRelativeMouseModeFn;
    if (fn == null || windowHandle == 0) return false;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle));
  }

  @override
  bool startTextInput(int windowHandle) {
    final fn = startTextInputFn;
    if (fn == null || windowHandle == 0) return false;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle));
  }

  @override
  bool stopTextInput(int windowHandle) {
    final fn = stopTextInputFn;
    if (fn == null || windowHandle == 0) return false;
    return fn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle));
  }
}

/// Safe dynamic loader for SDL3 gamepad, relative-mouse, and text-input FFI
/// symbols. Never throws when SDL3 is missing from the host environment.
final class Sdl3GamepadBindings {
  final List<String> candidateLibraries;
  final String? libraryName;
  final String? loadError;
  final Sdl3GamepadApi? api;

  Sdl3GamepadBindings._({
    required this.candidateLibraries,
    required this.libraryName,
    required this.loadError,
    required this.api,
  });

  /// Probes [candidateLibraries] (defaulting to
  /// [Sdl3Bindings.defaultCandidateLibraries]) via
  /// [openDynamicLibraryCandidates].
  factory Sdl3GamepadBindings({
    List<String> candidateLibraries = Sdl3Bindings.defaultCandidateLibraries,
    NativeCAllocator? allocator,
  }) {
    final candidates = List<String>.unmodifiable(candidateLibraries);
    final result = openDynamicLibraryCandidates(candidates);
    final library = result.library;
    if (library == null) {
      return Sdl3GamepadBindings._(
        candidateLibraries: candidates,
        libraryName: null,
        loadError: result.error,
        api: null,
      );
    }
    final ffiApi = _FfiSdl3GamepadApi.fromLibrary(
      library,
      allocator: allocator ?? NativeCAllocator.instance,
    );
    return Sdl3GamepadBindings._(
      candidateLibraries: candidates,
      libraryName: result.name,
      loadError: ffiApi.isAvailable
          ? null
          : 'Loaded SDL3 library lacks expected gamepad/input symbols',
      api: ffiApi.isAvailable ? ffiApi : null,
    );
  }

  /// Creates bindings backed by an injectable [api] test double.
  factory Sdl3GamepadBindings.forTest(
    Sdl3GamepadApi? api, {
    String? libraryName = 'mock-sdl3-gamepad',
    String? loadError,
  }) => Sdl3GamepadBindings._(
    candidateLibraries: const [],
    libraryName: api != null ? libraryName : null,
    loadError: loadError,
    api: api,
  );

  /// Whether SDL3 hardware input calls are currently usable.
  bool get isLoaded => api != null && api!.isAvailable;
}

/// Native desktop [Input] adapter bridging [ScriptedInput] and optional SDL3
/// hardware polling (gamepad axes/buttons, scroll wheel, relative mouse lock,
/// multi-touch, and text input).
final class NativeInput implements Input {
  final ScriptedInput scripted;
  NativeWindowBackend? windowBackend;
  final Sdl3GamepadApi? _gamepadApi;

  /// Diagnostic library name when SDL3 input symbols loaded dynamically.
  final String? sdl3LibraryName;

  /// Diagnostic error when dynamic SDL3 lookup failed, or `null` when healthy.
  final String? sdl3LoadError;

  /// Number of standard SDL3 gamepad axes polled per connected gamepad.
  final int gamepadAxisCount;

  /// Number of standard SDL3 gamepad buttons polled per connected gamepad.
  final int gamepadButtonCount;

  int _fallbackWindowHandle;
  final Map<int, int> _openGamepads = <int, int>{};
  int _lastHardwareGamepadCount = 0;
  bool _textInputActive = false;
  bool _disposed = false;

  factory NativeInput({
    ScriptedInput? scripted,
    NativeWindowBackend? windowBackend,
    Sdl3GamepadBindings? gamepadBindings,
    Sdl3GamepadApi? gamepadApi,
    bool probeSdl3 = true,
    int windowHandle = 0,
    int gamepadAxisCount = 6,
    int gamepadButtonCount = 16,
  }) {
    final resolvedBindings =
        (gamepadApi != null || gamepadBindings != null || !probeSdl3)
        ? gamepadBindings
        : Sdl3GamepadBindings();
    final resolvedApi = gamepadApi ?? resolvedBindings?.api;
    final resolvedLibName = gamepadApi != null
        ? 'injected-sdl3-gamepad'
        : resolvedBindings?.libraryName;
    final resolvedLoadError = gamepadApi != null
        ? null
        : resolvedBindings?.loadError;

    return NativeInput._(
      resolvedApi,
      windowHandle,
      scripted: scripted ?? ScriptedInput(),
      windowBackend: windowBackend,
      sdl3LibraryName: resolvedLibName,
      sdl3LoadError: resolvedLoadError,
      gamepadAxisCount: gamepadAxisCount < 0 ? 0 : gamepadAxisCount,
      gamepadButtonCount: gamepadButtonCount < 0 ? 0 : gamepadButtonCount,
    );
  }

  NativeInput._(
    this._gamepadApi,
    this._fallbackWindowHandle, {
    required this.scripted,
    this.windowBackend,
    required this.sdl3LibraryName,
    required this.sdl3LoadError,
    required this.gamepadAxisCount,
    required this.gamepadButtonCount,
  });

  /// Whether SDL3 gamepad / relative mouse / text input symbols are loaded.
  bool get isHardwareInputAvailable =>
      !_disposed && (_gamepadApi?.isAvailable ?? false);

  /// Whether SDL3 text input mode was enabled via [startTextInput].
  bool get isTextInputActive => _textInputActive;

  /// Updates the fallback SDL3 window handle used when [windowBackend] is not
  /// an initialized [Sdl3WindowBackend].
  set windowHandle(int value) => _fallbackWindowHandle = value;

  int get _effectiveWindowHandle {
    final backend = windowBackend;
    if (backend is Sdl3WindowBackend && backend.windowHandle != 0) {
      return backend.windowHandle;
    }
    return _fallbackWindowHandle;
  }

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
  void requestPointerLock() {
    scripted.requestPointerLock();
    final api = _gamepadApi;
    if (!_disposed && api != null && api.isAvailable) {
      api.setWindowRelativeMouseMode(_effectiveWindowHandle, true);
    }
  }

  @override
  void exitPointerLock() {
    scripted.exitPointerLock();
    final api = _gamepadApi;
    if (!_disposed && api != null && api.isAvailable) {
      api.setWindowRelativeMouseMode(_effectiveWindowHandle, false);
    }
  }

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

  /// Enables OS text input delivery (`SDL_StartTextInput`) when available.
  bool startTextInput() {
    final api = _gamepadApi;
    if (_disposed || api == null || !api.isAvailable) return false;
    final ok = api.startTextInput(_effectiveWindowHandle);
    if (ok) _textInputActive = true;
    return ok;
  }

  /// Disables OS text input delivery (`SDL_StopTextInput`) when available.
  bool stopTextInput() {
    _textInputActive = false;
    final api = _gamepadApi;
    if (_disposed || api == null || !api.isAvailable) return false;
    return api.stopTextInput(_effectiveWindowHandle);
  }

  /// Forwards key press into [scripted] and [NativeInput].
  void press(String code) => scripted.press(code);

  /// Forwards key release into [scripted] and [NativeInput].
  void release(String code) => scripted.release(code);

  /// Forwards mouse wheel deltas into [scripted] and [NativeInput].
  void scrollWheel(double dx, double dy) => scripted.scrollWheel(dx, dy);

  /// Alias for [scrollWheel] accumulating wheel deltas for the current frame.
  void addWheelDelta(double dx, double dy) => scripted.scrollWheel(dx, dy);

  /// Forwards relative mouse motion deltas into [scripted] and [NativeInput].
  void addPointerDelta(double dx, double dy) =>
      scripted.addPointerDelta(dx, dy);

  /// Replaces active multi-touch contacts on [scripted] and [NativeInput].
  void setTouches(Iterable<TouchPoint> activeTouches) =>
      scripted.setTouches(activeTouches);

  /// Clears all active multi-touch contacts.
  void clearTouches() => scripted.clearTouches();

  /// Appends committed printable characters to [textInputBuffer].
  void appendTextInput(String text) => scripted.appendTextInput(text);

  /// Pumps [windowBackend] events and polls SDL3 gamepad / relative-mouse state
  /// safely (no-op for missing SDL3 hardware).
  void pumpHardware() {
    if (_disposed) return;

    final prevPointerX = scripted.pointerX;
    final prevPointerY = scripted.pointerY;

    windowBackend?.pumpEvents(scripted);

    final movedX = scripted.pointerX - prevPointerX;
    final movedY = scripted.pointerY - prevPointerY;
    if (movedX != 0.0 || movedY != 0.0) {
      scripted.addPointerDelta(movedX, movedY);
    }

    if (windowBackend case final Sdl3WindowBackend sdl3
        when sdl3.isInitialized) {
      if (sdl3.wheelDeltaX != 0.0 || sdl3.wheelDeltaY != 0.0) {
        scripted.scrollWheel(sdl3.wheelDeltaX, sdl3.wheelDeltaY);
      }
    }

    _pollHardwareGamepads();
    _syncRelativeMouseMode();
  }

  void _pollHardwareGamepads() {
    final api = _gamepadApi;
    if (api == null || !api.isAvailable) return;

    final instanceIds = api.getGamepads();
    final activeSet = instanceIds.toSet();

    for (final existingId in _openGamepads.keys.toList(growable: false)) {
      if (!activeSet.contains(existingId)) {
        final handle = _openGamepads.remove(existingId) ?? 0;
        if (handle != 0) {
          api.closeGamepad(handle);
        }
      }
    }

    var connectedSlots = 0;
    for (var i = 0; i < instanceIds.length; i++) {
      final instanceId = instanceIds[i];
      var handle = _openGamepads[instanceId] ?? 0;
      if (handle == 0) {
        handle = api.openGamepad(instanceId);
        if (handle != 0) {
          _openGamepads[instanceId] = handle;
        }
      }

      if (handle == 0) {
        scripted.setGamepadConnected(i, false);
        continue;
      }

      connectedSlots++;
      scripted.setGamepadConnected(i, true);
      for (var axis = 0; axis < gamepadAxisCount; axis++) {
        final rawAxis = api.getGamepadAxis(handle, axis);
        scripted.setGamepadAxis(i, axis, normalizeSdl3GamepadAxis(rawAxis));
      }
      for (var button = 0; button < gamepadButtonCount; button++) {
        scripted.setGamepadButton(
          i,
          button,
          api.getGamepadButton(handle, button),
        );
      }
    }

    for (var i = instanceIds.length; i < _lastHardwareGamepadCount; i++) {
      scripted.setGamepadConnected(i, false);
    }
    _lastHardwareGamepadCount = instanceIds.length > connectedSlots
        ? instanceIds.length
        : connectedSlots;
  }

  void _syncRelativeMouseMode() {
    final api = _gamepadApi;
    final window = _effectiveWindowHandle;
    if (api == null || !api.isAvailable || window == 0) return;

    final relative = api.getWindowRelativeMouseMode(window);
    if (relative && !scripted.pointerLocked) {
      scripted.requestPointerLock();
    } else if (!relative && scripted.pointerLocked) {
      scripted.exitPointerLock();
    }
  }

  /// Clears per-frame transient input state (`wheelDelta*`, `pointerDelta*`,
  /// `textInputBuffer`, pressed/released edge flags).
  void endFrame() => scripted.endFrame();

  /// Releases opened SDL3 gamepad handles and restores relative-mouse/text-input
  /// modes idempotently.
  void dispose() {
    if (_disposed) return;
    final api = _gamepadApi;
    if (api != null && api.isAvailable) {
      final window = _effectiveWindowHandle;
      if (_textInputActive) {
        api.stopTextInput(window);
      }
      if (scripted.pointerLocked) {
        api.setWindowRelativeMouseMode(window, false);
      }
      for (final handle in _openGamepads.values) {
        if (handle != 0) {
          api.closeGamepad(handle);
        }
      }
    }
    _openGamepads.clear();
    _textInputActive = false;
    scripted.exitPointerLock();
    for (var i = _lastHardwareGamepadCount - 1; i >= 0; i--) {
      scripted.setGamepadConnected(i, false);
    }
    _lastHardwareGamepadCount = 0;
    _disposed = true;
  }
}
