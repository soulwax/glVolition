import 'dart:typed_data';

import '../../gl_volition.dart';

/// Optional lifecycle mixin/interface for native [AudioDevice] implementations
/// that hold OS mixer threads or FFI audio stream handles requiring cleanup on
/// host shutdown.
abstract interface class DisposableNativeAudioDevice implements AudioDevice {
  /// Stops active voices and releases any underlying native audio resources.
  void dispose();
}

/// Abstracts native window creation, GL/GLES3 context activation, frame
/// presentation, and OS event pumping so `gl_volition` desktop hosts can swap
/// hardware SDL3 bindings and deterministic VM test doubles cleanly.
abstract interface class NativeWindowBackend {
  /// Whether the native window and graphics context are currently initialized.
  bool get isInitialized;

  /// Whether a hardware-backed OS window/GLES context is active (as opposed to
  /// a headless test backend).
  bool get isHardwareAvailable;

  /// Current drawable framebuffer width in physical pixels.
  int get pixelWidth;

  /// Current drawable framebuffer height in physical pixels.
  int get pixelHeight;

  /// Current display pixel ratio (`pixelWidth / cssWidth`), always `>= 1.0`.
  double get devicePixelRatio;

  /// Whether the OS window has received a close/quit request.
  bool get quitRequested;

  /// Creates the OS window and initializes its OpenGL/GLES3 context.
  ///
  /// Returns `true` on success or `false` if initialization failed (for
  /// example when the SDL3 runtime library or display server is unavailable).
  bool openWindow({
    required String title,
    int width = 1280,
    int height = 720,
    bool resizable = true,
    bool gles3 = true,
  });

  /// Makes this window's OpenGL/GLES3 context current on the calling thread.
  void makeCurrent();

  /// Presents the backbuffer (`SDL_GL_SwapWindow`).
  void swapBuffers();

  /// Queries the latest drawable framebuffer size in pixels.
  ({int width, int height}) pollSize();

  /// Drains pending OS events into [input], invoking [onResize] whenever the
  /// drawable pixel size changes.
  void pumpEvents(
    ScriptedInput input, {
    void Function(int width, int height)? onResize,
  });

  /// Destroys the context/window and shuts down backend state idempotently.
  void dispose();
}

/// Abstracts native OpenGL ES 3.0 / EGL / ANGLE procedure lookup.
abstract interface class GlProcBindings {
  /// Whether a backing shared library or context proc table is available.
  bool get isLoaded;

  /// Human-readable name of the active shared library or backend table.
  String? get libraryName;

  /// Returns `true` when [name] is exported or resolvable.
  bool hasSymbol(String name);

  /// Returns the native function pointer address for [name], or `0` when
  /// unavailable.
  int lookupAddress(String name);
}

/// Audio stream format requested when opening a [NativeAudioSink].
final class NativeAudioConfig {
  final int sampleRate;
  final int channels;
  final int framesPerBuffer;

  const NativeAudioConfig({
    this.sampleRate = 48000,
    this.channels = 2,
    this.framesPerBuffer = 512,
  });
}

/// Low-level PCM output sink used by [NativeAudioDevice] to stream mixed float
/// frames to OS hardware or an inspectable VM capture buffer.
abstract interface class NativeAudioSink {
  /// Whether the audio sink stream is currently open.
  bool get isOpen;

  /// Whether frames are written to real OS audio hardware (`false` in test/CI
  /// software capture sinks).
  bool get isHardwareBacked;

  /// Active stream format configuration.
  NativeAudioConfig get config;

  /// Diagnostic backend name (for example `'sdl3-audio'` or `'software-pcm'`).
  String? get backendName;

  /// Last initialization/write diagnostic message, or `null` when healthy.
  String? get lastError;

  /// Opens the stream with [config], returning `false` on failure without
  /// throwing uncaught native errors.
  bool open(NativeAudioConfig config);

  /// Writes [samples] (interleaved 32-bit float frames) and returns the number
  /// of scalar samples consumed.
  int writeInterleavedFloat32(Float32List samples);

  /// Closes the audio sink and releases underlying handles idempotently.
  void close();
}
