import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:pixeldart/rendering/webgl/pixeldart_app.dart';
import 'package:web/web.dart' as web;

import '../../rocket.dart';
import 'inspector_overlay.dart';
import 'web_audio.dart';
import 'web_graphics.dart';
import 'web_input.dart';

export 'web_audio.dart';
export 'web_graphics.dart';
export 'web_input.dart';

/// Mounts an [Engine] onto a `<canvas>` element and drives it from
/// `requestAnimationFrame` through [PixeldartApp].
final class WebEngineHost implements EngineHost {
  final PixeldartApp app;

  @override
  late final WebInput input = WebInput(app.input, canvas: app.canvas);
  @override
  late final WebGraphics graphics = WebGraphics(app);
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
  /// unavailable). Call [WebEngineRunner.start] once initial assets/scenes are
  /// ready.
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
    app.onFrame = (ctx) {
      engine.encodeFrame(ctx.encoder);
      input.endFrame();
    };
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
    graphics.disposeRenderTargets();
    input.dispose();
    audio.dispose();
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

final class _WebAssets implements AssetLoader {
  final PixeldartApp _app;
  _WebAssets(this._app);

  @override
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  }) => _app.loadModel(path, materialOverride: materialOverride);

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
