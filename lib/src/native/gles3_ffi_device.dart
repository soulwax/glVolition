import 'dart:typed_data';

import 'package:pixeldart/rendering/api/capabilities.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';

import 'gles3_bindings.dart';
import 'native_ffi_transport.dart';

enum _GlesObjectKind {
  buffer,
  texture,
  target,
  vao,
  program,
  timer,
  occlusionQuery,
}

final class _GlesGpuObject implements GpuObject {
  final int id;
  final int generation;
  final _GlesObjectKind kind;

  const _GlesGpuObject(this.id, this.generation, this.kind);
}

final class _GlTexture {
  final int id;
  final int width;
  final int height;
  final int layers;
  final bool hasMips;
  final AnisotropyDecision anisotropy;
  final GpuTextureTarget target;
  final GpuTextureFormat format;

  const _GlTexture({
    required this.id,
    required this.width,
    required this.height,
    required this.layers,
    required this.hasMips,
    required this.anisotropy,
    this.target = GpuTextureTarget.tex2d,
    this.format = GpuTextureFormat.rgba8,
  });
}

final class _GlFramebuffer {
  final int fbo;
  final int? colorTex;
  final int? colorRb;
  final int? depthRb;
  final int? depthTex;
  final int? glowTex;
  final int? glowRb;
  final List<int> colorAttachments;
  final int width;
  final int height;
  final int samples;

  const _GlFramebuffer({
    required this.fbo,
    this.colorTex,
    this.colorRb,
    this.depthRb,
    this.depthTex,
    this.glowTex,
    this.glowRb,
    this.colorAttachments = const [],
    required this.width,
    required this.height,
    required this.samples,
  });
}

final class _GlTimerQuery {
  final int id;
  bool ended = false;

  _GlTimerQuery(this.id);
}

final class _GlOcclusionQuery {
  final int id;
  bool ended = false;

  _GlOcclusionQuery(this.id);
}

final class _UniformLocations {
  final Map<String, int> found = <String, int>{};
  final Set<String> missing = <String>{};
}

/// Hardware-backed OpenGL ES 3.0 / ANGLE [GpuDeviceV2] implementation driven
/// through [Gles3Api] (defaulting to [FfiGles3Api] over
/// [DynamicLibraryGlLoader]).
final class Gles3FfiDevice implements GpuDeviceV2, GpuContextGeneration {
  final Gles3Api _gl;
  final WebGlStateCache _stateCache = WebGlStateCache();
  final Float32List _clearColorScratch = Float32List(4);

  GpuDeviceStatus _status = GpuDeviceStatus.ready;
  int _contextGeneration = 0;

  int _viewportX = 0;
  int _viewportY = 0;
  int _viewportWidth;
  int _viewportHeight;

  RenderCapabilities? _cachedCapabilities;

  final Set<int> _buffers = <int>{};
  final Map<int, _GlTexture> _textures = <int, _GlTexture>{};
  final Map<int, _GlFramebuffer> _targets = <int, _GlFramebuffer>{};
  final Set<int> _vaos = <int>{};
  final Set<int> _programs = <int>{};
  final Map<int, _GlTimerQuery> _timers = <int, _GlTimerQuery>{};
  final Map<int, _GlOcclusionQuery> _occlusionQueries =
      <int, _GlOcclusionQuery>{};
  final Map<int, _UniformLocations> _uniformLocations =
      <int, _UniformLocations>{};

  int? _boundProgramId;
  _UniformLocations? _boundUniforms;
  GpuObject? _boundTarget;
  GpuObject? _boundVao;
  GpuObject? _boundElementBuffer;

  /// Creates a [Gles3FfiDevice] backed by [api] (defaulting to
  /// `FfiGles3Api(DynamicLibraryGlLoader())`) and an initial backbuffer
  /// viewport of [viewportWidth]x[viewportHeight].
  Gles3FfiDevice([
    Gles3Api? api,
    int viewportWidth = 1280,
    int viewportHeight = 720,
  ]) : _gl = api ?? FfiGles3Api(DynamicLibraryGlLoader()),
       _viewportWidth = viewportWidth,
       _viewportHeight = viewportHeight {
    RangeError.checkNotNegative(viewportWidth, 'viewportWidth');
    RangeError.checkNotNegative(viewportHeight, 'viewportHeight');
  }

  /// Underlying [Gles3Api] entrypoint table.
  Gles3Api get api => _gl;

  @override
  GpuDeviceStatus get status => _status;

  @override
  int get contextGeneration => _contextGeneration;

  int get viewportX => _viewportX;
  int get viewportY => _viewportY;
  int get viewportWidth => _viewportWidth;
  int get viewportHeight => _viewportHeight;

  int get liveBufferCount => _buffers.length;
  int get liveTextureCount => _textures.length;
  int get liveTargetCount => _targets.length;
  int get liveVaoCount => _vaos.length;
  int get liveProgramCount => _programs.length;
  int get liveTimerCount => _timers.length;
  int get liveObjectCount =>
      _buffers.length +
      _textures.length +
      _targets.length +
      _vaos.length +
      _programs.length;

  GpuObject? get boundTarget => _boundTarget;
  GpuObject? get boundVertexArray => _boundVao;
  GpuObject? get boundElementBuffer => _boundElementBuffer;

  void _requireReady() {
    if (_status != GpuDeviceStatus.ready) {
      throw StateError(
        'Gles3FfiDevice: operation attempted while context is not ready',
      );
    }
  }

  bool _isStaleOrInvalid(GpuObject obj, _GlesObjectKind expectedKind) {
    if (obj is! _GlesGpuObject || obj.kind != expectedKind) {
      throw ArgumentError.value(
        obj,
        'object',
        'is not a Gles3FfiDevice ${expectedKind.name}',
      );
    }
    return obj.generation != _contextGeneration;
  }

  _GlesGpuObject _asObject(GpuObject obj, _GlesObjectKind expectedKind) {
    if (obj is! _GlesGpuObject || obj.kind != expectedKind) {
      throw ArgumentError.value(
        obj,
        'object',
        'is not a Gles3FfiDevice ${expectedKind.name}',
      );
    }
    if (obj.generation != _contextGeneration) {
      throw StateError(
        'Gles3FfiDevice: stale ${expectedKind.name} handle from lost context',
      );
    }
    return obj;
  }

  int _requireBuffer(GpuObject buffer) {
    final obj = _asObject(buffer, _GlesObjectKind.buffer);
    if (!_buffers.contains(obj.id)) {
      throw StateError('Gles3FfiDevice: buffer ${obj.id} is not live');
    }
    return obj.id;
  }

  _GlTexture _requireTexture(GpuObject texture) {
    final obj = _asObject(texture, _GlesObjectKind.texture);
    final handle = _textures[obj.id];
    if (handle == null) {
      throw StateError('Gles3FfiDevice: texture ${obj.id} is not live');
    }
    return handle;
  }

  _GlFramebuffer _requireTarget(GpuObject target) {
    final obj = _asObject(target, _GlesObjectKind.target);
    final handle = _targets[obj.id];
    if (handle == null) {
      throw StateError('Gles3FfiDevice: target ${obj.id} is not live');
    }
    return handle;
  }

  int _requireVao(GpuObject vao) {
    final obj = _asObject(vao, _GlesObjectKind.vao);
    if (!_vaos.contains(obj.id)) {
      throw StateError('Gles3FfiDevice: vertex array ${obj.id} is not live');
    }
    return obj.id;
  }

  int _requireProgram(GpuObject program) {
    final obj = _asObject(program, _GlesObjectKind.program);
    if (!_programs.contains(obj.id)) {
      throw StateError('Gles3FfiDevice: program ${obj.id} is not live');
    }
    return obj.id;
  }

  _GlTimerQuery _requireTimer(GpuObject query) {
    final obj = _asObject(query, _GlesObjectKind.timer);
    final timer = _timers[obj.id];
    if (timer == null) {
      throw StateError('Gles3FfiDevice: timer ${obj.id} is not live');
    }
    return timer;
  }

  int _genOne(List<int> Function(int count) generator, String name) {
    final ids = generator(1);
    if (ids.isEmpty || ids.first == 0) {
      throw StateError('Gles3FfiDevice: $name() returned 0');
    }
    return ids.first;
  }

  Set<String> _readExtensions() {
    final raw = _gl.glGetString(GL_EXTENSIONS);
    if (raw != null && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toSet();
    }
    if (_gl case final Gles3ExtensionsApi ext) {
      final count = _gl.glGetIntegerv(GL_NUM_EXTENSIONS);
      if (count > 0) {
        final result = <String>{};
        for (var i = 0; i < count; i++) {
          final item = ext.glGetStringi(GL_EXTENSIONS, i);
          if (item != null && item.isNotEmpty) {
            result.add(item);
          }
        }
        return result;
      }
    }
    return const <String>{};
  }

  static bool _hasAnyExtension(Set<String> extensions, List<String> names) =>
      names.any(extensions.contains);

  @override
  RenderCapabilities queryCapabilities() {
    _requireReady();
    final cached = _cachedCapabilities;
    if (cached != null) return cached;

    final version = _gl.glGetString(GL_VERSION);
    final renderer = _gl.glGetString(GL_RENDERER);
    final vendor = _gl.glGetString(GL_VENDOR);
    final extensions = _readExtensions();

    int positiveInt(int pname) {
      final v = _gl.glGetIntegerv(pname);
      return v > 0 ? v : 1;
    }

    final maxTextureSize = positiveInt(GL_MAX_TEXTURE_SIZE);
    final maxArrayLayers = positiveInt(GL_MAX_ARRAY_TEXTURE_LAYERS);
    final maxSamples = positiveInt(GL_MAX_SAMPLES);
    final maxVertexAttribs = positiveInt(GL_MAX_VERTEX_ATTRIBS);
    final maxColorAttachments = positiveInt(GL_MAX_COLOR_ATTACHMENTS);

    final anisotropicFiltering = _hasAnyExtension(extensions, const [
      'GL_EXT_texture_filter_anisotropic',
      'EXT_texture_filter_anisotropic',
    ]);
    var maxAnisotropy = 1.0;
    if (anisotropicFiltering) {
      final queried = _gl.glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT);
      if (queried.isFinite && queried >= 1.0) {
        maxAnisotropy = queried;
      }
    }

    final disjointTimerQuery = _hasAnyExtension(extensions, const [
      'GL_EXT_disjoint_timer_query',
      'GL_EXT_disjoint_timer_query_webgl2',
      'EXT_disjoint_timer_query',
      'EXT_disjoint_timer_query_webgl2',
    ]);
    final floatRenderTarget = _hasAnyExtension(extensions, const [
      'GL_EXT_color_buffer_float',
      'EXT_color_buffer_float',
    ]);
    final halfFloatRenderTarget =
        floatRenderTarget ||
        _hasAnyExtension(extensions, const [
          'GL_EXT_color_buffer_half_float',
          'EXT_color_buffer_half_float',
        ]);
    final contextLossExtension = _hasAnyExtension(extensions, const [
      'GL_KHR_robustness',
      'GL_EXT_robustness',
    ]);

    final caps = RenderCapabilities(
      webglVersion: version,
      rendererString: renderer,
      vendorString: vendor,
      maxTextureSize: maxTextureSize,
      maxTextureArrayLayers: maxArrayLayers,
      maxSamples: maxSamples,
      maxVertexAttributes: maxVertexAttribs,
      maxColorAttachments: maxColorAttachments,
      anisotropicFiltering: anisotropicFiltering,
      maxAnisotropy: maxAnisotropy,
      disjointTimerQuery: disjointTimerQuery,
      floatRenderTarget: floatRenderTarget,
      halfFloatRenderTarget: halfFloatRenderTarget,
      contextLossExtension: contextLossExtension,
    );
    _cachedCapabilities = caps;
    return caps;
  }

  /// Updates the default backbuffer viewport and invokes `glViewport`.
  void setViewport(int x, int y, int width, int height) {
    _requireReady();
    RangeError.checkNotNegative(width, 'width');
    RangeError.checkNotNegative(height, 'height');
    _viewportX = x;
    _viewportY = y;
    _viewportWidth = width;
    _viewportHeight = height;
    _gl.glViewport(x, y, width, height);
  }

  /// Reads RGBA8 pixels from the currently bound framebuffer via
  /// `glReadPixels`.
  Uint8List readPixels(int x, int y, int width, int height) {
    _requireReady();
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Gles3FfiDevice.readPixels requires positive dimensions, '
        'got ${width}x$height',
      );
    }
    return _gl.glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE);
  }

  /// Returns the resolved [AnisotropyDecision] for [texture].
  AnisotropyDecision anisotropyDecisionOf(GpuObject texture) =>
      _requireTexture(texture).anisotropy;

  // --- GPU Timer Queries ---

  @override
  GpuObject? beginGpuTimer() {
    _requireReady();
    if (!queryCapabilities().disjointTimerQuery) {
      return null;
    }
    final id = _genOne(_gl.glGenQueries, 'glGenQueries');
    _gl.glBeginQuery(GL_TIME_ELAPSED_EXT, id);
    _timers[id] = _GlTimerQuery(id);
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.timer);
  }

  @override
  void endGpuTimer(GpuObject query) {
    _requireReady();
    final timer = _requireTimer(query);
    if (timer.ended) {
      throw StateError('Gles3FfiDevice: timer ${timer.id} already ended');
    }
    _gl.glEndQuery(GL_TIME_ELAPSED_EXT);
    timer.ended = true;
  }

  @override
  GpuTimerPoll pollGpuTimer(GpuObject query) {
    _requireReady();
    if (!queryCapabilities().disjointTimerQuery) {
      return const GpuTimerPoll(GpuTimerStatus.unsupported);
    }
    final timer = _requireTimer(query);
    final disjoint = _gl.glGetIntegerv(GL_GPU_DISJOINT_EXT);
    if (disjoint != 0) {
      return const GpuTimerPoll(GpuTimerStatus.disjoint);
    }
    if (!timer.ended) {
      return const GpuTimerPoll(GpuTimerStatus.pending);
    }
    final available = _gl.glGetQueryObjectuiv(
      timer.id,
      GL_QUERY_RESULT_AVAILABLE,
    );
    if (available == GL_FALSE) {
      return const GpuTimerPoll(GpuTimerStatus.pending);
    }
    final elapsedNs = _gl.glGetQueryObjectui64v(timer.id, GL_QUERY_RESULT);
    return GpuTimerPoll(GpuTimerStatus.ready, elapsedNs);
  }

  @override
  void deleteGpuTimer(GpuObject query) {
    if (_isStaleOrInvalid(query, _GlesObjectKind.timer)) return;
    final timer = _requireTimer(query);
    _timers.remove(timer.id);
    _gl.glDeleteQueries(<int>[timer.id]);
  }

  // --- Buffers ---

  static int _glUsage(GpuBufferUsage usage) => switch (usage) {
    GpuBufferUsage.staticDraw => GL_STATIC_DRAW,
    GpuBufferUsage.dynamicDraw => GL_DYNAMIC_DRAW,
    GpuBufferUsage.streamDraw => GL_STREAM_DRAW,
  };

  @override
  GpuObject createBuffer(GpuBufferDescriptor descriptor) {
    _requireReady();
    RangeError.checkNotNegative(descriptor.byteLength, 'descriptor.byteLength');
    final id = _genOne(_gl.glGenBuffers, 'glGenBuffers');
    final target = descriptor.kind == GpuBufferKind.indices
        ? GL_ELEMENT_ARRAY_BUFFER
        : GL_ARRAY_BUFFER;
    _gl.glBindBuffer(target, id);
    _gl.glBufferData(
      target,
      descriptor.byteLength,
      null,
      _glUsage(descriptor.usage),
    );
    _buffers.add(id);
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.buffer);
  }

  @override
  void uploadBuffer(
    GpuObject buffer,
    Float32List data, {
    int dstByteOffset = 0,
  }) {
    _requireReady();
    RangeError.checkNotNegative(dstByteOffset, 'dstByteOffset');
    final id = _requireBuffer(buffer);
    _gl.glBindBuffer(GL_ARRAY_BUFFER, id);
    if (data.isEmpty) return;
    _gl.glBufferSubData(
      GL_ARRAY_BUFFER,
      dstByteOffset,
      data.lengthInBytes,
      data,
    );
  }

  @override
  void deleteBuffer(GpuObject buffer) {
    if (_isStaleOrInvalid(buffer, _GlesObjectKind.buffer)) return;
    final id = _requireBuffer(buffer);
    _buffers.remove(id);
    if (_boundElementBuffer == buffer) {
      _boundElementBuffer = null;
    }
    _gl.glDeleteBuffers(<int>[id]);
  }

  // --- Textures ---

  static int _glFilter(GpuTextureFilter filter) => switch (filter) {
    GpuTextureFilter.nearest => GL_NEAREST,
    GpuTextureFilter.linear => GL_LINEAR,
    GpuTextureFilter.linearMipmapLinear => GL_LINEAR_MIPMAP_LINEAR,
  };

  static int _glWrap(GpuTextureWrap wrap) => switch (wrap) {
    GpuTextureWrap.clampToEdge => GL_CLAMP_TO_EDGE,
    GpuTextureWrap.repeat => GL_REPEAT,
  };

  @override
  GpuObject createTexture(GpuTextureDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    final caps = queryCapabilities();
    final id = _genOne(_gl.glGenTextures, 'glGenTextures');
    final target = descriptor.layers > 1 ? GL_TEXTURE_2D_ARRAY : GL_TEXTURE_2D;
    _gl.glBindTexture(target, id);

    if (descriptor.layers > 1) {
      _gl.glTexImage3D(
        target,
        0,
        GL_RGBA8,
        descriptor.width,
        descriptor.height,
        descriptor.layers,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        null,
      );
    } else {
      _gl.glTexImage2D(
        target,
        0,
        GL_RGBA8,
        descriptor.width,
        descriptor.height,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        null,
      );
    }

    _gl.glTexParameteri(
      target,
      GL_TEXTURE_MIN_FILTER,
      _glFilter(descriptor.minFilter),
    );
    _gl.glTexParameteri(
      target,
      GL_TEXTURE_MAG_FILTER,
      _glFilter(descriptor.magFilter),
    );
    _gl.glTexParameteri(target, GL_TEXTURE_WRAP_S, _glWrap(descriptor.wrap));
    _gl.glTexParameteri(target, GL_TEXTURE_WRAP_T, _glWrap(descriptor.wrap));

    final anisotropy = AnisotropyDecision.resolve(
      requested: descriptor.anisotropy,
      extensionAvailable: caps.anisotropicFiltering,
      maxSupported: caps.maxAnisotropy,
    );
    if (anisotropy.effective > 1.0) {
      _gl.glTexParameterf(
        target,
        GL_TEXTURE_MAX_ANISOTROPY_EXT,
        anisotropy.effective,
      );
    }

    _textures[id] = _GlTexture(
      id: id,
      width: descriptor.width,
      height: descriptor.height,
      layers: descriptor.layers,
      hasMips: descriptor.hasMips,
      anisotropy: anisotropy,
    );
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.texture);
  }

  @override
  void uploadTextureLayer(GpuObject texture, int layer, Uint8List pixels) {
    _requireReady();
    final tex = _requireTexture(texture);
    if (layer < 0 || layer >= tex.layers) {
      throw ArgumentError(
        'Gles3FfiDevice.uploadTextureLayer: layer $layer out of range for '
        '${tex.layers}-layer texture',
      );
    }
    final expectedBytes = tex.width * tex.height * 4;
    if (pixels.length != expectedBytes) {
      throw ArgumentError(
        'Gles3FfiDevice.uploadTextureLayer: expected $expectedBytes RGBA8 '
        'bytes for ${tex.width}x${tex.height}, got ${pixels.length}',
      );
    }
    final target = tex.layers > 1 ? GL_TEXTURE_2D_ARRAY : GL_TEXTURE_2D;
    _gl.glBindTexture(target, tex.id);
    if (tex.layers > 1) {
      _gl.glTexSubImage3D(
        target,
        0,
        0,
        0,
        layer,
        tex.width,
        tex.height,
        1,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        pixels,
      );
    } else {
      _gl.glTexSubImage2D(
        target,
        0,
        0,
        0,
        tex.width,
        tex.height,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        pixels,
      );
    }
  }

  @override
  void finalizeMips(GpuObject texture) {
    _requireReady();
    final tex = _requireTexture(texture);
    if (!tex.hasMips) return;
    final target = tex.layers > 1 ? GL_TEXTURE_2D_ARRAY : GL_TEXTURE_2D;
    _gl.glBindTexture(target, tex.id);
    _gl.glGenerateMipmap(target);
  }

  @override
  void deleteTexture(GpuObject texture) {
    if (_isStaleOrInvalid(texture, _GlesObjectKind.texture)) return;
    final tex = _requireTexture(texture);
    _textures.remove(tex.id);
    _gl.glDeleteTextures(<int>[tex.id]);
  }

  // --- Framebuffers / Render Targets ---

  int _createColorTexture(int width, int height) {
    final tex = _genOne(_gl.glGenTextures, 'glGenTextures');
    _gl.glBindTexture(GL_TEXTURE_2D, tex);
    _gl.glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_RGBA8,
      width,
      height,
      0,
      GL_RGBA,
      GL_UNSIGNED_BYTE,
      null,
    );
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return tex;
  }

  int _createDepthTexture(int width, int height) {
    final tex = _genOne(_gl.glGenTextures, 'glGenTextures');
    _gl.glBindTexture(GL_TEXTURE_2D, tex);
    _gl.glTexImage2D(
      GL_TEXTURE_2D,
      0,
      GL_DEPTH_COMPONENT24,
      width,
      height,
      0,
      GL_DEPTH_COMPONENT,
      GL_UNSIGNED_INT,
      null,
    );
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return tex;
  }

  int _createMultisampleRenderbuffer(
    int samples,
    int internalFormat,
    int width,
    int height,
  ) {
    final rb = _genOne(_gl.glGenRenderbuffers, 'glGenRenderbuffers');
    _gl.glBindRenderbuffer(GL_RENDERBUFFER, rb);
    _gl.glRenderbufferStorageMultisample(
      GL_RENDERBUFFER,
      samples,
      internalFormat,
      width,
      height,
    );
    return rb;
  }

  void _deleteFramebufferParts(
    int fbo,
    int? colorTex,
    int? colorRb,
    int? depthRb,
    int? depthTex,
    int? glowTex,
    int? glowRb,
  ) {
    _gl.glDeleteFramebuffers(<int>[fbo]);
    final textures = <int>[
      if (colorTex != null) colorTex,
      if (depthTex != null) depthTex,
      if (glowTex != null) glowTex,
    ];
    if (textures.isNotEmpty) {
      _gl.glDeleteTextures(textures);
    }
    final renderbuffers = <int>[
      if (colorRb != null) colorRb,
      if (depthRb != null) depthRb,
      if (glowRb != null) glowRb,
    ];
    if (renderbuffers.isNotEmpty) {
      _gl.glDeleteRenderbuffers(renderbuffers);
    }
  }

  @override
  GpuObject createTarget(GpuTargetDescriptor descriptor) {
    _requireReady();
    if (descriptor.width <= 0 || descriptor.height <= 0) {
      throw ArgumentError(
        'Gles3FfiDevice.createTarget requires positive dimensions, '
        'got ${descriptor.width}x${descriptor.height}',
      );
    }
    final depthOnly = descriptor.attachments == GpuTargetAttachment.depthOnly;
    if (depthOnly && !descriptor.hasDepth) {
      throw ArgumentError(
        'Gles3FfiDevice.createTarget: GpuTargetAttachment.depthOnly requires '
        'hasDepth: true',
      );
    }
    final hasGlow =
        descriptor.attachments == GpuTargetAttachment.colorAndGlow ||
        descriptor.attachments == GpuTargetAttachment.colorDepthGlow;

    final fbo = _genOne(_gl.glGenFramebuffers, 'glGenFramebuffers');
    _gl.glBindFramebuffer(GL_FRAMEBUFFER, fbo);

    int? colorTex;
    int? colorRb;
    int? glowTex;
    int? glowRb;
    int? depthRb;
    int? depthTex;

    try {
      if (depthOnly) {
        _gl.glDrawBuffers(const <int>[GL_NONE]);
        if (_gl case final Gles3ExtensionsApi ext) {
          ext.glReadBuffer(GL_NONE);
        }
      } else if (descriptor.samples > 1) {
        colorRb = _createMultisampleRenderbuffer(
          descriptor.samples,
          GL_RGBA8,
          descriptor.width,
          descriptor.height,
        );
        _gl.glFramebufferRenderbuffer(
          GL_FRAMEBUFFER,
          GL_COLOR_ATTACHMENT0,
          GL_RENDERBUFFER,
          colorRb,
        );
        if (hasGlow) {
          glowRb = _createMultisampleRenderbuffer(
            descriptor.samples,
            GL_RGBA8,
            descriptor.width,
            descriptor.height,
          );
          _gl.glFramebufferRenderbuffer(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT1,
            GL_RENDERBUFFER,
            glowRb,
          );
          _gl.glDrawBuffers(const <int>[
            GL_COLOR_ATTACHMENT0,
            GL_COLOR_ATTACHMENT1,
          ]);
        }
      } else {
        colorTex = _createColorTexture(descriptor.width, descriptor.height);
        _gl.glFramebufferTexture2D(
          GL_FRAMEBUFFER,
          GL_COLOR_ATTACHMENT0,
          GL_TEXTURE_2D,
          colorTex,
          0,
        );
        if (hasGlow) {
          glowTex = _createColorTexture(descriptor.width, descriptor.height);
          _gl.glFramebufferTexture2D(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT1,
            GL_TEXTURE_2D,
            glowTex,
            0,
          );
          _gl.glDrawBuffers(const <int>[
            GL_COLOR_ATTACHMENT0,
            GL_COLOR_ATTACHMENT1,
          ]);
        }
      }

      if (descriptor.hasDepth) {
        if (descriptor.samples > 1) {
          depthRb = _createMultisampleRenderbuffer(
            descriptor.samples,
            GL_DEPTH_COMPONENT24,
            descriptor.width,
            descriptor.height,
          );
          _gl.glFramebufferRenderbuffer(
            GL_FRAMEBUFFER,
            GL_DEPTH_ATTACHMENT,
            GL_RENDERBUFFER,
            depthRb,
          );
        } else {
          depthTex = _createDepthTexture(descriptor.width, descriptor.height);
          _gl.glFramebufferTexture2D(
            GL_FRAMEBUFFER,
            GL_DEPTH_ATTACHMENT,
            GL_TEXTURE_2D,
            depthTex,
            0,
          );
        }
      }

      final fbStatus = _gl.glCheckFramebufferStatus(GL_FRAMEBUFFER);
      _gl.glBindFramebuffer(GL_FRAMEBUFFER, 0);
      if (fbStatus != GL_FRAMEBUFFER_COMPLETE) {
        _deleteFramebufferParts(
          fbo,
          colorTex,
          colorRb,
          depthRb,
          depthTex,
          glowTex,
          glowRb,
        );
        throw StateError(
          'Gles3FfiDevice.createTarget: framebuffer incomplete '
          '(status=0x${fbStatus.toRadixString(16)})',
        );
      }
    } catch (_) {
      // Ensure partial attachments are not leaked if an inner GL call fails.
      if (!_targets.containsKey(fbo)) {
        try {
          _gl.glBindFramebuffer(GL_FRAMEBUFFER, 0);
          _deleteFramebufferParts(
            fbo,
            colorTex,
            colorRb,
            depthRb,
            depthTex,
            glowTex,
            glowRb,
          );
        } catch (_) {}
      }
      rethrow;
    }

    _targets[fbo] = _GlFramebuffer(
      fbo: fbo,
      colorTex: colorTex,
      colorRb: colorRb,
      depthRb: depthRb,
      depthTex: depthTex,
      glowTex: glowTex,
      glowRb: glowRb,
      width: descriptor.width,
      height: descriptor.height,
      samples: descriptor.samples,
    );
    return _GlesGpuObject(fbo, _contextGeneration, _GlesObjectKind.target);
  }

  @override
  void deleteTarget(GpuObject target) {
    if (_isStaleOrInvalid(target, _GlesObjectKind.target)) return;
    final fb = _requireTarget(target);
    _targets.remove(fb.fbo);
    if (_boundTarget == target) {
      _boundTarget = null;
    }
    _deleteFramebufferParts(
      fb.fbo,
      fb.colorTex,
      fb.colorRb,
      fb.depthRb,
      fb.depthTex,
      fb.glowTex,
      fb.glowRb,
    );
  }

  @override
  void resolveTarget(GpuObject source, GpuObject destination) {
    _requireReady();
    final src = _requireTarget(source);
    final dst = _requireTarget(destination);
    if (src.samples <= 1) {
      throw ArgumentError(
        'Gles3FfiDevice.resolveTarget: source must be multisampled '
        '(samples > 1), got ${src.samples}',
      );
    }
    if (dst.samples > 1) {
      throw ArgumentError(
        'Gles3FfiDevice.resolveTarget: destination must be single-sample, '
        'got samples=${dst.samples}',
      );
    }
    if (src.width != dst.width || src.height != dst.height) {
      throw ArgumentError(
        'Gles3FfiDevice.resolveTarget: source (${src.width}x${src.height}) '
        'and destination (${dst.width}x${dst.height}) must match',
      );
    }

    final resolveColor =
        (src.colorRb != null || src.colorTex != null) &&
        (dst.colorRb != null || dst.colorTex != null);
    final resolveGlow =
        (src.glowRb != null || src.glowTex != null) &&
        (dst.glowRb != null || dst.glowTex != null);
    final resolveDepth =
        (src.depthRb != null || src.depthTex != null) &&
        (dst.depthRb != null || dst.depthTex != null);

    final Gles3ExtensionsApi? ext = _gl is Gles3ExtensionsApi
        ? _gl as Gles3ExtensionsApi
        : null;

    _gl.glBindFramebuffer(GL_READ_FRAMEBUFFER, src.fbo);
    _gl.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, dst.fbo);

    if (resolveColor) {
      if (resolveGlow) {
        ext?.glReadBuffer(GL_COLOR_ATTACHMENT0);
        _gl.glDrawBuffers(const <int>[GL_COLOR_ATTACHMENT0, GL_NONE]);
      }
      _gl.glBlitFramebuffer(
        0,
        0,
        src.width,
        src.height,
        0,
        0,
        dst.width,
        dst.height,
        GL_COLOR_BUFFER_BIT,
        GL_LINEAR,
      );
    }
    if (resolveGlow) {
      ext?.glReadBuffer(GL_COLOR_ATTACHMENT1);
      _gl.glDrawBuffers(const <int>[GL_NONE, GL_COLOR_ATTACHMENT1]);
      _gl.glBlitFramebuffer(
        0,
        0,
        src.width,
        src.height,
        0,
        0,
        dst.width,
        dst.height,
        GL_COLOR_BUFFER_BIT,
        GL_LINEAR,
      );
    }
    if (resolveDepth) {
      _gl.glBlitFramebuffer(
        0,
        0,
        src.width,
        src.height,
        0,
        0,
        dst.width,
        dst.height,
        GL_DEPTH_BUFFER_BIT,
        GL_NEAREST,
      );
    }

    if (resolveGlow) {
      ext?.glReadBuffer(GL_COLOR_ATTACHMENT0);
      _gl.glDrawBuffers(const <int>[
        GL_COLOR_ATTACHMENT0,
        GL_COLOR_ATTACHMENT1,
      ]);
    }

    _gl.glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    _gl.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  }

  // --- Vertex Arrays ---

  @override
  GpuObject createVertexArray() {
    _requireReady();
    final id = _genOne(_gl.glGenVertexArrays, 'glGenVertexArrays');
    _vaos.add(id);
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.vao);
  }

  @override
  void deleteVertexArray(GpuObject vao) {
    if (_isStaleOrInvalid(vao, _GlesObjectKind.vao)) return;
    final id = _requireVao(vao);
    _vaos.remove(id);
    if (_boundVao == vao) {
      _boundVao = null;
    }
    _gl.glDeleteVertexArrays(<int>[id]);
  }

  // --- Shaders & Programs ---

  int _compileShaderStage(int type, String source) {
    final stage = type == GL_VERTEX_SHADER
        ? ShaderCompileStage.vertex
        : ShaderCompileStage.fragment;
    final shader = _gl.glCreateShader(type);
    if (shader == 0) {
      throw ShaderCompileException(stage, 'glCreateShader() returned 0');
    }
    _gl.glShaderSource(shader, source);
    _gl.glCompileShader(shader);
    if (_gl.glGetShaderiv(shader, GL_COMPILE_STATUS) == GL_FALSE) {
      final log = _gl.glGetShaderInfoLog(shader);
      _gl.glDeleteShader(shader);
      throw ShaderCompileException(
        stage,
        log.isEmpty ? '(no shader info log)' : log,
      );
    }
    return shader;
  }

  @override
  GpuObject compileProgram({
    required String vertexSource,
    required String fragmentSource,
    required List<String> requiredAttributes,
    required List<String> requiredUniforms,
  }) {
    _requireReady();
    final vertexShader = _compileShaderStage(GL_VERTEX_SHADER, vertexSource);
    final int fragmentShader;
    try {
      fragmentShader = _compileShaderStage(GL_FRAGMENT_SHADER, fragmentSource);
    } catch (_) {
      _gl.glDeleteShader(vertexShader);
      rethrow;
    }

    final program = _gl.glCreateProgram();
    if (program == 0) {
      _gl.glDeleteShader(vertexShader);
      _gl.glDeleteShader(fragmentShader);
      throw const ShaderCompileException(
        ShaderCompileStage.link,
        'glCreateProgram() returned 0',
      );
    }

    void cleanupFailedProgram() {
      _gl.glDeleteProgram(program);
      _gl.glDeleteShader(vertexShader);
      _gl.glDeleteShader(fragmentShader);
    }

    _gl.glAttachShader(program, vertexShader);
    _gl.glAttachShader(program, fragmentShader);
    _gl.glLinkProgram(program);

    if (_gl.glGetProgramiv(program, GL_LINK_STATUS) == GL_FALSE) {
      final log = _gl.glGetProgramInfoLog(program);
      cleanupFailedProgram();
      throw ShaderCompileException(
        ShaderCompileStage.link,
        log.isEmpty ? '(no program info log)' : log,
      );
    }

    final useAttribQuery =
        _gl is Gles3ExtensionsApi &&
        (_gl is! FfiGles3Api || _gl.hasSymbol('glGetAttribLocation'));
    for (final attr in requiredAttributes) {
      final valid = useAttribQuery
          ? (_gl as Gles3ExtensionsApi).glGetAttribLocation(program, attr) >= 0
          : vertexSource.contains(attr);
      if (!valid) {
        cleanupFailedProgram();
        throw ShaderCompileException(
          ShaderCompileStage.validation,
          'missing required attribute: $attr',
        );
      }
    }

    final cache = _UniformLocations();
    for (final uniform in requiredUniforms) {
      final loc = _gl.glGetUniformLocation(program, uniform);
      if (loc < 0) {
        cleanupFailedProgram();
        throw ShaderCompileException(
          ShaderCompileStage.validation,
          'missing required uniform: $uniform',
        );
      }
      cache.found[uniform] = loc;
    }

    _gl.glDeleteShader(vertexShader);
    _gl.glDeleteShader(fragmentShader);

    _programs.add(program);
    _uniformLocations[program] = cache;
    return _GlesGpuObject(program, _contextGeneration, _GlesObjectKind.program);
  }

  @override
  void deleteProgram(GpuObject program) {
    if (_isStaleOrInvalid(program, _GlesObjectKind.program)) return;
    final id = _requireProgram(program);
    _programs.remove(id);
    _uniformLocations.remove(id);
    if (_boundProgramId == id) {
      _boundProgramId = null;
      _boundUniforms = null;
    }
    _gl.glDeleteProgram(id);
  }

  // --- Context Lifecycle ---

  @override
  void simulateContextLoss() {
    _status = GpuDeviceStatus.lost;
    _buffers.clear();
    _textures.clear();
    _targets.clear();
    _vaos.clear();
    _programs.clear();
    _timers.clear();
    _uniformLocations.clear();
    _boundProgramId = null;
    _boundUniforms = null;
    _boundTarget = null;
    _boundVao = null;
    _boundElementBuffer = null;
    _cachedCapabilities = null;
    _stateCache.invalidate();
  }

  @override
  void simulateContextRestore() {
    _status = GpuDeviceStatus.ready;
    _contextGeneration++;
    _cachedCapabilities = null;
    _stateCache.invalidate();
  }

  // --- Draw & State Commands ---

  @override
  void bindTarget(GpuObject? target) {
    _requireReady();
    if (target == null) {
      _boundTarget = null;
      _gl.glBindFramebuffer(GL_FRAMEBUFFER, 0);
      _gl.glViewport(_viewportX, _viewportY, _viewportWidth, _viewportHeight);
      return;
    }
    final fb = _requireTarget(target);
    _boundTarget = target;
    _gl.glBindFramebuffer(GL_FRAMEBUFFER, fb.fbo);
    _gl.glViewport(0, 0, fb.width, fb.height);
  }

  @override
  void setColorAttachmentCount(int count) {
    _requireReady();
    switch (count) {
      case 1:
        _gl.glDrawBuffers(const <int>[GL_COLOR_ATTACHMENT0]);
      case 2:
        _gl.glDrawBuffers(const <int>[
          GL_COLOR_ATTACHMENT0,
          GL_COLOR_ATTACHMENT1,
        ]);
      default:
        throw ArgumentError(
          'Gles3FfiDevice.setColorAttachmentCount: count must be 1 or 2, '
          'got $count',
        );
    }
  }

  static int _glDepthFunc(DepthFunc fn) => switch (fn) {
    DepthFunc.less => GL_LESS,
    DepthFunc.lessEqual => GL_LEQUAL,
    DepthFunc.always => GL_ALWAYS,
    DepthFunc.never => GL_NEVER,
  };

  static int _glCullFace(CullFace face) => switch (face) {
    CullFace.front => GL_FRONT,
    CullFace.back => GL_BACK,
  };

  static int _glBlendFactor(BlendFactor factor) => switch (factor) {
    BlendFactor.zero => GL_ZERO,
    BlendFactor.one => GL_ONE,
    BlendFactor.srcAlpha => GL_SRC_ALPHA,
    BlendFactor.oneMinusSrcAlpha => GL_ONE_MINUS_SRC_ALPHA,
    BlendFactor.dstAlpha => GL_DST_ALPHA,
    BlendFactor.oneMinusDstAlpha => GL_ONE_MINUS_DST_ALPHA,
    BlendFactor.srcColor => GL_SRC_COLOR,
  };

  static int _glBlendEquation(BlendEquation eq) => switch (eq) {
    BlendEquation.add => GL_FUNC_ADD,
    BlendEquation.subtract => GL_FUNC_SUBTRACT,
    BlendEquation.reverseSubtract => GL_FUNC_REVERSE_SUBTRACT,
  };

  void _setGlCap(int cap, bool enabled) {
    if (enabled) {
      _gl.glEnable(cap);
    } else {
      _gl.glDisable(cap);
    }
  }

  @override
  void applyDrawState(DrawStateDescriptor state) {
    _requireReady();
    final changed = _stateCache.diff(state);
    if (changed.isEmpty) return;

    if (changed.contains(StateField.depthTest)) {
      _setGlCap(GL_DEPTH_TEST, state.depthTest);
    }
    if (changed.contains(StateField.depthFunc)) {
      _gl.glDepthFunc(_glDepthFunc(state.depthFunc));
    }
    if (changed.contains(StateField.depthWrite)) {
      _gl.glDepthMask(state.depthWrite);
    }
    if (changed.contains(StateField.cullEnable)) {
      _setGlCap(GL_CULL_FACE, state.cullEnable);
    }
    if (changed.contains(StateField.cullFace)) {
      _gl.glCullFace(_glCullFace(state.cullFace));
    }
    if (changed.contains(StateField.frontFace)) {
      _gl.glFrontFace(state.frontFaceCcw ? GL_CCW : GL_CW);
    }
    if (changed.contains(StateField.blendEnable)) {
      _setGlCap(GL_BLEND, state.blendEnable);
    }
    if (changed.contains(StateField.blendFunc)) {
      _gl.glBlendFunc(
        _glBlendFactor(state.blendSrc),
        _glBlendFactor(state.blendDst),
      );
    }
    if (changed.contains(StateField.blendEquation)) {
      _gl.glBlendEquation(_glBlendEquation(state.blendEquation));
    }
    if (changed.contains(StateField.stencilEnable)) {
      _setGlCap(GL_STENCIL_TEST, state.stencilEnable);
    }
    if (changed.contains(StateField.colorMask)) {
      _gl.glColorMask(
        state.colorMaskR,
        state.colorMaskG,
        state.colorMaskB,
        state.colorMaskA,
      );
    }
    if (changed.contains(StateField.scissorEnable)) {
      _setGlCap(GL_SCISSOR_TEST, state.scissorEnable);
    }
    _stateCache.markApplied(state);
  }

  static int _glClearBits(ClearMask mask) => switch (mask) {
    ClearMask.colorOnly => GL_COLOR_BUFFER_BIT,
    ClearMask.colorAndDepth => GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT,
    ClearMask.depthOnly => GL_DEPTH_BUFFER_BIT,
    ClearMask.colorDepthStencil =>
      GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT,
    ClearMask.stencilOnly => GL_STENCIL_BUFFER_BIT,
  };

  @override
  void clear(
    ClearMask mask, {
    double r = 0,
    double g = 0,
    double b = 0,
    double a = 1,
  }) {
    _requireReady();
    _gl.glClearColor(r, g, b, a);
    _gl.glClear(_glClearBits(mask));
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
    _clearColorScratch[0] = r;
    _clearColorScratch[1] = g;
    _clearColorScratch[2] = b;
    _clearColorScratch[3] = a;
    _gl.glClearBufferfv(GL_COLOR, index, _clearColorScratch);
  }

  @override
  void useProgram(GpuObject program) {
    _requireReady();
    final id = _requireProgram(program);
    _gl.glUseProgram(id);
    _boundProgramId = id;
    _boundUniforms = _uniformLocations.putIfAbsent(id, _UniformLocations.new);
  }

  @override
  void setUniform(String name, UniformValue value) {
    _requireReady();
    final programId = _boundProgramId;
    if (programId == null) {
      throw StateError(
        'Gles3FfiDevice.setUniform called with no bound program',
      );
    }
    final locations = _boundUniforms!;
    var location = locations.found[name];
    if (location == null) {
      if (locations.missing.contains(name)) return;
      location = _gl.glGetUniformLocation(programId, name);
      if (location < 0) {
        locations.missing.add(name);
        return;
      }
      locations.found[name] = location;
    }

    switch (value.type) {
      case UniformType.float1:
        _gl.glUniform1f(location, value.value as double);
      case UniformType.float2:
        _gl.glUniform2fv(location, 1, value.value as Float32List);
      case UniformType.float3:
        _gl.glUniform3fv(location, 1, value.value as Float32List);
      case UniformType.float4:
        _gl.glUniform4fv(location, 1, value.value as Float32List);
      case UniformType.int1:
        _gl.glUniform1i(location, value.value as int);
      case UniformType.sampler:
        _gl.glUniform1i(location, value.value as int);
      case UniformType.mat4:
        _gl.glUniformMatrix4fv(location, 1, false, value.value as Float32List);
      case UniformType.mat4Array:
        final matrices = value.value as Float32List;
        final matrixCount = matrices.length ~/ 16;
        if (matrixCount > 0) {
          _gl.glUniformMatrix4fv(location, matrixCount, false, matrices);
        }
    }
  }

  @override
  void bindVertexArray(GpuObject vao) {
    _requireReady();
    final id = _requireVao(vao);
    _boundVao = vao;
    _gl.glBindVertexArray(id);
  }

  @override
  void bindTexture(int unit, GpuObject texture) {
    _requireReady();
    if (texture is! _GlesGpuObject) {
      throw ArgumentError.value(
        texture,
        'texture',
        'is not a Gles3FfiDevice object',
      );
    }
    final obj = texture;
    _gl.glActiveTexture(GL_TEXTURE0 + unit);
    if (obj.kind == _GlesObjectKind.texture) {
      final tex = _requireTexture(texture);
      final target = tex.layers > 1 ? GL_TEXTURE_2D_ARRAY : GL_TEXTURE_2D;
      _gl.glBindTexture(target, tex.id);
      return;
    }
    if (obj.kind == _GlesObjectKind.target) {
      final fb = _requireTarget(texture);
      final colorTex = fb.colorTex;
      if (colorTex != null) {
        _gl.glBindTexture(GL_TEXTURE_2D, colorTex);
        return;
      }
      final depthTex = fb.depthTex;
      if (depthTex != null) {
        _gl.glBindTexture(GL_TEXTURE_2D, depthTex);
        return;
      }
      throw StateError(
        'Gles3FfiDevice.bindTexture: target ${fb.fbo} has no sampleable color '
        'or depth texture (multisampled targets must be resolved first)',
      );
    }
    throw StateError(
      'Gles3FfiDevice.bindTexture: object ${obj.id} (${obj.kind.name}) is not '
      'a texture or render target',
    );
  }

  @override
  void bindGlowTexture(int unit, GpuObject target) {
    _requireReady();
    final fb = _requireTarget(target);
    _gl.glActiveTexture(GL_TEXTURE0 + unit);
    final glowTex = fb.glowTex;
    if (glowTex == null) {
      throw StateError(
        'Gles3FfiDevice.bindGlowTexture: target ${fb.fbo} has no glow '
        'attachment (use colorAndGlow/colorDepthGlow and resolve multisampled '
        'targets before sampling)',
      );
    }
    _gl.glBindTexture(GL_TEXTURE_2D, glowTex);
  }

  @override
  void bindArrayBuffer(GpuObject buffer) {
    _requireReady();
    final id = _requireBuffer(buffer);
    _gl.glBindBuffer(GL_ARRAY_BUFFER, id);
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
    final glType = switch (format) {
      GpuAttribFormat.float => GL_FLOAT,
      GpuAttribFormat.unorm16 => GL_UNSIGNED_SHORT,
      GpuAttribFormat.unorm8 => GL_UNSIGNED_BYTE,
    };
    _gl.glVertexAttribPointer(
      location,
      componentCount,
      glType,
      format != GpuAttribFormat.float,
      strideBytes,
      offsetBytes,
    );
  }

  @override
  void enableVertexAttribArray(int location) {
    _requireReady();
    _gl.glEnableVertexAttribArray(location);
  }

  @override
  void vertexAttribDivisor(int location, int divisor) {
    _requireReady();
    _gl.glVertexAttribDivisor(location, divisor);
  }

  @override
  void bindElementArrayBuffer(GpuObject buffer) {
    _requireReady();
    final id = _requireBuffer(buffer);
    _boundElementBuffer = buffer;
    _gl.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, id);
  }

  @override
  void uploadIndices(GpuObject buffer, List<int> data) {
    _requireReady();
    final id = _requireBuffer(buffer);
    _gl.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, id);
    if (data.isEmpty) {
      _gl.glBufferData(GL_ELEMENT_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
      return;
    }
    final TypedData payload = switch (data) {
      Uint16List values => values,
      Uint32List values => values,
      _ => Uint32List.fromList(data),
    };
    _gl.glBufferData(
      GL_ELEMENT_ARRAY_BUFFER,
      payload.lengthInBytes,
      payload,
      GL_STATIC_DRAW,
    );
  }

  @override
  void drawArrays({required int first, required int count}) {
    _requireReady();
    _gl.glDrawArrays(GL_TRIANGLES, first, count);
  }

  @override
  void drawArraysInstanced({
    required int first,
    required int count,
    required int instanceCount,
  }) {
    _requireReady();
    _gl.glDrawArraysInstanced(GL_TRIANGLES, first, count, instanceCount);
  }

  @override
  void drawElements({
    required int count,
    required int offsetBytes,
    bool index32 = false,
  }) {
    _requireReady();
    _gl.glDrawElements(
      GL_TRIANGLES,
      count,
      index32 ? GL_UNSIGNED_INT : GL_UNSIGNED_SHORT,
      offsetBytes,
    );
  }

  @override
  void drawElementsInstanced({
    required int count,
    required int offsetBytes,
    required int instanceCount,
    bool index32 = false,
  }) {
    _requireReady();
    _gl.glDrawElementsInstanced(
      GL_TRIANGLES,
      count,
      index32 ? GL_UNSIGNED_INT : GL_UNSIGNED_SHORT,
      offsetBytes,
      instanceCount,
    );
  }

  // --- GpuDeviceV2 (S1-A) ---

  Gles3V2Api _requireV2Api(String op) {
    final gl = _gl;
    if (gl is Gles3V2Api) return gl as Gles3V2Api;
    throw UnsupportedError(
      'Gles3FfiDevice.$op requires a Gles3Api implementing Gles3V2Api',
    );
  }

  int _glInternalFormat(GpuTextureFormat fmt) => switch (fmt) {
    GpuTextureFormat.rgba8 => GL_RGBA8,
    GpuTextureFormat.srgb8Alpha8 => GL_SRGB8_ALPHA8,
    GpuTextureFormat.rgba16f => GL_RGBA16F,
    GpuTextureFormat.rgba32f => GL_RGBA32F,
    GpuTextureFormat.r16f => GL_R16F,
    GpuTextureFormat.r32f => GL_R32F,
    GpuTextureFormat.rg16f => GL_RG16F,
    GpuTextureFormat.depth24 => GL_DEPTH_COMPONENT24,
    GpuTextureFormat.depth32f => GL_DEPTH_COMPONENT32F,
  };

  int _glBaseFormat(GpuTextureFormat fmt) => switch (fmt) {
    GpuTextureFormat.r16f || GpuTextureFormat.r32f => GL_RED,
    GpuTextureFormat.rg16f => GL_RG,
    GpuTextureFormat.depth24 || GpuTextureFormat.depth32f => GL_DEPTH_COMPONENT,
    _ => GL_RGBA,
  };

  int _glColorTargetFormat(GpuColorTargetFormat fmt) => switch (fmt) {
    GpuColorTargetFormat.rgba8 => GL_RGBA8,
    GpuColorTargetFormat.rgba16f => GL_RGBA16F,
    GpuColorTargetFormat.rgba32f => GL_RGBA32F,
  };

  int _glCubeFaceTarget(GpuCubeFace face) => switch (face) {
    GpuCubeFace.positiveX => GL_TEXTURE_CUBE_MAP_POSITIVE_X,
    GpuCubeFace.negativeX => GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
    GpuCubeFace.positiveY => GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
    GpuCubeFace.negativeY => GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
    GpuCubeFace.positiveZ => GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
    GpuCubeFace.negativeZ => GL_TEXTURE_CUBE_MAP_NEGATIVE_Z,
  };

  int _glUsageV2(GpuBufferUsage usage) => switch (usage) {
    GpuBufferUsage.staticDraw => GL_STATIC_DRAW,
    GpuBufferUsage.dynamicDraw => GL_DYNAMIC_DRAW,
    GpuBufferUsage.streamDraw => GL_STREAM_DRAW,
  };

  int _glFilterV2(GpuTextureFilter filter) => switch (filter) {
    GpuTextureFilter.nearest => GL_NEAREST,
    GpuTextureFilter.linear => GL_LINEAR,
    GpuTextureFilter.linearMipmapLinear => GL_LINEAR_MIPMAP_LINEAR,
  };

  int _glWrapV2(GpuTextureWrap wrap) => switch (wrap) {
    GpuTextureWrap.clampToEdge => GL_CLAMP_TO_EDGE,
    GpuTextureWrap.repeat => GL_REPEAT,
  };

  @override
  GpuObject createUniformBuffer(GpuUniformBufferDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    final id = _gl.glGenBuffers(1).single;
    _buffers.add(id);
    _gl.glBindBuffer(GL_UNIFORM_BUFFER, id);
    _gl.glBufferData(
      GL_UNIFORM_BUFFER,
      descriptor.byteLength,
      null,
      _glUsageV2(descriptor.usage),
    );
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.buffer);
  }

  @override
  void updateUniformBuffer(
    GpuObject buffer,
    ByteData data, {
    int dstByteOffset = 0,
  }) {
    _requireReady();
    final id = _requireBuffer(buffer);
    _gl.glBindBuffer(GL_UNIFORM_BUFFER, id);
    _gl.glBufferSubData(
      GL_UNIFORM_BUFFER,
      dstByteOffset,
      data.lengthInBytes,
      data,
    );
  }

  @override
  void bindUniformBufferBase(int bindingPoint, GpuObject buffer) {
    _requireReady();
    final id = _requireBuffer(buffer);
    if (_stateCache.shouldBindUbo(bindingPoint, id)) {
      _requireV2Api(
        'bindUniformBufferBase',
      ).glBindBufferBase(GL_UNIFORM_BUFFER, bindingPoint, id);
      _stateCache.markUboBound(bindingPoint, id);
    }
  }

  @override
  void uniformBlockBinding(
    GpuObject program,
    String blockName,
    int bindingPoint,
  ) {
    _requireReady();
    final progId = _requireProgram(program);
    final v2 = _requireV2Api('uniformBlockBinding');
    final idx = v2.glGetUniformBlockIndex(progId, blockName);
    if (idx != GL_INVALID_INDEX) {
      v2.glUniformBlockBinding(progId, idx, bindingPoint);
    }
  }

  @override
  GpuObject createCubeTexture(GpuCubeTextureDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    final id = _gl.glGenTextures(1).single;
    _gl.glBindTexture(GL_TEXTURE_CUBE_MAP, id);
    final internal = _glInternalFormat(descriptor.format);
    final base = _glBaseFormat(descriptor.format);
    final type =
        (descriptor.format == GpuTextureFormat.rgba8 ||
            descriptor.format == GpuTextureFormat.srgb8Alpha8)
        ? GL_UNSIGNED_BYTE
        : GL_FLOAT;
    for (final face in GpuCubeFace.values) {
      _gl.glTexImage2D(
        _glCubeFaceTarget(face),
        0,
        internal,
        descriptor.size,
        descriptor.size,
        0,
        base,
        type,
        null,
      );
    }
    _gl.glTexParameteri(
      GL_TEXTURE_CUBE_MAP,
      GL_TEXTURE_MIN_FILTER,
      _glFilterV2(descriptor.minFilter),
    );
    _gl.glTexParameteri(
      GL_TEXTURE_CUBE_MAP,
      GL_TEXTURE_MAG_FILTER,
      _glFilterV2(descriptor.magFilter),
    );
    _gl.glTexParameteri(
      GL_TEXTURE_CUBE_MAP,
      GL_TEXTURE_WRAP_S,
      GL_CLAMP_TO_EDGE,
    );
    _gl.glTexParameteri(
      GL_TEXTURE_CUBE_MAP,
      GL_TEXTURE_WRAP_T,
      GL_CLAMP_TO_EDGE,
    );
    _gl.glTexParameteri(
      GL_TEXTURE_CUBE_MAP,
      GL_TEXTURE_WRAP_R,
      GL_CLAMP_TO_EDGE,
    );
    _textures[id] = _GlTexture(
      id: id,
      width: descriptor.size,
      height: descriptor.size,
      layers: 6,
      hasMips: descriptor.hasMips,
      anisotropy: const AnisotropyDecision(
        requested: 1,
        effective: 1,
        maxSupported: 1,
        extensionAvailable: false,
      ),
      target: GpuTextureTarget.cubeMap,
      format: descriptor.format,
    );
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.texture);
  }

  @override
  void uploadCubeFace(
    GpuObject texture,
    GpuCubeFace face,
    Uint8List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    final tex = _requireTexture(texture);
    final dim = (tex.width >> mipLevel).clamp(1, tex.width);
    _gl.glBindTexture(GL_TEXTURE_CUBE_MAP, tex.id);
    _gl.glTexSubImage2D(
      _glCubeFaceTarget(face),
      mipLevel,
      0,
      0,
      dim,
      dim,
      _glBaseFormat(tex.format),
      GL_UNSIGNED_BYTE,
      pixels,
    );
  }

  @override
  void uploadCubeFaceFloat(
    GpuObject texture,
    GpuCubeFace face,
    Float32List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    final tex = _requireTexture(texture);
    final dim = (tex.width >> mipLevel).clamp(1, tex.width);
    _gl.glBindTexture(GL_TEXTURE_CUBE_MAP, tex.id);
    _gl.glTexSubImage2D(
      _glCubeFaceTarget(face),
      mipLevel,
      0,
      0,
      dim,
      dim,
      _glBaseFormat(tex.format),
      GL_FLOAT,
      pixels,
    );
  }

  @override
  void bindCubeTexture(int unit, GpuObject texture) {
    _requireReady();
    final tex = _requireTexture(texture);
    if (_stateCache.shouldBindTexture(unit, GL_TEXTURE_CUBE_MAP, tex.id)) {
      _gl.glActiveTexture(GL_TEXTURE0 + unit);
      _gl.glBindTexture(GL_TEXTURE_CUBE_MAP, tex.id);
      _stateCache.markTextureBound(unit, GL_TEXTURE_CUBE_MAP, tex.id);
    }
  }

  @override
  GpuObject createTextureArray(GpuTextureArrayDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    final id = _gl.glGenTextures(1).single;
    _gl.glBindTexture(GL_TEXTURE_2D_ARRAY, id);
    final type =
        (descriptor.format == GpuTextureFormat.rgba8 ||
            descriptor.format == GpuTextureFormat.srgb8Alpha8)
        ? GL_UNSIGNED_BYTE
        : GL_FLOAT;
    _gl.glTexImage3D(
      GL_TEXTURE_2D_ARRAY,
      0,
      _glInternalFormat(descriptor.format),
      descriptor.width,
      descriptor.height,
      descriptor.layers,
      0,
      _glBaseFormat(descriptor.format),
      type,
      null,
    );
    _gl.glTexParameteri(
      GL_TEXTURE_2D_ARRAY,
      GL_TEXTURE_MIN_FILTER,
      _glFilterV2(descriptor.minFilter),
    );
    _gl.glTexParameteri(
      GL_TEXTURE_2D_ARRAY,
      GL_TEXTURE_MAG_FILTER,
      _glFilterV2(descriptor.magFilter),
    );
    _gl.glTexParameteri(
      GL_TEXTURE_2D_ARRAY,
      GL_TEXTURE_WRAP_S,
      _glWrapV2(descriptor.wrap),
    );
    _gl.glTexParameteri(
      GL_TEXTURE_2D_ARRAY,
      GL_TEXTURE_WRAP_T,
      _glWrapV2(descriptor.wrap),
    );
    _textures[id] = _GlTexture(
      id: id,
      width: descriptor.width,
      height: descriptor.height,
      layers: descriptor.layers,
      hasMips: descriptor.hasMips,
      anisotropy: const AnisotropyDecision(
        requested: 1,
        effective: 1,
        maxSupported: 1,
        extensionAvailable: false,
      ),
      target: GpuTextureTarget.tex2dArray,
      format: descriptor.format,
    );
    return _GlesGpuObject(id, _contextGeneration, _GlesObjectKind.texture);
  }

  @override
  void uploadTextureArrayLayer(
    GpuObject texture,
    int layer,
    Uint8List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    final tex = _requireTexture(texture);
    final w = (tex.width >> mipLevel).clamp(1, tex.width);
    final h = (tex.height >> mipLevel).clamp(1, tex.height);
    _gl.glBindTexture(GL_TEXTURE_2D_ARRAY, tex.id);
    _gl.glTexSubImage3D(
      GL_TEXTURE_2D_ARRAY,
      mipLevel,
      0,
      0,
      layer,
      w,
      h,
      1,
      _glBaseFormat(tex.format),
      GL_UNSIGNED_BYTE,
      pixels,
    );
  }

  @override
  void uploadTextureArrayLayerFloat(
    GpuObject texture,
    int layer,
    Float32List pixels, {
    int mipLevel = 0,
  }) {
    _requireReady();
    final tex = _requireTexture(texture);
    final w = (tex.width >> mipLevel).clamp(1, tex.width);
    final h = (tex.height >> mipLevel).clamp(1, tex.height);
    _gl.glBindTexture(GL_TEXTURE_2D_ARRAY, tex.id);
    _gl.glTexSubImage3D(
      GL_TEXTURE_2D_ARRAY,
      mipLevel,
      0,
      0,
      layer,
      w,
      h,
      1,
      _glBaseFormat(tex.format),
      GL_FLOAT,
      pixels,
    );
  }

  @override
  void bindTextureArray(int unit, GpuObject texture) {
    _requireReady();
    final tex = _requireTexture(texture);
    if (_stateCache.shouldBindTexture(unit, GL_TEXTURE_2D_ARRAY, tex.id)) {
      _gl.glActiveTexture(GL_TEXTURE0 + unit);
      _gl.glBindTexture(GL_TEXTURE_2D_ARRAY, tex.id);
      _stateCache.markTextureBound(unit, GL_TEXTURE_2D_ARRAY, tex.id);
    }
  }

  @override
  GpuObject createMrtTarget(GpuMrtTargetDescriptor descriptor) {
    _requireReady();
    descriptor.validate();
    final fbo = _gl.glGenFramebuffers(1).single;
    _gl.glBindFramebuffer(GL_FRAMEBUFFER, fbo);

    final colorAttachments = <int>[];
    final drawBufs = <int>[];
    for (var i = 0; i < descriptor.colorFormats.length; i++) {
      final fmt = descriptor.colorFormats[i];
      final tex = _gl.glGenTextures(1).single;
      _gl.glBindTexture(GL_TEXTURE_2D, tex);
      _gl.glTexImage2D(
        GL_TEXTURE_2D,
        0,
        _glColorTargetFormat(fmt),
        descriptor.width,
        descriptor.height,
        0,
        GL_RGBA,
        fmt == GpuColorTargetFormat.rgba8 ? GL_UNSIGNED_BYTE : GL_FLOAT,
        null,
      );
      _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      _gl.glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_COLOR_ATTACHMENT0 + i,
        GL_TEXTURE_2D,
        tex,
        0,
      );
      colorAttachments.add(tex);
      drawBufs.add(GL_COLOR_ATTACHMENT0 + i);
    }

    _gl.glDrawBuffers(drawBufs.isEmpty ? const [GL_NONE] : drawBufs);

    int? depthTex;
    if (descriptor.hasDepth) {
      depthTex = _gl.glGenTextures(1).single;
      _gl.glBindTexture(GL_TEXTURE_2D, depthTex);
      _gl.glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_DEPTH_COMPONENT24,
        descriptor.width,
        descriptor.height,
        0,
        GL_DEPTH_COMPONENT,
        GL_UNSIGNED_INT,
        null,
      );
      _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      _gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      _gl.glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_DEPTH_ATTACHMENT,
        GL_TEXTURE_2D,
        depthTex,
        0,
      );
    }

    final status = _gl.glCheckFramebufferStatus(GL_FRAMEBUFFER);
    _gl.glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      _gl.glDeleteFramebuffers([fbo]);
      if (colorAttachments.isNotEmpty) _gl.glDeleteTextures(colorAttachments);
      if (depthTex != null) _gl.glDeleteTextures([depthTex]);
      throw StateError(
        'Gles3FfiDevice.createMrtTarget: framebuffer incomplete (0x${status.toRadixString(16)})',
      );
    }

    _targets[fbo] = _GlFramebuffer(
      fbo: fbo,
      colorTex: colorAttachments.isNotEmpty ? colorAttachments.first : null,
      glowTex: colorAttachments.length > 1 ? colorAttachments[1] : null,
      colorAttachments: colorAttachments,
      depthTex: depthTex,
      width: descriptor.width,
      height: descriptor.height,
      samples: descriptor.samples,
    );
    return _GlesGpuObject(fbo, _contextGeneration, _GlesObjectKind.target);
  }

  @override
  void drawBuffers(List<int> colorAttachmentIndices) {
    _requireReady();
    if (colorAttachmentIndices.isEmpty) {
      _gl.glDrawBuffers(const [GL_NONE]);
      return;
    }
    _gl.glDrawBuffers([
      for (final i in colorAttachmentIndices)
        i < 0 ? GL_NONE : GL_COLOR_ATTACHMENT0 + i,
    ]);
  }

  @override
  void bindTargetColorAttachment(
    int unit,
    GpuObject target,
    int attachmentIndex,
  ) {
    _requireReady();
    final fb = _requireTarget(target);
    final int? tex = attachmentIndex < fb.colorAttachments.length
        ? fb.colorAttachments[attachmentIndex]
        : (attachmentIndex == 0
              ? fb.colorTex
              : attachmentIndex == 1
              ? fb.glowTex
              : null);
    if (tex == null) {
      throw RangeError.index(
        attachmentIndex,
        fb.colorAttachments,
        'attachmentIndex',
        'No color attachment at index $attachmentIndex',
      );
    }
    if (_stateCache.shouldBindTexture(unit, GL_TEXTURE_2D, tex)) {
      _gl.glActiveTexture(GL_TEXTURE0 + unit);
      _gl.glBindTexture(GL_TEXTURE_2D, tex);
      _stateCache.markTextureBound(unit, GL_TEXTURE_2D, tex);
    }
  }

  @override
  GpuObject? beginOcclusionQuery() {
    _requireReady();
    final id = _gl.glGenQueries(1).single;
    _occlusionQueries[id] = _GlOcclusionQuery(id);
    _gl.glBeginQuery(GL_ANY_SAMPLES_PASSED_CONSERVATIVE, id);
    return _GlesGpuObject(
      id,
      _contextGeneration,
      _GlesObjectKind.occlusionQuery,
    );
  }

  @override
  void endOcclusionQuery(GpuObject query) {
    _requireReady();
    final obj = query as _GlesGpuObject;
    final q = _occlusionQueries[obj.id];
    if (q == null) {
      throw StateError('Gles3FfiDevice: unknown occlusion query ${obj.id}');
    }
    if (q.ended) {
      throw StateError('Gles3FfiDevice: occlusion query already ended');
    }
    _gl.glEndQuery(GL_ANY_SAMPLES_PASSED_CONSERVATIVE);
    q.ended = true;
  }

  @override
  GpuOcclusionQueryPoll pollOcclusionQuery(GpuObject query) {
    final obj = query as _GlesGpuObject;
    final q = _occlusionQueries[obj.id];
    if (q == null || !q.ended) {
      return const GpuOcclusionQueryPoll(GpuOcclusionQueryStatus.pending);
    }
    final available = _gl.glGetQueryObjectuiv(q.id, GL_QUERY_RESULT_AVAILABLE);
    if (available == 0) {
      return const GpuOcclusionQueryPoll(GpuOcclusionQueryStatus.pending);
    }
    final passed = _gl.glGetQueryObjectuiv(q.id, GL_QUERY_RESULT);
    return GpuOcclusionQueryPoll(GpuOcclusionQueryStatus.ready, passed != 0);
  }

  @override
  void deleteOcclusionQuery(GpuObject query) {
    final obj = query as _GlesGpuObject;
    if (obj.generation != _contextGeneration) return;
    _occlusionQueries.remove(obj.id);
    _gl.glDeleteQueries([obj.id]);
  }

  @override
  GpuPassTimerScope? beginPassTimer(String passName) {
    final q = beginGpuTimer();
    if (q == null) return null;
    return GpuPassTimerScope(passName: passName, query: q);
  }

  @override
  void endPassTimer(GpuPassTimerScope scope) {
    endGpuTimer(scope.query);
  }
}
