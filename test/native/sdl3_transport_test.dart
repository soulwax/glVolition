import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../../example/dungeon_2d/game.dart';

final class _MockSdl3NativeApi implements Sdl3NativeApi {
  final List<String> callLog = <String>[];
  final Map<int, int> glAttributes = <int, int>{};
  final ListQueue<Sdl3RawEvent> eventQueue = ListQueue<Sdl3RawEvent>();

  bool initResult = true;
  int createWindowResult = 0x1001;
  bool setAttributeResult = true;
  int createContextResult = 0x2001;
  bool makeCurrentResult = true;
  bool swapWindowResult = true;
  String errorText = '';

  int logicalWidth = 800;
  int logicalHeight = 600;
  int pixelWidth = 1600;
  int pixelHeight = 1200;

  int lastWindowFlags = 0;
  int swapCount = 0;
  int makeCurrentCount = 0;
  bool destroyedContext = false;
  bool destroyedWindow = false;
  bool quitCalled = false;

  @override
  bool init(int flags) {
    callLog.add('SDL_Init($flags)');
    return initResult;
  }

  @override
  int createWindow(String title, int width, int height, int flags) {
    callLog.add('SDL_CreateWindow($title, $width, $height, $flags)');
    lastWindowFlags = flags;
    return createWindowResult;
  }

  @override
  bool glSetAttribute(int attr, int value) {
    callLog.add('SDL_GL_SetAttribute($attr, $value)');
    glAttributes[attr] = value;
    return setAttributeResult;
  }

  @override
  int glCreateContext(int windowHandle) {
    callLog.add('SDL_GL_CreateContext($windowHandle)');
    return createContextResult;
  }

  @override
  bool glMakeCurrent(int windowHandle, int contextHandle) {
    makeCurrentCount++;
    callLog.add('SDL_GL_MakeCurrent($windowHandle, $contextHandle)');
    return makeCurrentResult;
  }

  @override
  bool glSwapWindow(int windowHandle) {
    swapCount++;
    callLog.add('SDL_GL_SwapWindow($windowHandle)');
    return swapWindowResult;
  }

  @override
  Sdl3RawEvent? pollEvent(ffi.Pointer<ffi.Uint8> eventBuffer) {
    if (eventQueue.isEmpty) return null;
    final next = eventQueue.removeFirst();
    if (eventBuffer != ffi.nullptr) {
      // Exercise the real 128-byte native SDL_Event struct layout round-trip.
      next.writeToPointer(eventBuffer);
      return Sdl3RawEvent.fromPointer(eventBuffer);
    }
    return next;
  }

  @override
  ({int width, int height})? getWindowSizeInPixels(int windowHandle) =>
      (width: pixelWidth, height: pixelHeight);

  @override
  ({int width, int height})? getWindowSize(int windowHandle) =>
      (width: logicalWidth, height: logicalHeight);

  @override
  void destroyWindow(int windowHandle) {
    destroyedWindow = true;
    callLog.add('SDL_DestroyWindow($windowHandle)');
  }

  @override
  void glDestroyContext(int contextHandle) {
    destroyedContext = true;
    callLog.add('SDL_GL_DestroyContext($contextHandle)');
  }

  @override
  void quit() {
    quitCalled = true;
    callLog.add('SDL_Quit()');
  }

  @override
  String getError() => errorText;

  @override
  String getKeyName(int keycode) => keycode == 0x20 ? 'Space' : '';

  @override
  String getScancodeName(int scancode) =>
      scancode == SDL_SCANCODE_F12 ? 'F12' : '';
}

void main() {
  group('Sdl3Bindings & Sdl3WindowBackend', () {
    test(
      'missing SDL3 shared library fails cleanly with actionable lastError',
      () {
        final bindings = Sdl3Bindings(
          candidateLibraries: const [
            'definitely_missing_SDL3_w9.dll',
            'libSDL3_missing_w9.so.0',
          ],
        );
        expect(bindings.isLoaded, isFalse);
        expect(bindings.isHardwareBacked, isFalse);
        expect(bindings.loadError, isNotNull);

        final backend = Sdl3WindowBackend(bindings: bindings);
        final opened = backend.openWindow(
          title: 'glVolition Missing SDL3',
          width: 1280,
          height: 720,
        );

        expect(opened, isFalse);
        expect(backend.isInitialized, isFalse);
        expect(backend.isHardwareAvailable, isFalse);
        expect(backend.lastError, isNotNull);
        expect(backend.lastError, contains('definitely_missing_SDL3_w9.dll'));
        expect(backend.lastError, contains('libSDL3_missing_w9.so.0'));

        // Calling lifecycle methods on an uninitialized backend never throws.
        backend.makeCurrent();
        backend.swapBuffers();
        expect(backend.pollSize(), (width: 0, height: 0));
        backend.pumpEvents(ScriptedInput());
        backend.dispose();
      },
    );

    test('partial SDL3 context failure cleans up window and SDL_Quit', () {
      final api = _MockSdl3NativeApi()
        ..createContextResult = 0
        ..errorText = 'GLES 3.0 driver unavailable';
      final backend = Sdl3WindowBackend(bindings: Sdl3Bindings.forTest(api));

      final opened = backend.openWindow(title: 'Fail Context');
      expect(opened, isFalse);
      expect(backend.isInitialized, isFalse);
      expect(backend.lastError, contains('GLES 3.0 driver unavailable'));
      expect(api.destroyedWindow, isTrue);
      expect(api.quitCalled, isTrue);
    });

    test(
      '128-byte native SDL_Event buffer decoding and keycode mapping work accurately',
      () {
        final allocator = NativeCAllocator.instance;
        expect(allocator.isAvailable, isTrue);

        final buffer = allocator.allocateBytes(sdl3EventBufferSize);
        try {
          const keyEvent = Sdl3RawEvent(
            type: SDL_EVENT_KEY_DOWN,
            windowId: 1,
            scancode: SDL_SCANCODE_W,
            keycode: 0x77,
            down: true,
            repeat: true,
          );
          keyEvent.writeToPointer(buffer);
          final decodedKey = Sdl3RawEvent.fromPointer(buffer);
          expect(decodedKey.type, SDL_EVENT_KEY_DOWN);
          expect(decodedKey.scancode, SDL_SCANCODE_W);
          expect(decodedKey.keycode, 0x77);
          expect(decodedKey.down, isTrue);
          expect(decodedKey.repeat, isTrue);

          const wheelEvent = Sdl3RawEvent(
            type: SDL_EVENT_MOUSE_WHEEL,
            wheelX: 1.5,
            wheelY: -3.0,
            wheelDirection: SDL_MOUSEWHEEL_FLIPPED,
            x: 320.0,
            y: 240.0,
          );
          wheelEvent.writeToPointer(buffer);
          final decodedWheel = Sdl3RawEvent.fromPointer(buffer);
          expect(decodedWheel.type, SDL_EVENT_MOUSE_WHEEL);
          expect(decodedWheel.wheelX, closeTo(1.5, 1e-6));
          expect(decodedWheel.wheelY, closeTo(-3.0, 1e-6));
          expect(decodedWheel.wheelDirection, SDL_MOUSEWHEEL_FLIPPED);
          expect(decodedWheel.x, closeTo(320.0, 1e-6));
          expect(decodedWheel.y, closeTo(240.0, 1e-6));
        } finally {
          allocator.free(buffer);
        }

        expect(
          Sdl3KeyCodeMapper.decode(scancode: SDL_SCANCODE_W),
          equals('KeyW'),
        );
        expect(
          Sdl3KeyCodeMapper.decode(scancode: SDL_SCANCODE_SPACE),
          equals('Space'),
        );
        expect(
          Sdl3KeyCodeMapper.decode(scancode: SDL_SCANCODE_LEFT),
          equals('ArrowLeft'),
        );
        expect(
          Sdl3KeyCodeMapper.decode(scancode: SDL_SCANCODE_ESCAPE),
          equals('Escape'),
        );
        expect(
          Sdl3KeyCodeMapper.decode(keycode: 0x61), // 'a'
          equals('KeyA'),
        );
        expect(
          Sdl3KeyCodeMapper.decode(
            keycode: SDLK_SCANCODE_MASK | SDL_SCANCODE_D,
          ),
          equals('KeyD'),
        );
      },
    );

    test(
      'full Sdl3WindowBackend + NativeDesktopBridge lifecycle with mock Sdl3NativeApi',
      () async {
        final api = _MockSdl3NativeApi();
        final bindings = Sdl3Bindings.forTest(api);
        final backend = Sdl3WindowBackend(bindings: bindings);

        expect(
          backend.openWindow(
            title: 'glVolition Desktop',
            width: 800,
            height: 600,
            resizable: true,
            gles3: true,
          ),
          isTrue,
        );
        expect(backend.isInitialized, isTrue);
        expect(backend.isHardwareAvailable, isFalse);
        expect(backend.pixelWidth, 1600);
        expect(backend.pixelHeight, 1200);
        expect(backend.devicePixelRatio, closeTo(2.0, 1e-6));
        expect(api.makeCurrentCount, 1);
        expect(
          api.glAttributes[SDL_GL_CONTEXT_PROFILE_MASK],
          SDL_GL_CONTEXT_PROFILE_ES,
        );
        expect(api.glAttributes[SDL_GL_CONTEXT_MAJOR_VERSION], 3);
        expect(api.glAttributes[SDL_GL_CONTEXT_MINOR_VERSION], 0);
        expect(api.glAttributes[SDL_GL_DOUBLEBUFFER], 1);
        expect(api.glAttributes[SDL_GL_DEPTH_SIZE], 24);
        expect(
          api.lastWindowFlags,
          SDL_WINDOW_OPENGL |
              SDL_WINDOW_RESIZABLE |
              SDL_WINDOW_HIGH_PIXEL_DENSITY,
        );

        final transport = NativeGlTransport(
          procLoader: StubGlProcLoader(
            supportedSymbols: const {'glUseProgram'},
          ),
        );
        final device = transport.createDevice();
        final runner = await NativeEngineHost.boot(
          device: device,
          width: backend.pixelWidth,
          height: backend.pixelHeight,
          windowBackend: backend,
          initialScene: buildDungeon2DScene(),
        );
        final bridge = NativeDesktopBridge(
          runner: runner,
          transport: transport,
          windowBackend: backend,
        );

        // Frame 1: keyboard press, pointer move/down, and mouse wheel.
        api.eventQueue.addAll(const [
          Sdl3RawEvent(
            type: SDL_EVENT_KEY_DOWN,
            scancode: SDL_SCANCODE_W,
            down: true,
          ),
          Sdl3RawEvent(type: SDL_EVENT_MOUSE_MOTION, x: 100.0, y: 50.0),
          Sdl3RawEvent(
            type: SDL_EVENT_MOUSE_BUTTON_DOWN,
            button: 1,
            down: true,
            clicks: 1,
            x: 100.0,
            y: 50.0,
          ),
          Sdl3RawEvent(type: SDL_EVENT_MOUSE_WHEEL, wheelX: -0.5, wheelY: 2.0),
        ]);

        final stats1 = bridge.stepAndRender(1 / 60);
        expect(stats1, isNotNull);
        expect(stats1!.drawCalls, greaterThan(0));
        expect(api.swapCount, 1);
        expect(runner.host.input.isDown('KeyW'), isTrue);
        expect(runner.host.input.pointerDown, isTrue);
        expect(runner.host.input.pointerX, closeTo(200.0, 1e-4));
        expect(runner.host.input.pointerY, closeTo(100.0, 1e-4));
        expect(backend.wheelDeltaX, closeTo(-0.5, 1e-4));
        expect(backend.wheelDeltaY, closeTo(2.0, 1e-4));

        // Frame 2: key repeat keeps KeyW held without re-triggering wasPressed,
        // Space pressed, and window pixel size changed to 1920x1080.
        api.logicalWidth = 960;
        api.logicalHeight = 540;
        api.pixelWidth = 1920;
        api.pixelHeight = 1080;
        api.eventQueue.addAll(const [
          Sdl3RawEvent(
            type: SDL_EVENT_KEY_DOWN,
            scancode: SDL_SCANCODE_W,
            down: true,
            repeat: true,
          ),
          Sdl3RawEvent(
            type: SDL_EVENT_KEY_DOWN,
            scancode: SDL_SCANCODE_SPACE,
            down: true,
          ),
          Sdl3RawEvent(
            type: SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            data1: 1920,
            data2: 1080,
          ),
        ]);

        final stats2 = bridge.stepAndRender(1 / 60);
        expect(stats2, isNotNull);
        expect(api.swapCount, 2);
        expect(runner.host.input.isDown('KeyW'), isTrue);
        expect(runner.host.input.isDown('Space'), isTrue);
        expect(backend.wheelDeltaY, closeTo(0.0, 1e-6));
        expect(backend.pixelWidth, 1920);
        expect(backend.pixelHeight, 1080);
        expect(runner.host.graphics.viewportWidth, 1920);
        expect(runner.host.graphics.viewportHeight, 1080);

        // Frame 3: focus lost/gained, key up, mouse button up.
        api.eventQueue.addAll(const [
          Sdl3RawEvent(type: SDL_EVENT_WINDOW_FOCUS_LOST),
          Sdl3RawEvent(type: SDL_EVENT_WINDOW_FOCUS_GAINED),
          Sdl3RawEvent(type: SDL_EVENT_KEY_UP, scancode: SDL_SCANCODE_W),
          Sdl3RawEvent(
            type: SDL_EVENT_MOUSE_BUTTON_UP,
            button: 1,
            x: 120.0,
            y: 60.0,
          ),
        ]);

        final stats3 = bridge.stepAndRender(1 / 60);
        expect(stats3, isNotNull);
        expect(api.swapCount, 3);
        expect(backend.hasFocus, isTrue);
        expect(runner.host.input.isDown('KeyW'), isFalse);
        expect(runner.host.input.pointerDown, isFalse);

        // Frame 4: SDL_EVENT_QUIT ends the loop without swapping.
        api.eventQueue.add(const Sdl3RawEvent(type: SDL_EVENT_QUIT));
        expect(bridge.stepAndRender(1 / 60), isNull);
        expect(bridge.isQuitRequested, isTrue);
        expect(backend.quitRequested, isTrue);
        expect(api.swapCount, 3);

        // Disposal releases GPU resources, GL context, window, and SDL.
        bridge.dispose();
        expect(backend.isInitialized, isFalse);
        expect(api.destroyedContext, isTrue);
        expect(api.destroyedWindow, isTrue);
        expect(api.quitCalled, isTrue);
        expect(device.liveObjectCount, 0);
      },
    );

    test(
      'Sdl3EventPump supports keyRepeat, mouseWheel, windowResize, focus/blur',
      () {
        final pump = Sdl3EventPump();
        final input = ScriptedInput();
        final resizes = <(int, int)>[];

        pump.enqueueAll(const [
          Sdl3InputEvent(kind: Sdl3EventKind.keyDown, keyCode: 'KeyA'),
          Sdl3InputEvent(
            kind: Sdl3EventKind.keyRepeat,
            keyCode: 'KeyA',
            repeat: true,
          ),
          Sdl3InputEvent(
            kind: Sdl3EventKind.mouseWheel,
            wheelX: 1.0,
            wheelY: -2.5,
          ),
          Sdl3InputEvent(
            kind: Sdl3EventKind.windowResize,
            width: 1024,
            height: 768,
          ),
          Sdl3InputEvent(kind: Sdl3EventKind.windowBlur),
        ]);

        expect(
          pump.pumpInto(input, onResize: (w, h) => resizes.add((w, h))),
          isTrue,
        );
        expect(input.isDown('KeyA'), isTrue);
        expect(input.wasPressed('KeyA'), isTrue);
        expect(pump.wheelDeltaX, closeTo(1.0, 1e-6));
        expect(pump.wheelDeltaY, closeTo(-2.5, 1e-6));
        expect(resizes, equals([(1024, 768)]));
        expect(pump.hasWindowFocus, isFalse);

        input.endFrame();
        pump.enqueueAll(const [
          Sdl3InputEvent(
            kind: Sdl3EventKind.keyRepeat,
            keyCode: 'KeyA',
            repeat: true,
          ),
          Sdl3InputEvent(kind: Sdl3EventKind.windowFocus),
        ]);
        expect(pump.pumpInto(input), isTrue);
        expect(input.isDown('KeyA'), isTrue);
        expect(input.wasPressed('KeyA'), isFalse);
        expect(pump.hasWindowFocus, isTrue);

        // Verify decodeRawEventPacket supports new event kinds at indices >= 6.
        final wheelPacket = ByteData(24)
          ..setUint32(0, Sdl3EventKind.mouseWheel.index, Endian.little)
          ..setInt32(4, 0, Endian.little)
          ..setFloat64(8, 0.25, Endian.little)
          ..setFloat64(16, -1.5, Endian.little);
        final decodedWheel = Sdl3EventPump.decodeRawEventPacket(wheelPacket);
        expect(decodedWheel, isNotNull);
        expect(decodedWheel!.kind, Sdl3EventKind.mouseWheel);
        expect(decodedWheel.wheelX, closeTo(0.25, 1e-6));
        expect(decodedWheel.wheelY, closeTo(-1.5, 1e-6));
      },
    );
  });
}
