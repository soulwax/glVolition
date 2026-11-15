// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import '../../gl_volition.dart';
import 'native_bindings.dart';
import 'native_ffi_transport.dart';

/// SDL3 subsystem initialization flags (`<SDL3/SDL_init.h>`).
const int SDL_INIT_VIDEO = 0x00000020;

/// SDL3 window creation flags (`Uint64` `SDL_WindowFlags` in `<SDL3/SDL_video.h>`).
const int SDL_WINDOW_OPENGL = 0x0000000000000002;
const int SDL_WINDOW_RESIZABLE = 0x0000000000000020;
const int SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x0000000000002000;

/// SDL3 OpenGL context attributes (`SDL_GLAttr` in `<SDL3/SDL_video.h>`).
const int SDL_GL_DOUBLEBUFFER = 5;
const int SDL_GL_DEPTH_SIZE = 6;
const int SDL_GL_CONTEXT_MAJOR_VERSION = 17;
const int SDL_GL_CONTEXT_MINOR_VERSION = 18;
const int SDL_GL_CONTEXT_PROFILE_MASK = 20;

/// SDL3 OpenGL profile flag requesting an OpenGL ES context.
const int SDL_GL_CONTEXT_PROFILE_ES = 0x0004;

/// SDL3 event type identifiers (`SDL_EventType` in `<SDL3/SDL_events.h>`).
const int SDL_EVENT_QUIT = 0x100;
const int SDL_EVENT_WINDOW_RESIZED = 0x206;
const int SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = 0x207;
const int SDL_EVENT_WINDOW_FOCUS_GAINED = 0x20E;
const int SDL_EVENT_WINDOW_FOCUS_LOST = 0x20F;
const int SDL_EVENT_KEY_DOWN = 0x300;
const int SDL_EVENT_KEY_UP = 0x301;
const int SDL_EVENT_MOUSE_MOTION = 0x400;
const int SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401;
const int SDL_EVENT_MOUSE_BUTTON_UP = 0x402;
const int SDL_EVENT_MOUSE_WHEEL = 0x403;

/// SDL3 mouse wheel scroll direction constants.
const int SDL_MOUSEWHEEL_NORMAL = 0;
const int SDL_MOUSEWHEEL_FLIPPED = 1;

/// Bitmask applied to SDL3 keycodes derived directly from a scancode.
const int SDLK_SCANCODE_MASK = 0x40000000;

/// Common USB HID-backed SDL3 physical scancode constants.
const int SDL_SCANCODE_A = 4;
const int SDL_SCANCODE_D = 7;
const int SDL_SCANCODE_S = 22;
const int SDL_SCANCODE_W = 26;
const int SDL_SCANCODE_RETURN = 40;
const int SDL_SCANCODE_ESCAPE = 41;
const int SDL_SCANCODE_BACKSPACE = 42;
const int SDL_SCANCODE_TAB = 43;
const int SDL_SCANCODE_SPACE = 44;
const int SDL_SCANCODE_GRAVE = 53;
const int SDL_SCANCODE_F1 = 58;
const int SDL_SCANCODE_F12 = 69;
const int SDL_SCANCODE_RIGHT = 79;
const int SDL_SCANCODE_LEFT = 80;
const int SDL_SCANCODE_DOWN = 81;
const int SDL_SCANCODE_UP = 82;
const int SDL_SCANCODE_LCTRL = 224;
const int SDL_SCANCODE_LSHIFT = 225;
const int SDL_SCANCODE_LALT = 226;
const int SDL_SCANCODE_LGUI = 227;
const int SDL_SCANCODE_RCTRL = 228;
const int SDL_SCANCODE_RSHIFT = 229;
const int SDL_SCANCODE_RALT = 230;
const int SDL_SCANCODE_RGUI = 231;

/// Byte size of SDL3's `union SDL_Event` (`Uint8 padding[128]`).
const int sdl3EventBufferSize = 128;

typedef _SdlInitNative = ffi.Bool Function(ffi.Uint32 flags);
typedef _SdlInitDart = bool Function(int flags);

typedef _SdlCreateWindowNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8> title,
      ffi.Int width,
      ffi.Int height,
      ffi.Uint64 flags,
    );
typedef _SdlCreateWindowDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8> title,
      int width,
      int height,
      int flags,
    );

typedef _SdlGlSetAttributeNative =
    ffi.Bool Function(ffi.Int32 attr, ffi.Int value);
typedef _SdlGlSetAttributeDart = bool Function(int attr, int value);

typedef _SdlGlCreateContextNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void> window);
typedef _SdlGlCreateContextDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void> window);

typedef _SdlGlMakeCurrentNative =
    ffi.Bool Function(
      ffi.Pointer<ffi.Void> window,
      ffi.Pointer<ffi.Void> context,
    );
typedef _SdlGlMakeCurrentDart =
    bool Function(ffi.Pointer<ffi.Void> window, ffi.Pointer<ffi.Void> context);

typedef _SdlGlSwapWindowNative =
    ffi.Bool Function(ffi.Pointer<ffi.Void> window);
typedef _SdlGlSwapWindowDart = bool Function(ffi.Pointer<ffi.Void> window);

typedef _SdlPollEventNative = ffi.Bool Function(ffi.Pointer<ffi.Void> event);
typedef _SdlPollEventDart = bool Function(ffi.Pointer<ffi.Void> event);

typedef _SdlGetWindowSizeNative =
    ffi.Bool Function(
      ffi.Pointer<ffi.Void> window,
      ffi.Pointer<ffi.Int> w,
      ffi.Pointer<ffi.Int> h,
    );
typedef _SdlGetWindowSizeDart =
    bool Function(
      ffi.Pointer<ffi.Void> window,
      ffi.Pointer<ffi.Int> w,
      ffi.Pointer<ffi.Int> h,
    );

typedef _SdlDestroyWindowNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> window);
typedef _SdlDestroyWindowDart = void Function(ffi.Pointer<ffi.Void> window);

typedef _SdlGlDestroyContextNative =
    ffi.Bool Function(ffi.Pointer<ffi.Void> context);
typedef _SdlGlDestroyContextDart = bool Function(ffi.Pointer<ffi.Void> context);

typedef _SdlGlDeleteContextNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> context);
typedef _SdlGlDeleteContextDart = void Function(ffi.Pointer<ffi.Void> context);

typedef _SdlQuitNative = ffi.Void Function();
typedef _SdlQuitDart = void Function();

typedef _SdlGetErrorNative = ffi.Pointer<ffi.Uint8> Function();
typedef _SdlGetErrorDart = ffi.Pointer<ffi.Uint8> Function();

typedef _SdlGetKeyNameNative = ffi.Pointer<ffi.Uint8> Function(ffi.Uint32 key);
typedef _SdlGetKeyNameDart = ffi.Pointer<ffi.Uint8> Function(int key);

typedef _SdlGetScancodeNameNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Int32 scancode);
typedef _SdlGetScancodeNameDart = ffi.Pointer<ffi.Uint8> Function(int scancode);

/// Decoded SDL3 `SDL_Event` union payload covering window, keyboard, mouse,
/// wheel, and quit events.
final class Sdl3RawEvent {
  /// Raw SDL3 `SDL_EventType` discriminant (`type` at byte offset 0).
  final int type;

  /// Nanosecond event timestamp (`timestamp` at byte offset 8).
  final int timestamp;

  /// Associated SDL window identifier (`windowID` at byte offset 16).
  final int windowId;

  /// Window event primary integer payload (`data1` at byte offset 20).
  final int data1;

  /// Window event secondary integer payload (`data2` at byte offset 24).
  final int data2;

  /// Physical key scancode (`SDL_Scancode` at byte offset 24).
  final int scancode;

  /// Layout-mapped keycode (`SDL_Keycode` at byte offset 28).
  final int keycode;

  /// Active modifier key bitmask (`SDL_Keymod` at byte offset 32).
  final int mod;

  /// Whether a keyboard or mouse button event represents a press (`down`).
  final bool down;

  /// Whether a keyboard event is an OS auto-repeat (`repeat`).
  final bool repeat;

  /// SDL mouse button index (`1` = left, `2` = middle, `3` = right).
  final int button;

  /// Click count (`1` = single, `2` = double, etc.).
  final int clicks;

  /// Horizontal pointer coordinate (`x` in window logical coordinates).
  final double x;

  /// Vertical pointer coordinate (`y` in window logical coordinates).
  final double y;

  /// Relative horizontal motion delta (`xrel`).
  final double xRel;

  /// Relative vertical motion delta (`yrel`).
  final double yRel;

  /// Horizontal scroll delta (`SDL_MouseWheelEvent.x`).
  final double wheelX;

  /// Vertical scroll delta (`SDL_MouseWheelEvent.y`).
  final double wheelY;

  /// Scroll direction (`SDL_MOUSEWHEEL_NORMAL` or `SDL_MOUSEWHEEL_FLIPPED`).
  final int wheelDirection;

  /// Creates an [Sdl3RawEvent].
  const Sdl3RawEvent({
    required this.type,
    this.timestamp = 0,
    this.windowId = 0,
    this.data1 = 0,
    this.data2 = 0,
    this.scancode = 0,
    this.keycode = 0,
    this.mod = 0,
    this.down = false,
    this.repeat = false,
    this.button = 0,
    this.clicks = 0,
    this.x = 0.0,
    this.y = 0.0,
    this.xRel = 0.0,
    this.yRel = 0.0,
    this.wheelX = 0.0,
    this.wheelY = 0.0,
    this.wheelDirection = SDL_MOUSEWHEEL_NORMAL,
  });

  /// Decodes a native 128-byte `SDL_Event` buffer from [ptr].
  static Sdl3RawEvent fromPointer(
    ffi.Pointer<ffi.Uint8> ptr, {
    int byteLength = sdl3EventBufferSize,
    Endian? endian,
  }) {
    if (ptr == ffi.nullptr || byteLength < 4) {
      return const Sdl3RawEvent(type: 0);
    }
    final bytes = ptr.asTypedList(byteLength);
    return fromBuffer(ByteData.sublistView(bytes), endian: endian);
  }

  /// Decodes an [Sdl3RawEvent] from a raw `SDL_Event` [ByteData] buffer.
  static Sdl3RawEvent fromBuffer(ByteData data, {Endian? endian}) {
    final byteOrder = endian ?? Endian.host;
    if (data.lengthInBytes < 4) {
      return const Sdl3RawEvent(type: 0);
    }
    final type = data.getUint32(0, byteOrder);
    final timestamp = data.lengthInBytes >= 16
        ? data.getUint64(8, byteOrder)
        : 0;
    final windowId = data.lengthInBytes >= 20
        ? data.getUint32(16, byteOrder)
        : 0;

    if (_isWindowEvent(type) && data.lengthInBytes >= 28) {
      return Sdl3RawEvent(
        type: type,
        timestamp: timestamp,
        windowId: windowId,
        data1: data.getInt32(20, byteOrder),
        data2: data.getInt32(24, byteOrder),
      );
    }

    if ((type == SDL_EVENT_KEY_DOWN || type == SDL_EVENT_KEY_UP) &&
        data.lengthInBytes >= 38) {
      return Sdl3RawEvent(
        type: type,
        timestamp: timestamp,
        windowId: windowId,
        scancode: data.getInt32(24, byteOrder),
        keycode: data.getUint32(28, byteOrder),
        mod: data.getUint16(32, byteOrder),
        down: data.getUint8(36) != 0,
        repeat: data.getUint8(37) != 0,
      );
    }

    if (type == SDL_EVENT_MOUSE_MOTION && data.lengthInBytes >= 44) {
      return Sdl3RawEvent(
        type: type,
        timestamp: timestamp,
        windowId: windowId,
        button: data.getUint32(24, byteOrder),
        x: data.getFloat32(28, byteOrder),
        y: data.getFloat32(32, byteOrder),
        xRel: data.getFloat32(36, byteOrder),
        yRel: data.getFloat32(40, byteOrder),
      );
    }

    if ((type == SDL_EVENT_MOUSE_BUTTON_DOWN ||
            type == SDL_EVENT_MOUSE_BUTTON_UP) &&
        data.lengthInBytes >= 36) {
      return Sdl3RawEvent(
        type: type,
        timestamp: timestamp,
        windowId: windowId,
        button: data.getUint8(24),
        down: data.getUint8(25) != 0,
        clicks: data.getUint8(26),
        x: data.getFloat32(28, byteOrder),
        y: data.getFloat32(32, byteOrder),
      );
    }

    if (type == SDL_EVENT_MOUSE_WHEEL && data.lengthInBytes >= 44) {
      return Sdl3RawEvent(
        type: type,
        timestamp: timestamp,
        windowId: windowId,
        wheelX: data.getFloat32(24, byteOrder),
        wheelY: data.getFloat32(28, byteOrder),
        wheelDirection: data.getUint32(32, byteOrder),
        x: data.getFloat32(36, byteOrder),
        y: data.getFloat32(40, byteOrder),
      );
    }

    return Sdl3RawEvent(type: type, timestamp: timestamp, windowId: windowId);
  }

  /// Encodes this event into native memory at [ptr] using SDL3's C struct layout.
  void writeToPointer(
    ffi.Pointer<ffi.Uint8> ptr, {
    int byteLength = sdl3EventBufferSize,
    Endian? endian,
  }) {
    if (ptr == ffi.nullptr || byteLength < 4) return;
    final bytes = ptr.asTypedList(byteLength);
    bytes.fillRange(0, byteLength, 0);
    writeToBuffer(ByteData.sublistView(bytes), endian: endian);
  }

  /// Encodes this event into [data] using SDL3's C `SDL_Event` layout.
  void writeToBuffer(ByteData data, {Endian? endian}) {
    final byteOrder = endian ?? Endian.host;
    if (data.lengthInBytes < 4) return;
    data.setUint32(0, type, byteOrder);
    if (data.lengthInBytes >= 16) {
      data.setUint64(8, timestamp, byteOrder);
    }
    if (data.lengthInBytes >= 20) {
      data.setUint32(16, windowId, byteOrder);
    }

    if (_isWindowEvent(type) && data.lengthInBytes >= 28) {
      data.setInt32(20, data1, byteOrder);
      data.setInt32(24, data2, byteOrder);
    } else if ((type == SDL_EVENT_KEY_DOWN || type == SDL_EVENT_KEY_UP) &&
        data.lengthInBytes >= 38) {
      data.setInt32(24, scancode, byteOrder);
      data.setUint32(28, keycode, byteOrder);
      data.setUint16(32, mod, byteOrder);
      data.setUint8(36, down ? 1 : 0);
      data.setUint8(37, repeat ? 1 : 0);
    } else if (type == SDL_EVENT_MOUSE_MOTION && data.lengthInBytes >= 44) {
      data.setUint32(24, button, byteOrder);
      data.setFloat32(28, x, byteOrder);
      data.setFloat32(32, y, byteOrder);
      data.setFloat32(36, xRel, byteOrder);
      data.setFloat32(40, yRel, byteOrder);
    } else if ((type == SDL_EVENT_MOUSE_BUTTON_DOWN ||
            type == SDL_EVENT_MOUSE_BUTTON_UP) &&
        data.lengthInBytes >= 36) {
      data.setUint8(24, button);
      data.setUint8(25, down ? 1 : 0);
      data.setUint8(26, clicks);
      data.setFloat32(28, x, byteOrder);
      data.setFloat32(32, y, byteOrder);
    } else if (type == SDL_EVENT_MOUSE_WHEEL && data.lengthInBytes >= 44) {
      data.setFloat32(24, wheelX, byteOrder);
      data.setFloat32(28, wheelY, byteOrder);
      data.setUint32(32, wheelDirection, byteOrder);
      data.setFloat32(36, x, byteOrder);
      data.setFloat32(40, y, byteOrder);
    }
  }

  static bool _isWindowEvent(int type) => type >= 0x200 && type < 0x300;
}

/// Injectable SDL3 native call interface allowing [Sdl3Bindings] and
/// [Sdl3WindowBackend] to switch cleanly between real `dart:ffi` SDL3 symbols
/// and deterministic VM test doubles.
abstract interface class Sdl3NativeApi {
  bool init(int flags);
  int createWindow(String title, int width, int height, int flags);
  bool glSetAttribute(int attr, int value);
  int glCreateContext(int windowHandle);
  bool glMakeCurrent(int windowHandle, int contextHandle);
  bool glSwapWindow(int windowHandle);
  Sdl3RawEvent? pollEvent(ffi.Pointer<ffi.Uint8> eventBuffer);
  ({int width, int height})? getWindowSizeInPixels(int windowHandle);
  ({int width, int height})? getWindowSize(int windowHandle);
  void destroyWindow(int windowHandle);
  void glDestroyContext(int contextHandle);
  void quit();
  String getError();
  String getKeyName(int keycode);
  String getScancodeName(int scancode);
}

final class _FfiSdl3NativeApi implements Sdl3NativeApi {
  final NativeCAllocator allocator;
  final _SdlInitDart initFn;
  final _SdlCreateWindowDart createWindowFn;
  final _SdlGlSetAttributeDart glSetAttributeFn;
  final _SdlGlCreateContextDart glCreateContextFn;
  final _SdlGlMakeCurrentDart glMakeCurrentFn;
  final _SdlGlSwapWindowDart glSwapWindowFn;
  final _SdlPollEventDart pollEventFn;
  final _SdlGetWindowSizeDart getWindowSizeInPixelsFn;
  final _SdlGetWindowSizeDart? getWindowSizeFn;
  final _SdlDestroyWindowDart destroyWindowFn;
  final void Function(ffi.Pointer<ffi.Void> context) glDestroyContextFn;
  final _SdlQuitDart quitFn;
  final _SdlGetErrorDart? getErrorFn;
  final _SdlGetKeyNameDart? getKeyNameFn;
  final _SdlGetScancodeNameDart? getScancodeNameFn;

  _FfiSdl3NativeApi._({
    required this.allocator,
    required this.initFn,
    required this.createWindowFn,
    required this.glSetAttributeFn,
    required this.glCreateContextFn,
    required this.glMakeCurrentFn,
    required this.glSwapWindowFn,
    required this.pollEventFn,
    required this.getWindowSizeInPixelsFn,
    required this.getWindowSizeFn,
    required this.destroyWindowFn,
    required this.glDestroyContextFn,
    required this.quitFn,
    required this.getErrorFn,
    required this.getKeyNameFn,
    required this.getScancodeNameFn,
  });

  static _FfiSdl3NativeApi resolve(
    ffi.DynamicLibrary library,
    NativeCAllocator allocator,
  ) {
    final void Function(ffi.Pointer<ffi.Void>) glDestroyContext;
    if (library.providesSymbol('SDL_GL_DestroyContext')) {
      final destroyFn = library
          .lookupFunction<_SdlGlDestroyContextNative, _SdlGlDestroyContextDart>(
            'SDL_GL_DestroyContext',
          );
      glDestroyContext = (ctx) => destroyFn(ctx);
    } else if (library.providesSymbol('SDL_GL_DeleteContext')) {
      final deleteFn = library
          .lookupFunction<_SdlGlDeleteContextNative, _SdlGlDeleteContextDart>(
            'SDL_GL_DeleteContext',
          );
      glDestroyContext = deleteFn;
    } else {
      throw ArgumentError(
        'Missing required SDL3 symbol SDL_GL_DestroyContext / SDL_GL_DeleteContext',
      );
    }

    final getWindowSizeInPixels = library
        .lookupFunction<_SdlGetWindowSizeNative, _SdlGetWindowSizeDart>(
          'SDL_GetWindowSizeInPixels',
        );

    final getWindowSize = library.providesSymbol('SDL_GetWindowSize')
        ? library
              .lookupFunction<_SdlGetWindowSizeNative, _SdlGetWindowSizeDart>(
                'SDL_GetWindowSize',
              )
        : null;

    final getError = library.providesSymbol('SDL_GetError')
        ? library.lookupFunction<_SdlGetErrorNative, _SdlGetErrorDart>(
            'SDL_GetError',
          )
        : null;

    final getKeyName = library.providesSymbol('SDL_GetKeyName')
        ? library.lookupFunction<_SdlGetKeyNameNative, _SdlGetKeyNameDart>(
            'SDL_GetKeyName',
          )
        : null;

    final getScancodeName = library.providesSymbol('SDL_GetScancodeName')
        ? library.lookupFunction<
            _SdlGetScancodeNameNative,
            _SdlGetScancodeNameDart
          >('SDL_GetScancodeName')
        : null;

    return _FfiSdl3NativeApi._(
      allocator: allocator,
      initFn: library.lookupFunction<_SdlInitNative, _SdlInitDart>('SDL_Init'),
      createWindowFn: library
          .lookupFunction<_SdlCreateWindowNative, _SdlCreateWindowDart>(
            'SDL_CreateWindow',
          ),
      glSetAttributeFn: library
          .lookupFunction<_SdlGlSetAttributeNative, _SdlGlSetAttributeDart>(
            'SDL_GL_SetAttribute',
          ),
      glCreateContextFn: library
          .lookupFunction<_SdlGlCreateContextNative, _SdlGlCreateContextDart>(
            'SDL_GL_CreateContext',
          ),
      glMakeCurrentFn: library
          .lookupFunction<_SdlGlMakeCurrentNative, _SdlGlMakeCurrentDart>(
            'SDL_GL_MakeCurrent',
          ),
      glSwapWindowFn: library
          .lookupFunction<_SdlGlSwapWindowNative, _SdlGlSwapWindowDart>(
            'SDL_GL_SwapWindow',
          ),
      pollEventFn: library
          .lookupFunction<_SdlPollEventNative, _SdlPollEventDart>(
            'SDL_PollEvent',
          ),
      getWindowSizeInPixelsFn: getWindowSizeInPixels,
      getWindowSizeFn: getWindowSize,
      destroyWindowFn: library
          .lookupFunction<_SdlDestroyWindowNative, _SdlDestroyWindowDart>(
            'SDL_DestroyWindow',
          ),
      glDestroyContextFn: glDestroyContext,
      quitFn: library.lookupFunction<_SdlQuitNative, _SdlQuitDart>('SDL_Quit'),
      getErrorFn: getError,
      getKeyNameFn: getKeyName,
      getScancodeNameFn: getScancodeName,
    );
  }

  @override
  bool init(int flags) => initFn(flags);

  @override
  int createWindow(String title, int width, int height, int flags) {
    if (!allocator.isAvailable) return 0;
    return allocator.withUtf8(
      title,
      (titlePtr) => createWindowFn(titlePtr, width, height, flags).address,
    );
  }

  @override
  bool glSetAttribute(int attr, int value) => glSetAttributeFn(attr, value);

  @override
  int glCreateContext(int windowHandle) {
    if (windowHandle == 0) return 0;
    return glCreateContextFn(
      ffi.Pointer<ffi.Void>.fromAddress(windowHandle),
    ).address;
  }

  @override
  bool glMakeCurrent(int windowHandle, int contextHandle) {
    if (windowHandle == 0 || contextHandle == 0) return false;
    return glMakeCurrentFn(
      ffi.Pointer<ffi.Void>.fromAddress(windowHandle),
      ffi.Pointer<ffi.Void>.fromAddress(contextHandle),
    );
  }

  @override
  bool glSwapWindow(int windowHandle) {
    if (windowHandle == 0) return false;
    return glSwapWindowFn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle));
  }

  @override
  Sdl3RawEvent? pollEvent(ffi.Pointer<ffi.Uint8> eventBuffer) {
    if (eventBuffer == ffi.nullptr) return null;
    if (!pollEventFn(eventBuffer.cast<ffi.Void>())) {
      return null;
    }
    return Sdl3RawEvent.fromPointer(eventBuffer);
  }

  ({int width, int height})? _readWindowSize(
    int windowHandle,
    _SdlGetWindowSizeDart? fn,
  ) {
    if (fn == null || windowHandle == 0 || !allocator.isAvailable) {
      return null;
    }
    final intSize = ffi.sizeOf<ffi.Int>();
    final buf = allocator.allocateBytes(intSize * 2);
    try {
      final wPtr = buf.cast<ffi.Int>();
      final hPtr = ffi.Pointer<ffi.Int>.fromAddress(buf.address + intSize);
      final ok = fn(
        ffi.Pointer<ffi.Void>.fromAddress(windowHandle),
        wPtr,
        hPtr,
      );
      if (!ok) return null;
      return (width: wPtr.value, height: hPtr.value);
    } finally {
      allocator.free(buf);
    }
  }

  @override
  ({int width, int height})? getWindowSizeInPixels(int windowHandle) =>
      _readWindowSize(windowHandle, getWindowSizeInPixelsFn);

  @override
  ({int width, int height})? getWindowSize(int windowHandle) =>
      _readWindowSize(windowHandle, getWindowSizeFn ?? getWindowSizeInPixelsFn);

  @override
  void destroyWindow(int windowHandle) {
    if (windowHandle == 0) return;
    destroyWindowFn(ffi.Pointer<ffi.Void>.fromAddress(windowHandle));
  }

  @override
  void glDestroyContext(int contextHandle) {
    if (contextHandle == 0) return;
    glDestroyContextFn(ffi.Pointer<ffi.Void>.fromAddress(contextHandle));
  }

  @override
  void quit() => quitFn();

  @override
  String getError() {
    final fn = getErrorFn;
    if (fn == null) return '';
    return allocator.readCString(fn());
  }

  @override
  String getKeyName(int keycode) {
    final fn = getKeyNameFn;
    if (fn == null) return '';
    return allocator.readCString(fn(keycode));
  }

  @override
  String getScancodeName(int scancode) {
    final fn = getScancodeNameFn;
    if (fn == null) return '';
    return allocator.readCString(fn(scancode));
  }
}

/// Maps SDL3 physical scancodes, keycodes, and SDL key names to canonical web
/// `KeyboardEvent.code` strings used across `gl_volition`.
abstract final class Sdl3KeyCodeMapper {
  static const Map<int, String> _scancodeToWebCode = <int, String>{
    4: 'KeyA',
    5: 'KeyB',
    6: 'KeyC',
    7: 'KeyD',
    8: 'KeyE',
    9: 'KeyF',
    10: 'KeyG',
    11: 'KeyH',
    12: 'KeyI',
    13: 'KeyJ',
    14: 'KeyK',
    15: 'KeyL',
    16: 'KeyM',
    17: 'KeyN',
    18: 'KeyO',
    19: 'KeyP',
    20: 'KeyQ',
    21: 'KeyR',
    22: 'KeyS',
    23: 'KeyT',
    24: 'KeyU',
    25: 'KeyV',
    26: 'KeyW',
    27: 'KeyX',
    28: 'KeyY',
    29: 'KeyZ',
    30: 'Digit1',
    31: 'Digit2',
    32: 'Digit3',
    33: 'Digit4',
    34: 'Digit5',
    35: 'Digit6',
    36: 'Digit7',
    37: 'Digit8',
    38: 'Digit9',
    39: 'Digit0',
    40: 'Enter',
    41: 'Escape',
    42: 'Backspace',
    43: 'Tab',
    44: 'Space',
    45: 'Minus',
    46: 'Equal',
    47: 'BracketLeft',
    48: 'BracketRight',
    49: 'Backslash',
    50: 'Backslash',
    51: 'Semicolon',
    52: 'Quote',
    53: 'Backquote',
    54: 'Comma',
    55: 'Period',
    56: 'Slash',
    57: 'CapsLock',
    58: 'F1',
    59: 'F2',
    60: 'F3',
    61: 'F4',
    62: 'F5',
    63: 'F6',
    64: 'F7',
    65: 'F8',
    66: 'F9',
    67: 'F10',
    68: 'F11',
    69: 'F12',
    70: 'PrintScreen',
    71: 'ScrollLock',
    72: 'Pause',
    73: 'Insert',
    74: 'Home',
    75: 'PageUp',
    76: 'Delete',
    77: 'End',
    78: 'PageDown',
    79: 'ArrowRight',
    80: 'ArrowLeft',
    81: 'ArrowDown',
    82: 'ArrowUp',
    83: 'NumLock',
    84: 'NumpadDivide',
    85: 'NumpadMultiply',
    86: 'NumpadSubtract',
    87: 'NumpadAdd',
    88: 'NumpadEnter',
    89: 'Numpad1',
    90: 'Numpad2',
    91: 'Numpad3',
    92: 'Numpad4',
    93: 'Numpad5',
    94: 'Numpad6',
    95: 'Numpad7',
    96: 'Numpad8',
    97: 'Numpad9',
    98: 'Numpad0',
    99: 'NumpadDecimal',
    224: 'ControlLeft',
    225: 'ShiftLeft',
    226: 'AltLeft',
    227: 'MetaLeft',
    228: 'ControlRight',
    229: 'ShiftRight',
    230: 'AltRight',
    231: 'MetaRight',
  };

  static const Map<int, String> _asciiKeycodeToWebCode = <int, String>{
    8: 'Backspace',
    9: 'Tab',
    13: 'Enter',
    27: 'Escape',
    32: 'Space',
    39: 'Quote',
    44: 'Comma',
    45: 'Minus',
    46: 'Period',
    47: 'Slash',
    59: 'Semicolon',
    61: 'Equal',
    91: 'BracketLeft',
    92: 'Backslash',
    93: 'BracketRight',
    96: 'Backquote',
    127: 'Delete',
  };

  static const Map<String, String> _sdlNameAliases = <String, String>{
    'return': 'Enter',
    'enter': 'Enter',
    'escape': 'Escape',
    'backspace': 'Backspace',
    'tab': 'Tab',
    'space': 'Space',
    'left': 'ArrowLeft',
    'right': 'ArrowRight',
    'up': 'ArrowUp',
    'down': 'ArrowDown',
    'left shift': 'ShiftLeft',
    'right shift': 'ShiftRight',
    'left ctrl': 'ControlLeft',
    'right ctrl': 'ControlRight',
    'left alt': 'AltLeft',
    'right alt': 'AltRight',
    'left gui': 'MetaLeft',
    'right gui': 'MetaRight',
    '`': 'Backquote',
    '-': 'Minus',
    '=': 'Equal',
    '[': 'BracketLeft',
    ']': 'BracketRight',
    '\\': 'Backslash',
    ';': 'Semicolon',
    "'": 'Quote',
    ',': 'Comma',
    '.': 'Period',
    '/': 'Slash',
  };

  /// Resolves an SDL3 [scancode] and/or [keycode] into a canonical
  /// `KeyboardEvent.code` string, returning `''` if unknown.
  static String decode({
    int scancode = 0,
    int keycode = 0,
    String Function(int scancode)? scancodeNameLookup,
    String Function(int keycode)? keyNameLookup,
  }) {
    final directScancode = _scancodeToWebCode[scancode];
    if (directScancode != null) return directScancode;

    if ((keycode & SDLK_SCANCODE_MASK) != 0) {
      final maskedScancode = _scancodeToWebCode[keycode & ~SDLK_SCANCODE_MASK];
      if (maskedScancode != null) return maskedScancode;
    }

    final ascii = _decodeAsciiKeycode(keycode);
    if (ascii.isNotEmpty) return ascii;

    if (scancode != 0 && scancodeNameLookup != null) {
      final normalized = _normalizeSdlName(scancodeNameLookup(scancode));
      if (normalized.isNotEmpty) return normalized;
    }
    if (keycode != 0 && keyNameLookup != null) {
      final normalized = _normalizeSdlName(keyNameLookup(keycode));
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  static String _decodeAsciiKeycode(int keycode) {
    if (keycode >= 97 && keycode <= 122) {
      return 'Key${String.fromCharCode(keycode - 32)}';
    }
    if (keycode >= 65 && keycode <= 90) {
      return 'Key${String.fromCharCode(keycode)}';
    }
    if (keycode >= 48 && keycode <= 57) {
      return 'Digit${String.fromCharCode(keycode)}';
    }
    return _asciiKeycodeToWebCode[keycode] ?? '';
  }

  static String _normalizeSdlName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length == 1) {
      final unit = trimmed.codeUnitAt(0);
      final ascii = _decodeAsciiKeycode(unit);
      if (ascii.isNotEmpty) return ascii;
    }
    final lower = trimmed.toLowerCase();
    final alias = _sdlNameAliases[lower];
    if (alias != null) return alias;
    if (lower.startsWith('f') && lower.length <= 3) {
      final number = int.tryParse(lower.substring(1));
      if (number != null && number >= 1 && number <= 24) {
        return 'F$number';
      }
    }
    return trimmed;
  }
}

/// Loader and binding wrapper for SDL3 dynamic libraries (`SDL3.dll`,
/// `libSDL3.so.0`, `libSDL3.so`, `libSDL3.dylib`) or an injected test double.
final class Sdl3Bindings {
  /// Default SDL3 shared-library candidates probed on desktop platforms.
  static const List<String> defaultCandidateLibraries = <String>[
    'SDL3.dll',
    'libSDL3.so.0',
    'libSDL3.so',
    'libSDL3.dylib',
  ];

  /// Ordered shared-library candidates probed when loading SDL3 dynamically.
  final List<String> candidateLibraries;

  /// Bound native SDL3 API implementation, or `null` when unavailable.
  final Sdl3NativeApi? api;

  /// Loaded shared library path/name or diagnostic label, if available.
  final String? libraryName;

  /// Diagnostic error message when loading or symbol resolution failed.
  final String? loadError;

  /// Whether [api] talks to a real OS SDL3 shared library rather than a mock.
  final bool isHardwareBacked;

  /// Probes [candidateLibraries] via [openDynamicLibraryCandidates] and resolves
  /// required SDL3 symbols safely without throwing if SDL3 is absent.
  factory Sdl3Bindings({
    List<String> candidateLibraries = defaultCandidateLibraries,
    NativeCAllocator? allocator,
  }) {
    final candidates = List<String>.unmodifiable(candidateLibraries);
    final probed = openDynamicLibraryCandidates(candidates);
    final library = probed.library;
    if (library == null) {
      return Sdl3Bindings._(
        candidateLibraries: candidates,
        api: null,
        libraryName: null,
        loadError: probed.error,
        isHardwareBacked: false,
      );
    }

    try {
      final resolved = _FfiSdl3NativeApi.resolve(
        library,
        allocator ?? NativeCAllocator.instance,
      );
      return Sdl3Bindings._(
        candidateLibraries: candidates,
        api: resolved,
        libraryName: probed.name,
        loadError: null,
        isHardwareBacked: true,
      );
    } on Object catch (error) {
      return Sdl3Bindings._(
        candidateLibraries: candidates,
        api: null,
        libraryName: probed.name,
        loadError: error.toString(),
        isHardwareBacked: false,
      );
    }
  }

  /// Creates [Sdl3Bindings] backed by an injectable [Sdl3NativeApi] (or `null`
  /// to simulate an unavailable SDL3 runtime) for deterministic VM tests.
  Sdl3Bindings.forTest(
    Sdl3NativeApi? api, {
    String? libraryName = 'mock-sdl3',
    String? loadError,
    List<String> candidateLibraries = defaultCandidateLibraries,
    bool isHardwareBacked = false,
  }) : this._(
         candidateLibraries: List<String>.unmodifiable(candidateLibraries),
         api: api,
         libraryName: api == null ? null : libraryName,
         loadError: loadError,
         isHardwareBacked: api != null && isHardwareBacked,
       );

  const Sdl3Bindings._({
    required this.candidateLibraries,
    required this.api,
    required this.libraryName,
    required this.loadError,
    required this.isHardwareBacked,
  });

  /// Whether SDL3 functions are available for window creation and event pumping.
  bool get isLoaded => api != null;

  /// Decodes an SDL3 scancode/keycode pair to a canonical `KeyboardEvent.code`.
  String decodeKeyCode({int scancode = 0, int keycode = 0}) {
    final native = api;
    return Sdl3KeyCodeMapper.decode(
      scancode: scancode,
      keycode: keycode,
      scancodeNameLookup: native?.getScancodeName,
      keyNameLookup: native?.getKeyName,
    );
  }
}

/// Real SDL3 [NativeWindowBackend] managing video initialization, OpenGL /
/// GLES 3.0 context creation, buffer swaps, DPI-aware framebuffer sizing, and
/// live event decoding via a 128-byte native `SDL_Event` buffer.
final class Sdl3WindowBackend implements NativeWindowBackend {
  /// SDL3 bindings used for all native calls.
  final Sdl3Bindings bindings;

  final NativeCAllocator _allocator;
  final Set<int> _pressedMouseButtons = <int>{};

  int _windowHandle = 0;
  int _glContextHandle = 0;
  bool _sdlVideoInitialized = false;
  bool _initialized = false;
  bool _quitRequested = false;
  bool _hasFocus = true;
  int _pixelWidth = 0;
  int _pixelHeight = 0;
  int _logicalWidth = 0;
  double _devicePixelRatio = 1.0;
  double _wheelDeltaX = 0.0;
  double _wheelDeltaY = 0.0;
  String? _lastError;
  ffi.Pointer<ffi.Uint8> _eventBuffer = ffi.nullptr;

  /// Creates an [Sdl3WindowBackend] using [bindings] (probing desktop SDL3 by
  /// default) and [allocator] (defaulting to [NativeCAllocator.instance]).
  Sdl3WindowBackend({Sdl3Bindings? bindings, NativeCAllocator? allocator})
    : bindings = bindings ?? Sdl3Bindings(),
      _allocator = allocator ?? NativeCAllocator.instance;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isHardwareAvailable => _initialized && bindings.isHardwareBacked;

  @override
  int get pixelWidth => _pixelWidth;

  @override
  int get pixelHeight => _pixelHeight;

  @override
  double get devicePixelRatio => _devicePixelRatio;

  @override
  bool get quitRequested => _quitRequested;

  /// Whether the window currently holds keyboard/input focus.
  bool get hasFocus => _hasFocus;

  /// Horizontal mouse wheel delta accumulated during the latest [pumpEvents].
  double get wheelDeltaX => _wheelDeltaX;

  /// Vertical mouse wheel delta accumulated during the latest [pumpEvents].
  double get wheelDeltaY => _wheelDeltaY;

  /// Diagnostic error message from the most recent failed SDL3 operation, or
  /// `null` when healthy.
  String? get lastError => _lastError;

  /// Active native `SDL_Window*` pointer address, or `0` when closed.
  int get windowHandle => _windowHandle;

  /// Active native `SDL_GLContext` pointer address, or `0` when closed.
  int get glContextHandle => _glContextHandle;

  @override
  bool openWindow({
    required String title,
    int width = 1280,
    int height = 720,
    bool resizable = true,
    bool gles3 = true,
  }) {
    _lastError = null;
    _quitRequested = false;
    _hasFocus = true;
    _wheelDeltaX = 0.0;
    _wheelDeltaY = 0.0;
    _pressedMouseButtons.clear();

    final api = bindings.api;
    if (!bindings.isLoaded || api == null) {
      final probed = bindings.candidateLibraries.join(', ');
      final detail = bindings.loadError;
      _lastError = detail != null && detail.isNotEmpty
          ? 'SDL3 library unavailable (probed: $probed): $detail'
          : 'SDL3 library unavailable (probed: $probed)';
      return false;
    }

    if (width <= 0 || height <= 0) {
      _lastError =
          'SDL3 openWindow requires positive dimensions, got ${width}x$height';
      return false;
    }

    if (_initialized) {
      dispose();
    }

    if (!api.init(SDL_INIT_VIDEO)) {
      _lastError = _formatSdlError(api, 'SDL_Init(SDL_INIT_VIDEO) failed');
      return false;
    }
    _sdlVideoInitialized = true;

    final attributes = <(int, int)>[
      if (gles3) ...<(int, int)>[
        (SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES),
        (SDL_GL_CONTEXT_MAJOR_VERSION, 3),
        (SDL_GL_CONTEXT_MINOR_VERSION, 0),
      ],
      (SDL_GL_DOUBLEBUFFER, 1),
      (SDL_GL_DEPTH_SIZE, 24),
    ];

    for (final (attr, value) in attributes) {
      if (!api.glSetAttribute(attr, value)) {
        _lastError = _formatSdlError(
          api,
          'SDL_GL_SetAttribute($attr, $value) failed',
        );
        _cleanupFailedOpen(api);
        return false;
      }
    }

    var flags = SDL_WINDOW_OPENGL | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (resizable) {
      flags |= SDL_WINDOW_RESIZABLE;
    }

    final window = api.createWindow(title, width, height, flags);
    if (window == 0) {
      _lastError = _formatSdlError(api, 'SDL_CreateWindow failed');
      _cleanupFailedOpen(api);
      return false;
    }
    _windowHandle = window;

    final context = api.glCreateContext(window);
    if (context == 0) {
      _lastError = _formatSdlError(api, 'SDL_GL_CreateContext failed');
      _cleanupFailedOpen(api);
      return false;
    }
    _glContextHandle = context;

    if (!api.glMakeCurrent(window, context)) {
      _lastError = _formatSdlError(api, 'SDL_GL_MakeCurrent failed');
      _cleanupFailedOpen(api);
      return false;
    }

    final pixelSize = api.getWindowSizeInPixels(window);
    final logicalSize = api.getWindowSize(window);
    _logicalWidth = (logicalSize != null && logicalSize.width > 0)
        ? logicalSize.width
        : width;
    _pixelWidth = (pixelSize != null && pixelSize.width > 0)
        ? pixelSize.width
        : _logicalWidth;
    _pixelHeight = (pixelSize != null && pixelSize.height > 0)
        ? pixelSize.height
        : ((logicalSize != null && logicalSize.height > 0)
              ? logicalSize.height
              : height);
    _devicePixelRatio = _computePixelRatio(_pixelWidth, _logicalWidth);

    _ensureEventBuffer();
    _initialized = true;
    return true;
  }

  @override
  void makeCurrent() {
    final api = bindings.api;
    if (!_initialized || api == null) return;
    if (!api.glMakeCurrent(_windowHandle, _glContextHandle)) {
      _lastError = _formatSdlError(api, 'SDL_GL_MakeCurrent failed');
    }
  }

  @override
  void swapBuffers() {
    final api = bindings.api;
    if (!_initialized || api == null) return;
    if (!api.glSwapWindow(_windowHandle)) {
      _lastError = _formatSdlError(api, 'SDL_GL_SwapWindow failed');
    }
  }

  @override
  ({int width, int height}) pollSize() {
    final api = bindings.api;
    if (!_initialized || api == null) {
      return (width: _pixelWidth, height: _pixelHeight);
    }
    final logicalSize = api.getWindowSize(_windowHandle);
    if (logicalSize != null && logicalSize.width > 0) {
      _logicalWidth = logicalSize.width;
    }
    final pixelSize = api.getWindowSizeInPixels(_windowHandle);
    if (pixelSize != null && pixelSize.width > 0 && pixelSize.height > 0) {
      _pixelWidth = pixelSize.width;
      _pixelHeight = pixelSize.height;
    } else if (logicalSize != null &&
        logicalSize.width > 0 &&
        logicalSize.height > 0) {
      _pixelWidth = logicalSize.width;
      _pixelHeight = logicalSize.height;
    }
    _devicePixelRatio = _computePixelRatio(_pixelWidth, _logicalWidth);
    return (width: _pixelWidth, height: _pixelHeight);
  }

  @override
  void pumpEvents(
    ScriptedInput input, {
    void Function(int width, int height)? onResize,
  }) {
    final api = bindings.api;
    if (!_initialized || api == null) return;

    _wheelDeltaX = 0.0;
    _wheelDeltaY = 0.0;
    _ensureEventBuffer();

    while (true) {
      final event = api.pollEvent(_eventBuffer);
      if (event == null) break;
      _dispatchEvent(api, event, input, onResize);
    }
  }

  @override
  void dispose() {
    _freeEventBuffer();
    final api = bindings.api;
    if (api != null) {
      if (_glContextHandle != 0) {
        api.glDestroyContext(_glContextHandle);
        _glContextHandle = 0;
      }
      if (_windowHandle != 0) {
        api.destroyWindow(_windowHandle);
        _windowHandle = 0;
      }
      if (_sdlVideoInitialized) {
        api.quit();
        _sdlVideoInitialized = false;
      }
    } else {
      _glContextHandle = 0;
      _windowHandle = 0;
      _sdlVideoInitialized = false;
    }
    _pressedMouseButtons.clear();
    _initialized = false;
  }

  void _dispatchEvent(
    Sdl3NativeApi api,
    Sdl3RawEvent event,
    ScriptedInput input,
    void Function(int width, int height)? onResize,
  ) {
    switch (event.type) {
      case SDL_EVENT_QUIT:
        _quitRequested = true;

      case SDL_EVENT_WINDOW_RESIZED:
        _handleWindowResize(
          api,
          logicalWidth: event.data1,
          logicalHeight: event.data2,
          pixelSizeEvent: false,
          onResize: onResize,
        );

      case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        _handleWindowResize(
          api,
          logicalWidth: event.data1,
          logicalHeight: event.data2,
          pixelSizeEvent: true,
          onResize: onResize,
        );

      case SDL_EVENT_WINDOW_FOCUS_GAINED:
        _hasFocus = true;

      case SDL_EVENT_WINDOW_FOCUS_LOST:
        _hasFocus = false;

      case SDL_EVENT_KEY_DOWN:
        final code = bindings.decodeKeyCode(
          scancode: event.scancode,
          keycode: event.keycode,
        );
        if (code.isNotEmpty) {
          input.press(code);
        }

      case SDL_EVENT_KEY_UP:
        final code = bindings.decodeKeyCode(
          scancode: event.scancode,
          keycode: event.keycode,
        );
        if (code.isNotEmpty) {
          input.release(code);
        }

      case SDL_EVENT_MOUSE_MOTION:
        input.pointerX = event.x * _devicePixelRatio;
        input.pointerY = event.y * _devicePixelRatio;

      case SDL_EVENT_MOUSE_BUTTON_DOWN:
        input.pointerX = event.x * _devicePixelRatio;
        input.pointerY = event.y * _devicePixelRatio;
        if (event.button > 0) {
          _pressedMouseButtons.add(event.button);
        }
        if (!input.pointerDown) {
          input.pointerPressed = true;
        }
        input.pointerDown = true;

      case SDL_EVENT_MOUSE_BUTTON_UP:
        input.pointerX = event.x * _devicePixelRatio;
        input.pointerY = event.y * _devicePixelRatio;
        if (event.button > 0) {
          _pressedMouseButtons.remove(event.button);
        } else {
          _pressedMouseButtons.clear();
        }
        if (_pressedMouseButtons.isEmpty) {
          if (input.pointerDown) {
            input.pointerReleased = true;
          }
          input.pointerDown = false;
        }

      case SDL_EVENT_MOUSE_WHEEL:
        final sign = event.wheelDirection == SDL_MOUSEWHEEL_FLIPPED
            ? -1.0
            : 1.0;
        _wheelDeltaX += event.wheelX * sign;
        _wheelDeltaY += event.wheelY * sign;
    }
  }

  void _handleWindowResize(
    Sdl3NativeApi api, {
    required int logicalWidth,
    required int logicalHeight,
    required bool pixelSizeEvent,
    void Function(int width, int height)? onResize,
  }) {
    final prevW = _pixelWidth;
    final prevH = _pixelHeight;

    int nextW = prevW;
    int nextH = prevH;

    if (pixelSizeEvent) {
      final logical = api.getWindowSize(_windowHandle);
      if (logical != null && logical.width > 0) {
        _logicalWidth = logical.width;
      }
      if (logicalWidth > 0 && logicalHeight > 0) {
        nextW = logicalWidth;
        nextH = logicalHeight;
      }
    } else {
      if (logicalWidth > 0) {
        _logicalWidth = logicalWidth;
      }
      final queriedPixels = api.getWindowSizeInPixels(_windowHandle);
      if (queriedPixels != null &&
          queriedPixels.width > 0 &&
          queriedPixels.height > 0 &&
          (queriedPixels.width != prevW || queriedPixels.height != prevH)) {
        nextW = queriedPixels.width;
        nextH = queriedPixels.height;
      } else if (logicalWidth > 0 && logicalHeight > 0) {
        nextW = (logicalWidth * _devicePixelRatio).round();
        nextH = (logicalHeight * _devicePixelRatio).round();
      }
    }

    if (nextW <= 0 || nextH <= 0) return;

    _pixelWidth = nextW;
    _pixelHeight = nextH;
    _devicePixelRatio = _computePixelRatio(_pixelWidth, _logicalWidth);

    if (nextW != prevW || nextH != prevH) {
      onResize?.call(nextW, nextH);
    }
  }

  void _ensureEventBuffer() {
    if (_eventBuffer == ffi.nullptr && _allocator.isAvailable) {
      _eventBuffer = _allocator.allocateBytes(sdl3EventBufferSize);
    }
  }

  void _freeEventBuffer() {
    if (_eventBuffer != ffi.nullptr) {
      _allocator.free(_eventBuffer);
      _eventBuffer = ffi.nullptr;
    }
  }

  void _cleanupFailedOpen(Sdl3NativeApi api) {
    _freeEventBuffer();
    if (_glContextHandle != 0) {
      api.glDestroyContext(_glContextHandle);
      _glContextHandle = 0;
    }
    if (_windowHandle != 0) {
      api.destroyWindow(_windowHandle);
      _windowHandle = 0;
    }
    if (_sdlVideoInitialized) {
      api.quit();
      _sdlVideoInitialized = false;
    }
    _initialized = false;
  }

  static double _computePixelRatio(int pixelWidth, int logicalWidth) {
    if (pixelWidth <= 0 || logicalWidth <= 0) return 1.0;
    final ratio = pixelWidth / logicalWidth;
    return ratio < 1.0 ? 1.0 : ratio;
  }

  static String _formatSdlError(Sdl3NativeApi api, String prefix) {
    final err = api.getError().trim();
    return err.isEmpty ? prefix : '$prefix: $err';
  }
}
