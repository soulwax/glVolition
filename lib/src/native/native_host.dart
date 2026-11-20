import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pixeldart/pixeldart_advanced.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';

import '../../gl_volition.dart';
import 'gles3_bindings.dart';
import 'gles3_ffi_device.dart';
import 'native_audio_device.dart';
import 'native_bindings.dart';
import 'native_ffi_transport.dart';
import 'sdl3_bindings.dart';

/// Optional callback invoked by [RecordingGlesDevice] for each low-level GPU
/// operation, allowing an FFI OpenGL ES 3.0 / ANGLE host to forward validated
/// commands to native GL entrypoints.
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

final class _NativeOcclusionQuery implements GpuObject {
  final int id;
  bool ended = false;
  bool anySamplesPassed = true;
  _NativeOcclusionQuery(this.id);
}

/// Preserved backward-compatible alias for [RecordingGlesDevice].
typedef GlesDevice = RecordingGlesDevice;

/// Recording / software-validated native [GpuDeviceV2] implementation for
/// `glVolition` (E6-3 / S1-A).
///
/// Implements the full `pixeldart` [GpuDeviceV2] and [GpuContextGeneration]
/// contracts without `package:web`, validating shaders, render target
/// attachments, vertex/index bindings, and resource lifetimes while optionally
/// dispatching commands to a native GLES3 / FFI [onCommand] hook.
final class RecordingGlesDevice implements GpuDeviceV2, GpuContextGeneration {
  final bool timerQueries;
  final bool disjointTimer;
  int maxSamples;
  bool anisotropicFiltering;
  double maxAnisotropy;
  int? incompleteAboveSamples;
  final GlesDispatchHook? onCommand;

  RecordingGlesDevice({
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
  int activeViewportX = 0;
  int activeViewportY = 0;
  int activeViewportWidth = 0;
  int activeViewportHeight = 0;
  final List<({int x, int y, int width, int height})> viewportLog = [];

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

  /// Sets the active GL viewport rectangle and logs it for verification.
  void setViewport(int x, int y, int width, int height) {
    _requireReady();
    activeViewportX = x;
    activeViewportY = y;
    activeViewportWidth = width;
    activeViewportHeight = height;
    viewportLog.add((x: x, y: y, width: width, height: height));
    drawLog.add('setViewport($x, $y, $width, $height)');
    onCommand?.call('setViewport', [x, y, width, height]);
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

  // --- GpuDeviceV2 (S1-A) ---

  final Set<int> _occlusionIds = {};
  int _nextOcclusionId = 1;
  final Map<int, GpuObject> _boundUbos = {};

  @override
  GpuObject createUniformBuffer(GpuUniformBufferDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    bufferCreateCalls += 1;
    final obj = _create('ubo');
    drawLog.add('createUniformBuffer(${descriptor.byteLength})');
    onCommand?.call('createUniformBuffer', [
      (obj as _NativeGpuObject).id,
      descriptor.byteLength,
      descriptor.usage.name,
    ]);
    return obj;
  }

  @override
  void updateUniformBuffer(
    GpuObject buffer,
    ByteData data, {
    int dstByteOffset = 0,
  }) {
    _requireReady();
    _requireLive(buffer);
    bufferUploadCalls += 1;
    final id = (buffer as _NativeGpuObject).id;
    drawLog.add(
      'updateUniformBuffer($id, ${data.lengthInBytes}, $dstByteOffset)',
    );
    onCommand?.call('updateUniformBuffer', [
      id,
      data.lengthInBytes,
      dstByteOffset,
    ]);
  }

  @override
  void bindUniformBufferBase(int bindingPoint, GpuObject buffer) {
    _requireReady();
    _requireLive(buffer);
    _boundUbos[bindingPoint] = buffer;
    final id = (buffer as _NativeGpuObject).id;
    drawLog.add('bindUniformBufferBase($bindingPoint, $id)');
    onCommand?.call('bindUniformBufferBase', [bindingPoint, id]);
  }

  @override
  void uniformBlockBinding(
    GpuObject program,
    String blockName,
    int bindingPoint,
  ) {
    _requireReady();
    _requireLive(program);
    final id = (program as _NativeGpuObject).id;
    drawLog.add('uniformBlockBinding($id, $blockName, $bindingPoint)');
    onCommand?.call('uniformBlockBinding', [id, blockName, bindingPoint]);
  }

  @override
  GpuObject createCubeTexture(GpuCubeTextureDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    textureCreateCalls += 1;
    final obj = _create('cubeTexture');
    if (descriptor.hasMips) {
      _texturesMissingFinalizedMips.add((obj as _NativeGpuObject).id);
    }
    drawLog.add(
      'createCubeTexture(${descriptor.size}, ${descriptor.format.name})',
    );
    onCommand?.call('createCubeTexture', [
      (obj as _NativeGpuObject).id,
      descriptor.size,
      descriptor.format.name,
    ]);
    return obj;
  }

  @override
  void uploadCubeFace(
    GpuObject texture,
    GpuCubeFace face,
    Uint8List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    _requireLive(texture);
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('uploadCubeFace($id, ${face.name}, mip=$mipLevel)');
    onCommand?.call('uploadCubeFace', [id, face.name, pixels.length, mipLevel]);
  }

  @override
  void uploadCubeFaceFloat(
    GpuObject texture,
    GpuCubeFace face,
    Float32List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    _requireLive(texture);
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('uploadCubeFaceFloat($id, ${face.name}, mip=$mipLevel)');
    onCommand?.call('uploadCubeFaceFloat', [
      id,
      face.name,
      pixels.length,
      mipLevel,
    ]);
  }

  @override
  void bindCubeTexture(int unit, GpuObject texture) {
    _requireReady();
    _requireLive(texture);
    _sampledSinceUseProgram[unit] = texture;
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('bindCubeTexture($unit, $id)');
    onCommand?.call('bindCubeTexture', [unit, id]);
  }

  @override
  GpuObject createTextureArray(GpuTextureArrayDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    textureCreateCalls += 1;
    final obj = _create('textureArray');
    if (descriptor.hasMips) {
      _texturesMissingFinalizedMips.add((obj as _NativeGpuObject).id);
    }
    drawLog.add(
      'createTextureArray(${descriptor.width}x${descriptor.height}x${descriptor.layers})',
    );
    onCommand?.call('createTextureArray', [
      (obj as _NativeGpuObject).id,
      descriptor.width,
      descriptor.height,
      descriptor.layers,
      descriptor.format.name,
    ]);
    return obj;
  }

  @override
  void uploadTextureArrayLayer(
    GpuObject texture,
    int layer,
    Uint8List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    _requireLive(texture);
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('uploadTextureArrayLayer($id, layer=$layer, mip=$mipLevel)');
    onCommand?.call('uploadTextureArrayLayer', [
      id,
      layer,
      pixels.length,
      mipLevel,
    ]);
  }

  @override
  void uploadTextureArrayLayerFloat(
    GpuObject texture,
    int layer,
    Float32List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    _requireLive(texture);
    final id = (texture as _NativeGpuObject).id;
    drawLog.add(
      'uploadTextureArrayLayerFloat($id, layer=$layer, mip=$mipLevel)',
    );
    onCommand?.call('uploadTextureArrayLayerFloat', [
      id,
      layer,
      pixels.length,
      mipLevel,
    ]);
  }

  @override
  void bindTextureArray(int unit, GpuObject texture) {
    _requireReady();
    _requireLive(texture);
    _sampledSinceUseProgram[unit] = texture;
    final id = (texture as _NativeGpuObject).id;
    drawLog.add('bindTextureArray($unit, $id)');
    onCommand?.call('bindTextureArray', [unit, id]);
  }

  @override
  GpuObject createMrtTarget(GpuMrtTargetDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    targetCreateCalls += 1;
    final target = _create('mrtTarget');
    _targetDescriptors[(target as _NativeGpuObject).id] = GpuTargetDescriptor(
      width: descriptor.width,
      height: descriptor.height,
      samples: descriptor.samples,
      hasDepth: descriptor.hasDepth,
      hasStencil: descriptor.hasStencil,
    );
    drawLog.add(
      'createMrtTarget(${descriptor.width}x${descriptor.height}, '
      'attachments=${descriptor.colorFormats.length})',
    );
    onCommand?.call('createMrtTarget', [
      target.id,
      descriptor.width,
      descriptor.height,
      descriptor.colorFormats.map((f) => f.name).toList(),
    ]);
    return target;
  }

  @override
  void drawBuffers(List<int> colorAttachmentIndices) {
    _requireReady();
    drawLog.add('drawBuffers(${colorAttachmentIndices.join(',')})');
    onCommand?.call('drawBuffers', [colorAttachmentIndices]);
  }

  @override
  void bindTargetColorAttachment(
    int unit,
    GpuObject target,
    int attachmentIndex,
  ) {
    _requireReady();
    _requireLive(target);
    _sampledSinceUseProgram[unit] = target;
    final id = (target as _NativeGpuObject).id;
    drawLog.add('bindTargetColorAttachment($unit, $id, $attachmentIndex)');
    onCommand?.call('bindTargetColorAttachment', [unit, id, attachmentIndex]);
  }

  @override
  GpuObject? beginOcclusionQuery() {
    _requireReady();
    final q = _NativeOcclusionQuery(_nextOcclusionId++);
    _occlusionIds.add(q.id);
    drawLog.add('beginOcclusionQuery(${q.id})');
    onCommand?.call('beginOcclusionQuery', [q.id]);
    return q;
  }

  @override
  void endOcclusionQuery(GpuObject query) {
    if (query is! _NativeOcclusionQuery || !_occlusionIds.contains(query.id)) {
      throw StateError('GlesDevice: unknown occlusion query');
    }
    if (query.ended) {
      throw StateError('GlesDevice: occlusion query already ended');
    }
    query.ended = true;
    drawLog.add('endOcclusionQuery(${query.id})');
    onCommand?.call('endOcclusionQuery', [query.id]);
  }

  @override
  GpuOcclusionQueryPoll pollOcclusionQuery(GpuObject query) {
    if (query is! _NativeOcclusionQuery || !_occlusionIds.contains(query.id)) {
      throw StateError('GlesDevice: unknown occlusion query');
    }
    if (!query.ended) {
      return const GpuOcclusionQueryPoll(GpuOcclusionQueryStatus.pending);
    }
    return GpuOcclusionQueryPoll(
      GpuOcclusionQueryStatus.ready,
      query.anySamplesPassed,
    );
  }

  @override
  void deleteOcclusionQuery(GpuObject query) {
    if (query is! _NativeOcclusionQuery || !_occlusionIds.remove(query.id)) {
      throw StateError('GlesDevice: unknown occlusion query');
    }
    drawLog.add('deleteOcclusionQuery(${query.id})');
    onCommand?.call('deleteOcclusionQuery', [query.id]);
  }

  @override
  GpuPassTimerScope? beginPassTimer(String passName) {
    final q = beginGpuTimer();
    if (q == null) return null;
    drawLog.add('beginPassTimer($passName)');
    onCommand?.call('beginPassTimer', [passName]);
    return GpuPassTimerScope(passName: passName, query: q);
  }

  @override
  void endPassTimer(GpuPassTimerScope scope) {
    endGpuTimer(scope.query);
    drawLog.add('endPassTimer(${scope.passName})');
    onCommand?.call('endPassTimer', [scope.passName]);
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

  /// Headless-safe factory over [RecordingGlesDevice] and [SilentAudio] for
  /// deterministic CI and unit tests.
  static Future<NativeEngineRunner> recording({
    RecordingGlesDevice? device,
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
  }) => boot(
    device: device ?? RecordingGlesDevice(),
    audio: audio ?? SilentAudio(),
    windowBackend: windowBackend,
    width: width,
    height: height,
    devicePixelRatio: devicePixelRatio,
    requestedProfile: requestedProfile,
    assetsDirectory: assetsDirectory,
    storageFile: storageFile,
    rethrowErrors: rethrowErrors,
    registerSpecs: registerSpecs,
    initialScene: initialScene,
  );

  /// Default windowed hardware desktop factory wiring [Sdl3WindowBackend] +
  /// [Gles3FfiDevice] + [NativeAudioDevice].
  ///
  /// When [fallbackToRecording] is `true`, safely falls back to [recording] if
  /// native window or GLES3 initialization fails on headless CI machines.
  static Future<NativeEngineRunner> desktop({
    String title = 'glVolition',
    int width = 1280,
    int height = 720,
    bool resizable = true,
    double devicePixelRatio = 1.0,
    QualityProfile requestedProfile = QualityProfile.clean,
    Directory? assetsDirectory,
    File? storageFile,
    bool rethrowErrors = true,
    bool fallbackToRecording = false,
    Sdl3WindowBackend? windowBackend,
    Gles3Api? glesApi,
    NativeAudioSink? audioSink,
    NativeAudioConfig audioConfig = const NativeAudioConfig(),
    void Function(ComponentRegistry registry)? registerSpecs,
    Scene? initialScene,
  }) async {
    final ownsWindow = windowBackend == null;
    final window = windowBackend ?? Sdl3WindowBackend();
    if (!window.isInitialized) {
      final opened = window.openWindow(
        title: title,
        width: width,
        height: height,
        resizable: resizable,
        gles3: true,
      );
      if (!opened) {
        final error = window.lastError ?? 'failed to open SDL3 GLES3 window';
        if (ownsWindow) window.dispose();
        if (fallbackToRecording) {
          return recording(
            width: width,
            height: height,
            devicePixelRatio: devicePixelRatio,
            requestedProfile: requestedProfile,
            assetsDirectory: assetsDirectory,
            storageFile: storageFile,
            rethrowErrors: rethrowErrors,
            registerSpecs: registerSpecs,
            initialScene: initialScene,
          );
        }
        throw StateError('NativeEngineHost.desktop: $error');
      }
    }
    window.makeCurrent();

    final targetWidth = window.pixelWidth > 0 ? window.pixelWidth : width;
    final targetHeight = window.pixelHeight > 0 ? window.pixelHeight : height;
    final dpr = window.devicePixelRatio > 0
        ? window.devicePixelRatio
        : devicePixelRatio;
    final gl = glesApi ?? FfiGles3Api(DynamicLibraryGlLoader());
    final gpu = Gles3FfiDevice(gl, targetWidth, targetHeight);
    final audio = NativeAudioDevice(
      sink: audioSink,
      config: audioConfig,
      rootDirectory: assetsDirectory,
    );
    try {
      return await boot(
        device: gpu,
        audio: audio,
        windowBackend: window,
        width: targetWidth,
        height: targetHeight,
        devicePixelRatio: dpr,
        requestedProfile: requestedProfile,
        assetsDirectory: assetsDirectory,
        storageFile: storageFile,
        rethrowErrors: rethrowErrors,
        registerSpecs: registerSpecs,
        initialScene: initialScene,
      );
    } catch (_) {
      audio.dispose();
      if (ownsWindow) window.dispose();
      if (fallbackToRecording) {
        return recording(
          width: width,
          height: height,
          devicePixelRatio: devicePixelRatio,
          requestedProfile: requestedProfile,
          assetsDirectory: assetsDirectory,
          storageFile: storageFile,
          rethrowErrors: rethrowErrors,
          registerSpecs: registerSpecs,
          initialScene: initialScene,
        );
      }
      rethrow;
    }
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
    graphics._queuedCameraPasses.clear();
    graphics.lastFramePassStats.clear();
    graphics._collectingFramePasses = true;
    try {
      eng.step(dt);
    } finally {
      graphics._collectingFramePasses = false;
    }

    sceneRoot.syncToWorld(world);
    graphics.shakeEngine.update(dt);

    final updatedControllers = <CameraController>{};
    final queuedPasses = graphics._queuedCameraPasses;
    final FrameStats frameStats;
    if (queuedPasses.isEmpty) {
      if (graphics._activeViewportWidth > 0) {
        graphics.setViewport(0, 0, _surface.pixelWidth, _surface.pixelHeight);
      }
      frameStats = _executeRenderPass(
        eng: eng,
        dt: dt,
        camCtrl: graphics.camera,
        visibilityMask: graphics.visibilityMask,
        viewportWidth: _surface.pixelWidth,
        viewportHeight: _surface.pixelHeight,
        updateEmitters: true,
        updatedControllers: updatedControllers,
      );
    } else {
      final primaryMask = graphics.visibilityMask;
      final passes = List<CameraRenderDescriptor>.of(queuedPasses);
      queuedPasses.clear();
      final statsList = <FrameStats>[];
      for (var i = 0; i < passes.length; i++) {
        final pass = passes[i];
        final vp = graphics._resolvePixelViewport(
          pass.normalizedViewportRect,
          pass.target,
        );
        graphics._applyTargetAndClear(pass, pass.target);
        graphics.setViewport(vp.x, vp.y, vp.width, vp.height);
        graphics.visibilityMask = pass.visibilityMask;
        final passStats = _executeRenderPass(
          eng: eng,
          dt: dt,
          camCtrl: pass.camera ?? graphics.camera,
          visibilityMask: pass.visibilityMask,
          viewportWidth: vp.width,
          viewportHeight: vp.height,
          updateEmitters: i == 0,
          updatedControllers: updatedControllers,
        );
        graphics._boundRenderTarget = null;
        graphics.renderedCameraPasses.add(pass);
        graphics.lastFramePassStats.add((descriptor: pass, stats: passStats));
        statsList.add(passStats);
      }
      graphics.visibilityMask = primaryMask;
      frameStats = _mergeFrameStats(statsList);
    }

    if (audio case final NativeAudioDevice nativeAudio) {
      final audioFrames = dt > 0
          ? (dt * nativeAudio.config.sampleRate).round().clamp(
              1,
              nativeAudio.config.sampleRate,
            )
          : nativeAudio.config.framesPerBuffer;
      nativeAudio.pumpAudio(frames: audioFrames);
    }
    input.endFrame();
    return frameStats;
  }

  FrameStats _executeRenderPass({
    required Engine eng,
    required double dt,
    required CameraController? camCtrl,
    required int visibilityMask,
    required int viewportWidth,
    required int viewportHeight,
    required bool updateEmitters,
    required Set<CameraController> updatedControllers,
  }) {
    if (camCtrl != null && updatedControllers.add(camCtrl)) {
      camCtrl.update(dt);
    }

    final aspect = viewportHeight > 0 ? viewportWidth / viewportHeight : 1.0;
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
      visibilityMask: visibilityMask,
    );

    final encoder = renderer.beginFrame(world, frameInput);
    try {
      for (var i = 0; i < graphics._emitters.length; i++) {
        final emitter = graphics._emitters[i];
        if (updateEmitters) {
          emitter.update(dt);
        }
        emitter.submit(encoder, frameInput);
      }
      eng.encodeFrame(encoder, frameInput);
      return renderer.endFrame();
    } catch (error) {
      try {
        renderer.abortFrame();
      } catch (_) {}
      rethrow;
    }
  }

  static FrameStats _mergeFrameStats(List<FrameStats> statsList) {
    if (statsList.length == 1) return statsList.first;
    final last = statsList.last;
    var pointLightsDropped = 0;
    var drawCalls = 0;
    var trianglesSubmitted = 0;
    var trianglesCulled = 0;
    var instancesSubmitted = 0;
    var instancesCulled = 0;
    var peakGpuBytes = 0;
    var resourceCreateCount = 0;
    var resourceDeleteCount = 0;
    final mergedPasses = <String, FramePassStats>{};
    for (final s in statsList) {
      if (s.pointLightsDropped > pointLightsDropped) {
        pointLightsDropped = s.pointLightsDropped;
      }
      drawCalls += s.drawCalls;
      trianglesSubmitted += s.trianglesSubmitted;
      trianglesCulled += s.trianglesCulled;
      instancesSubmitted += s.instancesSubmitted;
      instancesCulled += s.instancesCulled;
      if (s.peakGpuBytes > peakGpuBytes) peakGpuBytes = s.peakGpuBytes;
      resourceCreateCount += s.resourceCreateCount;
      resourceDeleteCount += s.resourceDeleteCount;
      for (final entry in s.passStats.entries) {
        final prev = mergedPasses[entry.key];
        final cur = entry.value;
        mergedPasses[entry.key] = prev == null
            ? cur
            : FramePassStats(
                drawCalls: prev.drawCalls + cur.drawCalls,
                trianglesSubmitted:
                    prev.trianglesSubmitted + cur.trianglesSubmitted,
                trianglesCulled: prev.trianglesCulled + cur.trianglesCulled,
                instancesSubmitted:
                    prev.instancesSubmitted + cur.instancesSubmitted,
                instancesCulled: prev.instancesCulled + cur.instancesCulled,
              );
      }
    }
    return FrameStats(
      frameIndex: last.frameIndex,
      pointLightsDropped: pointLightsDropped,
      drawCalls: drawCalls,
      trianglesSubmitted: trianglesSubmitted,
      trianglesCulled: trianglesCulled,
      instancesSubmitted: instancesSubmitted,
      instancesCulled: instancesCulled,
      liveGpuBytes: last.liveGpuBytes,
      peakGpuBytes: peakGpuBytes,
      resourceCreateCount: resourceCreateCount,
      resourceDeleteCount: resourceDeleteCount,
      passStats: Map<String, FramePassStats>.unmodifiable(mergedPasses),
    );
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
    if (device case final Gles3FfiDevice gles3) {
      gles3.setViewport(0, 0, _surface.pixelWidth, _surface.pixelHeight);
    }
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
    graphics._dispose();
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

  /// Creates a [NativeDesktopBridge] bound to this runner and its active
  /// `windowBackend`.
  NativeDesktopBridge createDesktopBridge({
    NativeGlTransport? transport,
    Sdl3EventPump? eventPump,
    NativeWindowBackend? windowBackend,
  }) => NativeDesktopBridge(
    runner: this,
    transport: transport ?? NativeGlTransport(),
    eventPump: eventPump,
    windowBackend: windowBackend ?? host.windowBackend,
  );

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
  final Map<MeshHandle, MeshData> updatedMeshes = {};
  final Map<MeshHandle, Float32List> skinningPalettes = {};
  final Map<String, RenderPassDecl> declaredRenderPasses = {};
  final List<SubmittedIndirectBatch> indirectBatches = [];
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

  int _nextRenderTargetSlot = 1;
  final Set<RenderTargetHandle> liveRenderTargets = {};
  final Map<RenderTargetHandle, GpuObject> _gpuTargets = {};
  final List<CameraRenderDescriptor> renderedCameraPasses = [];
  final List<CameraRenderDescriptor> _queuedCameraPasses = [];
  final List<({CameraRenderDescriptor descriptor, FrameStats stats})>
  lastFramePassStats = [];
  RenderTargetHandle? _boundRenderTarget;
  bool _collectingFramePasses = false;
  int activeViewportX = 0;
  int activeViewportY = 0;
  int _activeViewportWidth = 0;
  int _activeViewportHeight = 0;

  int get activeViewportWidth =>
      _activeViewportWidth > 0 ? _activeViewportWidth : viewportWidth;
  int get activeViewportHeight =>
      _activeViewportHeight > 0 ? _activeViewportHeight : viewportHeight;

  GpuObject? gpuTargetFor(RenderTargetHandle handle) => _gpuTargets[handle];

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
    if (_host.device.status != GpuDeviceStatus.ready) {
      _boundRenderTarget = null;
      return;
    }
    if (target == null) {
      _host.device.bindTarget(null);
      _boundRenderTarget = null;
      return;
    }
    if (!liveRenderTargets.contains(target)) {
      throw StateError(
        'NativeGraphics: RenderTargetHandle(${target.slot}) has been released',
      );
    }
    final gpuTarget = _gpuTargets.putIfAbsent(
      target,
      () => _host.device.createTarget(
        GpuTargetDescriptor(
          width: target.width,
          height: target.height,
          hasDepth: true,
        ),
      ),
    );
    _host.device.bindTarget(gpuTarget);
    _boundRenderTarget = target;
  }

  void _applyTargetAndClear(
    CameraRenderDescriptor descriptor,
    RenderTargetHandle? target,
  ) {
    _bindTargetHandle(target);
    if (target == null || _host.device.status != GpuDeviceStatus.ready) return;
    final clearMask = switch ((descriptor.clearColor, descriptor.clearDepth)) {
      (true, true) => ClearMask.colorAndDepth,
      (true, false) => ClearMask.colorOnly,
      (false, true) => ClearMask.depthOnly,
      (false, false) => null,
    };
    if (clearMask != null) {
      final c = environment.clearColor;
      _host.device.clear(clearMask, r: c.r, g: c.g, b: c.b, a: 1.0);
    }
  }

  void _dispose() {
    for (final handle in liveRenderTargets.toList()) {
      releaseRenderTarget(handle);
    }
    _queuedCameraPasses.clear();
    _boundRenderTarget = null;
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
      _nextRenderTargetSlot++,
      width: width,
      height: height,
      colorTexture: colorTex,
      debugLabel: debugLabel,
    );
    liveRenderTargets.add(handle);
    if (_host.device.status == GpuDeviceStatus.ready) {
      _gpuTargets[handle] = _host.device.createTarget(
        GpuTargetDescriptor(width: width, height: height, hasDepth: true),
      );
    }
    return handle;
  }

  @override
  void releaseRenderTarget(RenderTargetHandle handle) {
    if (liveRenderTargets.remove(handle)) {
      final gpuTarget = _gpuTargets.remove(handle);
      if (gpuTarget != null && _host.device.status == GpuDeviceStatus.ready) {
        if (_boundRenderTarget == handle) {
          _host.device.bindTarget(null);
          _boundRenderTarget = null;
        }
        _host.device.deleteTarget(gpuTarget);
      }
      releaseTexture(handle.colorTexture);
    }
  }

  void _setViewportState(int x, int y, int width, int height) {
    activeViewportX = x;
    activeViewportY = y;
    _activeViewportWidth = width;
    _activeViewportHeight = height;
  }

  @override
  void setViewport(int x, int y, int width, int height) {
    _setViewportState(x, y, width, height);
    if (_host.device case final Gles3FfiDevice gles3) {
      gles3.setViewport(x, y, width, height);
    } else if (_host.device case final RecordingGlesDevice recording) {
      if (recording.status == GpuDeviceStatus.ready) {
        recording.setViewport(x, y, width, height);
      }
    }
  }

  @override
  void renderFrameToTarget(
    RenderTargetHandle? target, {
    required CameraRenderDescriptor descriptor,
  }) {
    final vp = _resolvePixelViewport(descriptor.normalizedViewportRect, target);
    visibilityMask = descriptor.visibilityMask;
    if (_collectingFramePasses) {
      _setViewportState(vp.x, vp.y, vp.width, vp.height);
      _queuedCameraPasses.add(descriptor);
    } else {
      _applyTargetAndClear(descriptor, target);
      setViewport(vp.x, vp.y, vp.width, vp.height);
      renderedCameraPasses.add(descriptor);
    }
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
