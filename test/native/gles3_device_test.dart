import 'dart:typed_data';

import 'package:gl_volition/gl_volition_native.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';
import 'package:test/test.dart';

import '../../example/dungeon_2d/game.dart';
import '../../example/island_3d/game.dart';

final class _FakeShader {
  final int type;
  String source = '';
  bool compiled = false;
  String infoLog = '';

  _FakeShader(this.type);
}

final class _FakeProgram {
  final List<int> attachedShaders = <int>[];
  bool linked = false;
  String infoLog = '';
  final Map<String, int> uniformLocations = <String, int>{};
  int nextUniformLocation = 1;
}

final class _FakeFramebuffer {
  int? colorTex;
  int? colorRb;
  int? glowTex;
  int? glowRb;
  int? depthTex;
  int? depthRb;
  List<int> drawBuffers = <int>[GL_COLOR_ATTACHMENT0];
}

final class _FakeQuery {
  bool ended = false;
  int available = 0;
  int elapsedNs = 0;
}

final class _FakeGles3Api implements Gles3Api {
  String versionString = 'OpenGL ES 3.0.0 (ANGLE Mock)';
  String rendererString = 'ANGLE (Fake Hardware GPU)';
  String vendorString = 'Google Inc. (Mock)';
  String extensionsString =
      'GL_EXT_texture_filter_anisotropic GL_EXT_disjoint_timer_query '
      'GL_EXT_color_buffer_float GL_EXT_color_buffer_half_float '
      'GL_KHR_robustness';

  int maxTextureSize = 8192;
  int maxArrayLayers = 256;
  int maxSamples = 8;
  int maxVertexAttribs = 16;
  int maxColorAttachments = 4;
  double maxAnisotropy = 16.0;

  int gpuDisjoint = 0;
  int framebufferStatus = GL_FRAMEBUFFER_COMPLETE;
  bool failNextVertexShader = false;
  bool failNextFragmentShader = false;
  bool failNextLink = false;
  String vertexErrorLog = 'ERROR: 0:1: synthetic vertex compile error';
  String fragmentErrorLog = 'ERROR: 0:2: synthetic fragment compile error';
  String linkErrorLog = 'ERROR: synthetic program link error';
  final Set<String> missingUniforms = <String>{};

  int _nextHandle = 1;
  final Set<int> liveBuffers = <int>{};
  final Set<int> liveVaos = <int>{};
  final Set<int> liveTextures = <int>{};
  final Set<int> liveRenderbuffers = <int>{};
  final Map<int, _FakeFramebuffer> liveFramebuffers = <int, _FakeFramebuffer>{};
  final Map<int, _FakeShader> liveShaders = <int, _FakeShader>{};
  final Map<int, _FakeProgram> livePrograms = <int, _FakeProgram>{};
  final Map<int, _FakeQuery> liveQueries = <int, _FakeQuery>{};

  final Map<int, Uint8List> bufferContents = <int, Uint8List>{};
  final Map<int, int> bufferTargets = <int, int>{};
  final Map<int, int> boundBuffers = <int, int>{};
  int boundVao = 0;
  int activeTextureUnit = GL_TEXTURE0;
  final Map<int, int> boundTextures = <int, int>{};
  int boundReadFramebuffer = 0;
  int boundDrawFramebuffer = 0;
  int boundRenderbuffer = 0;
  int boundProgram = 0;

  final List<String> calls = <String>[];
  final Map<String, int> uniformLookupCounts = <String, int>{};
  final Map<int, Object?> uniformValues = <int, Object?>{};
  final List<({int x0, int y0, int x1, int y1, int mask, int filter})> blits =
      <({int x0, int y0, int x1, int y1, int mask, int filter})>[];
  final Set<int> enabledCaps = <int>{};
  final List<
    ({
      int location,
      int size,
      int type,
      bool normalized,
      int stride,
      int offset,
    })
  >
  attribPointers =
      <
        ({
          int location,
          int size,
          int type,
          bool normalized,
          int stride,
          int offset,
        })
      >[];
  Uint8List readPixelsPayload = Uint8List.fromList(<int>[
    10,
    20,
    30,
    255,
    40,
    50,
    60,
    255,
    70,
    80,
    90,
    255,
    100,
    110,
    120,
    255,
  ]);

  int get totalLiveGlHandles =>
      liveBuffers.length +
      liveVaos.length +
      liveTextures.length +
      liveRenderbuffers.length +
      liveFramebuffers.length +
      liveShaders.length +
      livePrograms.length +
      liveQueries.length;

  @override
  String? glGetString(int name) {
    calls.add('glGetString($name)');
    return switch (name) {
      GL_VERSION => versionString,
      GL_RENDERER => rendererString,
      GL_VENDOR => vendorString,
      GL_EXTENSIONS => extensionsString,
      _ => null,
    };
  }

  @override
  int glGetIntegerv(int pname) {
    calls.add('glGetIntegerv($pname)');
    return switch (pname) {
      GL_MAX_TEXTURE_SIZE => maxTextureSize,
      GL_MAX_ARRAY_TEXTURE_LAYERS => maxArrayLayers,
      GL_MAX_SAMPLES => maxSamples,
      GL_MAX_VERTEX_ATTRIBS => maxVertexAttribs,
      GL_MAX_COLOR_ATTACHMENTS => maxColorAttachments,
      GL_GPU_DISJOINT_EXT => gpuDisjoint,
      _ => 0,
    };
  }

  @override
  double glGetFloatv(int pname) {
    calls.add('glGetFloatv($pname)');
    return switch (pname) {
      GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT => maxAnisotropy,
      _ => 0.0,
    };
  }

  @override
  List<int> glGenBuffers(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveBuffers.add(id);
      return id;
    });
    calls.add('glGenBuffers($ids)');
    return ids;
  }

  @override
  void glDeleteBuffers(List<int> buffers) {
    calls.add('glDeleteBuffers($buffers)');
    for (final id in buffers) {
      liveBuffers.remove(id);
      bufferContents.remove(id);
    }
  }

  @override
  void glBindBuffer(int target, int buffer) {
    calls.add('glBindBuffer($target, $buffer)');
    boundBuffers[target] = buffer;
    if (buffer != 0) {
      bufferTargets.putIfAbsent(buffer, () => target);
    }
  }

  @override
  void glBufferData(int target, int sizeBytes, TypedData? data, int usage) {
    calls.add('glBufferData($target, $sizeBytes, $usage)');
    final id = boundBuffers[target] ?? 0;
    if (data == null) {
      bufferContents[id] = Uint8List(sizeBytes);
    } else {
      final src = data.buffer.asUint8List(data.offsetInBytes, sizeBytes);
      bufferContents[id] = Uint8List.fromList(src);
    }
  }

  @override
  void glBufferSubData(
    int target,
    int offsetBytes,
    int sizeBytes,
    TypedData data,
  ) {
    calls.add('glBufferSubData($target, $offsetBytes, $sizeBytes)');
    final id = boundBuffers[target] ?? 0;
    final dst = bufferContents[id]!;
    final src = data.buffer.asUint8List(data.offsetInBytes, sizeBytes);
    dst.setRange(offsetBytes, offsetBytes + sizeBytes, src);
  }

  @override
  List<int> glGenVertexArrays(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveVaos.add(id);
      return id;
    });
    calls.add('glGenVertexArrays($ids)');
    return ids;
  }

  @override
  void glDeleteVertexArrays(List<int> arrays) {
    calls.add('glDeleteVertexArrays($arrays)');
    liveVaos.removeAll(arrays);
  }

  @override
  void glBindVertexArray(int array) {
    calls.add('glBindVertexArray($array)');
    boundVao = array;
  }

  @override
  void glEnableVertexAttribArray(int index) =>
      calls.add('glEnableVertexAttribArray($index)');

  @override
  void glVertexAttribPointer(
    int index,
    int size,
    int type,
    bool normalized,
    int stride,
    int offsetBytes,
  ) {
    calls.add('glVertexAttribPointer($index, $size, $type, $normalized)');
    attribPointers.add((
      location: index,
      size: size,
      type: type,
      normalized: normalized,
      stride: stride,
      offset: offsetBytes,
    ));
  }

  @override
  void glVertexAttribDivisor(int index, int divisor) =>
      calls.add('glVertexAttribDivisor($index, $divisor)');

  @override
  List<int> glGenTextures(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveTextures.add(id);
      return id;
    });
    calls.add('glGenTextures($ids)');
    return ids;
  }

  @override
  void glDeleteTextures(List<int> textures) {
    calls.add('glDeleteTextures($textures)');
    liveTextures.removeAll(textures);
  }

  @override
  void glBindTexture(int target, int texture) {
    calls.add('glBindTexture($target, $texture)');
    boundTextures[activeTextureUnit] = texture;
  }

  @override
  void glActiveTexture(int texture) {
    calls.add('glActiveTexture($texture)');
    activeTextureUnit = texture;
  }

  @override
  void glTexImage2D(
    int target,
    int level,
    int internalFormat,
    int width,
    int height,
    int border,
    int format,
    int type,
    TypedData? pixels,
  ) => calls.add('glTexImage2D($target, $internalFormat, $width, $height)');

  @override
  void glTexSubImage2D(
    int target,
    int level,
    int xoffset,
    int yoffset,
    int width,
    int height,
    int format,
    int type,
    TypedData pixels,
  ) => calls.add(
    'glTexSubImage2D($target, $width, $height, ${pixels.lengthInBytes})',
  );

  @override
  void glTexImage3D(
    int target,
    int level,
    int internalFormat,
    int width,
    int height,
    int depth,
    int border,
    int format,
    int type,
    TypedData? pixels,
  ) => calls.add('glTexImage3D($target, $width, $height, $depth)');

  @override
  void glTexSubImage3D(
    int target,
    int level,
    int xoffset,
    int yoffset,
    int zoffset,
    int width,
    int height,
    int depth,
    int format,
    int type,
    TypedData pixels,
  ) => calls.add('glTexSubImage3D($target, $zoffset, $width, $height)');

  @override
  void glGenerateMipmap(int target) => calls.add('glGenerateMipmap($target)');

  @override
  void glTexParameteri(int target, int pname, int param) =>
      calls.add('glTexParameteri($target, $pname, $param)');

  @override
  void glTexParameterf(int target, int pname, double param) =>
      calls.add('glTexParameterf($target, $pname, $param)');

  @override
  List<int> glGenFramebuffers(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveFramebuffers[id] = _FakeFramebuffer();
      return id;
    });
    calls.add('glGenFramebuffers($ids)');
    return ids;
  }

  @override
  void glDeleteFramebuffers(List<int> framebuffers) {
    calls.add('glDeleteFramebuffers($framebuffers)');
    for (final id in framebuffers) {
      liveFramebuffers.remove(id);
    }
  }

  @override
  void glBindFramebuffer(int target, int framebuffer) {
    calls.add('glBindFramebuffer($target, $framebuffer)');
    if (target == GL_FRAMEBUFFER || target == GL_READ_FRAMEBUFFER) {
      boundReadFramebuffer = framebuffer;
    }
    if (target == GL_FRAMEBUFFER || target == GL_DRAW_FRAMEBUFFER) {
      boundDrawFramebuffer = framebuffer;
    }
  }

  @override
  void glFramebufferTexture2D(
    int target,
    int attachment,
    int textarget,
    int texture,
    int level,
  ) {
    calls.add('glFramebufferTexture2D($attachment, $texture)');
    final fb = liveFramebuffers[boundDrawFramebuffer];
    if (fb != null) {
      if (attachment == GL_COLOR_ATTACHMENT0) fb.colorTex = texture;
      if (attachment == GL_COLOR_ATTACHMENT1) fb.glowTex = texture;
      if (attachment == GL_DEPTH_ATTACHMENT) fb.depthTex = texture;
    }
  }

  @override
  List<int> glGenRenderbuffers(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveRenderbuffers.add(id);
      return id;
    });
    calls.add('glGenRenderbuffers($ids)');
    return ids;
  }

  @override
  void glDeleteRenderbuffers(List<int> renderbuffers) {
    calls.add('glDeleteRenderbuffers($renderbuffers)');
    liveRenderbuffers.removeAll(renderbuffers);
  }

  @override
  void glBindRenderbuffer(int target, int renderbuffer) {
    calls.add('glBindRenderbuffer($target, $renderbuffer)');
    boundRenderbuffer = renderbuffer;
  }

  @override
  void glRenderbufferStorage(
    int target,
    int internalFormat,
    int width,
    int height,
  ) => calls.add('glRenderbufferStorage($internalFormat, $width, $height)');

  @override
  void glRenderbufferStorageMultisample(
    int target,
    int samples,
    int internalFormat,
    int width,
    int height,
  ) => calls.add(
    'glRenderbufferStorageMultisample($samples, $internalFormat, $width, $height)',
  );

  @override
  void glFramebufferRenderbuffer(
    int target,
    int attachment,
    int renderbuffertarget,
    int renderbuffer,
  ) {
    calls.add('glFramebufferRenderbuffer($attachment, $renderbuffer)');
    final fb = liveFramebuffers[boundDrawFramebuffer];
    if (fb != null) {
      if (attachment == GL_COLOR_ATTACHMENT0) fb.colorRb = renderbuffer;
      if (attachment == GL_COLOR_ATTACHMENT1) fb.glowRb = renderbuffer;
      if (attachment == GL_DEPTH_ATTACHMENT) fb.depthRb = renderbuffer;
    }
  }

  @override
  void glBlitFramebuffer(
    int srcX0,
    int srcY0,
    int srcX1,
    int srcY1,
    int dstX0,
    int dstY0,
    int dstX1,
    int dstY1,
    int mask,
    int filter,
  ) {
    calls.add('glBlitFramebuffer($mask, $filter)');
    blits.add((
      x0: srcX0,
      y0: srcY0,
      x1: srcX1,
      y1: srcY1,
      mask: mask,
      filter: filter,
    ));
  }

  @override
  int glCheckFramebufferStatus(int target) {
    calls.add('glCheckFramebufferStatus($target)');
    return framebufferStatus;
  }

  @override
  void glDrawBuffers(List<int> bufs) {
    calls.add('glDrawBuffers($bufs)');
    final fb = liveFramebuffers[boundDrawFramebuffer];
    if (fb != null) {
      fb.drawBuffers = List<int>.of(bufs);
    }
  }

  @override
  int glCreateShader(int type) {
    final id = _nextHandle++;
    liveShaders[id] = _FakeShader(type);
    calls.add('glCreateShader($type) -> $id');
    return id;
  }

  @override
  void glDeleteShader(int shader) {
    calls.add('glDeleteShader($shader)');
    liveShaders.remove(shader);
  }

  @override
  void glShaderSource(int shader, String source) {
    calls.add('glShaderSource($shader)');
    liveShaders[shader]!.source = source;
  }

  @override
  void glCompileShader(int shader) {
    calls.add('glCompileShader($shader)');
    final s = liveShaders[shader]!;
    if (s.type == GL_VERTEX_SHADER && failNextVertexShader) {
      failNextVertexShader = false;
      s.compiled = false;
      s.infoLog = vertexErrorLog;
      return;
    }
    if (s.type == GL_FRAGMENT_SHADER && failNextFragmentShader) {
      failNextFragmentShader = false;
      s.compiled = false;
      s.infoLog = fragmentErrorLog;
      return;
    }
    if (s.source.contains('FAIL_VERTEX') ||
        s.source.contains('FAIL_FRAGMENT')) {
      s.compiled = false;
      s.infoLog = s.type == GL_VERTEX_SHADER
          ? vertexErrorLog
          : fragmentErrorLog;
      return;
    }
    s.compiled = true;
  }

  @override
  int glGetShaderiv(int shader, int pname) {
    final s = liveShaders[shader]!;
    if (pname == GL_COMPILE_STATUS) return s.compiled ? GL_TRUE : GL_FALSE;
    if (pname == GL_INFO_LOG_LENGTH) return s.infoLog.length + 1;
    return 0;
  }

  @override
  String glGetShaderInfoLog(int shader) => liveShaders[shader]!.infoLog;

  @override
  int glCreateProgram() {
    final id = _nextHandle++;
    livePrograms[id] = _FakeProgram();
    calls.add('glCreateProgram() -> $id');
    return id;
  }

  @override
  void glDeleteProgram(int program) {
    calls.add('glDeleteProgram($program)');
    livePrograms.remove(program);
  }

  @override
  void glAttachShader(int program, int shader) {
    calls.add('glAttachShader($program, $shader)');
    livePrograms[program]!.attachedShaders.add(shader);
  }

  @override
  void glLinkProgram(int program) {
    calls.add('glLinkProgram($program)');
    final p = livePrograms[program]!;
    if (failNextLink) {
      failNextLink = false;
      p.linked = false;
      p.infoLog = linkErrorLog;
      return;
    }
    p.linked = true;
  }

  @override
  int glGetProgramiv(int program, int pname) {
    final p = livePrograms[program]!;
    if (pname == GL_LINK_STATUS) return p.linked ? GL_TRUE : GL_FALSE;
    if (pname == GL_INFO_LOG_LENGTH) return p.infoLog.length + 1;
    return 0;
  }

  @override
  String glGetProgramInfoLog(int program) => livePrograms[program]!.infoLog;

  @override
  void glUseProgram(int program) {
    calls.add('glUseProgram($program)');
    boundProgram = program;
  }

  @override
  int glGetUniformLocation(int program, String name) {
    final key = '$program:$name';
    uniformLookupCounts[key] = (uniformLookupCounts[key] ?? 0) + 1;
    calls.add('glGetUniformLocation($program, $name)');
    if (missingUniforms.contains(name)) return -1;
    final p = livePrograms[program]!;
    return p.uniformLocations.putIfAbsent(name, () => p.nextUniformLocation++);
  }

  @override
  void glUniform1i(int location, int v0) {
    calls.add('glUniform1i($location, $v0)');
    uniformValues[location] = v0;
  }

  @override
  void glUniform1f(int location, double v0) {
    calls.add('glUniform1f($location, $v0)');
    uniformValues[location] = v0;
  }

  @override
  void glUniform2fv(int location, int count, Float32List value) {
    calls.add('glUniform2fv($location, $count)');
    uniformValues[location] = Float32List.fromList(value.sublist(0, count * 2));
  }

  @override
  void glUniform3fv(int location, int count, Float32List value) {
    calls.add('glUniform3fv($location, $count)');
    uniformValues[location] = Float32List.fromList(value.sublist(0, count * 3));
  }

  @override
  void glUniform4fv(int location, int count, Float32List value) {
    calls.add('glUniform4fv($location, $count)');
    uniformValues[location] = Float32List.fromList(value.sublist(0, count * 4));
  }

  @override
  void glUniformMatrix4fv(
    int location,
    int count,
    bool transpose,
    Float32List value,
  ) {
    calls.add('glUniformMatrix4fv($location, $count, $transpose)');
    uniformValues[location] = Float32List.fromList(
      value.sublist(0, count * 16),
    );
  }

  @override
  void glViewport(int x, int y, int width, int height) =>
      calls.add('glViewport($x, $y, $width, $height)');

  @override
  void glScissor(int x, int y, int width, int height) =>
      calls.add('glScissor($x, $y, $width, $height)');

  @override
  void glEnable(int cap) {
    enabledCaps.add(cap);
    calls.add('glEnable($cap)');
  }

  @override
  void glDisable(int cap) {
    enabledCaps.remove(cap);
    calls.add('glDisable($cap)');
  }

  @override
  void glDepthMask(bool flag) => calls.add('glDepthMask($flag)');

  @override
  void glDepthFunc(int func) => calls.add('glDepthFunc($func)');

  @override
  void glBlendFunc(int sfactor, int dfactor) =>
      calls.add('glBlendFunc($sfactor, $dfactor)');

  @override
  void glBlendEquation(int mode) => calls.add('glBlendEquation($mode)');

  @override
  void glCullFace(int mode) => calls.add('glCullFace($mode)');

  @override
  void glFrontFace(int mode) => calls.add('glFrontFace($mode)');

  @override
  void glColorMask(bool red, bool green, bool blue, bool alpha) =>
      calls.add('glColorMask($red, $green, $blue, $alpha)');

  @override
  void glClearColor(double red, double green, double blue, double alpha) =>
      calls.add('glClearColor($red, $green, $blue, $alpha)');

  @override
  void glClear(int mask) => calls.add('glClear($mask)');

  @override
  void glClearBufferfv(int buffer, int drawbuffer, Float32List value) =>
      calls.add('glClearBufferfv($buffer, $drawbuffer)');

  @override
  void glDrawArrays(int mode, int first, int count) =>
      calls.add('glDrawArrays($mode, $first, $count)');

  @override
  void glDrawArraysInstanced(
    int mode,
    int first,
    int count,
    int instanceCount,
  ) =>
      calls.add('glDrawArraysInstanced($mode, $first, $count, $instanceCount)');

  @override
  void glDrawElements(int mode, int count, int type, int offsetBytes) =>
      calls.add('glDrawElements($mode, $count, $type, $offsetBytes)');

  @override
  void glDrawElementsInstanced(
    int mode,
    int count,
    int type,
    int offsetBytes,
    int instanceCount,
  ) => calls.add(
    'glDrawElementsInstanced($mode, $count, $type, $offsetBytes, $instanceCount)',
  );

  @override
  Uint8List glReadPixels(
    int x,
    int y,
    int width,
    int height,
    int format,
    int type,
  ) {
    calls.add('glReadPixels($x, $y, $width, $height, $format, $type)');
    return Uint8List.fromList(readPixelsPayload);
  }

  @override
  List<int> glGenQueries(int count) {
    final ids = List<int>.generate(count, (_) {
      final id = _nextHandle++;
      liveQueries[id] = _FakeQuery();
      return id;
    });
    calls.add('glGenQueries($ids)');
    return ids;
  }

  @override
  void glDeleteQueries(List<int> ids) {
    calls.add('glDeleteQueries($ids)');
    for (final id in ids) {
      liveQueries.remove(id);
    }
  }

  @override
  void glBeginQuery(int target, int id) =>
      calls.add('glBeginQuery($target, $id)');

  @override
  void glEndQuery(int target) {
    calls.add('glEndQuery($target)');
    for (final q in liveQueries.values) {
      q.ended = true;
    }
  }

  @override
  int glGetQueryObjectuiv(int id, int pname) {
    calls.add('glGetQueryObjectuiv($id, $pname)');
    if (pname == GL_QUERY_RESULT_AVAILABLE) {
      return liveQueries[id]?.available ?? 0;
    }
    return 0;
  }

  @override
  int glGetQueryObjectui64v(int id, int pname) {
    calls.add('glGetQueryObjectui64v($id, $pname)');
    if (pname == GL_QUERY_RESULT) {
      return liveQueries[id]?.elapsedNs ?? 0;
    }
    return 0;
  }
}

void main() {
  group('RecordingGlesDevice & GlesDevice typedef compatibility', () {
    test('GlesDevice typedef aliases RecordingGlesDevice identically', () {
      expect(identical(GlesDevice, RecordingGlesDevice), isTrue);

      final recorded = <String>[];
      final RecordingGlesDevice device = GlesDevice(
        onCommand: (cmd, _) => recorded.add(cmd),
      );
      expect(device, isA<GlesDevice>());
      expect(device, isA<RecordingGlesDevice>());

      final transport = NativeGlTransport();
      final GlesDevice transportDevice = transport.createDevice();
      expect(transportDevice, isA<RecordingGlesDevice>());

      final buf = device.createBuffer(
        const GpuBufferDescriptor(
          byteLength: 16,
          usage: GpuBufferUsage.staticDraw,
        ),
      );
      expect(device.liveObjectCount, 1);
      device.deleteBuffer(buf);
      expect(device.liveObjectCount, 0);
      expect(recorded, containsAll(['create:buffer', 'delete:buffer']));
    });
  });

  group('FfiGles3Api missing-symbol safety', () {
    test(
      'throws descriptive StateError when GL symbols or libs are missing',
      () {
        final missingLibApi = FfiGles3Api(
          DynamicLibraryGlLoader(
            candidateLibraries: const ['definitely_nonexistent_gles3_w9.dll'],
          ),
        );
        expect(missingLibApi.hasSymbol('glViewport'), isFalse);
        expect(
          () => missingLibApi.glViewport(0, 0, 1280, 720),
          throwsA(isA<StateError>()),
        );
        expect(
          () => missingLibApi.validateRequiredSymbols(),
          throwsA(isA<StateError>()),
        );

        final stubApi = FfiGles3Api(
          StubGlProcLoader(
            supportedSymbols: const {'glViewport', 'glGetString'},
            libraryName: 'mock-stub-angle',
          ),
        );
        expect(stubApi.hasSymbol('glViewport'), isTrue);
        expect(stubApi.resolveAddress('glViewport'), isNonZero);
        expect(stubApi.hasSymbol('glDrawElements'), isFalse);
        expect(
          () => stubApi.glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT, 0),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('glDrawElements'),
            ),
          ),
        );
        expect(
          () => stubApi.validateRequiredSymbols(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('missing required GLES3 symbols'),
            ),
          ),
        );
      },
    );
  });

  group('Gles3FfiDevice hardware GLES3 contract over mock Gles3Api', () {
    late _FakeGles3Api gl;
    late Gles3FfiDevice device;

    setUp(() {
      gl = _FakeGles3Api();
      device = Gles3FfiDevice(gl, 1280, 720);
    });

    test('queryCapabilities parses GL strings, limits, and extensions', () {
      final caps = device.queryCapabilities();
      expect(caps.webglVersion, gl.versionString);
      expect(caps.rendererString, gl.rendererString);
      expect(caps.vendorString, gl.vendorString);
      expect(caps.maxTextureSize, 8192);
      expect(caps.maxTextureArrayLayers, 256);
      expect(caps.maxSamples, 8);
      expect(caps.maxVertexAttributes, 16);
      expect(caps.maxColorAttachments, 4);
      expect(caps.anisotropicFiltering, isTrue);
      expect(caps.maxAnisotropy, 16.0);
      expect(caps.disjointTimerQuery, isTrue);
      expect(caps.floatRenderTarget, isTrue);
      expect(caps.halfFloatRenderTarget, isTrue);
      expect(caps.contextLossExtension, isTrue);
    });

    test('buffers, VAOs, attribute formats, indices, and instanced draws', () {
      final vao = device.createVertexArray();
      final vbo = device.createBuffer(
        const GpuBufferDescriptor(
          byteLength: 32,
          usage: GpuBufferUsage.dynamicDraw,
        ),
      );
      final ibo = device.createBuffer(
        const GpuBufferDescriptor(
          byteLength: 12,
          usage: GpuBufferUsage.staticDraw,
          kind: GpuBufferKind.indices,
        ),
      );
      expect(device.liveVaoCount, 1);
      expect(device.liveBufferCount, 2);
      expect(device.liveObjectCount, 3);

      final floats = Float32List.fromList([1.0, 2.0, 3.0, 4.0]);
      device.uploadBuffer(vbo, floats, dstByteOffset: 4);

      device.bindVertexArray(vao);
      device.bindArrayBuffer(vbo);
      device.enableVertexAttribArray(0);
      device.vertexAttribPointer(
        location: 0,
        componentCount: 3,
        strideBytes: 16,
        offsetBytes: 0,
        format: GpuAttribFormat.float,
      );
      device.vertexAttribPointer(
        location: 1,
        componentCount: 2,
        strideBytes: 16,
        offsetBytes: 12,
        format: GpuAttribFormat.unorm16,
      );
      device.vertexAttribPointer(
        location: 2,
        componentCount: 4,
        strideBytes: 16,
        offsetBytes: 12,
        format: GpuAttribFormat.unorm8,
      );
      device.vertexAttribDivisor(2, 1);

      expect(gl.attribPointers[0].type, GL_FLOAT);
      expect(gl.attribPointers[0].normalized, isFalse);
      expect(gl.attribPointers[1].type, GL_UNSIGNED_SHORT);
      expect(gl.attribPointers[1].normalized, isTrue);
      expect(gl.attribPointers[2].type, GL_UNSIGNED_BYTE);
      expect(gl.attribPointers[2].normalized, isTrue);

      device.bindElementArrayBuffer(ibo);
      device.uploadIndices(ibo, Uint16List.fromList([0, 1, 2]));
      device.uploadIndices(ibo, [0, 1, 2, 2, 3, 0]);

      device.drawArrays(first: 0, count: 6);
      device.drawArraysInstanced(first: 0, count: 6, instanceCount: 4);
      device.drawElements(count: 6, offsetBytes: 0, index32: false);
      device.drawElementsInstanced(
        count: 6,
        offsetBytes: 8,
        instanceCount: 12,
        index32: true,
      );

      expect(gl.calls, contains('glDrawArrays(4, 0, 6)'));
      expect(gl.calls, contains('glDrawArraysInstanced(4, 0, 6, 4)'));
      expect(gl.calls, contains('glDrawElements(4, 6, $GL_UNSIGNED_SHORT, 0)'));
      expect(
        gl.calls,
        contains('glDrawElementsInstanced(4, 6, $GL_UNSIGNED_INT, 8, 12)'),
      );

      device.deleteVertexArray(vao);
      device.deleteBuffer(vbo);
      device.deleteBuffer(ibo);
      expect(device.liveObjectCount, 0);
      expect(() => device.deleteBuffer(vbo), throwsA(isA<StateError>()));
    });

    test('textures 2D, 2D array, mips, and anisotropy clamping', () {
      final tex2d = device.createTexture(
        const GpuTextureDescriptor(
          width: 4,
          height: 4,
          hasMips: true,
          minFilter: GpuTextureFilter.linearMipmapLinear,
          magFilter: GpuTextureFilter.linear,
          wrap: GpuTextureWrap.repeat,
          anisotropy: 8,
        ),
      );
      expect(device.anisotropyDecisionOf(tex2d).effective, 8.0);
      device.uploadTextureLayer(tex2d, 0, Uint8List(4 * 4 * 4));
      device.finalizeMips(tex2d);
      expect(gl.calls, contains('glTexSubImage2D($GL_TEXTURE_2D, 4, 4, 64)'));
      expect(gl.calls, contains('glGenerateMipmap($GL_TEXTURE_2D)'));

      final texArray = device.createTexture(
        const GpuTextureDescriptor(
          width: 2,
          height: 2,
          layers: 3,
          hasMips: false,
        ),
      );
      device.uploadTextureLayer(texArray, 2, Uint8List(2 * 2 * 4));
      expect(
        gl.calls,
        contains('glTexSubImage3D($GL_TEXTURE_2D_ARRAY, 2, 2, 2)'),
      );
      device.bindTexture(3, texArray);
      expect(gl.activeTextureUnit, GL_TEXTURE0 + 3);

      device.deleteTexture(tex2d);
      device.deleteTexture(texArray);
      expect(device.liveTextureCount, 0);
    });

    test(
      'FBOs, MSAA resolve, glow, depth-only, incomplete cleanup, and viewport',
      () {
        final msaa = device.createTarget(
          const GpuTargetDescriptor(
            width: 320,
            height: 180,
            samples: 4,
            attachments: GpuTargetAttachment.colorDepthGlow,
            hasDepth: true,
          ),
        );
        final resolved = device.createTarget(
          const GpuTargetDescriptor(
            width: 320,
            height: 180,
            samples: 1,
            attachments: GpuTargetAttachment.colorDepthGlow,
            hasDepth: true,
          ),
        );
        final shadow = device.createTarget(
          const GpuTargetDescriptor(
            width: 256,
            height: 256,
            samples: 1,
            attachments: GpuTargetAttachment.depthOnly,
            hasDepth: true,
          ),
        );
        expect(device.liveTargetCount, 3);

        device.resolveTarget(msaa, resolved);
        expect(gl.blits.length, 3);
        expect(gl.blits[0].mask, GL_COLOR_BUFFER_BIT);
        expect(gl.blits[1].mask, GL_COLOR_BUFFER_BIT);
        expect(gl.blits[2].mask, GL_DEPTH_BUFFER_BIT);
        expect(gl.boundReadFramebuffer, 0);
        expect(gl.boundDrawFramebuffer, 0);

        device.setViewport(16, 8, 800, 600);
        device.bindTarget(resolved);
        expect(gl.calls, contains('glViewport(0, 0, 320, 180)'));
        device.setColorAttachmentCount(2);
        device.clearColorAttachment(1, r: 0.25, g: 0.5, b: 0.75, a: 1.0);
        device.bindTarget(null);
        expect(gl.calls, contains('glViewport(16, 8, 800, 600)'));

        device.bindTexture(0, resolved);
        device.bindGlowTexture(1, resolved);
        device.bindTexture(2, shadow);
        expect(
          () => device.bindGlowTexture(0, shadow),
          throwsA(isA<StateError>()),
        );

        // Incomplete FBO must clean up all allocated attachments without leaking.
        gl.framebufferStatus = 0x8CD6; // GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT
        expect(
          () => device.createTarget(
            const GpuTargetDescriptor(
              width: 64,
              height: 64,
              attachments: GpuTargetAttachment.colorAndGlow,
              hasDepth: true,
            ),
          ),
          throwsA(isA<StateError>()),
        );
        gl.framebufferStatus = GL_FRAMEBUFFER_COMPLETE;

        device.deleteTarget(msaa);
        device.deleteTarget(resolved);
        device.deleteTarget(shadow);
        expect(device.liveTargetCount, 0);
        expect(gl.totalLiveGlHandles, 0);
      },
    );

    test(
      'shader compile/link errors throw ShaderCompileException with GL info log',
      () {
        gl.failNextVertexShader = true;
        expect(
          () => device.compileProgram(
            vertexSource: 'void main() {}',
            fragmentSource: 'void main() {}',
            requiredAttributes: const [],
            requiredUniforms: const [],
          ),
          throwsA(
            isA<ShaderCompileException>()
                .having((e) => e.stage, 'stage', ShaderCompileStage.vertex)
                .having((e) => e.message, 'message', gl.vertexErrorLog),
          ),
        );
        expect(gl.totalLiveGlHandles, 0);

        gl.failNextFragmentShader = true;
        expect(
          () => device.compileProgram(
            vertexSource: 'void main() {}',
            fragmentSource: 'void main() {}',
            requiredAttributes: const [],
            requiredUniforms: const [],
          ),
          throwsA(
            isA<ShaderCompileException>()
                .having((e) => e.stage, 'stage', ShaderCompileStage.fragment)
                .having((e) => e.message, 'message', gl.fragmentErrorLog),
          ),
        );
        expect(gl.totalLiveGlHandles, 0);

        gl.failNextLink = true;
        expect(
          () => device.compileProgram(
            vertexSource: 'void main() {}',
            fragmentSource: 'void main() {}',
            requiredAttributes: const [],
            requiredUniforms: const [],
          ),
          throwsA(
            isA<ShaderCompileException>()
                .having((e) => e.stage, 'stage', ShaderCompileStage.link)
                .having((e) => e.message, 'message', gl.linkErrorLog),
          ),
        );
        expect(gl.totalLiveGlHandles, 0);

        gl.missingUniforms.add('uMissing');
        expect(
          () => device.compileProgram(
            vertexSource: 'in vec3 aPosition; void main() {}',
            fragmentSource: 'void main() {}',
            requiredAttributes: const ['aPosition'],
            requiredUniforms: const ['uMissing'],
          ),
          throwsA(
            isA<ShaderCompileException>().having(
              (e) => e.stage,
              'stage',
              ShaderCompileStage.validation,
            ),
          ),
        );
        expect(gl.totalLiveGlHandles, 0);
      },
    );

    test(
      'uniform location caching avoids duplicate glGetUniformLocation calls',
      () {
        final p1 = device.compileProgram(
          vertexSource: 'in vec3 aPosition; uniform mat4 uMvp; void main() {}',
          fragmentSource: 'uniform vec4 uTint; void main() {}',
          requiredAttributes: const ['aPosition'],
          requiredUniforms: const ['uMvp'],
        );
        final p2 = device.compileProgram(
          vertexSource:
              'in vec3 aPosition; uniform float uScale; void main() {}',
          fragmentSource: 'void main() {}',
          requiredAttributes: const ['aPosition'],
          requiredUniforms: const ['uScale'],
        );
        expect(device.liveProgramCount, 2);

        // uMvp was already looked up and cached during compileProgram validation.
        gl.uniformLookupCounts.clear();
        gl.missingUniforms.add('uAbsent');

        device.useProgram(p1);
        final mat = Float32List(16)..[0] = 1.0;
        device.setUniform('uMvp', UniformValue.mat4(mat));
        device.setUniform('uMvp', UniformValue.mat4(mat));
        device.setUniform('uTint', UniformValue.float4(Float32List(4)));
        device.setUniform('uTint', UniformValue.float4(Float32List(4)));
        device.setUniform('uAbsent', const UniformValue.float1(1.0));
        device.setUniform('uAbsent', const UniformValue.float1(2.0));

        // Switch to p2 and back to p1; p1's cache must stay warm.
        device.useProgram(p2);
        device.setUniform('uScale', const UniformValue.float1(0.5));
        device.setUniform('uBones', UniformValue.mat4Array(Float32List(32)));
        device.useProgram(p1);
        device.setUniform('uTint', UniformValue.float4(Float32List(4)));

        final p1Id = gl.livePrograms.keys.first;
        expect(gl.uniformLookupCounts['$p1Id:uMvp'], isNull);
        expect(gl.uniformLookupCounts['$p1Id:uTint'], 1);
        expect(gl.uniformLookupCounts['$p1Id:uAbsent'], 1);

        device.deleteProgram(p1);
        device.deleteProgram(p2);
        expect(device.liveProgramCount, 0);
        expect(gl.totalLiveGlHandles, 0);
      },
    );

    test('draw state cache, clear, and readPixels', () {
      device.applyDrawState(DrawStateDescriptor.opaqueDefault);
      final initialCalls = gl.calls.length;
      device.applyDrawState(DrawStateDescriptor.opaqueDefault);
      expect(gl.calls.length, initialCalls);

      device.applyDrawState(DrawStateDescriptor.blendedDefault);
      expect(gl.enabledCaps.contains(GL_BLEND), isTrue);

      device.clear(ClearMask.colorAndDepth, r: 0.1, g: 0.2, b: 0.3, a: 1.0);
      expect(
        gl.calls,
        contains('glClear(${GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT})'),
      );

      final pixels = device.readPixels(0, 0, 2, 2);
      expect(pixels, orderedEquals(gl.readPixelsPayload));
    });

    test(
      'pollGpuTimer reads dynamic driver values and handles unsupported/disjoint',
      () {
        final q1 = device.beginGpuTimer()!;
        expect(device.liveTimerCount, 1);
        expect(device.pollGpuTimer(q1).status, GpuTimerStatus.pending);

        device.endGpuTimer(q1);
        expect(device.pollGpuTimer(q1).status, GpuTimerStatus.pending);

        final queryId1 = gl.liveQueries.keys.single;
        gl.liveQueries[queryId1]!
          ..available = GL_TRUE
          ..elapsedNs = 987654;
        final poll1 = device.pollGpuTimer(q1);
        expect(poll1.status, GpuTimerStatus.ready);
        expect(poll1.elapsedNanoseconds, 987654);

        gl.gpuDisjoint = GL_TRUE;
        expect(device.pollGpuTimer(q1).status, GpuTimerStatus.disjoint);
        gl.gpuDisjoint = GL_FALSE;

        final q2 = device.beginGpuTimer()!;
        device.endGpuTimer(q2);
        final queryId2 = gl.liveQueries.keys.last;
        gl.liveQueries[queryId2]!
          ..available = GL_TRUE
          ..elapsedNs = 4321000;
        final poll2 = device.pollGpuTimer(q2);
        expect(poll2.status, GpuTimerStatus.ready);
        expect(poll2.elapsedNanoseconds, 4321000);

        device.deleteGpuTimer(q1);
        device.deleteGpuTimer(q2);
        expect(device.liveTimerCount, 0);

        // Unsupported timer query path.
        final noTimerGl = _FakeGles3Api()
          ..extensionsString = 'GL_EXT_texture_filter_anisotropic';
        final noTimerDevice = Gles3FfiDevice(noTimerGl);
        expect(noTimerDevice.queryCapabilities().disjointTimerQuery, isFalse);
        expect(noTimerDevice.beginGpuTimer(), isNull);
        expect(
          noTimerDevice.pollGpuTimer(q1).status,
          GpuTimerStatus.unsupported,
        );
      },
    );

    test(
      'SceneRenderer end-to-end boot, 2D+3D render, resize, and zero-leak dispose',
      () async {
        final runner = await NativeEngineHost.boot(
          device: device,
          width: 640,
          height: 360,
          requestedProfile: QualityProfile.clean,
          initialScene: buildDungeon2DScene(),
        );
        expect(device.liveProgramCount, greaterThan(0));
        expect(device.liveObjectCount, greaterThan(0));

        final stats2d = runner.renderFrame(1 / 60);
        expect(stats2d.drawCalls, greaterThan(0));

        runner.engine.loadScene(buildIsland3DScene());
        final stats3d = runner.renderFrame(1 / 60);
        expect(stats3d.drawCalls, greaterThan(0));
        expect(stats3d.trianglesSubmitted, greaterThan(0));

        await runner.resize(800, 600);
        final statsResized = runner.renderFrame(1 / 60);
        expect(statsResized.drawCalls, greaterThan(0));

        runner.dispose();
        expect(device.liveObjectCount, 0);
        expect(device.liveTimerCount, 0);
        expect(gl.totalLiveGlHandles, 0);
      },
    );

    test(
      'context loss/restore invalidates state and safely ignores stale deletes',
      () {
        final buf = device.createBuffer(
          const GpuBufferDescriptor(
            byteLength: 16,
            usage: GpuBufferUsage.staticDraw,
          ),
        );
        final vao = device.createVertexArray();
        final tex = device.createTexture(
          const GpuTextureDescriptor(width: 4, height: 4),
        );
        final target = device.createTarget(
          const GpuTargetDescriptor(width: 8, height: 8),
        );
        final prog = device.compileProgram(
          vertexSource: 'in vec3 aPosition; void main() {}',
          fragmentSource: 'void main() {}',
          requiredAttributes: const ['aPosition'],
          requiredUniforms: const [],
        );
        final timer = device.beginGpuTimer()!;
        expect(device.liveObjectCount, 5);
        expect(device.liveTimerCount, 1);

        device.simulateContextLoss();
        expect(device.status, GpuDeviceStatus.lost);
        expect(device.liveObjectCount, 0);
        expect(device.liveTimerCount, 0);
        expect(() => device.createVertexArray(), throwsA(isA<StateError>()));

        device.simulateContextRestore();
        expect(device.status, GpuDeviceStatus.ready);
        expect(device.contextGeneration, 1);

        // Stale handles from generation 0 are safely ignored on delete, but
        // rejected on active bind/upload calls.
        device.deleteBuffer(buf);
        device.deleteVertexArray(vao);
        device.deleteTexture(tex);
        device.deleteTarget(target);
        device.deleteProgram(prog);
        device.deleteGpuTimer(timer);
        expect(() => device.bindVertexArray(vao), throwsA(isA<StateError>()));
      },
    );

    test('all UniformValue types and Gles3ExtensionsApi path', () {
      final extGl = _FakeExtendedGles3Api()
        ..extensionsList = const [
          'GL_EXT_texture_filter_anisotropic',
          'GL_EXT_disjoint_timer_query',
        ]
        ..extensionsStringNull = true;
      final extDevice = Gles3FfiDevice(extGl);

      final caps = extDevice.queryCapabilities();
      expect(caps.anisotropicFiltering, isTrue);
      expect(caps.disjointTimerQuery, isTrue);

      extGl.missingAttributes.add('aMissingAttr');
      expect(
        () => extDevice.compileProgram(
          vertexSource: 'in vec3 aMissingAttr; void main() {}',
          fragmentSource: 'void main() {}',
          requiredAttributes: const ['aMissingAttr'],
          requiredUniforms: const [],
        ),
        throwsA(
          isA<ShaderCompileException>().having(
            (e) => e.stage,
            'stage',
            ShaderCompileStage.validation,
          ),
        ),
      );

      final prog = extDevice.compileProgram(
        vertexSource: 'in vec3 aPos; void main() {}',
        fragmentSource: 'void main() {}',
        requiredAttributes: const ['aPos'],
        requiredUniforms: const [
          'uF1',
          'uF2',
          'uF3',
          'uF4',
          'uI1',
          'uSamp',
          'uM4',
          'uArr',
        ],
      );
      extDevice.useProgram(prog);
      extDevice.setUniform('uF1', const UniformValue.float1(1.5));
      extDevice.setUniform(
        'uF2',
        UniformValue.float2(Float32List.fromList([1, 2])),
      );
      extDevice.setUniform(
        'uF3',
        UniformValue.float3(Float32List.fromList([1, 2, 3])),
      );
      extDevice.setUniform(
        'uF4',
        UniformValue.float4(Float32List.fromList([1, 2, 3, 4])),
      );
      extDevice.setUniform('uI1', const UniformValue.int1(7));
      extDevice.setUniform('uSamp', const UniformValue.sampler(2));
      extDevice.setUniform('uM4', UniformValue.mat4(Float32List(16)));
      extDevice.setUniform('uArr', UniformValue.mat4Array(Float32List(32)));

      expect(extGl.calls, contains('glUniform1f(1, 1.5)'));
      expect(extGl.calls, contains('glUniform2fv(2, 1)'));
      expect(extGl.calls, contains('glUniform3fv(3, 1)'));
      expect(extGl.calls, contains('glUniform4fv(4, 1)'));
      expect(extGl.calls, contains('glUniform1i(5, 7)'));
      expect(extGl.calls, contains('glUniform1i(6, 2)'));
      expect(extGl.calls, contains('glUniformMatrix4fv(7, 1, false)'));
      expect(extGl.calls, contains('glUniformMatrix4fv(8, 2, false)'));

      final msaa = extDevice.createTarget(
        const GpuTargetDescriptor(
          width: 64,
          height: 64,
          samples: 4,
          attachments: GpuTargetAttachment.colorAndGlow,
        ),
      );
      final dst = extDevice.createTarget(
        const GpuTargetDescriptor(
          width: 64,
          height: 64,
          samples: 1,
          attachments: GpuTargetAttachment.colorAndGlow,
        ),
      );
      extDevice.resolveTarget(msaa, dst);
      expect(extGl.calls, contains('glReadBuffer($GL_COLOR_ATTACHMENT1)'));
      expect(extGl.calls, contains('glReadBuffer($GL_COLOR_ATTACHMENT0)'));

      extDevice.deleteTarget(msaa);
      extDevice.deleteTarget(dst);
      extDevice.deleteProgram(prog);
      expect(extDevice.liveObjectCount, 0);
      expect(extGl.totalLiveGlHandles, 0);
    });
  });
}

final class _FakeExtendedGles3Api extends _FakeGles3Api
    implements Gles3ExtensionsApi {
  bool extensionsStringNull = false;
  List<String> extensionsList = const <String>[];
  final Set<String> missingAttributes = <String>{};

  @override
  String? glGetString(int name) {
    if (name == GL_EXTENSIONS && extensionsStringNull) {
      calls.add('glGetString($name)');
      return null;
    }
    return super.glGetString(name);
  }

  @override
  int glGetIntegerv(int pname) {
    if (pname == GL_NUM_EXTENSIONS) {
      calls.add('glGetIntegerv($pname)');
      return extensionsList.length;
    }
    return super.glGetIntegerv(pname);
  }

  @override
  String? glGetStringi(int name, int index) {
    calls.add('glGetStringi($name, $index)');
    if (name == GL_EXTENSIONS && index >= 0 && index < extensionsList.length) {
      return extensionsList[index];
    }
    return null;
  }

  @override
  int glGetAttribLocation(int program, String name) {
    calls.add('glGetAttribLocation($program, $name)');
    return missingAttributes.contains(name) ? -1 : 0;
  }

  @override
  void glReadBuffer(int mode) => calls.add('glReadBuffer($mode)');
}
