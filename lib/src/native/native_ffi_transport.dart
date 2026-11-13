import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import '../../gl_volition.dart';
import 'native_bindings.dart';
import 'native_host.dart';

typedef _CallocNative = ffi.Pointer<ffi.Uint8> Function(ffi.Size, ffi.Size);
typedef _CallocDart = ffi.Pointer<ffi.Uint8> Function(int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

/// Minimal zero-dependency native C heap helper (`calloc`/`free` via CRT) so
/// native FFI modules avoid adding external packages while staying leak-free.
final class NativeCAllocator {
  final _CallocDart? _calloc;
  final _FreeDart? _free;

  NativeCAllocator._(this._calloc, this._free);

  static final NativeCAllocator instance = _openDefault();

  /// Whether native CRT `calloc` and `free` symbols are available.
  bool get isAvailable => _calloc != null && _free != null;

  static NativeCAllocator _openDefault() {
    final libs = <ffi.DynamicLibrary>[];
    if (Platform.isWindows) {
      for (final name in const ['ucrtbase.dll', 'msvcrt.dll']) {
        try {
          libs.add(ffi.DynamicLibrary.open(name));
        } on Object {
          // Probe next CRT DLL.
        }
      }
    } else {
      try {
        libs.add(ffi.DynamicLibrary.process());
      } on Object {
        // Ignore if process symbol lookup is unavailable.
      }
    }

    for (final lib in libs) {
      try {
        if (lib.providesSymbol('calloc') && lib.providesSymbol('free')) {
          final callocFn = lib.lookupFunction<_CallocNative, _CallocDart>(
            'calloc',
          );
          final freeFn = lib.lookupFunction<_FreeNative, _FreeDart>('free');
          return NativeCAllocator._(callocFn, freeFn);
        }
      } on Object {
        // Probe next CRT candidate.
      }
    }
    return NativeCAllocator._(null, null);
  }

  /// Allocates [byteCount] zero-initialized native bytes (minimum 1 byte).
  ffi.Pointer<ffi.Uint8> allocateBytes(int byteCount) {
    final callocFn = _calloc;
    if (callocFn == null) {
      throw StateError('Native C calloc is unavailable on this host');
    }
    final count = byteCount <= 0 ? 1 : byteCount;
    final ptr = callocFn(count, 1);
    if (ptr == ffi.nullptr) {
      throw StateError('Native calloc($count) returned nullptr');
    }
    return ptr;
  }

  /// Allocates a NUL-terminated UTF-8 C string in native memory.
  ffi.Pointer<ffi.Uint8> allocUtf8(String value) {
    final encoded = utf8.encode(value);
    final ptr = allocateBytes(encoded.length + 1);
    final view = ptr.asTypedList(encoded.length + 1);
    view.setRange(0, encoded.length, encoded);
    view[encoded.length] = 0;
    return ptr;
  }

  /// Allocates a temporary NUL-terminated UTF-8 string, runs [action], and
  /// always frees the native buffer in a `finally` block.
  R withUtf8<R>(String value, R Function(ffi.Pointer<ffi.Uint8> ptr) action) {
    final ptr = allocUtf8(value);
    try {
      return action(ptr);
    } finally {
      free(ptr);
    }
  }

  /// Reads a NUL-terminated UTF-8 C string from [ptr].
  String readCString(ffi.Pointer<ffi.Uint8> ptr, {int maxBytes = 16384}) {
    if (ptr == ffi.nullptr) return '';
    final bytes = <int>[];
    for (var i = 0; i < maxBytes; i++) {
      final b = (ptr + i).value;
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Releases a pointer previously allocated by [allocateBytes] or [allocUtf8].
  void free(ffi.Pointer<ffi.NativeType> ptr) {
    if (ptr == ffi.nullptr) return;
    _free?.call(ptr.cast<ffi.Void>());
  }
}

/// Probes shared-library candidates safely, including executable-adjacent files.
({ffi.DynamicLibrary? library, String? name, String? error})
openDynamicLibraryCandidates(List<String> candidates) {
  final expanded = <String>[];
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    expanded.add(candidate);
    if (!candidate.contains('/') && !candidate.contains('\\')) {
      expanded.add('$exeDir$sep$candidate');
    }
  }

  Object? lastErr;
  for (final candidate in expanded) {
    try {
      return (
        library: ffi.DynamicLibrary.open(candidate),
        name: candidate,
        error: null,
      );
    } on Object catch (e) {
      lastErr = e;
    }
  }
  return (
    library: null,
    name: null,
    error: lastErr?.toString() ?? 'No candidate library loaded',
  );
}

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
final class DynamicLibraryGlLoader
    implements NativeGlProcLoader, GlProcBindings {
  /// Default shared-library candidates probed for desktop GLES3 / SDL3 hosts.
  static const List<String> defaultCandidateLibraries = <String>[
    'libGLESv2.dll',
    'libGLESv2.so.2',
    'libGLESv2.dylib',
    'libEGL.so.1',
    'SDL3.dll',
    'libSDL3.so.0',
    'libSDL3.dylib',
  ];

  /// Ordered list of shared-library names probed during construction.
  final List<String> candidateLibraries;

  ffi.DynamicLibrary? _library;
  String? _libraryName;
  String? _loadError;

  /// Probes [candidateLibraries] until one opens cleanly.
  DynamicLibraryGlLoader({
    List<String> candidateLibraries = defaultCandidateLibraries,
  }) : candidateLibraries = List<String>.unmodifiable(candidateLibraries) {
    final result = openDynamicLibraryCandidates(this.candidateLibraries);
    _library = result.library;
    _libraryName = result.name;
    _loadError = result.error;
  }

  /// The opened native library, or `null` if none of [candidateLibraries]
  /// could be loaded.
  ffi.DynamicLibrary? get library => _library;

  /// Diagnostic error message from the last failed library load attempt.
  String? get loadError => _loadError;

  @override
  bool get isAvailable => _library != null;

  @override
  bool get isLoaded => isAvailable;

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

  @override
  int lookupAddress(String name) {
    final lib = _library;
    if (lib == null || !providesSymbol(name)) return 0;
    try {
      return lib.lookup<ffi.NativeFunction<ffi.Void Function()>>(name).address;
    } on Object {
      return 0;
    }
  }
}

/// Software/mock [NativeGlProcLoader] and [GlProcBindings] for deterministic VM
/// unit tests without native shared libraries installed.
final class StubGlProcLoader implements NativeGlProcLoader, GlProcBindings {
  /// Set of GL entrypoint names advertised as supported by this stub.
  final Set<String> supportedSymbols;

  /// Optional explicit fake native pointer addresses keyed by symbol name.
  final Map<String, int> symbolAddresses;

  @override
  final String? libraryName;

  /// Creates a stub proc loader reporting [isAvailable] as `true` and
  /// resolving symbols against [supportedSymbols].
  StubGlProcLoader({
    Set<String> supportedSymbols = const <String>{},
    Map<String, int> symbolAddresses = const <String, int>{},
    this.libraryName = 'stub-gles3',
  }) : supportedSymbols = Set<String>.unmodifiable(supportedSymbols),
       symbolAddresses = Map<String, int>.unmodifiable(symbolAddresses);

  @override
  bool get isAvailable => true;

  @override
  bool get isLoaded => true;

  @override
  bool hasSymbol(String name) =>
      supportedSymbols.contains(name) || symbolAddresses.containsKey(name);

  @override
  int lookupAddress(String name) {
    final explicit = symbolAddresses[name];
    if (explicit != null) return explicit;
    if (!supportedSymbols.contains(name)) return 0;
    return 0x1000 + (name.hashCode.abs() & 0xFFFF);
  }
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
