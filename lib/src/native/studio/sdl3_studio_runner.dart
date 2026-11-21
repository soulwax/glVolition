/// Native AOT SDL3 + GLES3 Desktop Studio Runner (`[Wave G5]`):
/// Opens a native OS window via [Sdl3WindowBackend], binds [Gles3FfiDevice]
/// (or an injected [GpuDevice] for headless testing), pumps OS input into
/// [VoxInput], drives [NativeStudioApp], and swaps buffers at native speed.
library;

import 'package:pixeldart/rendering/webgl/device_api.dart';

import '../../../gl_volition.dart';
import '../../studio/studio.dart';
import '../gles3_bindings.dart';
import '../gles3_ffi_device.dart';
import '../native_bindings.dart';
import '../native_ffi_transport.dart';
import '../sdl3_bindings.dart';
import 'native_studio_app.dart';

/// Result of attempting to run the native SDL3 Studio desktop loop.
final class NativeStudioLaunchResult {
  final bool launched;
  final int framesRendered;
  final String? diagnostic;

  const NativeStudioLaunchResult({
    required this.launched,
    this.framesRendered = 0,
    this.diagnostic,
  });
}

/// Bridges pointer/mouse state into a per-frame [VoxInput] snapshot for
/// [StudioWorkspaceShell].
final class NativeStudioInputMapper {
  double _prevMouseX = 0.0;
  double _prevMouseY = 0.0;
  bool _wasDown = false;

  VoxInput sampleRaw({
    required double mouseX,
    required double mouseY,
    required bool isLeftDown,
    double scrollDeltaY = 0.0,
  }) {
    final dx = mouseX - _prevMouseX;
    final dy = mouseY - _prevMouseY;
    _prevMouseX = mouseX;
    _prevMouseY = mouseY;

    final clicked = isLeftDown && !_wasDown;
    final released = !isLeftDown && _wasDown;
    _wasDown = isLeftDown;

    return VoxInput(
      mouseX: mouseX,
      mouseY: mouseY,
      mouseDeltaX: dx,
      mouseDeltaY: dy,
      isMouseDown: isLeftDown,
      wasMouseClicked: clicked,
      wasMouseReleased: released,
      scrollDeltaY: scrollDeltaY,
    );
  }

  VoxInput sample(ScriptedInput input, {double scrollDeltaY = 0.0}) =>
      sampleRaw(
        mouseX: input.pointerX,
        mouseY: input.pointerY,
        isLeftDown: input.pointerDown,
        scrollDeltaY: scrollDeltaY,
      );
}

/// Native AOT SDL3 + GLES3 Studio desktop runner (`[Wave G5]`).
final class Sdl3StudioRunner {
  final StudioWorkspaceShell shell;
  final NativeWindowBackend windowBackend;
  final GpuDevice device;
  final String title;
  final int initialWidth;
  final int initialHeight;

  Sdl3StudioRunner({
    required this.shell,
    required this.windowBackend,
    required this.device,
    this.title = 'Volition Studio (AOT)',
    this.initialWidth = 1440,
    this.initialHeight = 900,
  });

  /// Attempts to load SDL3 + GLES3/ANGLE shared libraries and run the native
  /// AOT Studio window. Returns `launched: false` with a diagnostic if native
  /// libraries are unavailable so the CLI can fall back cleanly.
  static Future<NativeStudioLaunchResult> tryLaunchHardware({
    required StudioWorkspaceShell shell,
    String title = 'Volition Studio (AOT)',
    int width = 1440,
    int height = 900,
    int? maxFrames,
  }) async {
    final sdlBindings = Sdl3Bindings();
    if (!sdlBindings.isLoaded) {
      return const NativeStudioLaunchResult(
        launched: false,
        diagnostic:
            'SDL3 native library not found on PATH; falling back to web Studio.',
      );
    }
    final glLoader = DynamicLibraryGlLoader();
    if (!glLoader.isAvailable) {
      return const NativeStudioLaunchResult(
        launched: false,
        diagnostic:
            'OpenGL ES 3.0 / ANGLE library not found; falling back to web Studio.',
      );
    }

    final window = Sdl3WindowBackend(bindings: sdlBindings);
    final glesDevice = Gles3FfiDevice(FfiGles3Api(glLoader), width, height);
    final runner = Sdl3StudioRunner(
      shell: shell,
      windowBackend: window,
      device: glesDevice,
      title: title,
      initialWidth: width,
      initialHeight: height,
    );
    return runner.run(maxFrames: maxFrames);
  }

  /// Opens the native window and runs the Studio frame loop until quit or
  /// [maxFrames] is reached.
  Future<NativeStudioLaunchResult> run({int? maxFrames}) async {
    final opened = windowBackend.openWindow(
      title: title,
      width: initialWidth,
      height: initialHeight,
    );
    if (!opened) {
      return const NativeStudioLaunchResult(
        launched: false,
        diagnostic: 'Failed to open native SDL3 window.',
      );
    }

    windowBackend.makeCurrent();
    final app = NativeStudioApp(shell: shell, device: device);
    final input = ScriptedInput();
    final mapper = NativeStudioInputMapper();
    final sw = Stopwatch()..start();
    var lastUs = sw.elapsedMicroseconds;
    var rendered = 0;

    try {
      while (!windowBackend.quitRequested) {
        if (maxFrames != null && rendered >= maxFrames) break;
        windowBackend.pumpEvents(input);
        if (windowBackend.quitRequested) break;

        final size = windowBackend.pollSize();
        final w = size.width > 0 ? size.width : initialWidth;
        final h = size.height > 0 ? size.height : initialHeight;

        final nowUs = sw.elapsedMicroseconds;
        final dt = ((nowUs - lastUs) / 1e6).clamp(1 / 240.0, 0.1);
        lastUs = nowUs;

        final scrollY = windowBackend is Sdl3WindowBackend
            ? (windowBackend as Sdl3WindowBackend).wheelDeltaY
            : 0.0;
        final voxInput = mapper.sample(input, scrollDeltaY: scrollY);

        app.stepFrame(
          input: voxInput,
          pixelWidth: w,
          pixelHeight: h,
          dtSeconds: dt,
        );
        windowBackend.swapBuffers();
        rendered++;

        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      app.dispose();
      windowBackend.dispose();
    }

    return NativeStudioLaunchResult(launched: true, framesRendered: rendered);
  }
}
