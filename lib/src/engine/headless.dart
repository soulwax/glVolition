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

/// Input driven by test code: call [press]/[release], then [endFrame] after
/// each engine tick, exactly as a real host would.
final class ScriptedInput implements Input {
  final Set<String> _down = {};
  final Set<String> _pressed = {};
  final Set<String> _released = {};

  void press(String code) {
    if (_down.add(code)) _pressed.add(code);
  }

  void release(String code) {
    if (_down.remove(code)) _released.add(code);
  }

  void endFrame() {
    _pressed.clear();
    _released.clear();
    pointerPressed = false;
    pointerReleased = false;
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
}

final class HeadlessGraphics implements Graphics {
  @override
  FrameEnvironment environment = const FrameEnvironment(clearColor: LinearColor(0, 0, 0));
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
  void shakeCamera({double trauma = 0.5, double? rotation}) => shakeTrauma += trauma;

  @override
  void setShaderUniform(
    ShaderTarget target,
    String name,
    ShaderUniform value,
  ) {
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
}

final class _NoAssets implements AssetLoader {
  const _NoAssets();

  @override
  Future<ModelAsset> loadModel(String path, {MaterialOverride? materialOverride}) =>
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

final class _SilentChannel implements AudioChannel {
  @override
  bool isPlaying = false;
  bool _loop = false;

  @override
  void play(AudioClip clip, {double volume = 1, double pitch = 1, bool loop = false}) {
    _loop = loop;
    isPlaying = _loop;
  }

  @override
  void stop() => isPlaying = false;
  @override
  set volume(double value) {}
  @override
  set pitch(double value) {}
  @override
  void dispose() => isPlaying = false;
}

final class SilentAudio implements AudioDevice {
  @override
  bool muted = false;

  /// Paths of every one-shot requested, in order.
  final List<String> played = [];

  @override
  AudioClip clip(String path, {double volume = 1, int voices = 3}) => _SilentClip(path);

  @override
  AudioChannel createChannel() => _SilentChannel();

  @override
  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1}) {
    if (!muted) played.add(clip.path);
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
