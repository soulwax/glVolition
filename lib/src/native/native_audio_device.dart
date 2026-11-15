import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../gl_volition.dart';
import 'native_bindings.dart';
import 'native_ffi_transport.dart';

// ---------------------------------------------------------------------------
// SDL3 Native Audio FFI Sink
// ---------------------------------------------------------------------------

final class _SdlAudioSpec extends ffi.Struct {
  @ffi.Uint32()
  external int format;

  @ffi.Int()
  external int channels;

  @ffi.Int()
  external int freq;
}

typedef _SdlInitNative = ffi.Bool Function(ffi.Uint32 flags);
typedef _SdlInitDart = bool Function(int flags);

typedef _SdlOpenAudioDeviceStreamNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Uint32 devid,
      ffi.Pointer<_SdlAudioSpec> spec,
      ffi.Pointer<ffi.Void> callback,
      ffi.Pointer<ffi.Void> userdata,
    );
typedef _SdlOpenAudioDeviceStreamDart =
    ffi.Pointer<ffi.Void> Function(
      int devid,
      ffi.Pointer<_SdlAudioSpec> spec,
      ffi.Pointer<ffi.Void> callback,
      ffi.Pointer<ffi.Void> userdata,
    );

typedef _SdlPutAudioStreamDataNative =
    ffi.Bool Function(
      ffi.Pointer<ffi.Void> stream,
      ffi.Pointer<ffi.Void> buf,
      ffi.Int len,
    );
typedef _SdlPutAudioStreamDataDart =
    bool Function(
      ffi.Pointer<ffi.Void> stream,
      ffi.Pointer<ffi.Void> buf,
      int len,
    );

typedef _SdlGetAudioStreamDeviceNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> stream);
typedef _SdlGetAudioStreamDeviceDart =
    int Function(ffi.Pointer<ffi.Void> stream);

typedef _SdlResumeAudioDeviceNative = ffi.Bool Function(ffi.Uint32 dev);
typedef _SdlResumeAudioDeviceDart = bool Function(int dev);

typedef _SdlDestroyAudioStreamNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> stream);
typedef _SdlDestroyAudioStreamDart =
    void Function(ffi.Pointer<ffi.Void> stream);

typedef _SdlGetErrorNative = ffi.Pointer<ffi.Uint8> Function();
typedef _SdlGetErrorDart = ffi.Pointer<ffi.Uint8> Function();

/// [NativeAudioSink] backed by SDL3 (`SDL_OpenAudioDeviceStream` +
/// `SDL_PutAudioStreamData`) via `dart:ffi`.
///
/// Safely probes candidate SDL3 shared libraries and required audio symbols,
/// never throwing or segfaulting when SDL3 or an OS playback device is absent.
final class Sdl3AudioSink implements NativeAudioSink {
  static const int _sdlInitAudio = 0x00000010;
  static const int _sdlAudioDeviceDefaultPlayback = 0xFFFFFFFF;
  static const int _sdlAudioF32Le = 0x8120;
  static const int _sdlAudioF32Be = 0x9120;

  /// Default shared-library candidates probed for SDL3 audio playback.
  static const List<String> defaultCandidateLibraries = <String>[
    'SDL3.dll',
    'libSDL3.so.0',
    'libSDL3.so',
    'libSDL3.dylib',
  ];

  static const List<String> requiredSymbols = <String>[
    'SDL_Init',
    'SDL_OpenAudioDeviceStream',
    'SDL_PutAudioStreamData',
    'SDL_ResumeAudioDevice',
    'SDL_GetAudioStreamDevice',
    'SDL_DestroyAudioStream',
  ];

  /// Ordered shared-library candidates probed when opening the sink.
  final List<String> candidateLibraries;

  NativeAudioConfig _config = const NativeAudioConfig();
  bool _isOpen = false;
  bool _isHardwareBacked = false;
  String? _libraryName;
  String? _lastError;
  List<String> _missingSymbols = const <String>[];

  _SdlInitDart? _sdlInit;
  _SdlOpenAudioDeviceStreamDart? _sdlOpenAudioDeviceStream;
  _SdlPutAudioStreamDataDart? _sdlPutAudioStreamData;
  _SdlResumeAudioDeviceDart? _sdlResumeAudioDevice;
  _SdlGetAudioStreamDeviceDart? _sdlGetAudioStreamDevice;
  _SdlDestroyAudioStreamDart? _sdlDestroyAudioStream;
  _SdlGetErrorDart? _sdlGetError;

  ffi.Pointer<ffi.Void> _stream = ffi.nullptr;
  ffi.Pointer<ffi.Uint8> _scratchPtr = ffi.nullptr;
  int _scratchByteCapacity = 0;

  /// Creates an [Sdl3AudioSink] probing [candidateLibraries] on [open].
  Sdl3AudioSink({List<String> candidateLibraries = defaultCandidateLibraries})
    : candidateLibraries = List<String>.unmodifiable(candidateLibraries);

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isHardwareBacked => _isHardwareBacked;

  @override
  NativeAudioConfig get config => _config;

  @override
  String? get backendName => 'sdl3-audio';

  @override
  String? get lastError => _lastError;

  /// Name/path of the resolved SDL3 shared library, or `null` if unavailable.
  String? get libraryName => _libraryName;

  /// Required SDL3 symbols that were missing on the last [open] probe.
  List<String> get missingSymbols => _missingSymbols;

  /// Whether all required SDL3 audio entrypoints were resolved cleanly.
  bool get hasRequiredSymbols =>
      _sdlInit != null &&
      _sdlOpenAudioDeviceStream != null &&
      _sdlPutAudioStreamData != null &&
      _sdlResumeAudioDevice != null &&
      _sdlGetAudioStreamDevice != null &&
      _sdlDestroyAudioStream != null;

  String _readSdlError(String fallback) {
    final getErr = _sdlGetError;
    if (getErr == null) return fallback;
    try {
      final msg = NativeCAllocator.instance.readCString(getErr());
      return msg.isNotEmpty ? msg : fallback;
    } on Object {
      return fallback;
    }
  }

  void _clearBindings() {
    _sdlInit = null;
    _sdlOpenAudioDeviceStream = null;
    _sdlPutAudioStreamData = null;
    _sdlResumeAudioDevice = null;
    _sdlGetAudioStreamDevice = null;
    _sdlDestroyAudioStream = null;
    _sdlGetError = null;
  }

  bool _probeLibrary() {
    _clearBindings();
    _missingSymbols = const <String>[];
    _libraryName = null;

    final loaded = openDynamicLibraryCandidates(candidateLibraries);
    final lib = loaded.library;
    if (lib == null) {
      _lastError =
          loaded.error ?? 'SDL3 shared library not found in candidates';
      return false;
    }
    _libraryName = loaded.name;

    final missing = <String>[];
    for (final symbol in requiredSymbols) {
      var found = false;
      try {
        found = lib.providesSymbol(symbol);
      } on Object {
        found = false;
      }
      if (!found) {
        missing.add(symbol);
      }
    }
    if (missing.isNotEmpty) {
      _missingSymbols = List<String>.unmodifiable(missing);
      _lastError =
          'SDL3 library "${loaded.name}" missing audio symbols: ${missing.join(', ')}';
      return false;
    }

    try {
      _sdlInit = lib.lookupFunction<_SdlInitNative, _SdlInitDart>('SDL_Init');
      _sdlOpenAudioDeviceStream = lib
          .lookupFunction<
            _SdlOpenAudioDeviceStreamNative,
            _SdlOpenAudioDeviceStreamDart
          >('SDL_OpenAudioDeviceStream');
      _sdlPutAudioStreamData = lib
          .lookupFunction<
            _SdlPutAudioStreamDataNative,
            _SdlPutAudioStreamDataDart
          >('SDL_PutAudioStreamData');
      _sdlResumeAudioDevice = lib
          .lookupFunction<
            _SdlResumeAudioDeviceNative,
            _SdlResumeAudioDeviceDart
          >('SDL_ResumeAudioDevice');
      _sdlGetAudioStreamDevice = lib
          .lookupFunction<
            _SdlGetAudioStreamDeviceNative,
            _SdlGetAudioStreamDeviceDart
          >('SDL_GetAudioStreamDevice');
      _sdlDestroyAudioStream = lib
          .lookupFunction<
            _SdlDestroyAudioStreamNative,
            _SdlDestroyAudioStreamDart
          >('SDL_DestroyAudioStream');

      if (lib.providesSymbol('SDL_GetError')) {
        _sdlGetError = lib.lookupFunction<_SdlGetErrorNative, _SdlGetErrorDart>(
          'SDL_GetError',
        );
      }
      return true;
    } on Object catch (e) {
      _clearBindings();
      _lastError = 'Failed to bind SDL3 audio symbols: $e';
      return false;
    }
  }

  @override
  bool open(NativeAudioConfig config) {
    close();
    _config = config;
    _isOpen = false;
    _isHardwareBacked = false;

    if (config.sampleRate <= 0 ||
        config.channels <= 0 ||
        config.framesPerBuffer <= 0) {
      _lastError =
          'Invalid NativeAudioConfig(sampleRate=${config.sampleRate}, '
          'channels=${config.channels}, frames=${config.framesPerBuffer})';
      return false;
    }

    try {
      if (!_probeLibrary()) {
        return false;
      }

      final allocator = NativeCAllocator.instance;
      if (!allocator.isAvailable) {
        _lastError = 'Native C allocator (calloc/free) is unavailable';
        return false;
      }

      if (!_sdlInit!(_sdlInitAudio)) {
        _lastError = _readSdlError('SDL_Init(SDL_INIT_AUDIO) failed');
        return false;
      }

      final specRaw = allocator.allocateBytes(ffi.sizeOf<_SdlAudioSpec>());
      final ffi.Pointer<ffi.Void> stream;
      try {
        final spec = specRaw.cast<_SdlAudioSpec>();
        spec.ref
          ..format = Endian.host == Endian.little
              ? _sdlAudioF32Le
              : _sdlAudioF32Be
          ..channels = config.channels
          ..freq = config.sampleRate;

        stream = _sdlOpenAudioDeviceStream!(
          _sdlAudioDeviceDefaultPlayback,
          spec,
          ffi.nullptr,
          ffi.nullptr,
        );
      } finally {
        allocator.free(specRaw);
      }

      if (stream == ffi.nullptr) {
        _lastError = _readSdlError('SDL_OpenAudioDeviceStream returned null');
        return false;
      }

      final deviceId = _sdlGetAudioStreamDevice!(stream);
      if (deviceId == 0 || !_sdlResumeAudioDevice!(deviceId)) {
        _lastError = _readSdlError(
          'Failed to resume SDL3 audio device (deviceId=$deviceId)',
        );
        try {
          _sdlDestroyAudioStream!(stream);
        } on Object {
          // Best-effort cleanup on failed open.
        }
        return false;
      }

      _stream = stream;
      _isOpen = true;
      _isHardwareBacked = true;
      _lastError = null;
      return true;
    } on Object catch (e) {
      _isOpen = false;
      _isHardwareBacked = false;
      _lastError = 'SDL3 audio initialization failed: $e';
      return false;
    }
  }

  @override
  int writeInterleavedFloat32(Float32List samples) {
    if (!_isOpen || _stream == ffi.nullptr || samples.isEmpty) {
      return 0;
    }
    final putData = _sdlPutAudioStreamData;
    if (putData == null) return 0;

    final byteCount = samples.lengthInBytes;
    final allocator = NativeCAllocator.instance;
    if (!allocator.isAvailable) {
      _lastError = 'Native C allocator is unavailable';
      return 0;
    }

    try {
      if (_scratchPtr == ffi.nullptr || _scratchByteCapacity < byteCount) {
        if (_scratchPtr != ffi.nullptr) {
          allocator.free(_scratchPtr);
          _scratchPtr = ffi.nullptr;
          _scratchByteCapacity = 0;
        }
        _scratchPtr = allocator.allocateBytes(byteCount);
        _scratchByteCapacity = byteCount;
      }

      _scratchPtr
          .cast<ffi.Float>()
          .asTypedList(samples.length)
          .setAll(0, samples);
      final ok = putData(_stream, _scratchPtr.cast<ffi.Void>(), byteCount);
      if (!ok) {
        _lastError = _readSdlError('SDL_PutAudioStreamData failed');
        return 0;
      }
      return samples.length;
    } on Object catch (e) {
      _lastError = 'SDL3 audio write failed: $e';
      return 0;
    }
  }

  @override
  void close() {
    if (_stream != ffi.nullptr) {
      final destroy = _sdlDestroyAudioStream;
      if (destroy != null) {
        try {
          destroy(_stream);
        } on Object {
          // Ignore teardown errors during close.
        }
      }
      _stream = ffi.nullptr;
    }
    if (_scratchPtr != ffi.nullptr) {
      NativeCAllocator.instance.free(_scratchPtr);
      _scratchPtr = ffi.nullptr;
      _scratchByteCapacity = 0;
    }
    _isOpen = false;
    _isHardwareBacked = false;
  }
}

// ---------------------------------------------------------------------------
// Headless / CI Software Capture PCM Sink
// ---------------------------------------------------------------------------

/// Deterministic headless/CI [NativeAudioSink] capturing interleaved 32-bit
/// float PCM frames into memory for verification and offline inspection.
final class SoftwareCaptureAudioSink implements NativeAudioSink {
  final List<Float32List> _chunks = <Float32List>[];
  NativeAudioConfig _config = const NativeAudioConfig();
  bool _isOpen = false;
  String? _lastError;
  int _capturedSampleCount = 0;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isHardwareBacked => false;

  @override
  NativeAudioConfig get config => _config;

  @override
  String? get backendName => 'software-pcm';

  @override
  String? get lastError => _lastError;

  /// Number of scalar float samples written across all calls since last [clear].
  int get capturedSampleCount => _capturedSampleCount;

  /// Number of interleaved frames captured (`capturedSampleCount ~/ channels`).
  int get capturedFrameCount =>
      _config.channels > 0 ? _capturedSampleCount ~/ _config.channels : 0;

  /// Number of non-empty [writeInterleavedFloat32] buffers recorded.
  int get writeCount => _chunks.length;

  /// Concatenated snapshot of all captured interleaved PCM samples.
  Float32List get capturedSamples {
    final out = Float32List(_capturedSampleCount);
    var offset = 0;
    for (final chunk in _chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }

  /// Maximum absolute sample amplitude across all captured samples.
  double get peakAmplitude {
    var peak = 0.0;
    for (final chunk in _chunks) {
      for (var i = 0; i < chunk.length; i++) {
        final v = chunk[i].abs();
        if (v > peak) peak = v;
      }
    }
    return peak;
  }

  /// Root-mean-square amplitude across all captured samples.
  double get rmsAmplitude {
    if (_capturedSampleCount == 0) return 0.0;
    var sumSq = 0.0;
    for (final chunk in _chunks) {
      for (var i = 0; i < chunk.length; i++) {
        final v = chunk[i];
        sumSq += v * v;
      }
    }
    return math.sqrt(sumSq / _capturedSampleCount);
  }

  /// Clears captured buffers without closing the sink.
  void clear() {
    _chunks.clear();
    _capturedSampleCount = 0;
  }

  @override
  bool open(NativeAudioConfig config) {
    if (config.sampleRate <= 0 ||
        config.channels <= 0 ||
        config.framesPerBuffer <= 0) {
      _lastError =
          'Invalid NativeAudioConfig(sampleRate=${config.sampleRate}, '
          'channels=${config.channels}, frames=${config.framesPerBuffer})';
      _isOpen = false;
      return false;
    }
    _config = config;
    _isOpen = true;
    _lastError = null;
    return true;
  }

  @override
  int writeInterleavedFloat32(Float32List samples) {
    if (!_isOpen) {
      _lastError = 'SoftwareCaptureAudioSink is not open';
      return 0;
    }
    if (samples.isEmpty) return 0;
    _chunks.add(Float32List.fromList(samples));
    _capturedSampleCount += samples.length;
    return samples.length;
  }

  @override
  void close() {
    _isOpen = false;
  }
}

// ---------------------------------------------------------------------------
// WAV PCM Decoder & Fallback Synthesis
// ---------------------------------------------------------------------------

/// Container format identified by [WavPcmDecoder].
enum AudioContainerFormat {
  wavPcm16,
  wavFloat32,
  oggFallback,
  silenceFallback,
  toneFallback,
}

/// Decoded normalized `Float32List` PCM audio data with format metadata.
final class DecodedPcmAudio {
  final Float32List samples;
  final int sampleRate;
  final int channels;
  final AudioContainerFormat format;
  final bool isFallback;
  final String? diagnostic;

  const DecodedPcmAudio({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.format,
    this.isFallback = false,
    this.diagnostic,
  });

  int get frameCount => channels > 0 ? samples.length ~/ channels : 0;

  double get durationSeconds => sampleRate > 0 ? frameCount / sampleRate : 0.0;
}

/// Pure-Dart RIFF/WAVE decoder supporting 16-bit signed PCM and 32-bit IEEE
/// float WAV streams (mono and stereo), with OGG header detection and clean
/// silent/tone fallback generation.
abstract final class WavPcmDecoder {
  static const int _wavFormatPcm = 1;
  static const int _wavFormatIeeeFloat = 3;
  static const int _wavFormatExtensible = 0xFFFE;

  /// Returns `true` when [bytes] starts with a valid `RIFF....WAVE` header.
  static bool isWavHeader(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x41 && // A
      bytes[10] == 0x56 && // V
      bytes[11] == 0x45; // E

  /// Returns `true` when [bytes] starts with an `OggS` container magic header.
  static bool isOggHeader(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x4F && // O
      bytes[1] == 0x67 && // g
      bytes[2] == 0x67 && // g
      bytes[3] == 0x53; // S

  static bool _matchesTag(Uint8List bytes, int offset, String tag) =>
      bytes[offset] == tag.codeUnitAt(0) &&
      bytes[offset + 1] == tag.codeUnitAt(1) &&
      bytes[offset + 2] == tag.codeUnitAt(2) &&
      bytes[offset + 3] == tag.codeUnitAt(3);

  /// Strictly decodes a 16-bit PCM or 32-bit IEEE float RIFF/WAVE buffer, or
  /// returns `null` if [bytes] is not a supported WAV stream.
  static DecodedPcmAudio? tryDecodeWav(Uint8List bytes) {
    if (!isWavHeader(bytes)) return null;

    final bd = ByteData.sublistView(bytes);
    var offset = 12;

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataStart;
    int dataLength = 0;

    while (offset + 8 <= bytes.length) {
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = math.min(bytes.length, chunkStart + chunkSize);

      if (_matchesTag(bytes, offset, 'fmt ') && chunkEnd - chunkStart >= 16) {
        var fmt = bd.getUint16(chunkStart, Endian.little);
        channels = bd.getUint16(chunkStart + 2, Endian.little);
        sampleRate = bd.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = bd.getUint16(chunkStart + 14, Endian.little);

        if (fmt == _wavFormatExtensible && chunkEnd - chunkStart >= 26) {
          fmt = bd.getUint16(chunkStart + 24, Endian.little);
        }
        audioFormat = fmt;
      } else if (_matchesTag(bytes, offset, 'data')) {
        dataStart = chunkStart;
        dataLength = chunkEnd - chunkStart;
      }

      final pad = chunkSize.isOdd ? 1 : 0;
      final nextOffset = chunkStart + chunkSize + pad;
      if (nextOffset <= offset) break;
      offset = nextOffset;
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataStart == null ||
        sampleRate <= 0 ||
        (channels != 1 && channels != 2)) {
      return null;
    }

    if (audioFormat == _wavFormatPcm && bitsPerSample == 16) {
      final sampleCount = dataLength ~/ 2;
      final frameCount = sampleCount ~/ channels;
      final usableSamples = frameCount * channels;
      final out = Float32List(usableSamples);
      for (var i = 0; i < usableSamples; i++) {
        out[i] = bd.getInt16(dataStart + i * 2, Endian.little) / 32768.0;
      }
      return DecodedPcmAudio(
        samples: out,
        sampleRate: sampleRate,
        channels: channels,
        format: AudioContainerFormat.wavPcm16,
      );
    }

    if (audioFormat == _wavFormatIeeeFloat && bitsPerSample == 32) {
      final sampleCount = dataLength ~/ 4;
      final frameCount = sampleCount ~/ channels;
      final usableSamples = frameCount * channels;
      final out = Float32List(usableSamples);
      for (var i = 0; i < usableSamples; i++) {
        final raw = bd.getFloat32(dataStart + i * 4, Endian.little);
        out[i] = raw.isFinite ? raw.clamp(-1.0, 1.0) : 0.0;
      }
      return DecodedPcmAudio(
        samples: out,
        sampleRate: sampleRate,
        channels: channels,
        format: AudioContainerFormat.wavFloat32,
      );
    }

    return null;
  }

  /// Decodes [bytes] when it is a supported WAV stream, or detects OGG/invalid
  /// containers and returns a clean silent or diagnostic-tone fallback.
  static DecodedPcmAudio decode(
    Uint8List bytes, {
    int fallbackSampleRate = 48000,
    bool generateToneOnFallback = false,
    double fallbackToneHz = 440.0,
    double fallbackDurationSeconds = 0.25,
  }) {
    final decoded = tryDecodeWav(bytes);
    if (decoded != null) return decoded;

    final isOgg = isOggHeader(bytes);
    final reason = isOgg
        ? 'OGG container detected; using PCM fallback buffer'
        : 'Unsupported or non-WAV audio payload (${bytes.length} bytes); '
              'using PCM fallback buffer';

    if (generateToneOnFallback) {
      return generateFallbackTone(
        sampleRate: fallbackSampleRate,
        frequencyHz: fallbackToneHz,
        durationSeconds: fallbackDurationSeconds,
        format: isOgg
            ? AudioContainerFormat.oggFallback
            : AudioContainerFormat.toneFallback,
        diagnostic: reason,
      );
    }

    return generateSilence(
      sampleRate: fallbackSampleRate,
      format: isOgg
          ? AudioContainerFormat.oggFallback
          : AudioContainerFormat.silenceFallback,
      diagnostic: reason,
    );
  }

  /// Generates a deterministic silent PCM buffer for fallback assets.
  static DecodedPcmAudio generateSilence({
    int sampleRate = 48000,
    int channels = 1,
    int frameCount = 512,
    AudioContainerFormat format = AudioContainerFormat.silenceFallback,
    String? diagnostic,
  }) {
    final safeRate = sampleRate > 0 ? sampleRate : 48000;
    final safeChannels = (channels == 1 || channels == 2) ? channels : 1;
    final safeFrames = frameCount >= 0 ? frameCount : 0;
    return DecodedPcmAudio(
      samples: Float32List(safeFrames * safeChannels),
      sampleRate: safeRate,
      channels: safeChannels,
      format: format,
      isFallback: true,
      diagnostic: diagnostic,
    );
  }

  /// Generates a clean sine tone PCM buffer for diagnostic fallback playback.
  static DecodedPcmAudio generateFallbackTone({
    int sampleRate = 48000,
    int channels = 1,
    double frequencyHz = 440.0,
    double durationSeconds = 0.25,
    double amplitude = 0.25,
    AudioContainerFormat format = AudioContainerFormat.toneFallback,
    String? diagnostic,
  }) {
    final safeRate = sampleRate > 0 ? sampleRate : 48000;
    final safeChannels = (channels == 1 || channels == 2) ? channels : 1;
    final frames = math.max(1, (safeRate * durationSeconds).round());
    final out = Float32List(frames * safeChannels);
    final amp = amplitude.clamp(0.0, 1.0);
    for (var f = 0; f < frames; f++) {
      final t = f / safeRate;
      final v = math.sin(2.0 * math.pi * frequencyHz * t) * amp;
      if (safeChannels == 1) {
        out[f] = v;
      } else {
        out[f * 2] = v;
        out[f * 2 + 1] = v;
      }
    }
    return DecodedPcmAudio(
      samples: out,
      sampleRate: safeRate,
      channels: safeChannels,
      format: format,
      isFallback: true,
      diagnostic: diagnostic,
    );
  }

  /// Encodes normalized [samples] as a 16-bit signed PCM RIFF/WAVE buffer.
  static Uint8List encodePcm16(
    Float32List samples, {
    required int sampleRate,
    int channels = 1,
  }) {
    if (channels != 1 && channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'Must be 1 or 2');
    }
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be > 0');
    }
    final dataSize = samples.length * 2;
    final bytes = Uint8List(44 + dataSize);
    final bd = _writeWavHeader(
      bytes,
      audioFormat: _wavFormatPcm,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: 16,
      dataSize: dataSize,
    );
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].isFinite ? samples[i].clamp(-1.0, 1.0) : 0.0;
      final scaled = (clamped * 32767.0).round().clamp(-32768, 32767);
      bd.setInt16(44 + i * 2, scaled, Endian.little);
    }
    return bytes;
  }

  /// Encodes normalized [samples] as a 32-bit IEEE float RIFF/WAVE buffer.
  static Uint8List encodeFloat32(
    Float32List samples, {
    required int sampleRate,
    int channels = 1,
  }) {
    if (channels != 1 && channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'Must be 1 or 2');
    }
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be > 0');
    }
    final dataSize = samples.length * 4;
    final bytes = Uint8List(44 + dataSize);
    final bd = _writeWavHeader(
      bytes,
      audioFormat: _wavFormatIeeeFloat,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: 32,
      dataSize: dataSize,
    );
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].isFinite ? samples[i].clamp(-1.0, 1.0) : 0.0;
      bd.setFloat32(44 + i * 4, v, Endian.little);
    }
    return bytes;
  }

  static ByteData _writeWavHeader(
    Uint8List bytes, {
    required int audioFormat,
    required int channels,
    required int sampleRate,
    required int bitsPerSample,
    required int dataSize,
  }) {
    final bd = ByteData.sublistView(bytes);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final byteRate = sampleRate * blockAlign;

    bytes.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // RIFF
    bd.setUint32(4, 36 + dataSize, Endian.little);
    bytes.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]); // WAVE
    bytes.setRange(12, 16, const [0x66, 0x6D, 0x74, 0x20]); // fmt
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, audioFormat, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    bytes.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]); // data
    bd.setUint32(40, dataSize, Endian.little);
    return bd;
  }
}

// ---------------------------------------------------------------------------
// Native AudioClip, AudioChannel, and PCM Mixer Device
// ---------------------------------------------------------------------------

/// Decoded native PCM [AudioClip] holding interleaved float samples.
final class NativeAudioClip implements AudioClip {
  @override
  final String path;

  /// Normalized `[-1.0, 1.0]` interleaved PCM samples.
  final Float32List samples;

  /// Source sample rate in Hz.
  final int sampleRate;

  /// Channel count (`1` = mono, `2` = stereo).
  final int channels;

  /// Base clip gain applied when declared via [NativeAudioDevice.clip].
  final double baseVolume;

  /// Maximum concurrent one-shot voices permitted for this clip.
  final int maxVoices;

  /// Whether this clip fell back to synthesized silence/tone (e.g. missing file
  /// or unsupported OGG container).
  final bool isFallback;

  /// Optional diagnostic string describing fallback reason, if any.
  final String? diagnostic;

  NativeAudioClip._({
    required this.path,
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.baseVolume,
    required this.maxVoices,
    required this.isFallback,
    required this.diagnostic,
  });

  /// Creates a [NativeAudioClip] directly from normalized [samples].
  factory NativeAudioClip.fromSamples({
    required String path,
    required Float32List samples,
    int sampleRate = 48000,
    int channels = 1,
    double baseVolume = 1.0,
    int maxVoices = 3,
    bool isFallback = false,
    String? diagnostic,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be > 0');
    }
    if (channels != 1 && channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'Must be 1 or 2');
    }
    return NativeAudioClip._(
      path: path,
      samples: Float32List.fromList(samples),
      sampleRate: sampleRate,
      channels: channels,
      baseVolume: baseVolume,
      maxVoices: math.max(1, maxVoices),
      isFallback: isFallback,
      diagnostic: diagnostic,
    );
  }

  /// Creates a [NativeAudioClip] by decoding RIFF/WAVE bytes (or falling back
  /// cleanly for OGG / malformed buffers).
  factory NativeAudioClip.fromWavBytes(
    Uint8List wavBytes, {
    required String path,
    double baseVolume = 1.0,
    int maxVoices = 3,
    int fallbackSampleRate = 48000,
    bool generateToneOnFallback = false,
  }) {
    final decoded = WavPcmDecoder.decode(
      wavBytes,
      fallbackSampleRate: fallbackSampleRate,
      generateToneOnFallback: generateToneOnFallback,
    );
    return NativeAudioClip._(
      path: path,
      samples: decoded.samples,
      sampleRate: decoded.sampleRate,
      channels: decoded.channels,
      baseVolume: baseVolume,
      maxVoices: math.max(1, maxVoices),
      isFallback: decoded.isFallback,
      diagnostic: decoded.diagnostic,
    );
  }

  /// Creates a [NativeAudioClip] from an in-memory [ProceduralAudioClip].
  factory NativeAudioClip.fromProcedural(
    ProceduralAudioClip clip, {
    double baseVolume = 1.0,
    int maxVoices = 3,
  }) => NativeAudioClip.fromWavBytes(
    clip.wavBytes,
    path: clip.path,
    baseVolume: baseVolume,
    maxVoices: maxVoices,
  );

  /// Loads a [NativeAudioClip] from [path] on disk (resolved relative to
  /// [rootDirectory] if non-absolute), returning a silent/diagnostic fallback
  /// if missing or unreadable.
  factory NativeAudioClip.fromFile(
    String path, {
    Directory? rootDirectory,
    double baseVolume = 1.0,
    int maxVoices = 3,
    int fallbackSampleRate = 48000,
    bool generateToneOnFallback = false,
  }) {
    if (path.startsWith('procedural://')) {
      final fallback = WavPcmDecoder.generateSilence(
        sampleRate: fallbackSampleRate,
        diagnostic: 'Procedural path "$path" resolved without WAV payload',
      );
      return NativeAudioClip._(
        path: path,
        samples: fallback.samples,
        sampleRate: fallback.sampleRate,
        channels: fallback.channels,
        baseVolume: baseVolume,
        maxVoices: math.max(1, maxVoices),
        isFallback: true,
        diagnostic: fallback.diagnostic,
      );
    }

    final file = _resolveAudioFile(path, rootDirectory);
    if (!file.existsSync()) {
      final fallback = generateToneOnFallback
          ? WavPcmDecoder.generateFallbackTone(
              sampleRate: fallbackSampleRate,
              diagnostic: 'Missing audio file: ${file.path}',
            )
          : WavPcmDecoder.generateSilence(
              sampleRate: fallbackSampleRate,
              diagnostic: 'Missing audio file: ${file.path}',
            );
      return NativeAudioClip._(
        path: path,
        samples: fallback.samples,
        sampleRate: fallback.sampleRate,
        channels: fallback.channels,
        baseVolume: baseVolume,
        maxVoices: math.max(1, maxVoices),
        isFallback: true,
        diagnostic: fallback.diagnostic,
      );
    }

    try {
      final bytes = file.readAsBytesSync();
      return NativeAudioClip.fromWavBytes(
        bytes,
        path: path,
        baseVolume: baseVolume,
        maxVoices: maxVoices,
        fallbackSampleRate: fallbackSampleRate,
        generateToneOnFallback: generateToneOnFallback,
      );
    } on Object catch (e) {
      final fallback = WavPcmDecoder.generateSilence(
        sampleRate: fallbackSampleRate,
        diagnostic: 'Failed to read audio file "${file.path}": $e',
      );
      return NativeAudioClip._(
        path: path,
        samples: fallback.samples,
        sampleRate: fallback.sampleRate,
        channels: fallback.channels,
        baseVolume: baseVolume,
        maxVoices: math.max(1, maxVoices),
        isFallback: true,
        diagnostic: fallback.diagnostic,
      );
    }
  }

  /// Returns a view sharing decoded samples with updated [baseVolume]/[maxVoices].
  NativeAudioClip withPlaybackDefaults({double? baseVolume, int? maxVoices}) =>
      NativeAudioClip._(
        path: path,
        samples: samples,
        sampleRate: sampleRate,
        channels: channels,
        baseVolume: baseVolume ?? this.baseVolume,
        maxVoices: math.max(1, maxVoices ?? this.maxVoices),
        isFallback: isFallback,
        diagnostic: diagnostic,
      );

  int get frameCount => channels > 0 ? samples.length ~/ channels : 0;

  double get durationSeconds => sampleRate > 0 ? frameCount / sampleRate : 0.0;

  static File _resolveAudioFile(String path, Directory? rootDirectory) {
    final direct = File(path);
    if (rootDirectory == null || direct.isAbsolute) return direct;
    final clean = path.replaceAll('\\', '/');
    return File('${rootDirectory.path}/$clean');
  }
}

final class _VoiceState {
  NativeAudioClip? clip;
  double cursor = 0.0;
  double volume = 1.0;
  double pitch = 1.0;
  bool loop = false;
  double pan = 0.0;
  double lowPassCutoffHz = 20000.0;
  double reverbWet = 0.0;
  bool playing = false;
  bool paused = false;

  double lpfL = 0.0;
  double lpfR = 0.0;

  Float32List? _delayL;
  Float32List? _delayR;
  int _delayPosL = 0;
  int _delayPosR = 0;

  void resetDspState() {
    lpfL = 0.0;
    lpfR = 0.0;
    _delayPosL = 0;
    _delayPosR = 0;
    _delayL?.fillRange(0, _delayL!.length, 0.0);
    _delayR?.fillRange(0, _delayR!.length, 0.0);
  }

  (double, double) processReverb(
    double inL,
    double inR,
    double wet,
    int sampleRate,
  ) {
    final lenL = math.max(64, (sampleRate * 0.029).round());
    final lenR = math.max(64, (sampleRate * 0.037).round());
    var bufL = _delayL;
    var bufR = _delayR;
    if (bufL == null || bufL.length != lenL) {
      bufL = Float32List(lenL);
      _delayL = bufL;
      _delayPosL = 0;
    }
    if (bufR == null || bufR.length != lenR) {
      bufR = Float32List(lenR);
      _delayR = bufR;
      _delayPosR = 0;
    }

    final delayedL = bufL[_delayPosL];
    final delayedR = bufR[_delayPosR];
    bufL[_delayPosL] = (inL + delayedR * 0.35).clamp(-1.0, 1.0);
    bufR[_delayPosR] = (inR + delayedL * 0.35).clamp(-1.0, 1.0);
    _delayPosL = (_delayPosL + 1) % lenL;
    _delayPosR = (_delayPosR + 1) % lenR;

    final dryScale = 1.0 - wet * 0.35;
    return (inL * dryScale + delayedL * wet, inR * dryScale + delayedR * wet);
  }
}

/// Controllable audio voice channel created by [NativeAudioDevice.createChannel].
final class NativeAudioChannel implements AudioChannel {
  final NativeAudioDevice _device;
  final _VoiceState _voice = _VoiceState();
  bool _disposed = false;

  NativeAudioChannel._(this._device);

  double get volume => _voice.volume;

  @override
  set volume(double value) => _voice.volume = value;

  double get pitch => _voice.pitch;

  @override
  set pitch(double value) => _voice.pitch = value;

  bool get loop => _voice.loop;
  set loop(bool value) => _voice.loop = value;

  double get pan => _voice.pan;
  set pan(double value) => _voice.pan = value;

  double get lowPassCutoffHz => _voice.lowPassCutoffHz;
  set lowPassCutoffHz(double value) => _voice.lowPassCutoffHz = value;

  double get reverbWet => _voice.reverbWet;
  set reverbWet(double value) => _voice.reverbWet = value;

  @override
  void setPan(double pan) => this.pan = pan.clamp(-1.0, 1.0);

  @override
  void setLowPass(double cutoffHz, {double resonance = 0.707}) {
    lowPassCutoffHz = cutoffHz;
  }

  @override
  void setReverbSend(double wet) => reverbWet = wet.clamp(0.0, 1.0);

  @override
  bool get isPlaying => _voice.playing && !_voice.paused && !_disposed;

  /// Whether this channel is currently paused via [pause].
  bool get isPaused => _voice.paused && !_disposed;

  /// Whether this channel has been disposed.
  bool get isDisposed => _disposed;

  /// Current fractional playhead position in source frames.
  double get playheadFrame => _voice.cursor;

  @override
  void play(
    AudioClip clip, {
    double volume = 1,
    double pitch = 1,
    bool loop = false,
  }) {
    if (_disposed || _device.isDisposed) return;
    final resolved = _device.resolveClip(clip);
    _voice
      ..clip = resolved
      ..volume = volume
      ..pitch = pitch
      ..loop = loop
      ..cursor = 0.0
      ..paused = false
      ..playing = true
      ..resetDspState();
  }

  /// Pauses playback without resetting the playhead position.
  void pause() {
    if (_disposed || !_voice.playing) return;
    _voice.paused = true;
  }

  /// Resumes playback from the paused playhead position.
  void resume() {
    if (_disposed || !_voice.playing) return;
    _voice.paused = false;
  }

  @override
  void stop() {
    _voice
      ..playing = false
      ..paused = false
      ..cursor = 0.0
      ..resetDspState();
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _voice.clip = null;
    _disposed = true;
    _device._channels.remove(this);
  }
}

/// Software-mixed PCM [DisposableNativeAudioDevice] streaming interleaved stereo
/// `Float32List` frames to a [NativeAudioSink] (hardware SDL3 or software capture).
final class NativeAudioDevice implements DisposableNativeAudioDevice {
  static const double _softKneeThreshold = 0.9;
  static const double _softKneeHeadroom = 1.0 - _softKneeThreshold;

  /// Underlying PCM output sink.
  final NativeAudioSink sink;

  /// Requested audio stream configuration.
  final NativeAudioConfig config;

  /// Optional asset root directory used to resolve relative `.wav` paths.
  final Directory? rootDirectory;

  /// Maximum total concurrent one-shot voices allowed in the pool.
  final int maxOneShotVoices;

  final List<NativeAudioChannel> _channels = <NativeAudioChannel>[];
  final ListQueue<_VoiceState> _oneShots = ListQueue<_VoiceState>();
  final Map<String, NativeAudioClip> _pathClipCache =
      <String, NativeAudioClip>{};
  final Expando<NativeAudioClip> _proceduralClipCache =
      Expando<NativeAudioClip>('proceduralAudioClipCache');

  bool _muted = false;
  bool _disposed = false;
  Vec3 listenerPosition = const Vec3(0, 0, 0);
  Vec3 listenerForward = const Vec3(0, 0, -1);
  Vec3 listenerUp = const Vec3(0, 1, 0);

  /// Creates a [NativeAudioDevice], opening [sink] with [config] unless
  /// `autoOpenSink` is `false` or [sink] is already open.
  NativeAudioDevice({
    NativeAudioSink? sink,
    this.config = const NativeAudioConfig(),
    this.rootDirectory,
    this.maxOneShotVoices = 32,
    bool autoOpenSink = true,
  }) : sink = sink ?? Sdl3AudioSink() {
    if (maxOneShotVoices <= 0) {
      throw RangeError.range(
        maxOneShotVoices,
        1,
        null,
        'maxOneShotVoices',
        'Must be >= 1',
      );
    }
    if (autoOpenSink && !this.sink.isOpen) {
      this.sink.open(config);
    }
  }

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  /// Whether [dispose] has been called on this device.
  bool get isDisposed => _disposed;

  /// Number of live (non-disposed) channels created by this device.
  int get activeChannelCount => _channels.length;

  /// Number of currently playing one-shot voices in the pool.
  int get activeOneShotCount => _oneShots.length;

  /// Total number of actively playing voices (channels + one-shots).
  int get activeVoiceCount {
    var count = _oneShots.length;
    for (final ch in _channels) {
      if (ch.isPlaying) count++;
    }
    return count;
  }

  int get _outputSampleRate =>
      sink.isOpen ? sink.config.sampleRate : config.sampleRate;

  /// Resolves any [AudioClip] (native, procedural synth, or path-based) into
  /// a cached [NativeAudioClip].
  NativeAudioClip resolveClip(AudioClip clip) {
    if (clip is NativeAudioClip) return clip;
    if (clip is ProceduralAudioClip) {
      final cached = _proceduralClipCache[clip];
      if (cached != null) return cached;
      final decoded = NativeAudioClip.fromProcedural(clip);
      _proceduralClipCache[clip] = decoded;
      return decoded;
    }
    return _pathClipCache.putIfAbsent(
      clip.path,
      () => NativeAudioClip.fromFile(
        clip.path,
        rootDirectory: rootDirectory,
        fallbackSampleRate: _outputSampleRate,
      ),
    );
  }

  @override
  NativeAudioClip clip(String path, {double volume = 1, int voices = 3}) {
    final existing = _pathClipCache[path];
    if (existing != null) {
      final updated = existing.withPlaybackDefaults(
        baseVolume: volume,
        maxVoices: voices,
      );
      _pathClipCache[path] = updated;
      return updated;
    }
    final loaded = NativeAudioClip.fromFile(
      path,
      rootDirectory: rootDirectory,
      baseVolume: volume,
      maxVoices: voices,
      fallbackSampleRate: _outputSampleRate,
    );
    _pathClipCache[path] = loaded;
    return loaded;
  }

  @override
  NativeAudioChannel createChannel() {
    final channel = NativeAudioChannel._(this);
    if (!_disposed) {
      _channels.add(channel);
    }
    return channel;
  }

  @override
  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1}) {
    if (_disposed || _muted) return;
    final resolved = resolveClip(clip);

    // Enforce per-clip concurrency cap by stealing the oldest matching voice.
    var matchingCount = 0;
    _VoiceState? oldestMatching;
    for (final voice in _oneShots) {
      if (voice.clip?.path == resolved.path) {
        oldestMatching ??= voice;
        matchingCount++;
      }
    }
    if (matchingCount >= resolved.maxVoices && oldestMatching != null) {
      _oneShots.remove(oldestMatching);
    }

    while (_oneShots.length >= maxOneShotVoices) {
      _oneShots.removeFirst();
    }

    final voice = _VoiceState()
      ..clip = resolved
      ..volume = volume
      ..pitch = pitch
      ..loop = false
      ..playing = true;
    _oneShots.addLast(voice);
  }

  @override
  void setListenerPose({
    Vec3 position = const Vec3(0, 0, 0),
    Vec3 forward = const Vec3(0, 0, -1),
    Vec3 up = const Vec3(0, 1, 0),
  }) {
    listenerPosition = position;
    listenerForward = forward;
    listenerUp = up;
  }

  /// Mixes [frameCount] interleaved stereo frames from all active channels and
  /// one-shot voices, advancing playheads and retiring finished one-shots.
  Float32List mixFrames(int frameCount) {
    if (frameCount <= 0 || _disposed) {
      return Float32List(0);
    }
    final out = Float32List(frameCount * 2);
    final sampleRate = _outputSampleRate;
    final isMuted = _muted;

    for (var i = 0; i < _channels.length; i++) {
      _mixVoice(_channels[i]._voice, out, frameCount, sampleRate, isMuted);
    }

    if (_oneShots.isNotEmpty) {
      final remaining = <_VoiceState>[];
      while (_oneShots.isNotEmpty) {
        final voice = _oneShots.removeFirst();
        _mixVoice(voice, out, frameCount, sampleRate, isMuted);
        if (voice.playing) {
          remaining.add(voice);
        }
      }
      _oneShots.addAll(remaining);
    }

    if (!isMuted) {
      _softClampBuffer(out);
    }
    return out;
  }

  /// Mixes [frames] (defaults to `config.framesPerBuffer`) stereo frames and
  /// streams them to [sink], returning the number of scalar samples consumed.
  int pumpAudio({int? frames}) {
    if (_disposed) return 0;
    final frameCount = frames ?? config.framesPerBuffer;
    if (frameCount <= 0) return 0;

    final mixed = mixFrames(frameCount);
    if (!sink.isOpen) return 0;
    return sink.writeInterleavedFloat32(mixed);
  }

  static void _mixVoice(
    _VoiceState voice,
    Float32List out,
    int frameCount,
    int outputSampleRate,
    bool muted,
  ) {
    final clip = voice.clip;
    if (!voice.playing || voice.paused || clip == null) return;

    final clipFrames = clip.frameCount;
    if (clipFrames <= 0) {
      if (!voice.loop) {
        voice.playing = false;
      }
      return;
    }

    final safePitch = voice.pitch.isFinite ? voice.pitch.clamp(0.05, 8.0) : 1.0;
    final step = (clip.sampleRate / outputSampleRate) * safePitch;
    final rawVol = voice.volume.isFinite ? math.max(0.0, voice.volume) : 0.0;
    final gain = clip.baseVolume * rawVol;

    final pan = voice.pan.isFinite ? voice.pan.clamp(-1.0, 1.0) : 0.0;
    final gainL = gain * (1.0 - pan).clamp(0.0, 1.0);
    final gainR = gain * (1.0 + pan).clamp(0.0, 1.0);

    final cutoff = voice.lowPassCutoffHz.isFinite
        ? voice.lowPassCutoffHz.clamp(20.0, 24000.0)
        : 20000.0;
    final useLpf = cutoff < 18000.0;
    final double lpfAlpha;
    if (useLpf) {
      final omega = 2.0 * math.pi * cutoff;
      lpfAlpha = omega / (omega + outputSampleRate);
    } else {
      lpfAlpha = 1.0;
    }

    final wet = voice.reverbWet.isFinite
        ? voice.reverbWet.clamp(0.0, 1.0)
        : 0.0;
    final useReverb = wet > 0.0;

    final samples = clip.samples;
    final chCount = clip.channels;
    var cursor = voice.cursor;
    var lpfL = voice.lpfL;
    var lpfR = voice.lpfR;

    for (var f = 0; f < frameCount; f++) {
      if (cursor >= clipFrames) {
        if (voice.loop) {
          cursor %= clipFrames;
        } else {
          voice.playing = false;
          break;
        }
      }

      final i0 = cursor.floor();
      final frac = cursor - i0;
      final int i1;
      if (i0 + 1 < clipFrames) {
        i1 = i0 + 1;
      } else if (voice.loop) {
        i1 = 0;
      } else {
        i1 = i0;
      }

      double sampleL;
      double sampleR;
      if (chCount == 1) {
        final s0 = samples[i0];
        final s1 = samples[i1];
        final m = s0 + (s1 - s0) * frac;
        sampleL = m;
        sampleR = m;
      } else {
        final b0 = i0 * 2;
        final b1 = i1 * 2;
        sampleL = samples[b0] + (samples[b1] - samples[b0]) * frac;
        sampleR = samples[b0 + 1] + (samples[b1 + 1] - samples[b0 + 1]) * frac;
      }

      if (useLpf) {
        lpfL += lpfAlpha * (sampleL - lpfL);
        lpfR += lpfAlpha * (sampleR - lpfR);
        sampleL = lpfL;
        sampleR = lpfR;
      } else {
        lpfL = sampleL;
        lpfR = sampleR;
      }

      if (useReverb) {
        (sampleL, sampleR) = voice.processReverb(
          sampleL,
          sampleR,
          wet,
          outputSampleRate,
        );
      }

      if (!muted) {
        out[f * 2] += sampleL * gainL;
        out[f * 2 + 1] += sampleR * gainR;
      }

      cursor += step;
      if (cursor >= clipFrames) {
        if (voice.loop) {
          cursor %= clipFrames;
        } else {
          voice.playing = false;
          break;
        }
      }
    }

    voice.cursor = cursor;
    voice.lpfL = lpfL;
    voice.lpfR = lpfR;
  }

  static void _softClampBuffer(Float32List buffer) {
    for (var i = 0; i < buffer.length; i++) {
      final x = buffer[i];
      if (!x.isFinite) {
        buffer[i] = 0.0;
        continue;
      }
      final absX = x.abs();
      if (absX <= _softKneeThreshold) {
        continue;
      }
      final excess = absX - _softKneeThreshold;
      final compressed =
          _softKneeThreshold +
          _softKneeHeadroom * (excess / (_softKneeHeadroom + excess));
      final clamped = compressed > 1.0 ? 1.0 : compressed;
      buffer[i] = x < 0.0 ? -clamped : clamped;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final ch in List<NativeAudioChannel>.of(_channels)) {
      ch.dispose();
    }
    _channels.clear();
    _oneShots.clear();
    _pathClipCache.clear();
    sink.close();
  }
}
