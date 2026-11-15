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

/// Active multi-touch contact point in drawing-buffer pixel coordinates.
final class TouchPoint {
  final int id;
  final double x;
  final double y;
  final double pressure;

  const TouchPoint({
    required this.id,
    required this.x,
    required this.y,
    this.pressure = 1.0,
  });

  @override
  bool operator ==(Object other) =>
      other is TouchPoint &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(id, x, y, pressure);
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

  /// Horizontal scroll-wheel delta accumulated during the current frame.
  double get wheelDeltaX;

  /// Vertical scroll-wheel delta accumulated during the current frame.
  double get wheelDeltaY;

  /// Relative horizontal pointer delta during the current frame.
  double get pointerDeltaX;

  /// Relative vertical pointer delta during the current frame.
  double get pointerDeltaY;

  /// Whether pointer lock is currently engaged on this host.
  bool get pointerLocked;

  /// Requests OS/browser pointer lock when supported by the host.
  void requestPointerLock();

  /// Exits OS/browser pointer lock when supported by the host.
  void exitPointerLock();

  /// Active touch contacts sorted by touch id.
  List<TouchPoint> get touches;

  /// Number of connected gamepads currently reported by the host.
  int get gamepadCount;

  /// Normalized axis value in `[-1, 1]` for [gamepadIndex] and [axisIndex],
  /// or `0.0` if unavailable.
  double gamepadAxis(int gamepadIndex, int axisIndex);

  /// Whether [buttonIndex] is held on [gamepadIndex].
  bool gamepadButtonDown(int gamepadIndex, int buttonIndex);

  /// Printable text typed during the current frame.
  String get textInputBuffer;
}

/// Host-owned offscreen color/depth render target usable by secondary cameras
/// or render-to-texture materials/UI.
final class RenderTargetHandle {
  final int slot;
  final int width;
  final int height;
  final TextureHandle colorTexture;
  final String? debugLabel;

  const RenderTargetHandle(
    this.slot, {
    required this.width,
    required this.height,
    required this.colorTexture,
    this.debugLabel,
  });

  @override
  bool operator ==(Object other) =>
      other is RenderTargetHandle &&
      other.slot == slot &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(slot, width, height);

  @override
  String toString() =>
      'RenderTargetHandle($slot, ${width}x$height, ${debugLabel ?? "unnamed"})';
}

/// Per-camera render pass descriptor used for multi-camera depth sorting and
/// offscreen render-to-texture passes.
final class CameraRenderDescriptor {
  final CameraController? camera;
  final int visibilityMask;
  final Vec4 normalizedViewportRect;
  final int depth;
  final bool clearColor;
  final bool clearDepth;
  final RenderTargetHandle? target;

  const CameraRenderDescriptor({
    this.camera,
    this.visibilityMask = -1,
    this.normalizedViewportRect = const Vec4(0, 0, 1, 1),
    this.depth = 0,
    this.clearColor = true,
    this.clearDepth = true,
    this.target,
  });
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

  /// Visibility layer bitmask applied when rendering frames (-1 renders all).
  int get visibilityMask;
  set visibilityMask(int value);

  /// Updates a single uniform value on an active shader target.
  void setShaderUniform(ShaderTarget target, String name, ShaderUniform value);

  /// Binds a texture sampler on an active shader target.
  void setShaderTexture(
    ShaderTarget target,
    String name,
    TextureHandle texture,
  );

  /// Applies active shader slot overrides and custom post-effect stages.
  void applyShaderConfiguration({
    Map<ShaderSlot, ShaderOverride> shaderOverrides = const {},
    Map<String, ShaderOverride> postEffects = const {},
  });

  /// A world-space ray through drawing-buffer pixel ([x], [y]) for the
  /// camera rendered last frame, or null when unavailable.
  Ray? screenRay(double x, double y);

  /// Allocates an offscreen render target of [width]x[height] pixels.
  RenderTargetHandle createRenderTarget({
    required int width,
    required int height,
    String? debugLabel,
  });

  /// Releases an offscreen render target created via [createRenderTarget].
  void releaseRenderTarget(RenderTargetHandle handle);

  /// Sets the active pixel viewport rectangle `[x, y, width, height]`.
  void setViewport(int x, int y, int width, int height);

  /// Executes or queues a camera pass targeting [target] (or the main backbuffer
  /// when `target == null`) described by [descriptor].
  void renderFrameToTarget(
    RenderTargetHandle? target, {
    required CameraRenderDescriptor descriptor,
  });

  /// Re-uploads dynamic vertex/normal/bounds buffers (e.g. soft bodies).
  void updateMeshVertices(MeshHandle handle, MeshData data);

  /// Binds or updates the GPU bone-matrix palette for skeletal skinning.
  void setSkinningPalette(
    MeshHandle mesh,
    Float32List jointMatrices, {
    int jointCount = 0,
  });

  /// Registers or updates a host-declared `R3` render graph pass.
  void declareRenderPass(RenderPassDecl pass);

  /// Unregisters a previously declared `R3` render graph pass.
  void removeDeclaredRenderPass(String passId);

  /// Submits a clustered indirect draw batch descriptor from `DrawBatcher`.
  void submitIndirectBatch(SubmittedIndirectBatch batch);
}

/// Computes a canonical structural signature for a shader override and
/// post-effect configuration.
///
/// Includes slot/effect keys, shader sources (`vertex`, `fragment`, `effect`),
/// declared uniform names and their `glslType`s, and declared texture sampler
/// names, while ignoring bound uniform values and [TextureHandle] instances.
String shaderConfigurationSignature(
  Map<ShaderSlot, ShaderOverride> shaderOverrides,
  Map<String, ShaderOverride> postEffects,
) {
  final buffer = StringBuffer();

  void writeString(String? value) {
    if (value == null) {
      buffer.write('0;');
    } else {
      buffer
        ..write('1:')
        ..write(value.length)
        ..write(':')
        ..write(value)
        ..write(';');
    }
  }

  void writeOverride(ShaderOverride override) {
    writeString(override.vertex);
    writeString(override.fragment);
    writeString(override.effect);

    final uniformKeys = override.uniforms.keys.toList()..sort();
    buffer
      ..write('u')
      ..write(uniformKeys.length)
      ..write(':');
    for (final key in uniformKeys) {
      final glslType = override.uniforms[key]!.glslType;
      buffer
        ..write(key.length)
        ..write(':')
        ..write(key)
        ..write('=')
        ..write(glslType.length)
        ..write(':')
        ..write(glslType)
        ..write(';');
    }

    final textureKeys = override.textures.keys.toList()..sort();
    buffer
      ..write('t')
      ..write(textureKeys.length)
      ..write(':');
    for (final key in textureKeys) {
      buffer
        ..write(key.length)
        ..write(':')
        ..write(key)
        ..write(';');
    }
  }

  final sortedSlots = shaderOverrides.keys.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  buffer
    ..write('s')
    ..write(sortedSlots.length)
    ..write('[');
  for (final slot in sortedSlots) {
    buffer
      ..write(slot.index)
      ..write('=>');
    writeOverride(shaderOverrides[slot]!);
  }
  buffer.write(']');

  buffer
    ..write('p')
    ..write(postEffects.length)
    ..write('[');
  for (final entry in postEffects.entries) {
    buffer
      ..write(entry.key.length)
      ..write(':')
      ..write(entry.key)
      ..write('=>');
    writeOverride(entry.value);
  }
  buffer.write(']');

  return buffer.toString();
}

abstract interface class AssetLoader {
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  });
  Future<Uint8List> loadBytes(String path);
  Future<String> loadText(String path);
}

/// An opaque, host-owned sound asset.
abstract interface class AudioClip {
  String get path;
}

/// One voice that plays one clip at a time.
abstract interface class AudioChannel {
  void play(
    AudioClip clip, {
    double volume = 1,
    double pitch = 1,
    bool loop = false,
  });
  void stop();
  bool get isPlaying;
  set volume(double value);
  set pitch(double value);

  /// Sets stereo pan in `[-1.0, 1.0]` (`-1` = full left, `0` = center, `1` = right).
  void setPan(double pan);

  /// Configures the per-channel low-pass filter cutoff in Hz and Q resonance.
  void setLowPass(double cutoffHz, {double resonance = 0.707});

  /// Sets normalized wet reverb send level in `[0.0, 1.0]`.
  void setReverbSend(double wet);

  void dispose();
}

abstract interface class AudioDevice {
  bool get muted;
  set muted(bool value);

  /// Declares a clip. [voices] bounds how many one-shots of it may overlap.
  AudioClip clip(String path, {double volume = 1, int voices = 3});

  AudioChannel createChannel();

  void playOneShot(AudioClip clip, {double volume = 1, double pitch = 1});

  /// Updates the active 3D audio listener pose for spatial panning/attenuation.
  void setListenerPose({
    Vec3 position = const Vec3(0, 0, 0),
    Vec3 forward = const Vec3(0, 0, -1),
    Vec3 up = const Vec3(0, 1, 0),
  });
}

abstract interface class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}
