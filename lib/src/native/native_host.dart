import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pixeldart/pixeldart_advanced.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';

import '../../gl_volition.dart';
import 'native_bindings.dart';

/// Optional callback invoked by [GlesDevice] for each low-level GPU operation,
/// allowing an FFI OpenGL ES 3.0 / ANGLE host to forward validated commands
/// to native GL entrypoints.
typedef GlesDispatchHook = void Function(String command, List<Object?> args);

final class _NativeGpuObject implements GpuObject {
  final int id;
  const _NativeGpuObject(this.id);
}

final class _NativeTimerQuery implements GpuObject {
  final int id;
  bool ended = false;
  bool returnedPending = false;
  bool disjoint = false;
  _NativeTimerQuery(this.id);
}

/// Native / AOT [GpuDevice] implementation for `glVolition` (E6-3).
///
/// Implements the full `pixeldart` [GpuDevice] and [GpuContextGeneration]
/// contracts without `package:web`, validating shaders, render target
/// attachments, vertex/index bindings, and resource lifetimes while optionally
/// dispatching commands to a native GLES3 / FFI [onCommand] hook.
final class GlesDevice implements GpuDevice, GpuContextGeneration {
  final bool timerQueries;
  final bool disjointTimer;
  int maxSamples;
  bool anisotropicFiltering;
  double maxAnisotropy;
  int? incompleteAboveSamples;
  final GlesDispatchHook? onCommand;

  GlesDevice({
    this.timerQueries = true,
    this.disjointTimer = false,
    this.maxSamples = 4,
    this.anisotropicFiltering = true,
    this.maxAnisotropy = 16,
    this.incompleteAboveSamples,
    this.onCommand,
  });

  GpuDeviceStatus _status = GpuDeviceStatus.ready;
  int _nextId = 1;
  int _contextGeneration = 0;

  int bufferCreateCalls = 0;
  int bufferDeleteCalls = 0;
  int bufferUploadCalls = 0;
  final Map<int, Float32List> uploadedBufferData = {};
  int textureCreateCalls = 0;
  int textureDeleteCalls = 0;
  int targetCreateCalls = 0;
  int targetDeleteCalls = 0;
  int resolveTargetCalls = 0;
  Set<String> lastResolvedAttachments = const {};
  final Map<int, GpuTargetDescriptor> _targetDescriptors = {};
  int vaoCreateCalls = 0;
  int vaoDeleteCalls = 0;
  int programCompileCalls = 0;
  int programDeleteCalls = 0;
  int textureMipsFinalizedCalls = 0;

  String? lastCompiledVertexSource;
  String? lastCompiledFragmentSource;
  final List<({String vertex, String fragment})> compiledShaderSources = [];

  final Set<int> _liveObjects = {};
  final Set<int> _texturesMissingFinalizedMips = {};
  final List<String> drawLog = [];
  final List<({String name, UniformValue value})> uniformLog = [];
  final List<({ClearMask mask, double r, double g, double b, double a})>
  clearLog = [];

  GpuObject? _boundTarget;
  GpuObject? _boundProgram;
  GpuObject? _boundVao;
  GpuObject? _boundElementBuffer;
  DrawStateDescriptor? lastAppliedDrawState;
  final Map<int, GpuObject> _sampledSinceUseProgram = {};

  int timerBeginCalls = 0;
  int timerEndCalls = 0;
  int timerDeleteCalls = 0;
  int _nextTimerId = 1;
  final Set<int> _timerIds = {};

  @override
  GpuDeviceStatus get status => _status;

  @override
  int get contextGeneration => _contextGeneration;

  int get liveObjectCount => _liveObjects.length;
  int get liveTimerCount => _timerIds.length;
  GpuObject? get boundTarget => _boundTarget;

  bool isLive(GpuObject obj) =>
      _liveObjects.contains((obj as _NativeGpuObject).id);

  GpuTargetDescriptor targetDescriptor(GpuObject target) =>
      _targetDescriptors[(target as _NativeGpuObject).id]!;

  Iterable<GpuTargetDescriptor> get liveTargetDescriptors =>
      _targetDescriptors.values;

  @override
  RenderCapabilities queryCapabilities() => RenderCapabilities(
    webglVersion: 'gles-3.0-native',
    rendererString: 'GlesDevice (glVolition Native)',
    maxTextureSize: 4096,
    maxTextureArrayLayers: 8,
    maxSamples: maxSamples,
    maxVertexAttributes: 16,
    maxColorAttachments: 4,
    anisotropicFiltering: anisotropicFiltering,
    maxAnisotropy: maxAnisotropy,
    floatRenderTarget: true,
    contextLossExtension: true,
    disjointTimerQuery: timerQueries,
  );

  GpuObject _create(String kind) {
    final obj = _NativeGpuObject(_nextId++);
    _liveObjects.add(obj.id);
    onCommand?.call('create:$kind', [obj.id]);
    return obj;
  }

  void _delete(GpuObject obj, String kind) {
    final id = (obj as _NativeGpuObject).id;
    if (!_liveObjects.remove(id)) {
      throw StateError('GlesDevice: double delete of $kind $id');
    }
    onCommand?.call('delete:$kind', [id]);
  }

  void _requireReady() {
    if (_status != GpuDeviceStatus.ready) {
      throw StateError('GlesDevice: operation attempted while not ready');
    }
  }

  void _requireLive(GpuObject obj) {
    if (!isLive(obj)) {
      throw StateError('GlesDevice: operation on a released or unknown object');
    }
  }

  void _requireDrawState() {
    if (_boundProgram == null) {
      throw StateError('GlesDevice: draw call with no bound program');
    }
    if (_boundVao == null) {
      throw StateError('GlesDevice: draw call with no bound vertex array');
    }
    final target = _boundTarget;
    if (target != null && _sampledSinceUseProgram.containsValue(target)) {
      throw StateError(
        'GlesDevice: feedback loop: draw samples its own render target '
        '${(target as _NativeGpuObject).id}',
      );
    }
  }

  @override
  GpuObject createBuffer(GpuBufferDescriptor descriptor) {
    _requireReady();
    bufferCreateCalls += 1;
    return _create('buffer');
  }

  @override
  void uploadBuffer(
    GpuObject buffer,
    Float32List data, {
    int dstByteOffset = 0,
  }) {
    _requireReady();
    _requireLive(buffer);
    bufferUploadCalls += 1;
    final id = (buffer as _NativeGpuObject).id;
    uploadedBufferData[id] = Float32List.fromList(data);
    onCommand?.call('uploadBuffer', [id, data.length, dstByteOffset]);
  }

  @override
  void deleteBuffer(GpuObject buffer) {
    bufferDeleteCalls += 1;
    _delete(buffer, 'buffer');
  }

  @override
  GpuObject createTexture(GpuTextureDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    textureCreateCalls += 1;
    final obj = _create('texture');
    if (descriptor.hasMips) {
      _texturesMissingFinalizedMips.add((obj as _NativeGpuObject).id);
    }
    return obj;
  }

  @override
  void uploadTextureLayer(GpuObject texture, int layer, Uint8List pixels) {
    _requireReady();
    _requireLive(texture);
    onCommand?.call('uploadTextureLayer', [
      (texture as _NativeGpuObject).id,
      layer,
      pixels.length,
    ]);
  }

  @override
  void finalizeMips(GpuObject texture) {
    _requireReady();
    _requireLive(texture);
    textureMipsFinalizedCalls += 1;
    final id = (texture as _NativeGpuObject).id;
    _texturesMissingFinalizedMips.remove(id);
    onCommand?.call('finalizeMips', [id]);
  }

  bool hasUnfinalizedMips(GpuObject texture) =>
      _texturesMissingFinalizedMips.contains((texture as _NativeGpuObject).id);

  @override
  void deleteTexture(GpuObject texture) {
    textureDeleteCalls += 1;
    _texturesMissingFinalizedMips.remove((texture as _NativeGpuObject).id);
    _delete(texture, 'texture');
  }

  @override
  GpuObject createTarget(GpuTargetDescriptor descriptor) {
    _requireReady();
    if (descriptor.width <= 0 || descriptor.height <= 0) {
      throw ArgumentError(
        'GlesDevice.createTarget requires positive dimensions, '
        'got ${descriptor.width}x${descriptor.height}',
      );
    }
    final incompleteAbove = incompleteAboveSamples;
    if (incompleteAbove != null && descriptor.samples > incompleteAbove) {
      throw StateError('GlesDevice.createTarget: framebuffer incomplete');
    }
    targetCreateCalls += 1;
    final target = _create('target');
    _targetDescriptors[(target as _NativeGpuObject).id] = descriptor;
    return target;
  }

  @override
  void deleteTarget(GpuObject target) {
    targetDeleteCalls += 1;
    _targetDescriptors.remove((target as _NativeGpuObject).id);
    _delete(target, 'target');
  }

  @override
  void resolveTarget(GpuObject source, GpuObject destination) {
    _requireReady();
    _requireLive(source);
    _requireLive(destination);
    final srcId = (source as _NativeGpuObject).id;
    final dstId = (destination as _NativeGpuObject).id;
    final src = _targetDescriptors[srcId];
    final dst = _targetDescriptors[dstId];
    if (src == null || dst == null) {
      throw ArgumentError(
        'GlesDevice.resolveTarget: both source and destination must be '
        'targets created via createTarget',
      );
    }
    if (src.samples <= 1) {
      throw ArgumentError(
        'GlesDevice.resolveTarget: source must be multisampled '
        '(samples > 1), got ${src.samples}',
      );
    }
    if (dst.samples > 1) {
      throw ArgumentError(
        'GlesDevice.resolveTarget: destination must be single-sample, '
        'got samples=${dst.samples}',
      );
    }
    if (src.width != dst.width || src.height != dst.height) {
      throw ArgumentError(
        'GlesDevice.resolveTarget: source (${src.width}x${src.height}) '
        'and destination (${dst.width}x${dst.height}) must match',
      );
    }
    resolveTargetCalls += 1;
    bool hasGlow(GpuTargetDescriptor d) =>
        d.attachments == GpuTargetAttachment.colorAndGlow ||
        d.attachments == GpuTargetAttachment.colorDepthGlow;
    lastResolvedAttachments = {
      if (src.attachments != GpuTargetAttachment.depthOnly &&
          dst.attachments != GpuTargetAttachment.depthOnly)
        'color',
      if (hasGlow(src) && hasGlow(dst)) 'glow',
      if (src.hasDepth && dst.hasDepth) 'depth',
    };
    final entry = 'resolveTarget($srcId, $dstId)';
    drawLog.add(entry);
    onCommand?.call('resolveTarget', [srcId, dstId]);
  }

  @override
  GpuObject createVertexArray() {
    _requireReady();
    vaoCreateCalls += 1;
    return _create('vao');
  }

  @override
  void deleteVertexArray(GpuObject vao) {
    vaoDeleteCalls += 1;
    _delete(vao, 'vao');
  }

  @override
  GpuObject compileProgram({
    required String vertexSource,
    required String fragmentSource,
    required List<String> requiredAttributes,
    required List<String> requiredUniforms,
  }) {
    _requireReady();
    if (vertexSource.contains('FAIL_VERTEX')) {
      throw const ShaderCompileException(
        ShaderCompileStage.vertex,
        'vertex compile failure',
      );
    }
    if (fragmentSource.contains('FAIL_FRAGMENT')) {
      throw const ShaderCompileException(
        ShaderCompileStage.fragment,
        'fragment compile failure',
      );
    }
    if (vertexSource.contains('FAIL_LINK') ||
        fragmentSource.contains('FAIL_LINK')) {
      throw const ShaderCompileException(
        ShaderCompileStage.link,
        'program link failure',
      );
    }
    final combined = '$vertexSource\n$fragmentSource';
    for (final attr in requiredAttributes) {
      if (!combined.contains(attr)) {
        throw ShaderCompileException(
          ShaderCompileStage.validation,
          'missing required attribute: $attr',
        );
      }
    }
    for (final uniform in requiredUniforms) {
      if (!combined.contains(uniform)) {
        throw ShaderCompileException(
          ShaderCompileStage.validation,
          'missing required uniform: $uniform',
        );
      }
    }
    lastCompiledVertexSource = vertexSource;
    lastCompiledFragmentSource = fragmentSource;
    compiledShaderSources.add((vertex: vertexSource, fragment: fragmentSource));
    programCompileCalls += 1;
    return _create('program');
  }

  @override
  void deleteProgram(GpuObject program) {
    programDeleteCalls += 1;
    _delete(program, 'program');
  }

  @override
  void simulateContextLoss() {
    _status = GpuDeviceStatus.lost;
    _liveObjects.clear();
    _targetDescriptors.clear();
    _texturesMissingFinalizedMips.clear();
    _boundTarget = null;
    _boundProgram = null;
    _boundVao = null;
    _boundElementBuffer = null;
    onCommand?.call('contextLost', const []);
  }

  @override
  void simulateContextRestore() {
    _status = GpuDeviceStatus.ready;
    _contextGeneration++;
    onCommand?.call('contextRestore', [_contextGeneration]);
  }

  @override
  void bindTarget(GpuObject? target) {
    _requireReady();
    if (target != null) {
      _requireLive(target);
    }
    _boundTarget = target;
    final label = target == null
        ? 'canvas'
        : '${(target as _NativeGpuObject).id}';
    drawLog.add('bindTarget($label)');
    onCommand?.call('bindTarget', [label]);
  }

  @override
  void setColorAttachmentCount(int count) {
    _requireReady();
    if (count != 1 && count != 2) {
      throw ArgumentError(
        'GlesDevice.setColorAttachmentCount: count must be 1 or 2, got $count',
      );
    }
    drawLog.add('setColorAttachmentCount($count)');
    onCommand?.call('setColorAttachmentCount', [count]);
  }

  @override
  void applyDrawState(DrawStateDescriptor state) {
    _requireReady();
    lastAppliedDrawState = state;
    drawLog.add(
      'applyDrawState(depthTest=${state.depthTest}, cullEnable=${state.cullEnable}, cullFace=${state.cullFace.name})',
    );
    onCommand?.call('applyDrawState', [state]);
  }

  @override
  void clear(
    ClearMask mask, {
    double r = 0,
    double g = 0,
    double b = 0,
    double a = 1,
  }) {
    _requireReady();
    clearLog.add((mask: mask, r: r, g: g, b: b, a: a));
    drawLog.add('clear(${mask.name})');
    onCommand?.call('clear', [mask.name, r, g, b, a]);
  }

  @override
  void useProgram(GpuObject program) {
    _requireReady();
    _requireLive(program);
    _boundProgram = program;
    _sampledSinceUseProgram.clear();
    final id = (program as _NativeGpuObject).id;
    drawLog.add('useProgram($id)');
    onCommand?.call('useProgram', [id]);
  }

  @override
  void setUniform(String name, UniformValue value) {
    _requireReady();
    if (_boundProgram == null) {
      throw StateError('GlesDevice.setUniform called with no bound program');
    }
    drawLog.add('setUniform($name, ${value.type.name})');
    uniformLog.add((name: name, value: value));
    onCommand?.call('setUniform', [name, value.type.name, value.value]);
  }

  @override
  void bindVertexArray(GpuObject vao) {
    _requireReady();
    _requireLive(vao);
    _boundVao = vao;
    final id = (vao as _NativeGpuObject).id;
    drawLog.add('bindVertexArray($id)');
    onCommand?.call('bindVertexArray', [id]);
  }

  @override
  void bindArrayBuffer(GpuObject buffer) {
    _requireReady();
    _requireLive(buffer);
    final id = (buffer as _NativeGpuObject).id;
    drawLog.add('bindArrayBuffer($id)');
    onCommand?.call('bindArrayBuffer', [id]);
  }

  @override
  void vertexAttribPointer({
    required int location,
    required int componentCount,
    required int strideBytes,
    required int offsetBytes,
    GpuAttribFormat format = GpuAttribFormat.float,
  }) {
    _requireReady();
    final suffix = format == GpuAttribFormat.float ? '' : ', ${format.name}';
    drawLog.add(
      'vertexAttribPointer($location, $componentCount, $strideBytes, $offsetBytes$suffix)',
    );
    onCommand?.call('vertexAttribPointer', [
      location,
      componentCount,
      strideBytes,
      offsetBytes,
      format.name,
    ]);
  }

  @override
  void clearColorAttachment(
    int index, {
    double r = 0,
    double g = 0,
    double b = 0,
    double a = 0,
  }) {
    _requireReady();
    drawLog.add('clearColorAttachment($index)');
    onCommand?.call('clearColorAttachment', [index, r, g, b, a]);
  }

  @override
  void enableVertexAttribArray(int location) {
    _requireReady();
    drawLog.add('enableVertexAttribArray($location)');
    onCommand?.call('enableVertexAttribArray', [location]);
  }

  @override
  void vertexAttribDivisor(int location, int divisor) {
    _requireReady();
    drawLog.add('vertexAttribDivisor($location, $divisor)');
    onCommand?.call('vertexAttribDivisor', [location, divisor]);
  }

  @override
  void bindTexture(int unit, GpuObject texture) {
    _requireReady();
    _requireLive(texture);
    _sampledSinceUseProgram[unit] = texture;
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('bindTexture($unit, $id)');
    onCommand?.call('bindTexture', [unit, id]);
  }

  @override
  void bindGlowTexture(int unit, GpuObject target) {
    _requireReady();
    _requireLive(target);
    _sampledSinceUseProgram[unit] = target;
    final id = (target as _NativeGpuObject).id;
    drawLog.add('bindGlowTexture($unit, $id)');
    onCommand?.call('bindGlowTexture', [unit, id]);
  }

  @override
  void drawArrays({required int first, required int count}) {
    _requireReady();
    _requireDrawState();
    drawLog.add('drawArrays($first, $count)');
    onCommand?.call('drawArrays', [first, count]);
  }

  @override
  void drawArraysInstanced({
    required int first,
    required int count,
    required int instanceCount,
  }) {
    _requireReady();
    _requireDrawState();
    drawLog.add('drawArraysInstanced($first, $count, $instanceCount)');
    onCommand?.call('drawArraysInstanced', [first, count, instanceCount]);
  }

  @override
  void bindElementArrayBuffer(GpuObject buffer) {
    _requireReady();
    _requireLive(buffer);
    _boundElementBuffer = buffer;
    final id = (buffer as _NativeGpuObject).id;
    drawLog.add('bindElementArrayBuffer($id)');
    onCommand?.call('bindElementArrayBuffer', [id]);
  }

  @override
  void uploadIndices(GpuObject buffer, List<int> data) {
    _requireReady();
    _requireLive(buffer);
    final id = (buffer as _NativeGpuObject).id;
    drawLog.add('uploadIndices($id, ${data.length})');
    onCommand?.call('uploadIndices', [id, data.length]);
  }

  @override
  void drawElements({
    required int count,
    required int offsetBytes,
    bool index32 = false,
  }) {
    _requireReady();
    _requireDrawState();
    if (_boundElementBuffer == null) {
      throw StateError(
        'GlesDevice: drawElements with no bound element array buffer',
      );
    }
    drawLog.add('drawElements($count, $offsetBytes, index32=$index32)');
    onCommand?.call('drawElements', [count, offsetBytes, index32]);
  }

  @override
  void drawElementsInstanced({
    required int count,
    required int offsetBytes,
    required int instanceCount,
    bool index32 = false,
  }) {
    _requireReady();
    _requireDrawState();
    if (_boundElementBuffer == null) {
      throw StateError(
        'GlesDevice: drawElementsInstanced with no bound element array buffer',
      );
    }
    drawLog.add(
      'drawElementsInstanced($count, $offsetBytes, $instanceCount, '
      'index32=$index32)',
    );
    onCommand?.call('drawElementsInstanced', [
      count,
      offsetBytes,
      instanceCount,
      index32,
    ]);
  }

  @override
  GpuObject? beginGpuTimer() {
    _requireReady();
    if (!timerQueries) return null;
    timerBeginCalls += 1;
    final query = _NativeTimerQuery(_nextTimerId++)..disjoint = disjointTimer;
    _timerIds.add(query.id);
    return query;
  }

  @override
  void endGpuTimer(GpuObject query) {
    final timer = _timer(query);
    if (timer.ended) throw StateError('GlesDevice: timer already ended');
    timer.ended = true;
    timerEndCalls += 1;
  }

  @override
  GpuTimerPoll pollGpuTimer(GpuObject query) {
    final timer = _timer(query);
    if (!timer.ended) return const GpuTimerPoll(GpuTimerStatus.pending);
    if (!timer.returnedPending) {
      timer.returnedPending = true;
      return const GpuTimerPoll(GpuTimerStatus.pending);
    }
    if (timer.disjoint) return const GpuTimerPoll(GpuTimerStatus.disjoint);
    return const GpuTimerPoll(GpuTimerStatus.ready, 1250000);
  }

  @override
  void deleteGpuTimer(GpuObject query) {
    final timer = _timer(query);
    if (!_timerIds.remove(timer.id)) {
      throw StateError('GlesDevice: double delete of timer');
    }
    timerDeleteCalls += 1;
  }

  _NativeTimerQuery _timer(GpuObject query) {
    if (query is! _NativeTimerQuery || !_timerIds.contains(query.id)) {
      throw StateError('GlesDevice: unknown timer query');
    }
    return query;
  }
}

/// Native / AOT [EngineHost] that drives `pixeldart`'s [SceneRenderer] over a
/// [GpuDevice] (such as [GlesDevice]) via [DefaultSceneRendererFactory] (E6-3).
///
/// Runs on the Dart VM and `dart compile exe` without `package:web`.
final class NativeEngineHost implements EngineHost {
  final GpuDevice device;
  final SceneRenderer renderer;
  final RenderWorld world;
  final FrameSequencer sequencer;
  SurfaceMetrics _surface;

  @override
  final SceneNode sceneRoot = SceneNode.group(name: 'root');

  @override
  final ScriptedInput input = ScriptedInput();

  @override
  late final NativeGraphics graphics = NativeGraphics._(this);

  @override
  final AssetLoader assets;

  @override
  final AudioDevice audio;

  @override
  final KeyValueStore storage;

  final NativeWindowBackend? windowBackend;

  final List<Object> errors = [];
  bool rethrowErrors;

  Engine? _engine;
  double _elapsedSeconds = 0.0;
  bool _disposed = false;

  NativeEngineHost._({
    required this.device,
    required this.renderer,
    required this.world,
    required this.sequencer,
    required this._surface,
    required this.assets,
    required this.audio,
    required this.storage,
    this.windowBackend,
    this.rethrowErrors = true,
  });

  /// Boots a [SceneRenderer] via [DefaultSceneRendererFactory] over [device]
  /// (defaults to a fresh [GlesDevice]), initializes its quality profile
  /// ladder, and binds a new [Engine] with [initialScene].
  static Future<NativeEngineRunner> boot({
    GpuDevice? device,
    AudioDevice? audio,
    NativeWindowBackend? windowBackend,
    int width = 1280,
    int height = 720,
    double devicePixelRatio = 1.0,
    QualityProfile requestedProfile = QualityProfile.clean,
    Directory? assetsDirectory,
    File? storageFile,
    bool rethrowErrors = true,
    void Function(ComponentRegistry registry)? registerSpecs,
    Scene? initialScene,
  }) async {
    final gpu = device ?? GlesDevice();
    final renderer = const DefaultSceneRendererFactory().create(gpu);
    final surface = SurfaceMetrics.forCanvas(
      cssWidth: width,
      cssHeight: height,
      devicePixelRatio: devicePixelRatio,
      maxDevicePixelRatio: 2.0,
    );

    await bootstrapRenderer(
      renderer: renderer,
      surface: surface,
      ladder: defaultProfileLadder(requestedProfile),
      configurationFor: (p) => RendererConfiguration(
        profile: p,
        internalWidth: surface.pixelWidth,
        internalHeight: surface.pixelHeight,
        sampleCount: p.kind == QualityProfileKind.high ? 2 : 1,
        shadowMapCount: p == QualityProfile.safe ? 0 : 1,
      ),
    );

    final world = renderer.createWorld();
    final sequencer = FrameSequencer();
    final host = NativeEngineHost._(
      device: gpu,
      renderer: renderer,
      world: world,
      sequencer: sequencer,
      surface: surface,
      assets: FileAssetLoader(
        resources: renderer.resources,
        rootDirectory: assetsDirectory ?? Directory.current,
      ),
      audio: audio ?? SilentAudio(),
      storage: storageFile != null ? JsonFileStore(storageFile) : MemoryStore(),
      windowBackend: windowBackend,
      rethrowErrors: rethrowErrors,
    );

    final engine = Engine(host, initialScene: initialScene);
    registerSpecs?.call(engine.registry);
    host._engine = engine;
    return NativeEngineRunner._(host, engine);
  }

  SurfaceMetrics get surface => _surface;

  /// Steps the bound [Engine] by [dt], synchronizes [sceneRoot] to [world],
  /// encodes all 3D/2D/particle/UI passes into [renderer], and executes the
  /// full `pixeldart` render graph via [SceneRenderer.endFrame].
  FrameStats renderFrame(double dt) {
    final eng = _engine;
    if (eng == null) {
      throw StateError('NativeEngineHost.renderFrame: no Engine bound');
    }

    _elapsedSeconds += dt;
    eng.step(dt);

    sceneRoot.syncToWorld(world);

    final camCtrl = graphics.camera;
    if (camCtrl != null) {
      camCtrl.update(dt);
    }
    graphics.shakeEngine.update(dt);

    final aspect = _surface.pixelWidth / _surface.pixelHeight;
    var cameraView = camCtrl != null
        ? camCtrl.toCameraView(aspect)
        : CameraView.look(
            eye: const Vec3(0, 2, 5),
            forward: const Vec3(0, -0.2, -1),
            fovYRadians: 1.0,
            aspect: aspect,
            near: 0.1,
            far: 200,
          );
    cameraView = graphics.shakeEngine.applyTo(cameraView);
    graphics._lastCameraView = cameraView;

    final frameInput = sequencer.next(
      camera: cameraView,
      environment: graphics.environment,
      post: graphics.post,
      timeSeconds: _elapsedSeconds,
      visibilityMask: graphics.visibilityMask,
    );

    final encoder = renderer.beginFrame(world, frameInput);
    try {
      for (var i = 0; i < graphics._emitters.length; i++) {
        final emitter = graphics._emitters[i];
        emitter.update(dt);
        emitter.submit(encoder, frameInput);
      }
      eng.encodeFrame(encoder, frameInput);
      final stats = renderer.endFrame();
      input.endFrame();
      return stats;
    } catch (error) {
      try {
        renderer.abortFrame();
      } catch (_) {}
      rethrow;
    }
  }

  /// Resizes the native surface and reconfigures internal render targets.
  Future<void> resize(
    int width,
    int height, {
    double devicePixelRatio = 1.0,
  }) async {
    _surface = _surface.resized(
      cssWidth: width,
      cssHeight: height,
      devicePixelRatio: devicePixelRatio,
      maxDevicePixelRatio: 2.0,
    );
    renderer.resize(_surface);
    await renderer.configure(
      renderer.configuration.copyWith(
        internalWidth: _surface.pixelWidth,
        internalHeight: _surface.pixelHeight,
      ),
    );
    sequencer.invalidateHistory('native surface resized');
  }

  @override
  void reportError(Object error, StackTrace stack) {
    errors.add(error);
    if (rethrowErrors) Error.throwWithStackTrace(error, stack);
  }

  /// Disposes the [Engine], removes all nodes from [world], and releases all
  /// GPU resources held by [world] and [renderer].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine?.dispose();
    _engine = null;
    if (audio case final DisposableNativeAudioDevice disposableAudio) {
      disposableAudio.dispose();
    }
    sceneRoot.removeFromWorld(world);
    world.dispose();
    renderer.dispose();
    windowBackend?.dispose();
  }
}

/// Pair of [NativeEngineHost] and [Engine] returned by [NativeEngineHost.boot].
final class NativeEngineRunner {
  final NativeEngineHost host;
  final Engine engine;

  NativeEngineRunner._(this.host, this.engine);

  SceneRenderer get renderer => host.renderer;
  Scene get scene => engine.scene;

  FrameStats renderFrame(double dt) => host.renderFrame(dt);

  Future<void> resize(int width, int height, {double devicePixelRatio = 1.0}) =>
      host.resize(width, height, devicePixelRatio: devicePixelRatio);

  void dispose() => host.dispose();
}

/// [Graphics] implementation backed by [SceneRenderer.resources].
final class NativeGraphics implements Graphics {
  final NativeEngineHost _host;
  final CameraShakeEngine shakeEngine = CameraShakeEngine();
  final List<ParticleEmitter> _emitters = [];
  final Map<MaterialHandle, MaterialDefinition> _materialDefinitions = {};
  final Map<ShaderTarget, Map<String, ShaderUniform>> _shaderUniforms = {};
  final Map<ShaderTarget, Map<String, TextureHandle>> _shaderTextures = {};
  Map<ShaderSlot, ShaderOverride> _shaderOverrides = const {};
  Map<String, ShaderOverride> _postEffects = const {};
  int _visibilityMask = -1;
  int _configureCalls = 0;
  String? _lastAppliedShaderSignature;
  String? _lastShaderError;
  CameraView? _lastCameraView;

  NativeGraphics._(this._host);

  ResourceLibrary get resources => _host.renderer.resources;

  Map<ShaderTarget, Map<String, ShaderUniform>> get shaderUniforms =>
      Map<ShaderTarget, Map<String, ShaderUniform>>.unmodifiable(
        <ShaderTarget, Map<String, ShaderUniform>>{
          for (final entry in _shaderUniforms.entries)
            entry.key: Map<String, ShaderUniform>.unmodifiable(entry.value),
        },
      );

  Map<ShaderTarget, Map<String, TextureHandle>> get shaderTextures =>
      Map<ShaderTarget, Map<String, TextureHandle>>.unmodifiable(
        <ShaderTarget, Map<String, TextureHandle>>{
          for (final entry in _shaderTextures.entries)
            entry.key: Map<String, TextureHandle>.unmodifiable(entry.value),
        },
      );

  Map<ShaderSlot, ShaderOverride> get shaderOverrides => _shaderOverrides;

  Map<String, ShaderOverride> get postEffects => _postEffects;

  int get configureCalls => _configureCalls;

  String? get lastShaderError => _lastShaderError;

  @override
  int get visibilityMask => _visibilityMask;

  @override
  set visibilityMask(int value) => _visibilityMask = value;

  @override
  FrameEnvironment environment = const FrameEnvironment(
    clearColor: LinearColor(0.03, 0.03, 0.04),
  );

  @override
  PostProcessState post = const PostProcessState();

  @override
  CameraController? camera;

  @override
  double get aspect => _host._surface.pixelWidth / _host._surface.pixelHeight;

  @override
  int get viewportWidth => _host._surface.pixelWidth;

  @override
  int get viewportHeight => _host._surface.pixelHeight;

  @override
  MeshHandle createMesh(MeshData data, {String? debugLabel}) =>
      resources.registerMesh(data, debugLabel: debugLabel);

  @override
  MaterialHandle createMaterial(MaterialDefinition definition) {
    final handle = resources.registerMaterial(definition);
    _materialDefinitions[handle] = definition;
    return handle;
  }

  @override
  MaterialHandle createParticleMaterial({
    required String key,
    LinearColor color = const LinearColor(1, 1, 1),
    double glow = 2,
  }) => createMaterial(
    ParticleMaterials.softDefinition(
      resources,
      key: key,
      color: color,
      glow: glow,
    ),
  );

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
    final handle = resources.registerTexture(
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
      resources.finalizeTextureMips(handle);
    }
    return handle;
  }

  @override
  void releaseMesh(MeshHandle handle) => resources.releaseMesh(handle);

  @override
  void releaseMaterial(MaterialHandle handle) {
    _materialDefinitions.remove(handle);
    resources.releaseMaterial(handle);
  }

  @override
  void releaseTexture(TextureHandle handle) => resources.releaseTexture(handle);

  @override
  void addEmitter(ParticleEmitter emitter) {
    if (emitter.needsColorGradientBinding) {
      final base = _materialDefinitions[emitter.material];
      if (base != null) emitter.bindColorGradient(resources, base);
    }
    _emitters.add(emitter);
  }

  @override
  void removeEmitter(ParticleEmitter emitter) => _emitters.remove(emitter);

  @override
  void shakeCamera({double trauma = 0.5, double? rotation}) {
    if (rotation != null) shakeEngine.rotationScale = rotation;
    shakeEngine.addTrauma(trauma);
  }

  @override
  void setShaderUniform(ShaderTarget target, String name, ShaderUniform value) {
    _shaderUniforms.putIfAbsent(target, () => {})[name] = value;
    _guardShaderOp(() => _host.renderer.setShaderUniform(target, name, value));
  }

  @override
  void setShaderTexture(
    ShaderTarget target,
    String name,
    TextureHandle texture,
  ) {
    _shaderTextures.putIfAbsent(target, () => {})[name] = texture;
    _guardShaderOp(
      () => _host.renderer.setShaderTexture(target, name, texture),
    );
  }

  void _guardShaderOp(void Function() action) {
    if (_host._disposed || _host.renderer.state == RendererState.disposed) {
      return;
    }
    try {
      action();
    } on ArgumentError catch (e) {
      _lastShaderError = e.toString();
    } on StateError catch (e) {
      _lastShaderError = e.toString();
    }
  }

  String _initialShaderSignature() {
    if (!_host._disposed && _host.renderer.state == RendererState.ready) {
      final config = _host.renderer.configuration;
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
    _shaderOverrides = nextOverrides;
    _postEffects = nextEffects;

    final baseline = _lastAppliedShaderSignature ??= _initialShaderSignature();
    if (signature == baseline) return;
    if (_host._disposed || _host.renderer.state != RendererState.ready) return;

    _lastAppliedShaderSignature = signature;
    _configureCalls += 1;
    _lastShaderError = null;
    final nextConfig = _host.renderer.configuration.copyWith(
      shaderOverrides: nextOverrides,
      postEffects: nextEffects,
    );
    try {
      _host.renderer
          .configure(nextConfig)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              if (!_host._disposed) {
                _lastShaderError = error.toString();
              }
            },
          );
    } on Object catch (error) {
      if (!_host._disposed) {
        _lastShaderError = error.toString();
      }
    }
  }

  @override
  Ray? screenRay(double x, double y) {
    final w = viewportWidth;
    final h = viewportHeight;
    if (x < 0 || x > w || y < 0 || y > h) return null;
    final cam =
        _lastCameraView ??
        (camera != null
            ? camera!.toCameraView(aspect)
            : CameraView.look(
                eye: const Vec3(0, 2, 5),
                forward: const Vec3(0, -0.2, -1),
                fovYRadians: 1.0,
                aspect: aspect,
                near: 0.1,
                far: 200,
              ));
    return cam.screenPointToRay(x, y, w, h);
  }
}

/// File-system [AssetLoader] for native desktop builds.
final class FileAssetLoader implements AssetLoader {
  final ResourceLibrary resources;
  final Directory rootDirectory;

  const FileAssetLoader({required this.resources, required this.rootDirectory});

  File _resolve(String path) {
    final clean = path.replaceAll('\\', '/');
    return File('${rootDirectory.path}/$clean');
  }

  @override
  Future<ModelAsset> loadModel(
    String path, {
    MaterialOverride? materialOverride,
  }) async {
    final bytes = await loadBytes(path);
    final name = path.split('/').last.replaceAll('.glb', '');
    return ModelAsset.fromGlb(
      GlbDecoder.decode(bytes),
      resources,
      name: name,
      materialOverride: materialOverride,
    );
  }

  @override
  Future<Uint8List> loadBytes(String path) => _resolve(path).readAsBytes();

  @override
  Future<String> loadText(String path) => _resolve(path).readAsString();
}

/// Persistent JSON-file [KeyValueStore] for native desktop builds.
final class JsonFileStore implements KeyValueStore {
  final File file;
  final Map<String, String> _cache = {};

  JsonFileStore(this.file) {
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            _cache['${entry.key}'] = '${entry.value}';
          }
        }
      } catch (_) {}
    }
  }

  void _flush() {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_cache));
    } catch (_) {}
  }

  @override
  String? read(String key) => _cache[key];

  @override
  void write(String key, String value) {
    _cache[key] = value;
    _flush();
  }

  @override
  void remove(String key) {
    if (_cache.remove(key) != null) {
      _flush();
    }
  }
}
