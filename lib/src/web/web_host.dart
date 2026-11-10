import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:pixeldart/rendering/webgl/pixeldart_app.dart';
import 'package:web/web.dart' as web;

import '../../rocket.dart';
import 'inspector_overlay.dart';

/// Mounts an [Engine] onto a `<canvas>` element and drives it from
/// `requestAnimationFrame` through [PixeldartApp].
final class WebEngineHost implements EngineHost {
  final PixeldartApp app;

  @override
  late final Input input = _WebInput(app.input);
  @override
  late final Graphics graphics = _WebGraphics(app);
  @override
  late final AssetLoader assets = _WebAssets(app);
  @override
  final WebAudioDevice audio = WebAudioDevice();
  @override
  final KeyValueStore storage = const _LocalStorageStore();

  late final JSFunction _preventScroll = ((web.KeyboardEvent e) {
    final code = e.code;
    if (code == 'Space' || code.startsWith('Arrow')) e.preventDefault();
  }).toJS;

  Engine? _engine;
  InspectorOverlay? _inspector;
  bool _hotStateEnabled = false;

  late final JSFunction _onBeforeUnload = ((web.Event _) {
    final eng = _engine;
    if (!_hotStateEnabled || eng == null) return;
    try {
      final snap = jsonEncode(eng.captureSessionSnapshot());
      web.window.sessionStorage.setItem('__rocket_hot_state', snap);
    } catch (_) {}
  }).toJS;

  WebEngineHost(this.app) {
    web.window.addEventListener('keydown', _preventScroll);
    web.window.addEventListener('beforeunload', _onBeforeUnload);
  }

  /// Creates the WebGL2 renderer on [canvas], boots an [Engine] with
  /// [initialScene], and returns the bound [Engine] (or `null` when WebGL2 is
  /// unavailable). Call [start] once initial assets/scenes are ready.
  static Future<WebEngineRunner?> mount(
    web.HTMLCanvasElement canvas, {
    QualityProfile requestedProfile = QualityProfile.clean,
    double maxDevicePixelRatio = 2.0,
    bool showStats = false,
    bool enableInspector = true,
    bool enableHotState = false,
    void Function(ComponentRegistry registry)? registerSpecs,
    Scene? initialScene,
  }) async {
    final app = await PixeldartApp.mount(
      canvas,
      requestedProfile: requestedProfile,
      maxDevicePixelRatio: maxDevicePixelRatio,
      showStats: showStats,
      enableOrbitControls: false,
    );
    if (app == null) return null;
    final host = WebEngineHost(app).._hotStateEnabled = enableHotState;
    final engine = Engine(host, initialScene: initialScene);
    registerSpecs?.call(engine.registry);
    host._bind(engine, enableInspector: enableInspector);
    if (enableHotState) {
      host.tryRestoreHotState();
    }
    return WebEngineRunner._(host, engine);
  }

  void _bind(Engine engine, {bool enableInspector = true}) {
    _engine = engine;
    if (enableInspector) {
      _inspector = InspectorOverlay(engine, app.canvas);
    }
    app.onBeforeFrame = (_, dt) => engine.step(dt);
    app.onFrame = (ctx) => engine.encodeFrame(ctx.encoder);
  }

  /// Restores any snapshot stored in `sessionStorage['__rocket_hot_state']`
  /// and removes the key after consumption (E2-3).
  bool tryRestoreHotState() {
    final eng = _engine;
    if (eng == null) return false;
    try {
      final raw = web.window.sessionStorage.getItem('__rocket_hot_state');
      if (raw == null || raw.isEmpty) return false;
      web.window.sessionStorage.removeItem('__rocket_hot_state');
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        eng.restoreSessionSnapshot(decoded);
        return true;
      }
    } catch (_) {}
    return false;
  }

  InspectorOverlay? get inspector => _inspector;

  @override
  SceneNode get sceneRoot => app.scene;

  @override
  void reportError(Object error, StackTrace stack) {
    web.console.error('Rocket engine error: $error\n$stack'.toJS);
  }

  void dispose() {
    web.window.removeEventListener('keydown', _preventScroll);
    web.window.removeEventListener('beforeunload', _onBeforeUnload);
    _inspector?.dispose();
    _engine?.dispose();
    app.dispose();
  }
}

/// Pair of [WebEngineHost] and [Engine] returned by [WebEngineHost.mount].
final class WebEngineRunner {
  final WebEngineHost host;
  final Engine engine;

  WebEngineRunner._(this.host, this.engine);

  PixeldartApp get app => host.app;
  Scene get scene => engine.scene;

  void start() => host.app.start();
  void stop() => host.app.stop();
  void dispose() => host.dispose();
}

final class _WebInput implements Input {
  final InputState _state;
  _WebInput(this._state);

  @override
  bool isDown(String code) => _state.isDown(code);
  @override
  bool wasPressed(String code) => _state.wasPressed(code);
  @override
  bool wasReleased(String code) => _state.wasReleased(code);
  @override
  double get pointerX => _state.pointerX;
  @override
  double get pointerY => _state.pointerY;
  @override
  bool get pointerDown => _state.pointerDown;
  @override
  bool get pointerPressed => _state.pointerPressed;
  @override
  bool get pointerReleased => _state.pointerReleased;
}

final class _WebGraphics implements Graphics {
  final PixeldartApp _app;
  _WebGraphics(this._app);

  @override
  FrameEnvironment get environment => _app.environment;
  @override
  set environment(FrameEnvironment value) => _app.environment = value;

  @override
  PostProcessState get post => _app.post;
  @override
  set post(PostProcessState value) => _app.post = value;

  @override
  CameraController? get camera => _app.cameraController;
  @override
  set camera(CameraController? value) => _app.cameraController = value;

  @override
  double get aspect => _app.surface.pixelWidth / _app.surface.pixelHeight;

  @override
  int get viewportWidth => _app.surface.pixelWidth;

  @override
  int get viewportHeight => _app.surface.pixelHeight;

  @override
  MeshHandle createMesh(MeshData data, {String? debugLabel}) =>
      _app.createMesh(data, debugLabel: debugLabel);

  @override
  MaterialHandle createMaterial(MaterialDefinition definition) =>
      _app.createMaterial(definition);

  @override
  MaterialHandle createParticleMaterial({
    required String key,
    LinearColor color = const LinearColor(1, 1, 1),
    double glow = 2,
  }) =>
      _app.createParticleMaterial(key: key, color: color, glow: glow);

  @override
  TextureHandle createTexture({
    required int width,
    required int height,
    Uint8List? pixels,
    bool hasMips = false,
    GpuTextureFilter minFilter = GpuTextureFilter.linear,
    GpuTextureFilter magFilter = GpuTextureFilter.linear,
    GpuTextureWrap wrap = GpuTextureWrap.clampToEdge,
    double anisotropy = 1,
    String? debugLabel,
  }) {
    final handle = _app.createTexture(
      width: width,
      height: height,
      pixels: pixels,
      hasMips: hasMips,
      minFilter: minFilter,
      magFilter: magFilter,
      wrap: wrap,
      anisotropy: anisotropy,
      debugLabel: debugLabel,
    );
    if (hasMips) {
      _app.resources.finalizeTextureMips(handle);
    }
    return handle;
  }

  @override
  void releaseMesh(MeshHandle handle) => _app.resources.releaseMesh(handle);

  @override
  void releaseMaterial(MaterialHandle handle) =>
      _app.resources.releaseMaterial(handle);

  @override
  void releaseTexture(TextureHandle handle) =>
      _app.resources.releaseTexture(handle);

  @override
  void addEmitter(ParticleEmitter emitter) => _app.addEmitter(emitter);

  @override
  void removeEmitter(ParticleEmitter emitter) => _app.removeEmitter(emitter);

  @override
  void shakeCamera({double trauma = 0.5, double? rotation}) =>
      _app.shakeCamera(trauma: trauma, rotation: rotation);

  @override
  Ray? screenRay(double x, double y) {
    final rect = _app.canvas.getBoundingClientRect();
    if (_app.canvas.width <= 0 || _app.canvas.height <= 0) return null;
    final clientX = rect.left + x * rect.width / _app.canvas.width;
    final clientY = rect.top + y * rect.height / _app.canvas.height;
    return _app.screenRay(clientX, clientY);
  }
}

final class _WebAssets implements AssetLoader {
  final PixeldartApp _app;
  _WebAssets(this._app);

  @override
  Future<ModelAsset> loadModel(String path, {MaterialOverride? materialOverride}) =>
      _app.loadModel(path, materialOverride: materialOverride);

  @override
  Future<Uint8List> loadBytes(String path) async {
    final response = await web.window.fetch(path.toJS).toDart;
    if (!response.ok) {
      throw StateError('loadBytes: failed to fetch $path (${response.status})');
    }
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<String> loadText(String path) async {
    final response = await web.window.fetch(path.toJS).toDart;
    if (!response.ok) {
      throw StateError('loadText: failed to fetch $path (${response.status})');
    }
    return (await response.text().toDart).toDart;
  }
}

final class _WebAudioClip implements AudioClip {
  @override
  final String path;
  final double baseVolume;
  final List<web.HTMLAudioElement> pool;
  int next = 0;

  _WebAudioClip(this.path, this.baseVolume, int voices)
      : pool = [
          for (var i = 0; i < voices; i++)
            web.HTMLAudioElement()
              ..src = path
              ..preload = 'auto'
              ..volume = baseVolume.clamp(0.0, 1.0),
        ];
}

final class _WebAudioChannel implements AudioChannel {
  final WebAudioDevice _device;
  web.HTMLAudioElement? _el;
  double _baseVolume = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;
  bool _playing = false;

  _WebAudioChannel(this._device);

  @override
  bool get isPlaying => _playing && (_el != null && !_el!.paused);

  @override
  void play(AudioClip clip, {double volume = 1, double pitch = 1, bool loop = false}) {
    final base = clip is _WebAudioClip ? clip.baseVolume : 1.0;
    _baseVolume = base;
    _volume = volume;
    _pitch = pitch;
    final el = _el ??= web.HTMLAudioElement()..preload = 'auto';
    if (!el.src.endsWith(clip.path)) {
      el.src = clip.path;
    }
    el
      ..loop = loop
      ..volume = (_baseVolume * _volume).clamp(0.0, 1.0)
      ..playbackRate = _pitch.clamp(0.25, 4.0);
    _playing = true;
    _syncMute();
  }

  void _syncMute() {
    final el = _el;
    if (el == null) return;
    if (_playing && !_device.muted) {
      if (el.paused) WebAudioDevice._safePlay(el);
    } else if (!el.paused) {
      el.pause();
    }
  }

  @override
  void stop() {
    _playing = false;
    final el = _el;
    if (el != null && !el.paused) el.pause();
  }

  @override
  set volume(double value) {
    _volume = value;
    _el?.volume = (_baseVolume * _volume).clamp(0.0, 1.0);
  }

  @override
  set pitch(double value) {
    _pitch = value;
    _el?.playbackRate = _pitch.clamp(0.25, 4.0);
    _syncMute();
  }

  @override
  void dispose() {
    stop();
    _device._channels.remove(this);
    _el = null;
  }
}

final class WebAudioDevice implements AudioDevice {
  bool _muted = false;
  final List<_WebAudioChannel> _channels = [];

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    for (final ch in _channels) {
      ch._syncMute();
    }
  }

  @override
  AudioClip clip(String path, {double volume = 1, int voices = 3}) =>
      _WebAudioClip(path, volume, voices);

  @override
  AudioChannel createChannel() {
    final ch = _WebAudioChannel(this);
    _channels.add(ch);
    return ch;
  }

  @override
  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1}) {
    if (_muted || clip is! _WebAudioClip || clip.pool.isEmpty) return;
    final i = clip.next;
    clip.next = (i + 1) % clip.pool.length;
    final voice = clip.pool[i]
      ..currentTime = 0
      ..volume = (clip.baseVolume * volume).clamp(0.0, 1.0)
      ..playbackRate = pitch.clamp(0.25, 4.0);
    _safePlay(voice);
  }

  // Browser autoplay policies reject play() before the first user gesture;
  // swallow that rejection rather than surfacing an unhandled error.
  static void _safePlay(web.HTMLAudioElement voice) {
    voice.play().toDart.then((_) {}, onError: (Object _) {});
  }
}

final class _LocalStorageStore implements KeyValueStore {
  const _LocalStorageStore();

  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {}
  }

  @override
  void remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }
}
