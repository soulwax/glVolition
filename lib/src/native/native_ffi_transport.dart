import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import '../../gl_volition.dart';
import 'native_host.dart';

/// Immutable record of a single low-level GL command forwarded from
/// [GlesDevice] through [NativeGlTransport].
final class GlCommandRecord {
  /// Monotonically increasing 1-based dispatch sequence number.
  final int sequence;

  /// GL command name (for example `glDrawElements` or `glBindBuffer`).
  final String command;

  /// Unmodifiable snapshot of arguments passed to [command].
  final List<Object?> args;

  /// Creates an immutable [GlCommandRecord], copying [args] into an
  /// unmodifiable list.
  GlCommandRecord({
    required this.sequence,
    required this.command,
    required List<Object?> args,
  }) : args = List<Object?>.unmodifiable(args);

  @override
  String toString() => 'GlCommandRecord(#$sequence $command($args))';
}

/// Abstracts native OpenGL ES / EGL / SDL3 dynamic library symbol lookup so
/// [NativeGlTransport] can probe entrypoints on desktop hosts or run against
/// a software stub in VM/CI tests.
abstract interface class NativeGlProcLoader {
  /// Whether a backing native GL library or stub proc table is available.
  bool get isAvailable;

  /// Name of the loaded shared library or mock table, if available.
  String? get libraryName;

  /// Returns `true` if the GL entrypoint [name] is exported by this loader.
  bool hasSymbol(String name);
}

/// [NativeGlProcLoader] backed by `dart:ffi` [ffi.DynamicLibrary.open].
///
/// Probes [candidateLibraries] in order and wraps every `DynamicLibrary.open`
/// call safely so environments without native GL/SDL3 shared libraries report
/// [isAvailable] as `false` instead of throwing.
final class DynamicLibraryGlLoader implements NativeGlProcLoader {
  /// Default shared-library candidates probed for desktop GLES3 / SDL3 hosts.
  static const List<String> defaultCandidateLibraries = <String>[
    'libGLESv2.dll',
    'libGLESv2.so.2',
    'libEGL.so.1',
    'SDL3.dll',
    'libSDL3.so.0',
  ];

  /// Ordered list of shared-library names probed during construction.
  final List<String> candidateLibraries;

  ffi.DynamicLibrary? _library;
  String? _libraryName;

  /// Probes [candidateLibraries] until one opens cleanly.
  DynamicLibraryGlLoader({
    List<String> candidateLibraries = defaultCandidateLibraries,
  }) : candidateLibraries = List<String>.unmodifiable(candidateLibraries) {
    for (final candidate in this.candidateLibraries) {
      try {
        final opened = ffi.DynamicLibrary.open(candidate);
        _library = opened;
        _libraryName = candidate;
        break;
      } on Object {
        // Shared library unavailable on this host; try the next candidate.
      }
    }
  }

  /// The opened native library, or `null` if none of [candidateLibraries]
  /// could be loaded.
  ffi.DynamicLibrary? get library => _library;

  @override
  bool get isAvailable => _library != null;

  @override
  String? get libraryName => _libraryName;

  /// Checks whether the loaded [library] exports [name].
  bool providesSymbol(String name) {
    final lib = _library;
    if (lib == null) return false;
    try {
      return lib.providesSymbol(name);
    } on Object {
      return false;
    }
  }

  @override
  bool hasSymbol(String name) => providesSymbol(name);
}

/// Software/mock [NativeGlProcLoader] for deterministic VM unit tests without
/// native shared libraries installed.
final class StubGlProcLoader implements NativeGlProcLoader {
  /// Set of GL entrypoint names advertised as supported by this stub.
  final Set<String> supportedSymbols;

  @override
  final String? libraryName;

  /// Creates a stub proc loader reporting [isAvailable] as `true` and
  /// resolving symbols against [supportedSymbols].
  StubGlProcLoader({
    Set<String> supportedSymbols = const <String>{},
    this.libraryName = 'stub-gles3',
  }) : supportedSymbols = Set<String>.unmodifiable(supportedSymbols);

  @override
  bool get isAvailable => true;

  @override
  bool hasSymbol(String name) => supportedSymbols.contains(name);
}

/// Native FFI command transport that receives [GlesDispatchHook] calls from
/// [GlesDevice], records a bounded command trace, tracks per-opcode counts, and
/// optionally forwards each [GlCommandRecord] to a native dispatch callback.
final class NativeGlTransport {
  /// Optional loader used to query native GL entrypoint availability.
  final NativeGlProcLoader? procLoader;

  /// Optional sink invoked synchronously for every dispatched command.
  final void Function(GlCommandRecord record)? onForward;

  /// Maximum number of recent [GlCommandRecord] entries retained in [records].
  final int maxRecordedCommands;

  final ListQueue<GlCommandRecord> _records = ListQueue<GlCommandRecord>();
  final Map<String, int> _commandCounts = <String, int>{};
  int _totalDispatched = 0;

  /// Creates a [NativeGlTransport] with optional [procLoader], [onForward]
  /// sink, and bounded [maxRecordedCommands] ring capacity.
  NativeGlTransport({
    this.procLoader,
    this.onForward,
    this.maxRecordedCommands = 4096,
  }) {
    RangeError.checkNotNegative(maxRecordedCommands, 'maxRecordedCommands');
  }

  /// [GlesDispatchHook] entrypoint invoked by [GlesDevice] for each low-level
  /// GPU command.
  void dispatch(String command, List<Object?> args) {
    _totalDispatched++;
    _commandCounts[command] = (_commandCounts[command] ?? 0) + 1;

    final record = GlCommandRecord(
      sequence: _totalDispatched,
      command: command,
      args: args,
    );

    if (maxRecordedCommands > 0) {
      if (_records.length >= maxRecordedCommands) {
        _records.removeFirst();
      }
      _records.addLast(record);
    }

    onForward?.call(record);
  }

  /// Creates a [GlesDevice] whose [GlesDevice.onCommand] hook is wired to
  /// [dispatch].
  GlesDevice createDevice({
    bool timerQueries = true,
    bool disjointTimer = false,
    int maxSamples = 4,
    bool anisotropicFiltering = true,
    double maxAnisotropy = 16,
    int? incompleteAboveSamples,
  }) => GlesDevice(
    timerQueries: timerQueries,
    disjointTimer: disjointTimer,
    maxSamples: maxSamples,
    anisotropicFiltering: anisotropicFiltering,
    maxAnisotropy: maxAnisotropy,
    incompleteAboveSamples: incompleteAboveSamples,
    onCommand: dispatch,
  );

  /// Unmodifiable snapshot of the retained [GlCommandRecord] history.
  List<GlCommandRecord> get records =>
      List<GlCommandRecord>.unmodifiable(_records);

  /// Unmodifiable per-command dispatch counts accumulated since creation.
  Map<String, int> get commandCounts =>
      Map<String, int>.unmodifiable(_commandCounts);

  /// Total number of commands dispatched through this transport.
  int get totalDispatched => _totalDispatched;

  /// Clears retained [records] without resetting [totalDispatched] or
  /// [commandCounts].
  void clearRecords() => _records.clear();
}

/// Event kinds recognized by [Sdl3EventPump].
enum Sdl3EventKind { keyDown, keyUp, mouseMove, mouseDown, mouseUp, quit }

/// Normalized desktop input event produced by an SDL3 native bridge or decoded
/// from a compact raw bridge packet.
final class Sdl3InputEvent {
  /// Classification of this input or window lifecycle event.
  final Sdl3EventKind kind;

  /// Key identifier (for [Sdl3EventKind.keyDown] and [Sdl3EventKind.keyUp]).
  final String keyCode;

  /// Horizontal pointer coordinate in surface pixels.
  final double x;

  /// Vertical pointer coordinate in surface pixels.
  final double y;

  /// Mouse button index (1 = primary/left by SDL3 convention).
  final int mouseButton;

  /// Creates an [Sdl3InputEvent].
  const Sdl3InputEvent({
    required this.kind,
    this.keyCode = '',
    this.x = 0.0,
    this.y = 0.0,
    this.mouseButton = 1,
  });
}

/// Queues and drains [Sdl3InputEvent]s into a [ScriptedInput] instance each
/// frame, tracking window quit requests without requiring `libsdl3.so`.
final class Sdl3EventPump {
  static const int _rawPacketByteLength = 24;

  final ListQueue<Sdl3InputEvent> _queue = ListQueue<Sdl3InputEvent>();
  bool _quitRequested = false;
  int _pumpedCount = 0;

  /// Whether a [Sdl3EventKind.quit] event has been pumped.
  bool get quitRequested => _quitRequested;

  /// Total number of events drained by [pumpInto].
  int get pumpedCount => _pumpedCount;

  /// Number of events currently waiting in the queue.
  int get pendingCount => _queue.length;

  /// Appends a single [event] to the pending queue.
  void enqueue(Sdl3InputEvent event) => _queue.addLast(event);

  /// Appends all [events] in iteration order to the pending queue.
  void enqueueAll(Iterable<Sdl3InputEvent> events) => _queue.addAll(events);

  /// Decodes a compact 24-byte native bridge packet (`uint32 kindIndex`,
  /// `int32 mouseButton`, `float64 x`, `float64 y`, plus optional trailing UTF-8
  /// key tag bytes) into an [Sdl3InputEvent], or returns `null` if [bytes] is
  /// shorter than 24 bytes or has an invalid `kindIndex`.
  static Sdl3InputEvent? decodeRawEventPacket(
    ByteData bytes, {
    Endian endian = Endian.little,
  }) {
    if (bytes.lengthInBytes < _rawPacketByteLength) return null;

    final kindIndex = bytes.getUint32(0, endian);
    if (kindIndex >= Sdl3EventKind.values.length) return null;

    final mouseButton = bytes.getInt32(4, endian);
    final x = bytes.getFloat64(8, endian);
    final y = bytes.getFloat64(16, endian);

    var keyCode = '';
    if (bytes.lengthInBytes > _rawPacketByteLength) {
      final rawTag = bytes.buffer.asUint8List(
        bytes.offsetInBytes + _rawPacketByteLength,
        bytes.lengthInBytes - _rawPacketByteLength,
      );
      var length = rawTag.indexOf(0);
      if (length < 0) length = rawTag.length;
      if (length > 0) {
        keyCode = utf8.decode(rawTag.sublist(0, length), allowMalformed: true);
      }
    }

    return Sdl3InputEvent(
      kind: Sdl3EventKind.values[kindIndex],
      keyCode: keyCode,
      x: x,
      y: y,
      mouseButton: mouseButton,
    );
  }

  /// Drains all queued events into [input] and returns `true` while the host
  /// should continue running (`!quitRequested`), or `false` if quit was
  /// requested.
  bool pumpInto(ScriptedInput input) {
    while (_queue.isNotEmpty) {
      final event = _queue.removeFirst();
      _pumpedCount++;
      switch (event.kind) {
        case Sdl3EventKind.keyDown:
          if (event.keyCode.isNotEmpty) {
            input.press(event.keyCode);
          }
        case Sdl3EventKind.keyUp:
          if (event.keyCode.isNotEmpty) {
            input.release(event.keyCode);
          }
        case Sdl3EventKind.mouseMove:
          input.pointerX = event.x;
          input.pointerY = event.y;
        case Sdl3EventKind.mouseDown:
          input.pointerX = event.x;
          input.pointerY = event.y;
          if (!input.pointerDown) {
            input.pointerPressed = true;
          }
          input.pointerDown = true;
        case Sdl3EventKind.mouseUp:
          input.pointerX = event.x;
          input.pointerY = event.y;
          if (input.pointerDown) {
            input.pointerReleased = true;
          }
          input.pointerDown = false;
        case Sdl3EventKind.quit:
          _quitRequested = true;
      }
    }
    return !_quitRequested;
  }
}

/// High-level desktop host bridge coordinating [NativeEngineRunner],
/// [NativeGlTransport], and [Sdl3EventPump] into a single frame loop entrypoint.
final class NativeDesktopBridge {
  /// Booted native engine runner driving the scene and renderer.
  final NativeEngineRunner runner;

  /// GL command transport wired to the runner's [GlesDevice].
  final NativeGlTransport transport;

  /// Event pump feeding desktop input and quit events into `runner.host.input`.
  final Sdl3EventPump eventPump;

  /// Creates a [NativeDesktopBridge] wrapping [runner], [transport], and an
  /// optional [eventPump].
  NativeDesktopBridge({
    required this.runner,
    required this.transport,
    Sdl3EventPump? eventPump,
  }) : eventPump = eventPump ?? Sdl3EventPump();

  /// Whether [eventPump] has received a [Sdl3EventKind.quit] event.
  bool get isQuitRequested => eventPump.quitRequested;

  /// Pumps queued events from [eventPump] into `runner.host.input` and, if
  /// not quit, renders a single frame of duration [dt].
  ///
  /// Returns `null` when quit has been requested.
  FrameStats? stepAndRender(double dt) {
    final running = eventPump.pumpInto(runner.host.input);
    if (!running || isQuitRequested) {
      return null;
    }
    return runner.renderFrame(dt);
  }

  /// Disposes the underlying [runner] and releases its GPU/engine resources.
  void dispose() => runner.dispose();
}
