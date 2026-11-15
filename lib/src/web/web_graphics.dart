import 'dart:typed_data';

import 'package:pixeldart/pixeldart_advanced.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/pixeldart_app.dart';
import 'package:pixeldart/rendering/webgl/webgl2_device.dart';

import '../../rocket.dart';

/// WebGL2 [Graphics] backend wrapping [PixeldartApp].
final class WebGraphics implements Graphics {
  final PixeldartApp _app;
  final Set<RenderTargetHandle> _renderTargets = {};
  final Map<RenderTargetHandle, GpuObject> _gpuTargets = {};
  final List<CameraRenderDescriptor> renderedPasses = [];
  final Map<MeshHandle, MeshData> updatedMeshes = {};
  final Map<MeshHandle, Float32List> skinningPalettes = {};
  final Map<String, RenderPassDecl> declaredRenderPasses = {};
  final List<SubmittedIndirectBatch> indirectBatches = [];
  RenderTargetHandle? _activeTarget;
  int _nextTargetSlot = 1;
  int _activeViewportX = 0;
  int _activeViewportY = 0;
  int _activeViewportWidth = 0;
  int _activeViewportHeight = 0;

  WebGraphics(this._app);

  Set<RenderTargetHandle> get liveRenderTargets =>
      Set<RenderTargetHandle>.unmodifiable(_renderTargets);
  List<CameraRenderDescriptor> get renderedCameraPasses =>
      List<CameraRenderDescriptor>.unmodifiable(renderedPasses);
  RenderTargetHandle? get activeTarget => _activeTarget;
  int get activeViewportX => _activeViewportX;
  int get activeViewportY => _activeViewportY;
  int get activeViewportWidth =>
      _activeViewportWidth > 0 ? _activeViewportWidth : viewportWidth;
  int get activeViewportHeight =>
      _activeViewportHeight > 0 ? _activeViewportHeight : viewportHeight;

  GpuDevice? get _device => _app.renderer is SceneRendererImpl
      ? (_app.renderer as SceneRendererImpl).device
      : null;

  @override
  int get visibilityMask => _app.visibilityMask;

  @override
  set visibilityMask(int value) => _app.visibilityMask = value;

  String? _lastAppliedShaderSignature;
  String? lastShaderError;

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
  }) => _app.createParticleMaterial(key: key, color: color, glow: glow);

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
  void setShaderUniform(ShaderTarget target, String name, ShaderUniform value) {
    _guardShaderOp(() => _app.setShaderUniform(target, name, value));
  }

  @override
  void setShaderTexture(
    ShaderTarget target,
    String name,
    TextureHandle texture,
  ) {
    _guardShaderOp(() => _app.setShaderTexture(target, name, texture));
  }

  void _guardShaderOp(void Function() action) {
    if (_app.renderer.state == RendererState.disposed) return;
    try {
      action();
    } on ArgumentError catch (e) {
      lastShaderError = e.toString();
    } on StateError catch (e) {
      lastShaderError = e.toString();
    }
  }

  String _initialShaderSignature() {
    if (_app.renderer.state == RendererState.ready) {
      final config = _app.renderer.configuration;
      return shaderConfigurationSignature(
        config.shaderOverrides,
        config.postEffects,
      );
    }
    return shaderConfigurationSignature(const {}, const {});
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
    final baseline = _lastAppliedShaderSignature ??= _initialShaderSignature();
    if (signature == baseline) return;
    if (_app.renderer.state != RendererState.ready) return;

    _lastAppliedShaderSignature = signature;
    lastShaderError = null;
    final nextConfig = _app.renderer.configuration.copyWith(
      shaderOverrides: nextOverrides,
      postEffects: nextEffects,
    );
    try {
      _app.renderer
          .configure(nextConfig)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              if (_app.renderer.state != RendererState.disposed) {
                lastShaderError = error.toString();
              }
            },
          );
    } on Object catch (error) {
      if (_app.renderer.state != RendererState.disposed) {
        lastShaderError = error.toString();
      }
    }
  }

  @override
  Ray? screenRay(double x, double y) {
    final rect = _app.canvas.getBoundingClientRect();
    if (_app.canvas.width <= 0 || _app.canvas.height <= 0) return null;
    final clientX = rect.left + x * rect.width / _app.canvas.width;
    final clientY = rect.top + y * rect.height / _app.canvas.height;
    return _app.screenRay(clientX, clientY);
  }

  ({int x, int y, int width, int height}) _resolvePixelViewport(
    Vec4 rect,
    RenderTargetHandle? target,
  ) {
    final tw = target?.width ?? viewportWidth;
    final th = target?.height ?? viewportHeight;
    final maxW = tw > 0 ? tw : 1;
    final maxH = th > 0 ? th : 1;
    return (
      x: (rect.x * tw).round(),
      y: (rect.y * th).round(),
      width: (rect.z * tw).round().clamp(1, maxW),
      height: (rect.w * th).round().clamp(1, maxH),
    );
  }

  void _bindTargetHandle(RenderTargetHandle? target) {
    final dev = _device;
    if (dev == null || dev.status != GpuDeviceStatus.ready) {
      _activeTarget = target;
      return;
    }
    if (target == null) {
      dev.bindTarget(null);
      _activeTarget = null;
      return;
    }
    if (!_renderTargets.contains(target)) {
      throw StateError(
        'WebGraphics: RenderTargetHandle(${target.slot}) has been released',
      );
    }
    final gpuTarget = _gpuTargets.putIfAbsent(
      target,
      () => dev.createTarget(
        GpuTargetDescriptor(
          width: target.width,
          height: target.height,
          hasDepth: true,
        ),
      ),
    );
    dev.bindTarget(gpuTarget);
    _activeTarget = target;
  }

  void clearRenderedPasses() => renderedPasses.clear();

  void disposeRenderTargets() {
    for (final handle in _renderTargets.toList()) {
      releaseRenderTarget(handle);
    }
    _activeTarget = null;
  }

  @override
  RenderTargetHandle createRenderTarget({
    required int width,
    required int height,
    String? debugLabel,
  }) {
    final colorTex = createTexture(
      width: width,
      height: height,
      debugLabel: debugLabel,
    );
    final handle = RenderTargetHandle(
      _nextTargetSlot++,
      width: width,
      height: height,
      colorTexture: colorTex,
      debugLabel: debugLabel,
    );
    _renderTargets.add(handle);
    final dev = _device;
    if (dev != null && dev.status == GpuDeviceStatus.ready) {
      _gpuTargets[handle] = dev.createTarget(
        GpuTargetDescriptor(width: width, height: height, hasDepth: true),
      );
    }
    return handle;
  }

  @override
  void releaseRenderTarget(RenderTargetHandle handle) {
    if (_renderTargets.remove(handle)) {
      final gpuTarget = _gpuTargets.remove(handle);
      final dev = _device;
      if (gpuTarget != null &&
          dev != null &&
          dev.status == GpuDeviceStatus.ready) {
        if (_activeTarget == handle) {
          dev.bindTarget(null);
          _activeTarget = null;
        }
        dev.deleteTarget(gpuTarget);
      } else if (_activeTarget == handle) {
        _activeTarget = null;
      }
      releaseTexture(handle.colorTexture);
    }
  }

  @override
  void setViewport(int x, int y, int width, int height) {
    _activeViewportX = x;
    _activeViewportY = y;
    _activeViewportWidth = width;
    _activeViewportHeight = height;
    final dev = _device;
    if (dev is WebGl2Device && dev.status == GpuDeviceStatus.ready) {
      dev.gl.viewport(x, y, width, height);
    }
  }

  @override
  void renderFrameToTarget(
    RenderTargetHandle? target, {
    required CameraRenderDescriptor descriptor,
  }) {
    final vp = _resolvePixelViewport(descriptor.normalizedViewportRect, target);
    _bindTargetHandle(target);
    setViewport(vp.x, vp.y, vp.width, vp.height);
    final dev = _device;
    if (target != null && dev != null && dev.status == GpuDeviceStatus.ready) {
      final clearMask = switch ((
        descriptor.clearColor,
        descriptor.clearDepth,
      )) {
        (true, true) => ClearMask.colorAndDepth,
        (true, false) => ClearMask.colorOnly,
        (false, true) => ClearMask.depthOnly,
        (false, false) => null,
      };
      if (clearMask != null) {
        final c = environment.clearColor;
        dev.clear(clearMask, r: c.r, g: c.g, b: c.b, a: 1.0);
      }
    }
    if (descriptor.camera != null) {
      _app.cameraController = descriptor.camera;
    }
    visibilityMask = descriptor.visibilityMask;
    renderedPasses.add(descriptor);
  }

  @override
  void updateMeshVertices(MeshHandle handle, MeshData data) {
    updatedMeshes[handle] = data;
  }

  @override
  void setSkinningPalette(
    MeshHandle mesh,
    Float32List jointMatrices, {
    int jointCount = 0,
  }) {
    skinningPalettes[mesh] = Float32List.fromList(jointMatrices);
  }

  @override
  void declareRenderPass(RenderPassDecl pass) {
    declaredRenderPasses[pass.id] = pass;
  }

  @override
  void removeDeclaredRenderPass(String passId) {
    declaredRenderPasses.remove(passId);
  }

  @override
  void submitIndirectBatch(SubmittedIndirectBatch batch) {
    indirectBatches.add(batch);
  }
}
