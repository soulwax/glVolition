part of '../engine.dart';

/// Everything the engine needs from the platform. The core never imports
/// `package:web` or `dart:io`; a host (browser, native shell, headless test)
/// implements these interfaces instead.
abstract interface class EngineHost {
  /// The scene graph root the host renders. The engine parents each scene
  /// under it.
  SceneNode get sceneRoot;

  Input get input;
  Graphics get graphics;
  AssetLoader get assets;
  AudioDevice get audio;
  KeyValueStore get storage;

  /// Called for exceptions thrown by game code. The engine keeps running.
  void reportError(Object error, StackTrace stack);
}

/// Raw device input. Key codes are `KeyboardEvent.code` strings
/// (`KeyW`, `ArrowLeft`, `Space`, `ShiftLeft`, ...) on every platform.
/// Pointer coordinates are in drawing-buffer pixels.
abstract interface class Input {
  bool isDown(String code);
  bool wasPressed(String code);
  bool wasReleased(String code);

  double get pointerX;
  double get pointerY;
  bool get pointerDown;
  bool get pointerPressed;
  bool get pointerReleased;
}

abstract interface class Graphics {
  FrameEnvironment get environment;
  set environment(FrameEnvironment value);

  PostProcessState get post;
  set post(PostProcessState value);

  CameraController? get camera;
  set camera(CameraController? value);

  /// Drawing-buffer width / height.
  double get aspect;

  int get viewportWidth;
  int get viewportHeight;

  MeshHandle createMesh(MeshData data, {String? debugLabel});
  MaterialHandle createMaterial(MaterialDefinition definition);
  MaterialHandle createParticleMaterial({
    required String key,
    LinearColor color = const LinearColor(1, 1, 1),
    double glow = 2,
  });
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
  });

  void releaseMesh(MeshHandle handle);
  void releaseMaterial(MaterialHandle handle);
  void releaseTexture(TextureHandle handle);

  void addEmitter(ParticleEmitter emitter);
  void removeEmitter(ParticleEmitter emitter);

  void shakeCamera({double trauma = 0.5, double? rotation});

  /// A world-space ray through drawing-buffer pixel ([x], [y]) for the
  /// camera rendered last frame, or null when unavailable.
  Ray? screenRay(double x, double y);
}

abstract interface class AssetLoader {
  Future<ModelAsset> loadModel(String path, {MaterialOverride? materialOverride});
  Future<Uint8List> loadBytes(String path);
  Future<String> loadText(String path);
}

/// An opaque, host-owned sound asset.
abstract interface class AudioClip {
  String get path;
}

/// One voice that plays one clip at a time.
abstract interface class AudioChannel {
  void play(AudioClip clip, {double volume = 1, double pitch = 1, bool loop = false});
  void stop();
  bool get isPlaying;
  set volume(double value);
  set pitch(double value);
  void dispose();
}

abstract interface class AudioDevice {
  bool get muted;
  set muted(bool value);

  /// Declares a clip. [voices] bounds how many one-shots of it may overlap.
  AudioClip clip(String path, {double volume = 1, int voices = 3});

  AudioChannel createChannel();

  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1});
}

abstract interface class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}
