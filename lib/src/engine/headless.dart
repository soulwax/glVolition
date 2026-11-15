part of '../engine.dart';

/// A host with no window, GPU or speakers: for tests, servers and tools.
/// Resource creation mints placeholder handles; nothing is drawn.
final class HeadlessHost implements EngineHost {
  @override
  final SceneNode sceneRoot = SceneNode.group(name: 'root');
  @override
  final ScriptedInput input = ScriptedInput();
  @override
  final HeadlessGraphics graphics = HeadlessGraphics();
  @override
  final AssetLoader assets = const _NoAssets();
  @override
  final SilentAudio audio = SilentAudio();
  @override
  final MemoryStore storage = MemoryStore();

  final List<Object> errors = [];

  /// When true (the default) errors are rethrown, so tests fail loudly.
  bool rethrowErrors;

  HeadlessHost({this.rethrowErrors = true});

  @override
  void reportError(Object error, StackTrace stack) {
    errors.add(error);
    if (rethrowErrors) Error.throwWithStackTrace(error, stack);
  }
}

/// Alias matching Wave 10 host contract naming.
typedef HeadlessInput = ScriptedInput;

/// Input driven by test code: call [press]/[release], then [endFrame] after
/// each engine tick, exactly as a real host would.
final class ScriptedInput implements Input {
  final Set<String> _down = {};
  final Set<String> _pressed = {};
  final Set<String> _released = {};
  final List<TouchPoint> _touches = [];
  final Map<int, Map<int, double>> _gamepadAxes = {};
  final Map<int, Set<int>> _gamepadButtons = {};
  int _gamepadCount = 0;
  final StringBuffer _textInput = StringBuffer();

  void press(String code) {
    if (_down.add(code)) _pressed.add(code);
  }

  void release(String code) {
    if (_down.remove(code)) _released.add(code);
  }

  void scrollWheel(double dx, double dy) {
    wheelDeltaX += dx;
    wheelDeltaY += dy;
  }

  void addPointerDelta(double dx, double dy) {
    pointerDeltaX += dx;
    pointerDeltaY += dy;
  }

  void setTouches(Iterable<TouchPoint> activeTouches) {
    _touches
      ..clear()
      ..addAll(activeTouches);
  }

  void clearTouches() => _touches.clear();

  void setGamepadConnected(int index, bool connected) {
    if (connected) {
      if (index + 1 > _gamepadCount) _gamepadCount = index + 1;
      _gamepadAxes.putIfAbsent(index, () => {});
      _gamepadButtons.putIfAbsent(index, () => {});
    } else {
      _gamepadAxes.remove(index);
      _gamepadButtons.remove(index);
      if (index + 1 >= _gamepadCount) {
        var highest = -1;
        for (final k in _gamepadAxes.keys) {
          if (k > highest) highest = k;
        }
        for (final k in _gamepadButtons.keys) {
          if (k > highest) highest = k;
        }
        _gamepadCount = highest + 1;
      }
    }
  }

  void setGamepadAxis(int gamepadIndex, int axisIndex, double value) {
    setGamepadConnected(gamepadIndex, true);
    _gamepadAxes[gamepadIndex]![axisIndex] = value.clamp(-1.0, 1.0);
  }

  void setGamepadButton(int gamepadIndex, int buttonIndex, bool down) {
    setGamepadConnected(gamepadIndex, true);
    final buttons = _gamepadButtons[gamepadIndex]!;
    if (down) {
      buttons.add(buttonIndex);
    } else {
      buttons.remove(buttonIndex);
    }
  }

  void appendTextInput(String text) => _textInput.write(text);

  void endFrame() {
    _pressed.clear();
    _released.clear();
    pointerPressed = false;
    pointerReleased = false;
    wheelDeltaX = 0.0;
    wheelDeltaY = 0.0;
    pointerDeltaX = 0.0;
    pointerDeltaY = 0.0;
    _textInput.clear();
  }

  @override
  bool isDown(String code) => _down.contains(code);
  @override
  bool wasPressed(String code) => _pressed.contains(code);
  @override
  bool wasReleased(String code) => _released.contains(code);

  @override
  double pointerX = 0;
  @override
  double pointerY = 0;
  @override
  bool pointerDown = false;
  @override
  bool pointerPressed = false;
  @override
  bool pointerReleased = false;

  @override
  double wheelDeltaX = 0;
  @override
  double wheelDeltaY = 0;
  @override
  double pointerDeltaX = 0;
  @override
  double pointerDeltaY = 0;
  @override
  bool pointerLocked = false;

  @override
  void requestPointerLock() {
    pointerLocked = true;
  }

  @override
  void exitPointerLock() {
    pointerLocked = false;
  }

  @override
  List<TouchPoint> get touches => List<TouchPoint>.unmodifiable(_touches);

  @override
  int get gamepadCount => _gamepadCount;

  @override
  double gamepadAxis(int gamepadIndex, int axisIndex) =>
      _gamepadAxes[gamepadIndex]?[axisIndex] ?? 0.0;

  @override
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex) =>
      _gamepadButtons[gamepadIndex]?.contains(buttonIndex) ?? false;

  @override
  String get textInputBuffer => _textInput.toString();
}

final class HeadlessGraphics implements Graphics {
  @override
  FrameEnvironment environment = const FrameEnvironment(
    clearColor: LinearColor(0, 0, 0),
  );
  @override
  PostProcessState post = PostProcessState.off;
  @override
  CameraController? camera;
  @override
  double aspect = 16 / 9;
  @override
  int viewportWidth = 1280;
  @override
  int viewportHeight = 720;
  @override
  int visibilityMask = -1;

  final List<ParticleEmitter> emitters = [];
  final Set<MeshHandle> liveMeshes = {};
  final Set<MaterialHandle> liveMaterials = {};
  final Set<TextureHandle> liveTextures = {};
  final Set<RenderTargetHandle> liveRenderTargets = {};
  final List<CameraRenderDescriptor> renderedCameraPasses = [];
  int activeViewportX = 0;
  int activeViewportY = 0;
  int activeViewportWidth = 1280;
  int activeViewportHeight = 720;
  final Map<ShaderTarget, Map<String, ShaderUniform>> shaderUniforms = {};
  final Map<ShaderTarget, Map<String, TextureHandle>> shaderTextures = {};
  Map<ShaderSlot, ShaderOverride> shaderOverrides = const {};
  Map<String, ShaderOverride> postEffects = const {};
  int configureCalls = 0;
  String _lastShaderSignature = shaderConfigurationSignature(
    const {},
    const {},
  );
  double shakeTrauma = 0;
  int _slot = 0;

  @override
  MeshHandle createMesh(MeshData data, {String? debugLabel}) {
    final h = MeshHandle(_slot++, 0, debugLabel);
    liveMeshes.add(h);
    return h;
  }

  @override
  MaterialHandle createMaterial(MaterialDefinition definition) {
    final h = MaterialHandle(_slot++, 0, definition.key);
    liveMaterials.add(h);
    return h;
  }

  @override
  MaterialHandle createParticleMaterial({
    required String key,
    LinearColor color = const LinearColor(1, 1, 1),
    double glow = 2,
  }) {
    final h = MaterialHandle(_slot++, 0, key);
    liveMaterials.add(h);
    return h;
  }

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
    final h = TextureHandle(_slot++, 0, debugLabel);
    liveTextures.add(h);
    return h;
  }

  @override
  void releaseMesh(MeshHandle handle) => liveMeshes.remove(handle);

  @override
  void releaseMaterial(MaterialHandle handle) => liveMaterials.remove(handle);

  @override
  void releaseTexture(TextureHandle handle) => liveTextures.remove(handle);

  @override
  void addEmitter(ParticleEmitter emitter) => emitters.add(emitter);

  @override
  void removeEmitter(ParticleEmitter emitter) => emitters.remove(emitter);

  @override
  void shakeCamera({double trauma = 0.5, double? rotation}) =>
      shakeTrauma += trauma;

  @override
  void setShaderUniform(ShaderTarget target, String name, ShaderUniform value) {
    shaderUniforms.putIfAbsent(target, () => {})[name] = value;
  }

  @override
  void setShaderTexture(
    ShaderTarget target,
    String name,
    TextureHandle texture,
  ) {
    shaderTextures.putIfAbsent(target, () => {})[name] = texture;
  }

  @override
  void applyShaderConfiguration({
    Map<ShaderSlot, ShaderOverride> shaderOverrides = const {},
    Map<String, ShaderOverride> postEffects = const {},
  }) {
    final nextOverrides = Map<ShaderSlot, ShaderOverride>.unmodifiable(
      shaderOverrides,
    );
    final nextEffects = Map<String, ShaderOverride>.unmodifiable(postEffects);
    final signature = shaderConfigurationSignature(nextOverrides, nextEffects);
    this.shaderOverrides = nextOverrides;
    this.postEffects = nextEffects;
    if (signature == _lastShaderSignature) return;
    _lastShaderSignature = signature;
    configureCalls += 1;
  }

  @override
  Ray? screenRay(double x, double y) => null;

  @override
  RenderTargetHandle createRenderTarget({
    required int width,
    required int height,
    String? debugLabel,
  }) {
    final slot = _slot++;
    final colorTex = TextureHandle(slot, 0, debugLabel);
    liveTextures.add(colorTex);
    final handle = RenderTargetHandle(
      slot,
      width: width,
      height: height,
      colorTexture: colorTex,
      debugLabel: debugLabel,
    );
    liveRenderTargets.add(handle);
    return handle;
  }

  @override
  void releaseRenderTarget(RenderTargetHandle handle) {
    liveRenderTargets.remove(handle);
    liveTextures.remove(handle.colorTexture);
  }

  @override
  void setViewport(int x, int y, int width, int height) {
    activeViewportX = x;
    activeViewportY = y;
    activeViewportWidth = width;
    activeViewportHeight = height;
  }

  @override
  void renderFrameToTarget(
    RenderTargetHandle? target, {
    required CameraRenderDescriptor descriptor,
  }) {
    final rect = descriptor.normalizedViewportRect;
    final targetW = target?.width ?? viewportWidth;
    final targetH = target?.height ?? viewportHeight;
    final pxX = (rect.x * targetW).round();
    final pxY = (rect.y * targetH).round();
    final pxW = (rect.z * targetW).round().clamp(1, targetW);
    final pxH = (rect.w * targetH).round().clamp(1, targetH);
    setViewport(pxX, pxY, pxW, pxH);
    visibilityMask = descriptor.visibilityMask;
    renderedCameraPasses.add(descriptor);
  }
}

final class _NoAssets implements AssetLoader {
  const _NoAssets();

  @override
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  }) =>
      Future.error(UnsupportedError('HeadlessHost cannot load models ($path)'));

  @override
  Future<Uint8List> loadBytes(String path) =>
      Future.error(UnsupportedError('HeadlessHost cannot load files ($path)'));

  @override
  Future<String> loadText(String path) =>
      Future.error(UnsupportedError('HeadlessHost cannot load files ($path)'));
}

final class _SilentClip implements AudioClip {
  @override
  final String path;
  _SilentClip(this.path);
}

/// Inspectable mock channel backing [SilentAudio] / [HeadlessAudio].
final class _SilentChannel implements AudioChannel {
  @override
  bool isPlaying = false;
  bool _loop = false;
  double lastVolume = 1.0;
  double lastPitch = 1.0;
  double lastPan = 0.0;
  double lastLowPassCutoffHz = 20000.0;
  double lastLowPassResonance = 0.707;
  double lastReverbSend = 0.0;
  bool disposed = false;

  @override
  void play(
    AudioClip clip, {
    double volume = 1,
    double pitch = 1,
    bool loop = false,
  }) {
    lastVolume = volume;
    lastPitch = pitch;
    _loop = loop;
    isPlaying = _loop;
  }

  @override
  void stop() => isPlaying = false;
  @override
  set volume(double value) => lastVolume = value;
  @override
  set pitch(double value) => lastPitch = value;
  @override
  void setPan(double pan) => lastPan = pan.clamp(-1.0, 1.0);
  @override
  void setLowPass(double cutoffHz, {double resonance = 0.707}) {
    lastLowPassCutoffHz = cutoffHz;
    lastLowPassResonance = resonance;
  }

  @override
  void setReverbSend(double wet) => lastReverbSend = wet.clamp(0.0, 1.0);

  @override
  void dispose() {
    disposed = true;
    isPlaying = false;
  }
}

/// Alias matching Wave 10 host contract naming.
typedef HeadlessAudio = SilentAudio;

final class SilentAudio implements AudioDevice {
  @override
  bool muted = false;

  /// Paths of every one-shot requested, in order.
  final List<String> played = [];

  /// Channels created on this device, retained for DSP inspection in tests.
  final List<_SilentChannel> channels = [];

  Vec3 listenerPosition = const Vec3(0, 0, 0);
  Vec3 listenerForward = const Vec3(0, 0, -1);
  Vec3 listenerUp = const Vec3(0, 1, 0);

  @override
  AudioClip clip(String path, {double volume = 1, int voices = 3}) =>
      _SilentClip(path);

  @override
  AudioChannel createChannel() {
    final ch = _SilentChannel();
    channels.add(ch);
    return ch;
  }

  @override
  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1}) {
    if (!muted) played.add(clip.path);
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
}

final class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}
