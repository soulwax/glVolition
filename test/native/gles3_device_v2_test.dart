/// S1-A tests: Device API v2 implementations on RecordingGlesDevice &
/// Gles3FfiDevice, plus requiredGles3Symbols FFI symbol table assertions.
library;

import 'dart:typed_data';

import 'package:gl_volition/src/native/gles3_bindings.dart';
import 'package:gl_volition/src/native/gles3_ffi_device.dart';
import 'package:gl_volition/src/native/native_host.dart';
import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:test/test.dart';

final class _RecordingGles3V2Api implements Gles3Api, Gles3V2Api {
  final List<String> calls = [];
  int _nextId = 1;

  @override
  void glBindBufferBase(int target, int index, int buffer) =>
      calls.add('glBindBufferBase($target,$index,$buffer)');

  @override
  int glGetUniformBlockIndex(int program, String uniformBlockName) {
    calls.add('glGetUniformBlockIndex($program,$uniformBlockName)');
    return 0;
  }

  @override
  void glUniformBlockBinding(
    int program,
    int uniformBlockIndex,
    int uniformBlockBinding,
  ) => calls.add(
    'glUniformBlockBinding($program,$uniformBlockIndex,$uniformBlockBinding)',
  );

  @override
  List<int> glGenBuffers(int count) => List.generate(count, (_) => _nextId++);
  @override
  void glDeleteBuffers(List<int> buffers) {}
  @override
  void glBindBuffer(int target, int buffer) =>
      calls.add('glBindBuffer($target,$buffer)');
  @override
  void glBufferData(int target, int sizeBytes, TypedData? data, int usage) =>
      calls.add('glBufferData($target,$sizeBytes)');
  @override
  void glBufferSubData(
    int target,
    int offsetBytes,
    int sizeBytes,
    TypedData data,
  ) => calls.add('glBufferSubData($target,$offsetBytes,$sizeBytes)');

  @override
  List<int> glGenTextures(int count) => List.generate(count, (_) => _nextId++);
  @override
  void glDeleteTextures(List<int> textures) {}
  @override
  void glBindTexture(int target, int texture) =>
      calls.add('glBindTexture($target,$texture)');
  @override
  void glActiveTexture(int texture) => calls.add('glActiveTexture($texture)');
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
  ) => calls.add('glTexImage2D($target,$internalFormat,${width}x$height)');
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
  ) => calls.add('glTexSubImage2D($target,$level)');
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
  ) => calls.add(
    'glTexImage3D($target,$internalFormat,${width}x${height}x$depth)',
  );
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
  ) => calls.add('glTexSubImage3D($target,$zoffset)');
  @override
  void glGenerateMipmap(int target) {}
  @override
  void glTexParameteri(int target, int pname, int param) {}
  @override
  void glTexParameterf(int target, int pname, double param) {}

  @override
  List<int> glGenFramebuffers(int count) =>
      List.generate(count, (_) => _nextId++);
  @override
  void glDeleteFramebuffers(List<int> framebuffers) {}
  @override
  void glBindFramebuffer(int target, int framebuffer) {}
  @override
  void glFramebufferTexture2D(
    int target,
    int attachment,
    int textarget,
    int texture,
    int level,
  ) => calls.add('glFramebufferTexture2D($attachment,$texture)');
  @override
  int glCheckFramebufferStatus(int target) => GL_FRAMEBUFFER_COMPLETE;
  @override
  void glDrawBuffers(List<int> bufs) =>
      calls.add('glDrawBuffers(${bufs.length})');

  @override
  List<int> glGenQueries(int count) => List.generate(count, (_) => _nextId++);
  @override
  void glDeleteQueries(List<int> ids) => calls.add('glDeleteQueries');
  @override
  void glBeginQuery(int target, int id) => calls.add('glBeginQuery($target)');
  @override
  void glEndQuery(int target) => calls.add('glEndQuery($target)');
  @override
  int glGetQueryObjectuiv(int id, int pname) => 1;
  @override
  int glGetQueryObjectui64v(int id, int pname) => 500000;

  @override
  String? glGetString(int name) => 'GL_EXT_disjoint_timer_query';
  @override
  int glGetIntegerv(int pname) => 4096;
  @override
  double glGetFloatv(int pname) => 16.0;
  @override
  List<int> glGenVertexArrays(int count) => [_nextId++];
  @override
  void glDeleteVertexArrays(List<int> arrays) {}
  @override
  void glBindVertexArray(int array) {}
  @override
  void glEnableVertexAttribArray(int index) {}
  @override
  void glVertexAttribPointer(
    int index,
    int size,
    int type,
    bool normalized,
    int stride,
    int offsetBytes,
  ) {}
  @override
  void glVertexAttribDivisor(int index, int divisor) {}
  @override
  List<int> glGenRenderbuffers(int count) => [_nextId++];
  @override
  void glDeleteRenderbuffers(List<int> renderbuffers) {}
  @override
  void glBindRenderbuffer(int target, int renderbuffer) {}
  @override
  void glRenderbufferStorage(int target, int internalFormat, int w, int h) {}
  @override
  void glRenderbufferStorageMultisample(
    int target,
    int samples,
    int internalFormat,
    int w,
    int h,
  ) {}
  @override
  void glFramebufferRenderbuffer(
    int target,
    int attachment,
    int renderbuffertarget,
    int renderbuffer,
  ) {}
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
  ) {}
  @override
  int glCreateShader(int type) => _nextId++;
  @override
  void glDeleteShader(int shader) {}
  @override
  void glShaderSource(int shader, String source) {}
  @override
  void glCompileShader(int shader) {}
  @override
  int glGetShaderiv(int shader, int pname) => GL_TRUE;
  @override
  String glGetShaderInfoLog(int shader) => '';
  @override
  int glCreateProgram() => _nextId++;
  @override
  void glDeleteProgram(int program) {}
  @override
  void glAttachShader(int program, int shader) {}
  @override
  void glLinkProgram(int program) {}
  @override
  int glGetProgramiv(int program, int pname) => GL_TRUE;
  @override
  String glGetProgramInfoLog(int shader) => '';
  @override
  void glUseProgram(int program) {}
  @override
  int glGetUniformLocation(int program, String name) => 0;
  @override
  void glUniform1i(int location, int v0) {}
  @override
  void glUniform1f(int location, double v0) {}
  @override
  void glUniform2fv(int location, int count, Float32List value) {}
  @override
  void glUniform3fv(int location, int count, Float32List value) {}
  @override
  void glUniform4fv(int location, int count, Float32List value) {}
  @override
  void glUniformMatrix4fv(
    int location,
    int count,
    bool transpose,
    Float32List value,
  ) {}
  @override
  void glViewport(int x, int y, int width, int height) {}
  @override
  void glScissor(int x, int y, int width, int height) {}
  @override
  void glEnable(int cap) {}
  @override
  void glDisable(int cap) {}
  @override
  void glDepthMask(bool flag) {}
  @override
  void glDepthFunc(int func) {}
  @override
  void glBlendFunc(int sfactor, int dfactor) {}
  @override
  void glBlendEquation(int mode) {}
  @override
  void glCullFace(int mode) {}
  @override
  void glFrontFace(int mode) {}
  @override
  void glColorMask(bool red, bool green, bool blue, bool alpha) {}
  @override
  void glClearColor(double red, double green, double blue, double alpha) {}
  @override
  void glClear(int mask) {}
  @override
  void glClearBufferfv(int buffer, int drawbuffer, Float32List value) {}
  @override
  void glDrawArrays(int mode, int first, int count) {}
  @override
  void glDrawArraysInstanced(
    int mode,
    int first,
    int count,
    int instanceCount,
  ) {}
  @override
  void glDrawElements(int mode, int count, int type, int offsetBytes) {}
  @override
  void glDrawElementsInstanced(
    int mode,
    int count,
    int type,
    int offsetBytes,
    int instanceCount,
  ) {}
  @override
  Uint8List glReadPixels(int x, int y, int w, int h, int format, int type) =>
      Uint8List(w * h * 4);
}

void main() {
  group('S1-A — FFI Symbol Table & GpuDeviceV2 Implementations', () {
    test('requiredGles3Symbols includes all Device API v2 entrypoints', () {
      expect(
        requiredGles3Symbols,
        containsAll([
          'glBindBufferBase',
          'glGetUniformBlockIndex',
          'glUniformBlockBinding',
          'glTexImage3D',
          'glDrawBuffers',
          'glVertexAttribDivisor',
          'glBeginQuery',
        ]),
      );
    });

    test(
      'RecordingGlesDevice records all Device API v2 commands deterministically',
      () {
        final commands = <String>[];
        final device = RecordingGlesDevice(
          onCommand: (cmd, args) => commands.add(cmd),
        );

        final ubo = device.createUniformBuffer(
          const GpuUniformBufferDescriptor(byteLength: 256),
        );
        device.updateUniformBuffer(ubo, ByteData(64));
        device.bindUniformBufferBase(0, ubo);

        final prog = device.compileProgram(
          vertexSource: '#version 300 es\nvoid main(){}',
          fragmentSource: '#version 300 es\nvoid main(){}',
          requiredAttributes: const [],
          requiredUniforms: const [],
        );
        device.uniformBlockBinding(prog, 'FrameBlock', 0);

        final cube = device.createCubeTexture(
          const GpuCubeTextureDescriptor(
            size: 32,
            format: GpuTextureFormat.rgba16f,
          ),
        );
        device.uploadCubeFaceFloat(
          cube,
          GpuCubeFace.positiveX,
          Float32List(32 * 32 * 4),
        );
        device.bindCubeTexture(2, cube);

        final arr = device.createTextureArray(
          const GpuTextureArrayDescriptor(width: 16, height: 16, layers: 4),
        );
        device.uploadTextureArrayLayer(arr, 1, Uint8List(16 * 16 * 4));
        device.bindTextureArray(3, arr);

        final mrt = device.createMrtTarget(
          const GpuMrtTargetDescriptor(
            width: 320,
            height: 180,
            colorFormats: [
              GpuColorTargetFormat.rgba16f,
              GpuColorTargetFormat.rgba8,
            ],
          ),
        );
        device.drawBuffers([0, 1]);
        device.bindTargetColorAttachment(4, mrt, 1);

        final occ = device.beginOcclusionQuery()!;
        device.endOcclusionQuery(occ);
        final poll = device.pollOcclusionQuery(occ);
        expect(poll.status, equals(GpuOcclusionQueryStatus.ready));
        expect(poll.anySamplesPassed, isTrue);
        device.deleteOcclusionQuery(occ);

        final scope = device.beginPassTimer('shadow_pass')!;
        expect(scope.passName, equals('shadow_pass'));
        device.endPassTimer(scope);

        expect(
          commands,
          containsAll([
            'createUniformBuffer',
            'updateUniformBuffer',
            'bindUniformBufferBase',
            'uniformBlockBinding',
            'createCubeTexture',
            'uploadCubeFaceFloat',
            'bindCubeTexture',
            'createTextureArray',
            'uploadTextureArrayLayer',
            'bindTextureArray',
            'createMrtTarget',
            'drawBuffers',
            'bindTargetColorAttachment',
            'beginOcclusionQuery',
            'endOcclusionQuery',
            'deleteOcclusionQuery',
            'beginPassTimer',
            'endPassTimer',
          ]),
        );
      },
    );

    test(
      'Gles3FfiDevice dispatches v2 calls with UBO & texture state caching',
      () {
        final api = _RecordingGles3V2Api();
        final device = Gles3FfiDevice(api);

        final ubo = device.createUniformBuffer(
          const GpuUniformBufferDescriptor(byteLength: 128),
        );
        device.updateUniformBuffer(ubo, ByteData(128));
        device.bindUniformBufferBase(0, ubo);
        // Second identical bind should be deduplicated by WebGlStateCache
        device.bindUniformBufferBase(0, ubo);

        final prog = device.compileProgram(
          vertexSource: '#version 300 es\nvoid main(){}',
          fragmentSource: '#version 300 es\nvoid main(){}',
          requiredAttributes: const [],
          requiredUniforms: const [],
        );
        device.uniformBlockBinding(prog, 'FrameBlock', 0);

        final cube = device.createCubeTexture(
          const GpuCubeTextureDescriptor(size: 16),
        );
        device.uploadCubeFace(
          cube,
          GpuCubeFace.negativeZ,
          Uint8List(16 * 16 * 4),
        );
        device.bindCubeTexture(1, cube);
        device.bindCubeTexture(1, cube); // cached

        final arr = device.createTextureArray(
          const GpuTextureArrayDescriptor(width: 8, height: 8, layers: 2),
        );
        device.uploadTextureArrayLayer(arr, 0, Uint8List(8 * 8 * 4));
        device.bindTextureArray(2, arr);

        final mrt = device.createMrtTarget(
          const GpuMrtTargetDescriptor(
            width: 64,
            height: 64,
            colorFormats: [GpuColorTargetFormat.rgba16f],
          ),
        );
        device.drawBuffers([0]);
        device.bindTargetColorAttachment(3, mrt, 0);

        final occ = device.beginOcclusionQuery()!;
        device.endOcclusionQuery(occ);
        final poll = device.pollOcclusionQuery(occ);
        expect(poll.status, equals(GpuOcclusionQueryStatus.ready));
        expect(poll.anySamplesPassed, isTrue);
        device.deleteOcclusionQuery(occ);

        // Assert deduplication: glBindBufferBase called once for bindingPoint 0
        expect(
          api.calls.where((c) => c.startsWith('glBindBufferBase(')).length,
          equals(1),
        );
        expect(api.calls, contains('glUniformBlockBinding(4,0,0)'));
        expect(
          api.calls.any(
            (c) => c.startsWith('glTexImage3D($GL_TEXTURE_2D_ARRAY'),
          ),
          isTrue,
        );
        expect(
          api.calls,
          contains('glBeginQuery($GL_ANY_SAMPLES_PASSED_CONSERVATIVE)'),
        );
      },
    );
  });
}
