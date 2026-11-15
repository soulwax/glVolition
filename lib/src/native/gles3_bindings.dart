// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_bindings.dart';
import 'native_ffi_transport.dart';

// --- GLES 3.0 / ANGLE numeric constants ---

const int GL_FALSE = 0;
const int GL_TRUE = 1;
const int GL_NONE = 0;

const int GL_DEPTH_BUFFER_BIT = 0x00000100;
const int GL_STENCIL_BUFFER_BIT = 0x00000400;
const int GL_COLOR_BUFFER_BIT = 0x00004000;

const int GL_TRIANGLES = 0x0004;

const int GL_UNSIGNED_BYTE = 0x1401;
const int GL_UNSIGNED_SHORT = 0x1403;
const int GL_UNSIGNED_INT = 0x1405;
const int GL_FLOAT = 0x1406;

const int GL_ARRAY_BUFFER = 0x8892;
const int GL_ELEMENT_ARRAY_BUFFER = 0x8893;
const int GL_STREAM_DRAW = 0x88E0;
const int GL_STATIC_DRAW = 0x88E4;
const int GL_DYNAMIC_DRAW = 0x88E8;

const int GL_TEXTURE_2D = 0x0DE1;
const int GL_TEXTURE_2D_ARRAY = 0x8C1A;
const int GL_TEXTURE0 = 0x84C0;

const int GL_COLOR = 0x1800;
const int GL_DEPTH_COMPONENT = 0x1902;
const int GL_RGBA = 0x1908;
const int GL_RGBA8 = 0x8058;
const int GL_DEPTH_COMPONENT24 = 0x81A6;

const int GL_FRAMEBUFFER = 0x8D40;
const int GL_READ_FRAMEBUFFER = 0x8CA8;
const int GL_DRAW_FRAMEBUFFER = 0x8CA9;
const int GL_RENDERBUFFER = 0x8D41;
const int GL_COLOR_ATTACHMENT0 = 0x8CE0;
const int GL_COLOR_ATTACHMENT1 = 0x8CE1;
const int GL_DEPTH_ATTACHMENT = 0x8D00;
const int GL_FRAMEBUFFER_COMPLETE = 0x8CD5;

const int GL_FRAGMENT_SHADER = 0x8B30;
const int GL_VERTEX_SHADER = 0x8B31;
const int GL_COMPILE_STATUS = 0x8B81;
const int GL_LINK_STATUS = 0x8B82;
const int GL_INFO_LOG_LENGTH = 0x8B84;

const int GL_DEPTH_TEST = 0x0B71;
const int GL_CULL_FACE = 0x0B44;
const int GL_BLEND = 0x0BE2;
const int GL_SCISSOR_TEST = 0x0C11;
const int GL_STENCIL_TEST = 0x0B90;

const int GL_FRONT = 0x0404;
const int GL_BACK = 0x0405;
const int GL_CW = 0x0900;
const int GL_CCW = 0x0901;

const int GL_NEVER = 0x0200;
const int GL_LESS = 0x0201;
const int GL_LEQUAL = 0x0203;
const int GL_ALWAYS = 0x0207;

const int GL_ZERO = 0;
const int GL_ONE = 1;
const int GL_SRC_COLOR = 0x0300;
const int GL_SRC_ALPHA = 0x0302;
const int GL_ONE_MINUS_SRC_ALPHA = 0x0303;
const int GL_DST_ALPHA = 0x0304;
const int GL_ONE_MINUS_DST_ALPHA = 0x0305;

const int GL_FUNC_ADD = 0x8006;
const int GL_FUNC_SUBTRACT = 0x800A;
const int GL_FUNC_REVERSE_SUBTRACT = 0x800B;

const int GL_TEXTURE_MAG_FILTER = 0x2800;
const int GL_TEXTURE_MIN_FILTER = 0x2801;
const int GL_TEXTURE_WRAP_S = 0x2802;
const int GL_TEXTURE_WRAP_T = 0x2803;
const int GL_NEAREST = 0x2600;
const int GL_LINEAR = 0x2601;
const int GL_LINEAR_MIPMAP_LINEAR = 0x2703;
const int GL_REPEAT = 0x2901;
const int GL_CLAMP_TO_EDGE = 0x812F;

const int GL_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FE;
const int GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FF;

const int GL_TIME_ELAPSED_EXT = 0x88BF;
const int GL_GPU_DISJOINT_EXT = 0x8FBB;
const int GL_QUERY_RESULT = 0x8866;
const int GL_QUERY_RESULT_AVAILABLE = 0x8867;

const int GL_VENDOR = 0x1F00;
const int GL_RENDERER = 0x1F01;
const int GL_VERSION = 0x1F02;
const int GL_EXTENSIONS = 0x1F03;
const int GL_NUM_EXTENSIONS = 0x821D;

const int GL_MAX_TEXTURE_SIZE = 0x0D33;
const int GL_MAX_VERTEX_ATTRIBS = 0x8869;
const int GL_MAX_ARRAY_TEXTURE_LAYERS = 0x88FF;
const int GL_MAX_COLOR_ATTACHMENTS = 0x8CDF;
const int GL_MAX_SAMPLES = 0x8D57;

/// Abstracts OpenGL ES 3.0 / ANGLE entrypoints without exposing raw `dart:ffi`
/// pointers so hardware FFI bindings and deterministic VM test doubles can be
/// swapped cleanly behind [Gles3FfiDevice].
abstract interface class Gles3Api {
  String? glGetString(int name);
  int glGetIntegerv(int pname);
  double glGetFloatv(int pname);

  List<int> glGenBuffers(int count);
  void glDeleteBuffers(List<int> buffers);
  void glBindBuffer(int target, int buffer);
  void glBufferData(int target, int sizeBytes, TypedData? data, int usage);
  void glBufferSubData(
    int target,
    int offsetBytes,
    int sizeBytes,
    TypedData data,
  );

  List<int> glGenVertexArrays(int count);
  void glDeleteVertexArrays(List<int> arrays);
  void glBindVertexArray(int array);
  void glEnableVertexAttribArray(int index);
  void glVertexAttribPointer(
    int index,
    int size,
    int type,
    bool normalized,
    int stride,
    int offsetBytes,
  );
  void glVertexAttribDivisor(int index, int divisor);

  List<int> glGenTextures(int count);
  void glDeleteTextures(List<int> textures);
  void glBindTexture(int target, int texture);
  void glActiveTexture(int texture);
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
  );
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
  );
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
  );
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
  );
  void glGenerateMipmap(int target);
  void glTexParameteri(int target, int pname, int param);
  void glTexParameterf(int target, int pname, double param);

  List<int> glGenFramebuffers(int count);
  void glDeleteFramebuffers(List<int> framebuffers);
  void glBindFramebuffer(int target, int framebuffer);
  void glFramebufferTexture2D(
    int target,
    int attachment,
    int textarget,
    int texture,
    int level,
  );

  List<int> glGenRenderbuffers(int count);
  void glDeleteRenderbuffers(List<int> renderbuffers);
  void glBindRenderbuffer(int target, int renderbuffer);
  void glRenderbufferStorage(
    int target,
    int internalFormat,
    int width,
    int height,
  );
  void glRenderbufferStorageMultisample(
    int target,
    int samples,
    int internalFormat,
    int width,
    int height,
  );
  void glFramebufferRenderbuffer(
    int target,
    int attachment,
    int renderbuffertarget,
    int renderbuffer,
  );
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
  );
  int glCheckFramebufferStatus(int target);
  void glDrawBuffers(List<int> bufs);

  int glCreateShader(int type);
  void glDeleteShader(int shader);
  void glShaderSource(int shader, String source);
  void glCompileShader(int shader);
  int glGetShaderiv(int shader, int pname);
  String glGetShaderInfoLog(int shader);

  int glCreateProgram();
  void glDeleteProgram(int program);
  void glAttachShader(int program, int shader);
  void glLinkProgram(int program);
  int glGetProgramiv(int program, int pname);
  String glGetProgramInfoLog(int program);
  void glUseProgram(int program);
  int glGetUniformLocation(int program, String name);
  void glUniform1i(int location, int v0);
  void glUniform1f(int location, double v0);
  void glUniform2fv(int location, int count, Float32List value);
  void glUniform3fv(int location, int count, Float32List value);
  void glUniform4fv(int location, int count, Float32List value);
  void glUniformMatrix4fv(
    int location,
    int count,
    bool transpose,
    Float32List value,
  );

  void glViewport(int x, int y, int width, int height);
  void glScissor(int x, int y, int width, int height);
  void glEnable(int cap);
  void glDisable(int cap);
  void glDepthMask(bool flag);
  void glDepthFunc(int func);
  void glBlendFunc(int sfactor, int dfactor);
  void glBlendEquation(int mode);
  void glCullFace(int mode);
  void glFrontFace(int mode);
  void glColorMask(bool red, bool green, bool blue, bool alpha);
  void glClearColor(double red, double green, double blue, double alpha);
  void glClear(int mask);
  void glClearBufferfv(int buffer, int drawbuffer, Float32List value);

  void glDrawArrays(int mode, int first, int count);
  void glDrawArraysInstanced(int mode, int first, int count, int instanceCount);
  void glDrawElements(int mode, int count, int type, int offsetBytes);
  void glDrawElementsInstanced(
    int mode,
    int count,
    int type,
    int offsetBytes,
    int instanceCount,
  );
  Uint8List glReadPixels(
    int x,
    int y,
    int width,
    int height,
    int format,
    int type,
  );

  List<int> glGenQueries(int count);
  void glDeleteQueries(List<int> ids);
  void glBeginQuery(int target, int id);
  void glEndQuery(int target);
  int glGetQueryObjectuiv(int id, int pname);
  int glGetQueryObjectui64v(int id, int pname);
}

/// Optional supplementary GLES 3.0 entrypoints used by [Gles3FfiDevice] when
/// available on the underlying driver (e.g. [FfiGles3Api]).
abstract interface class Gles3ExtensionsApi {
  int glGetAttribLocation(int program, String name);
  void glReadBuffer(int mode);
  String? glGetStringi(int name, int index);
}

// --- Native FFI function typedefs ---

typedef _GlGetStringNative = ffi.Pointer<ffi.Uint8> Function(ffi.Uint32);
typedef _GlGetStringDart = ffi.Pointer<ffi.Uint8> Function(int);

typedef _GlGetStringiNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Uint32, ffi.Uint32);
typedef _GlGetStringiDart = ffi.Pointer<ffi.Uint8> Function(int, int);

typedef _GlGetIntegervNative =
    ffi.Void Function(ffi.Uint32, ffi.Pointer<ffi.Int32>);
typedef _GlGetIntegervDart = void Function(int, ffi.Pointer<ffi.Int32>);

typedef _GlGetFloatvNative =
    ffi.Void Function(ffi.Uint32, ffi.Pointer<ffi.Float>);
typedef _GlGetFloatvDart = void Function(int, ffi.Pointer<ffi.Float>);

typedef _GlGenIdsNative = ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Uint32>);
typedef _GlGenIdsDart = void Function(int, ffi.Pointer<ffi.Uint32>);

typedef _GlDeleteIdsNative =
    ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Uint32>);
typedef _GlDeleteIdsDart = void Function(int, ffi.Pointer<ffi.Uint32>);

typedef _GlUintUintNative = ffi.Void Function(ffi.Uint32, ffi.Uint32);
typedef _GlUintUintDart = void Function(int, int);

typedef _GlUintNative = ffi.Void Function(ffi.Uint32);
typedef _GlUintDart = void Function(int);

typedef _GlUintReturnUintNative = ffi.Uint32 Function(ffi.Uint32);
typedef _GlUintReturnUintDart = int Function(int);

typedef _GlBufferDataNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
    );
typedef _GlBufferDataDart = void Function(int, int, ffi.Pointer<ffi.Void>, int);

typedef _GlBufferSubDataNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.IntPtr,
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlBufferSubDataDart =
    void Function(int, int, int, ffi.Pointer<ffi.Void>);

typedef _GlVertexAttribPointerNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint8,
      ffi.Int32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlVertexAttribPointerDart =
    void Function(int, int, int, int, int, ffi.Pointer<ffi.Void>);

typedef _GlTexImage2DNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlTexImage2DDart =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    );

typedef _GlTexSubImage2DNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlTexSubImage2DDart =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    );

typedef _GlTexImage3DNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlTexImage3DDart =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    );

typedef _GlTexSubImage3DNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlTexSubImage3DDart =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    );

typedef _GlTexParameteriNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Int32);
typedef _GlTexParameteriDart = void Function(int, int, int);

typedef _GlTexParameterfNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Float);
typedef _GlTexParameterfDart = void Function(int, int, double);

typedef _GlFramebufferTexture2DNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Int32,
    );
typedef _GlFramebufferTexture2DDart = void Function(int, int, int, int, int);

typedef _GlRenderbufferStorageNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Int32, ffi.Int32);
typedef _GlRenderbufferStorageDart = void Function(int, int, int, int);

typedef _GlRenderbufferStorageMultisampleNative =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Uint32, ffi.Int32, ffi.Int32);
typedef _GlRenderbufferStorageMultisampleDart =
    void Function(int, int, int, int, int);

typedef _GlFramebufferRenderbufferNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Uint32);
typedef _GlFramebufferRenderbufferDart = void Function(int, int, int, int);

typedef _GlBlitFramebufferNative =
    ffi.Void Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
    );
typedef _GlBlitFramebufferDart =
    void Function(int, int, int, int, int, int, int, int, int, int);

typedef _GlShaderSourceNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Int32>,
    );
typedef _GlShaderSourceDart =
    void Function(
      int,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Int32>,
    );

typedef _GlGetivNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Int32>);
typedef _GlGetivDart = void Function(int, int, ffi.Pointer<ffi.Int32>);

typedef _GlGetInfoLogNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Pointer<ffi.Int32>,
      ffi.Pointer<ffi.Uint8>,
    );
typedef _GlGetInfoLogDart =
    void Function(int, int, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Uint8>);

typedef _GlCreateProgramNative = ffi.Uint32 Function();
typedef _GlCreateProgramDart = int Function();

typedef _GlGetLocationNative =
    ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Uint8>);
typedef _GlGetLocationDart = int Function(int, ffi.Pointer<ffi.Uint8>);

typedef _GlUniform1iNative = ffi.Void Function(ffi.Int32, ffi.Int32);
typedef _GlUniform1iDart = void Function(int, int);

typedef _GlUniform1fNative = ffi.Void Function(ffi.Int32, ffi.Float);
typedef _GlUniform1fDart = void Function(int, double);

typedef _GlUniformVecFvNative =
    ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Float>);
typedef _GlUniformVecFvDart = void Function(int, int, ffi.Pointer<ffi.Float>);

typedef _GlUniformMatrix4fvNative =
    ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Uint8, ffi.Pointer<ffi.Float>);
typedef _GlUniformMatrix4fvDart =
    void Function(int, int, int, ffi.Pointer<ffi.Float>);

typedef _GlRectIntNative =
    ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _GlRectIntDart = void Function(int, int, int, int);

typedef _GlBool1Native = ffi.Void Function(ffi.Uint8);
typedef _GlBool1Dart = void Function(int);

typedef _GlBool4Native =
    ffi.Void Function(ffi.Uint8, ffi.Uint8, ffi.Uint8, ffi.Uint8);
typedef _GlBool4Dart = void Function(int, int, int, int);

typedef _GlClearColorNative =
    ffi.Void Function(ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _GlClearColorDart = void Function(double, double, double, double);

typedef _GlClearBufferfvNative =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Pointer<ffi.Float>);
typedef _GlClearBufferfvDart = void Function(int, int, ffi.Pointer<ffi.Float>);

typedef _GlDrawArraysNative =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Int32);
typedef _GlDrawArraysDart = void Function(int, int, int);

typedef _GlDrawArraysInstancedNative =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _GlDrawArraysInstancedDart = void Function(int, int, int, int);

typedef _GlDrawElementsNative =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Uint32, ffi.Pointer<ffi.Void>);
typedef _GlDrawElementsDart =
    void Function(int, int, int, ffi.Pointer<ffi.Void>);

typedef _GlDrawElementsInstancedNative =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
    );
typedef _GlDrawElementsInstancedDart =
    void Function(int, int, int, ffi.Pointer<ffi.Void>, int);

typedef _GlReadPixelsNative =
    ffi.Void Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlReadPixelsDart =
    void Function(int, int, int, int, int, int, ffi.Pointer<ffi.Void>);

typedef _GlGetQueryObjectuivNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Uint32>);
typedef _GlGetQueryObjectuivDart =
    void Function(int, int, ffi.Pointer<ffi.Uint32>);

typedef _GlGetQueryObjectui64vNative =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Uint64>);
typedef _GlGetQueryObjectui64vDart =
    void Function(int, int, ffi.Pointer<ffi.Uint64>);

/// Core GLES 3.0 entrypoint names checked by [FfiGles3Api.validateRequiredSymbols].
const List<String> requiredGles3Symbols = <String>[
  'glGetString',
  'glGetIntegerv',
  'glGetFloatv',
  'glGenBuffers',
  'glDeleteBuffers',
  'glBindBuffer',
  'glBufferData',
  'glBufferSubData',
  'glGenVertexArrays',
  'glDeleteVertexArrays',
  'glBindVertexArray',
  'glEnableVertexAttribArray',
  'glVertexAttribPointer',
  'glVertexAttribDivisor',
  'glGenTextures',
  'glDeleteTextures',
  'glBindTexture',
  'glActiveTexture',
  'glTexImage2D',
  'glTexSubImage2D',
  'glTexImage3D',
  'glTexSubImage3D',
  'glGenerateMipmap',
  'glTexParameteri',
  'glTexParameterf',
  'glGenFramebuffers',
  'glDeleteFramebuffers',
  'glBindFramebuffer',
  'glFramebufferTexture2D',
  'glGenRenderbuffers',
  'glDeleteRenderbuffers',
  'glBindRenderbuffer',
  'glRenderbufferStorage',
  'glRenderbufferStorageMultisample',
  'glFramebufferRenderbuffer',
  'glBlitFramebuffer',
  'glCheckFramebufferStatus',
  'glDrawBuffers',
  'glCreateShader',
  'glDeleteShader',
  'glShaderSource',
  'glCompileShader',
  'glGetShaderiv',
  'glGetShaderInfoLog',
  'glCreateProgram',
  'glDeleteProgram',
  'glAttachShader',
  'glLinkProgram',
  'glGetProgramiv',
  'glGetProgramInfoLog',
  'glUseProgram',
  'glGetUniformLocation',
  'glUniform1i',
  'glUniform1f',
  'glUniform2fv',
  'glUniform3fv',
  'glUniform4fv',
  'glUniformMatrix4fv',
  'glViewport',
  'glScissor',
  'glEnable',
  'glDisable',
  'glDepthMask',
  'glDepthFunc',
  'glBlendFunc',
  'glBlendEquation',
  'glCullFace',
  'glFrontFace',
  'glColorMask',
  'glClearColor',
  'glClear',
  'glClearBufferfv',
  'glDrawArrays',
  'glDrawArraysInstanced',
  'glDrawElements',
  'glDrawElementsInstanced',
  'glReadPixels',
  'glGenQueries',
  'glDeleteQueries',
  'glBeginQuery',
  'glEndQuery',
  'glGetQueryObjectuiv',
];

/// `dart:ffi` implementation of [Gles3Api] and [Gles3ExtensionsApi] resolving
/// OpenGL ES 3.0 / ANGLE entrypoints dynamically via [GlProcBindings].
final class FfiGles3Api implements Gles3Api, Gles3ExtensionsApi {
  final GlProcBindings bindings;
  final NativeCAllocator _allocator;

  FfiGles3Api(this.bindings, {NativeCAllocator? allocator})
    : _allocator = allocator ?? NativeCAllocator.instance;

  /// Returns `true` when [name] resolves to a non-zero native function pointer.
  bool hasSymbol(String name) =>
      bindings.isLoaded &&
      bindings.hasSymbol(name) &&
      bindings.lookupAddress(name) != 0;

  /// Resolves [name] (or optional [fallback]) via [bindings], throwing a
  /// descriptive [StateError] when missing instead of calling address `0`.
  int resolveAddress(String name, [String? fallback]) {
    if (!bindings.isLoaded) {
      throw StateError(
        'FfiGles3Api: GL proc bindings are not loaded; cannot resolve "$name"',
      );
    }
    var addr = bindings.lookupAddress(name);
    if (addr == 0 && fallback != null) {
      addr = bindings.lookupAddress(fallback);
    }
    if (addr == 0) {
      throw StateError(
        'FfiGles3Api: missing required GLES3 symbol "$name" '
        '(library: ${bindings.libraryName ?? "unknown"})',
      );
    }
    return addr;
  }

  /// Validates that all core GLES 3.0 symbols in [requiredGles3Symbols] can be
  /// resolved through [bindings], throwing [StateError] if any are absent.
  void validateRequiredSymbols() {
    if (!bindings.isLoaded) {
      throw StateError(
        'FfiGles3Api: GL proc bindings are not loaded '
        '(library: ${bindings.libraryName ?? "unknown"})',
      );
    }
    final missing = <String>[];
    for (final name in requiredGles3Symbols) {
      if (bindings.lookupAddress(name) == 0) {
        missing.add(name);
      }
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'FfiGles3Api: missing required GLES3 symbols '
        '(${missing.length}): ${missing.join(', ')}',
      );
    }
  }

  // --- Lazy resolved native function handles ---

  late final _GlGetStringDart _fnGlGetString =
      ffi.Pointer<ffi.NativeFunction<_GlGetStringNative>>.fromAddress(
        resolveAddress('glGetString'),
      ).asFunction<_GlGetStringDart>();

  late final _GlGetStringiDart _fnGlGetStringi =
      ffi.Pointer<ffi.NativeFunction<_GlGetStringiNative>>.fromAddress(
        resolveAddress('glGetStringi'),
      ).asFunction<_GlGetStringiDart>();

  late final _GlGetIntegervDart _fnGlGetIntegerv =
      ffi.Pointer<ffi.NativeFunction<_GlGetIntegervNative>>.fromAddress(
        resolveAddress('glGetIntegerv'),
      ).asFunction<_GlGetIntegervDart>();

  late final _GlGetFloatvDart _fnGlGetFloatv =
      ffi.Pointer<ffi.NativeFunction<_GlGetFloatvNative>>.fromAddress(
        resolveAddress('glGetFloatv'),
      ).asFunction<_GlGetFloatvDart>();

  late final _GlGenIdsDart _fnGlGenBuffers =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenBuffers'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteBuffers =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteBuffers'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintUintDart _fnGlBindBuffer =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBindBuffer'),
      ).asFunction<_GlUintUintDart>();

  late final _GlBufferDataDart _fnGlBufferData =
      ffi.Pointer<ffi.NativeFunction<_GlBufferDataNative>>.fromAddress(
        resolveAddress('glBufferData'),
      ).asFunction<_GlBufferDataDart>();

  late final _GlBufferSubDataDart _fnGlBufferSubData =
      ffi.Pointer<ffi.NativeFunction<_GlBufferSubDataNative>>.fromAddress(
        resolveAddress('glBufferSubData'),
      ).asFunction<_GlBufferSubDataDart>();

  late final _GlGenIdsDart _fnGlGenVertexArrays =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenVertexArrays'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteVertexArrays =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteVertexArrays'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintDart _fnGlBindVertexArray =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glBindVertexArray'),
      ).asFunction<_GlUintDart>();

  late final _GlUintDart _fnGlEnableVertexAttribArray =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glEnableVertexAttribArray'),
      ).asFunction<_GlUintDart>();

  late final _GlVertexAttribPointerDart _fnGlVertexAttribPointer =
      ffi.Pointer<ffi.NativeFunction<_GlVertexAttribPointerNative>>.fromAddress(
        resolveAddress('glVertexAttribPointer'),
      ).asFunction<_GlVertexAttribPointerDart>();

  late final _GlUintUintDart _fnGlVertexAttribDivisor =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glVertexAttribDivisor'),
      ).asFunction<_GlUintUintDart>();

  late final _GlGenIdsDart _fnGlGenTextures =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenTextures'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteTextures =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteTextures'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintUintDart _fnGlBindTexture =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBindTexture'),
      ).asFunction<_GlUintUintDart>();

  late final _GlUintDart _fnGlActiveTexture =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glActiveTexture'),
      ).asFunction<_GlUintDart>();

  late final _GlTexImage2DDart _fnGlTexImage2D =
      ffi.Pointer<ffi.NativeFunction<_GlTexImage2DNative>>.fromAddress(
        resolveAddress('glTexImage2D'),
      ).asFunction<_GlTexImage2DDart>();

  late final _GlTexSubImage2DDart _fnGlTexSubImage2D =
      ffi.Pointer<ffi.NativeFunction<_GlTexSubImage2DNative>>.fromAddress(
        resolveAddress('glTexSubImage2D'),
      ).asFunction<_GlTexSubImage2DDart>();

  late final _GlTexImage3DDart _fnGlTexImage3D =
      ffi.Pointer<ffi.NativeFunction<_GlTexImage3DNative>>.fromAddress(
        resolveAddress('glTexImage3D'),
      ).asFunction<_GlTexImage3DDart>();

  late final _GlTexSubImage3DDart _fnGlTexSubImage3D =
      ffi.Pointer<ffi.NativeFunction<_GlTexSubImage3DNative>>.fromAddress(
        resolveAddress('glTexSubImage3D'),
      ).asFunction<_GlTexSubImage3DDart>();

  late final _GlUintDart _fnGlGenerateMipmap =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glGenerateMipmap'),
      ).asFunction<_GlUintDart>();

  late final _GlTexParameteriDart _fnGlTexParameteri =
      ffi.Pointer<ffi.NativeFunction<_GlTexParameteriNative>>.fromAddress(
        resolveAddress('glTexParameteri'),
      ).asFunction<_GlTexParameteriDart>();

  late final _GlTexParameterfDart _fnGlTexParameterf =
      ffi.Pointer<ffi.NativeFunction<_GlTexParameterfNative>>.fromAddress(
        resolveAddress('glTexParameterf'),
      ).asFunction<_GlTexParameterfDart>();

  late final _GlGenIdsDart _fnGlGenFramebuffers =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenFramebuffers'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteFramebuffers =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteFramebuffers'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintUintDart _fnGlBindFramebuffer =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBindFramebuffer'),
      ).asFunction<_GlUintUintDart>();

  late final _GlFramebufferTexture2DDart _fnGlFramebufferTexture2D =
      ffi.Pointer<
            ffi.NativeFunction<_GlFramebufferTexture2DNative>
          >.fromAddress(resolveAddress('glFramebufferTexture2D'))
          .asFunction<_GlFramebufferTexture2DDart>();

  late final _GlGenIdsDart _fnGlGenRenderbuffers =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenRenderbuffers'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteRenderbuffers =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteRenderbuffers'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintUintDart _fnGlBindRenderbuffer =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBindRenderbuffer'),
      ).asFunction<_GlUintUintDart>();

  late final _GlRenderbufferStorageDart _fnGlRenderbufferStorage =
      ffi.Pointer<ffi.NativeFunction<_GlRenderbufferStorageNative>>.fromAddress(
        resolveAddress('glRenderbufferStorage'),
      ).asFunction<_GlRenderbufferStorageDart>();

  late final _GlRenderbufferStorageMultisampleDart
  _fnGlRenderbufferStorageMultisample =
      ffi.Pointer<
            ffi.NativeFunction<_GlRenderbufferStorageMultisampleNative>
          >.fromAddress(resolveAddress('glRenderbufferStorageMultisample'))
          .asFunction<_GlRenderbufferStorageMultisampleDart>();

  late final _GlFramebufferRenderbufferDart _fnGlFramebufferRenderbuffer =
      ffi.Pointer<
            ffi.NativeFunction<_GlFramebufferRenderbufferNative>
          >.fromAddress(resolveAddress('glFramebufferRenderbuffer'))
          .asFunction<_GlFramebufferRenderbufferDart>();

  late final _GlBlitFramebufferDart _fnGlBlitFramebuffer =
      ffi.Pointer<ffi.NativeFunction<_GlBlitFramebufferNative>>.fromAddress(
        resolveAddress('glBlitFramebuffer'),
      ).asFunction<_GlBlitFramebufferDart>();

  late final _GlUintReturnUintDart _fnGlCheckFramebufferStatus =
      ffi.Pointer<ffi.NativeFunction<_GlUintReturnUintNative>>.fromAddress(
        resolveAddress('glCheckFramebufferStatus'),
      ).asFunction<_GlUintReturnUintDart>();

  late final _GlGenIdsDart _fnGlDrawBuffers =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glDrawBuffers'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlUintDart _fnGlReadBuffer =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glReadBuffer'),
      ).asFunction<_GlUintDart>();

  late final _GlUintReturnUintDart _fnGlCreateShader =
      ffi.Pointer<ffi.NativeFunction<_GlUintReturnUintNative>>.fromAddress(
        resolveAddress('glCreateShader'),
      ).asFunction<_GlUintReturnUintDart>();

  late final _GlUintDart _fnGlDeleteShader =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glDeleteShader'),
      ).asFunction<_GlUintDart>();

  late final _GlShaderSourceDart _fnGlShaderSource =
      ffi.Pointer<ffi.NativeFunction<_GlShaderSourceNative>>.fromAddress(
        resolveAddress('glShaderSource'),
      ).asFunction<_GlShaderSourceDart>();

  late final _GlUintDart _fnGlCompileShader =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glCompileShader'),
      ).asFunction<_GlUintDart>();

  late final _GlGetivDart _fnGlGetShaderiv =
      ffi.Pointer<ffi.NativeFunction<_GlGetivNative>>.fromAddress(
        resolveAddress('glGetShaderiv'),
      ).asFunction<_GlGetivDart>();

  late final _GlGetInfoLogDart _fnGlGetShaderInfoLog =
      ffi.Pointer<ffi.NativeFunction<_GlGetInfoLogNative>>.fromAddress(
        resolveAddress('glGetShaderInfoLog'),
      ).asFunction<_GlGetInfoLogDart>();

  late final _GlCreateProgramDart _fnGlCreateProgram =
      ffi.Pointer<ffi.NativeFunction<_GlCreateProgramNative>>.fromAddress(
        resolveAddress('glCreateProgram'),
      ).asFunction<_GlCreateProgramDart>();

  late final _GlUintDart _fnGlDeleteProgram =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glDeleteProgram'),
      ).asFunction<_GlUintDart>();

  late final _GlUintUintDart _fnGlAttachShader =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glAttachShader'),
      ).asFunction<_GlUintUintDart>();

  late final _GlUintDart _fnGlLinkProgram =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glLinkProgram'),
      ).asFunction<_GlUintDart>();

  late final _GlGetivDart _fnGlGetProgramiv =
      ffi.Pointer<ffi.NativeFunction<_GlGetivNative>>.fromAddress(
        resolveAddress('glGetProgramiv'),
      ).asFunction<_GlGetivDart>();

  late final _GlGetInfoLogDart _fnGlGetProgramInfoLog =
      ffi.Pointer<ffi.NativeFunction<_GlGetInfoLogNative>>.fromAddress(
        resolveAddress('glGetProgramInfoLog'),
      ).asFunction<_GlGetInfoLogDart>();

  late final _GlUintDart _fnGlUseProgram =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glUseProgram'),
      ).asFunction<_GlUintDart>();

  late final _GlGetLocationDart _fnGlGetUniformLocation =
      ffi.Pointer<ffi.NativeFunction<_GlGetLocationNative>>.fromAddress(
        resolveAddress('glGetUniformLocation'),
      ).asFunction<_GlGetLocationDart>();

  late final _GlGetLocationDart _fnGlGetAttribLocation =
      ffi.Pointer<ffi.NativeFunction<_GlGetLocationNative>>.fromAddress(
        resolveAddress('glGetAttribLocation'),
      ).asFunction<_GlGetLocationDart>();

  late final _GlUniform1iDart _fnGlUniform1i =
      ffi.Pointer<ffi.NativeFunction<_GlUniform1iNative>>.fromAddress(
        resolveAddress('glUniform1i'),
      ).asFunction<_GlUniform1iDart>();

  late final _GlUniform1fDart _fnGlUniform1f =
      ffi.Pointer<ffi.NativeFunction<_GlUniform1fNative>>.fromAddress(
        resolveAddress('glUniform1f'),
      ).asFunction<_GlUniform1fDart>();

  late final _GlUniformVecFvDart _fnGlUniform2fv =
      ffi.Pointer<ffi.NativeFunction<_GlUniformVecFvNative>>.fromAddress(
        resolveAddress('glUniform2fv'),
      ).asFunction<_GlUniformVecFvDart>();

  late final _GlUniformVecFvDart _fnGlUniform3fv =
      ffi.Pointer<ffi.NativeFunction<_GlUniformVecFvNative>>.fromAddress(
        resolveAddress('glUniform3fv'),
      ).asFunction<_GlUniformVecFvDart>();

  late final _GlUniformVecFvDart _fnGlUniform4fv =
      ffi.Pointer<ffi.NativeFunction<_GlUniformVecFvNative>>.fromAddress(
        resolveAddress('glUniform4fv'),
      ).asFunction<_GlUniformVecFvDart>();

  late final _GlUniformMatrix4fvDart _fnGlUniformMatrix4fv =
      ffi.Pointer<ffi.NativeFunction<_GlUniformMatrix4fvNative>>.fromAddress(
        resolveAddress('glUniformMatrix4fv'),
      ).asFunction<_GlUniformMatrix4fvDart>();

  late final _GlRectIntDart _fnGlViewport =
      ffi.Pointer<ffi.NativeFunction<_GlRectIntNative>>.fromAddress(
        resolveAddress('glViewport'),
      ).asFunction<_GlRectIntDart>();

  late final _GlRectIntDart _fnGlScissor =
      ffi.Pointer<ffi.NativeFunction<_GlRectIntNative>>.fromAddress(
        resolveAddress('glScissor'),
      ).asFunction<_GlRectIntDart>();

  late final _GlUintDart _fnGlEnable =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glEnable'),
      ).asFunction<_GlUintDart>();

  late final _GlUintDart _fnGlDisable =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glDisable'),
      ).asFunction<_GlUintDart>();

  late final _GlBool1Dart _fnGlDepthMask =
      ffi.Pointer<ffi.NativeFunction<_GlBool1Native>>.fromAddress(
        resolveAddress('glDepthMask'),
      ).asFunction<_GlBool1Dart>();

  late final _GlUintDart _fnGlDepthFunc =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glDepthFunc'),
      ).asFunction<_GlUintDart>();

  late final _GlUintUintDart _fnGlBlendFunc =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBlendFunc'),
      ).asFunction<_GlUintUintDart>();

  late final _GlUintDart _fnGlBlendEquation =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glBlendEquation'),
      ).asFunction<_GlUintDart>();

  late final _GlUintDart _fnGlCullFace =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glCullFace'),
      ).asFunction<_GlUintDart>();

  late final _GlUintDart _fnGlFrontFace =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glFrontFace'),
      ).asFunction<_GlUintDart>();

  late final _GlBool4Dart _fnGlColorMask =
      ffi.Pointer<ffi.NativeFunction<_GlBool4Native>>.fromAddress(
        resolveAddress('glColorMask'),
      ).asFunction<_GlBool4Dart>();

  late final _GlClearColorDart _fnGlClearColor =
      ffi.Pointer<ffi.NativeFunction<_GlClearColorNative>>.fromAddress(
        resolveAddress('glClearColor'),
      ).asFunction<_GlClearColorDart>();

  late final _GlUintDart _fnGlClear =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glClear'),
      ).asFunction<_GlUintDart>();

  late final _GlClearBufferfvDart _fnGlClearBufferfv =
      ffi.Pointer<ffi.NativeFunction<_GlClearBufferfvNative>>.fromAddress(
        resolveAddress('glClearBufferfv'),
      ).asFunction<_GlClearBufferfvDart>();

  late final _GlDrawArraysDart _fnGlDrawArrays =
      ffi.Pointer<ffi.NativeFunction<_GlDrawArraysNative>>.fromAddress(
        resolveAddress('glDrawArrays'),
      ).asFunction<_GlDrawArraysDart>();

  late final _GlDrawArraysInstancedDart _fnGlDrawArraysInstanced =
      ffi.Pointer<ffi.NativeFunction<_GlDrawArraysInstancedNative>>.fromAddress(
        resolveAddress('glDrawArraysInstanced'),
      ).asFunction<_GlDrawArraysInstancedDart>();

  late final _GlDrawElementsDart _fnGlDrawElements =
      ffi.Pointer<ffi.NativeFunction<_GlDrawElementsNative>>.fromAddress(
        resolveAddress('glDrawElements'),
      ).asFunction<_GlDrawElementsDart>();

  late final _GlDrawElementsInstancedDart _fnGlDrawElementsInstanced =
      ffi.Pointer<
            ffi.NativeFunction<_GlDrawElementsInstancedNative>
          >.fromAddress(resolveAddress('glDrawElementsInstanced'))
          .asFunction<_GlDrawElementsInstancedDart>();

  late final _GlReadPixelsDart _fnGlReadPixels =
      ffi.Pointer<ffi.NativeFunction<_GlReadPixelsNative>>.fromAddress(
        resolveAddress('glReadPixels'),
      ).asFunction<_GlReadPixelsDart>();

  late final _GlGenIdsDart _fnGlGenQueries =
      ffi.Pointer<ffi.NativeFunction<_GlGenIdsNative>>.fromAddress(
        resolveAddress('glGenQueries', 'glGenQueriesEXT'),
      ).asFunction<_GlGenIdsDart>();

  late final _GlDeleteIdsDart _fnGlDeleteQueries =
      ffi.Pointer<ffi.NativeFunction<_GlDeleteIdsNative>>.fromAddress(
        resolveAddress('glDeleteQueries', 'glDeleteQueriesEXT'),
      ).asFunction<_GlDeleteIdsDart>();

  late final _GlUintUintDart _fnGlBeginQuery =
      ffi.Pointer<ffi.NativeFunction<_GlUintUintNative>>.fromAddress(
        resolveAddress('glBeginQuery', 'glBeginQueryEXT'),
      ).asFunction<_GlUintUintDart>();

  late final _GlUintDart _fnGlEndQuery =
      ffi.Pointer<ffi.NativeFunction<_GlUintNative>>.fromAddress(
        resolveAddress('glEndQuery', 'glEndQueryEXT'),
      ).asFunction<_GlUintDart>();

  late final _GlGetQueryObjectuivDart _fnGlGetQueryObjectuiv =
      ffi.Pointer<ffi.NativeFunction<_GlGetQueryObjectuivNative>>.fromAddress(
        resolveAddress('glGetQueryObjectuiv', 'glGetQueryObjectuivEXT'),
      ).asFunction<_GlGetQueryObjectuivDart>();

  late final _GlGetQueryObjectui64vDart _fnGlGetQueryObjectui64v =
      ffi.Pointer<ffi.NativeFunction<_GlGetQueryObjectui64vNative>>.fromAddress(
        resolveAddress('glGetQueryObjectui64v', 'glGetQueryObjectui64vEXT'),
      ).asFunction<_GlGetQueryObjectui64vDart>();

  // --- Marshaling helpers (always release temporary C allocations) ---

  List<int> _genIds(int count, _GlGenIdsDart fn) {
    if (count <= 0) return const <int>[];
    final buf = _allocator.allocateBytes(count * 4);
    try {
      final ptr = buf.cast<ffi.Uint32>();
      fn(count, ptr);
      return List<int>.generate(count, (i) => ptr[i], growable: false);
    } finally {
      _allocator.free(buf);
    }
  }

  void _deleteIds(List<int> ids, _GlDeleteIdsDart fn) {
    if (ids.isEmpty) return;
    final buf = _allocator.allocateBytes(ids.length * 4);
    try {
      final ptr = buf.cast<ffi.Uint32>();
      for (var i = 0; i < ids.length; i++) {
        ptr[i] = ids[i];
      }
      fn(ids.length, ptr);
    } finally {
      _allocator.free(buf);
    }
  }

  R _withNativeBytes<R>(
    TypedData? data,
    int byteLength,
    R Function(ffi.Pointer<ffi.Void> ptr) action,
  ) {
    if (data == null || byteLength <= 0) {
      return action(ffi.nullptr);
    }
    if (data.lengthInBytes < byteLength) {
      throw ArgumentError.value(
        data.lengthInBytes,
        'data.lengthInBytes',
        'expected at least $byteLength bytes',
      );
    }
    final buf = _allocator.allocateBytes(byteLength);
    try {
      final src = data.buffer.asUint8List(data.offsetInBytes, byteLength);
      buf.asTypedList(byteLength).setAll(0, src);
      return action(buf.cast<ffi.Void>());
    } finally {
      _allocator.free(buf);
    }
  }

  void _withFloatSlice(
    Float32List values,
    int floatCount,
    void Function(ffi.Pointer<ffi.Float> ptr) action,
  ) {
    if (floatCount <= 0) return;
    if (values.length < floatCount) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'expected at least $floatCount floats',
      );
    }
    _withNativeBytes<void>(
      values,
      floatCount * 4,
      (ptr) => action(ptr.cast<ffi.Float>()),
    );
  }

  String _readInfoLog(
    int handle,
    int Function(int, int) getiv,
    _GlGetInfoLogDart getLog,
  ) {
    final logLen = getiv(handle, GL_INFO_LOG_LENGTH);
    if (logLen <= 1) return '';
    final buf = _allocator.allocateBytes(logLen);
    final written = _allocator.allocateBytes(4);
    try {
      getLog(handle, logLen, written.cast<ffi.Int32>(), buf);
      return _allocator.readCString(buf, maxBytes: logLen);
    } finally {
      _allocator.free(written);
      _allocator.free(buf);
    }
  }

  // --- Gles3Api implementation ---

  @override
  String? glGetString(int name) {
    final ptr = _fnGlGetString(name);
    if (ptr == ffi.nullptr) return null;
    return _allocator.readCString(ptr, maxBytes: 65536);
  }

  @override
  String? glGetStringi(int name, int index) {
    if (!hasSymbol('glGetStringi')) return null;
    final ptr = _fnGlGetStringi(name, index);
    if (ptr == ffi.nullptr) return null;
    return _allocator.readCString(ptr, maxBytes: 4096);
  }

  @override
  int glGetIntegerv(int pname) {
    final buf = _allocator.allocateBytes(16);
    try {
      final ptr = buf.cast<ffi.Int32>();
      _fnGlGetIntegerv(pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }

  @override
  double glGetFloatv(int pname) {
    final buf = _allocator.allocateBytes(16);
    try {
      final ptr = buf.cast<ffi.Float>();
      _fnGlGetFloatv(pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }

  @override
  List<int> glGenBuffers(int count) => _genIds(count, _fnGlGenBuffers);

  @override
  void glDeleteBuffers(List<int> buffers) =>
      _deleteIds(buffers, _fnGlDeleteBuffers);

  @override
  void glBindBuffer(int target, int buffer) => _fnGlBindBuffer(target, buffer);

  @override
  void glBufferData(int target, int sizeBytes, TypedData? data, int usage) {
    _withNativeBytes<void>(data, sizeBytes, (ptr) {
      _fnGlBufferData(target, sizeBytes, ptr, usage);
    });
  }

  @override
  void glBufferSubData(
    int target,
    int offsetBytes,
    int sizeBytes,
    TypedData data,
  ) {
    if (sizeBytes <= 0) return;
    _withNativeBytes<void>(data, sizeBytes, (ptr) {
      _fnGlBufferSubData(target, offsetBytes, sizeBytes, ptr);
    });
  }

  @override
  List<int> glGenVertexArrays(int count) =>
      _genIds(count, _fnGlGenVertexArrays);

  @override
  void glDeleteVertexArrays(List<int> arrays) =>
      _deleteIds(arrays, _fnGlDeleteVertexArrays);

  @override
  void glBindVertexArray(int array) => _fnGlBindVertexArray(array);

  @override
  void glEnableVertexAttribArray(int index) =>
      _fnGlEnableVertexAttribArray(index);

  @override
  void glVertexAttribPointer(
    int index,
    int size,
    int type,
    bool normalized,
    int stride,
    int offsetBytes,
  ) {
    _fnGlVertexAttribPointer(
      index,
      size,
      type,
      normalized ? GL_TRUE : GL_FALSE,
      stride,
      ffi.Pointer<ffi.Void>.fromAddress(offsetBytes),
    );
  }

  @override
  void glVertexAttribDivisor(int index, int divisor) =>
      _fnGlVertexAttribDivisor(index, divisor);

  @override
  List<int> glGenTextures(int count) => _genIds(count, _fnGlGenTextures);

  @override
  void glDeleteTextures(List<int> textures) =>
      _deleteIds(textures, _fnGlDeleteTextures);

  @override
  void glBindTexture(int target, int texture) =>
      _fnGlBindTexture(target, texture);

  @override
  void glActiveTexture(int texture) => _fnGlActiveTexture(texture);

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
  ) {
    final byteLen = pixels?.lengthInBytes ?? 0;
    _withNativeBytes<void>(pixels, byteLen, (ptr) {
      _fnGlTexImage2D(
        target,
        level,
        internalFormat,
        width,
        height,
        border,
        format,
        type,
        ptr,
      );
    });
  }

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
  ) {
    _withNativeBytes<void>(pixels, pixels.lengthInBytes, (ptr) {
      _fnGlTexSubImage2D(
        target,
        level,
        xoffset,
        yoffset,
        width,
        height,
        format,
        type,
        ptr,
      );
    });
  }

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
  ) {
    final byteLen = pixels?.lengthInBytes ?? 0;
    _withNativeBytes<void>(pixels, byteLen, (ptr) {
      _fnGlTexImage3D(
        target,
        level,
        internalFormat,
        width,
        height,
        depth,
        border,
        format,
        type,
        ptr,
      );
    });
  }

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
  ) {
    _withNativeBytes<void>(pixels, pixels.lengthInBytes, (ptr) {
      _fnGlTexSubImage3D(
        target,
        level,
        xoffset,
        yoffset,
        zoffset,
        width,
        height,
        depth,
        format,
        type,
        ptr,
      );
    });
  }

  @override
  void glGenerateMipmap(int target) => _fnGlGenerateMipmap(target);

  @override
  void glTexParameteri(int target, int pname, int param) =>
      _fnGlTexParameteri(target, pname, param);

  @override
  void glTexParameterf(int target, int pname, double param) =>
      _fnGlTexParameterf(target, pname, param);

  @override
  List<int> glGenFramebuffers(int count) =>
      _genIds(count, _fnGlGenFramebuffers);

  @override
  void glDeleteFramebuffers(List<int> framebuffers) =>
      _deleteIds(framebuffers, _fnGlDeleteFramebuffers);

  @override
  void glBindFramebuffer(int target, int framebuffer) =>
      _fnGlBindFramebuffer(target, framebuffer);

  @override
  void glFramebufferTexture2D(
    int target,
    int attachment,
    int textarget,
    int texture,
    int level,
  ) => _fnGlFramebufferTexture2D(target, attachment, textarget, texture, level);

  @override
  List<int> glGenRenderbuffers(int count) =>
      _genIds(count, _fnGlGenRenderbuffers);

  @override
  void glDeleteRenderbuffers(List<int> renderbuffers) =>
      _deleteIds(renderbuffers, _fnGlDeleteRenderbuffers);

  @override
  void glBindRenderbuffer(int target, int renderbuffer) =>
      _fnGlBindRenderbuffer(target, renderbuffer);

  @override
  void glRenderbufferStorage(
    int target,
    int internalFormat,
    int width,
    int height,
  ) => _fnGlRenderbufferStorage(target, internalFormat, width, height);

  @override
  void glRenderbufferStorageMultisample(
    int target,
    int samples,
    int internalFormat,
    int width,
    int height,
  ) => _fnGlRenderbufferStorageMultisample(
    target,
    samples,
    internalFormat,
    width,
    height,
  );

  @override
  void glFramebufferRenderbuffer(
    int target,
    int attachment,
    int renderbuffertarget,
    int renderbuffer,
  ) => _fnGlFramebufferRenderbuffer(
    target,
    attachment,
    renderbuffertarget,
    renderbuffer,
  );

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
  ) => _fnGlBlitFramebuffer(
    srcX0,
    srcY0,
    srcX1,
    srcY1,
    dstX0,
    dstY0,
    dstX1,
    dstY1,
    mask,
    filter,
  );

  @override
  int glCheckFramebufferStatus(int target) =>
      _fnGlCheckFramebufferStatus(target);

  @override
  void glDrawBuffers(List<int> bufs) => _deleteIds(bufs, _fnGlDrawBuffers);

  @override
  void glReadBuffer(int mode) {
    if (!hasSymbol('glReadBuffer')) return;
    _fnGlReadBuffer(mode);
  }

  @override
  int glCreateShader(int type) => _fnGlCreateShader(type);

  @override
  void glDeleteShader(int shader) => _fnGlDeleteShader(shader);

  @override
  void glShaderSource(int shader, String source) {
    final strPtr = _allocator.allocUtf8(source);
    final ptrArray = _allocator.allocateBytes(ffi.sizeOf<ffi.IntPtr>());
    try {
      ptrArray.cast<ffi.Pointer<ffi.Uint8>>().value = strPtr;
      _fnGlShaderSource(
        shader,
        1,
        ptrArray.cast<ffi.Pointer<ffi.Uint8>>(),
        ffi.nullptr,
      );
    } finally {
      _allocator.free(ptrArray);
      _allocator.free(strPtr);
    }
  }

  @override
  void glCompileShader(int shader) => _fnGlCompileShader(shader);

  @override
  int glGetShaderiv(int shader, int pname) {
    final buf = _allocator.allocateBytes(4);
    try {
      final ptr = buf.cast<ffi.Int32>();
      _fnGlGetShaderiv(shader, pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }

  @override
  String glGetShaderInfoLog(int shader) =>
      _readInfoLog(shader, glGetShaderiv, _fnGlGetShaderInfoLog);

  @override
  int glCreateProgram() => _fnGlCreateProgram();

  @override
  void glDeleteProgram(int program) => _fnGlDeleteProgram(program);

  @override
  void glAttachShader(int program, int shader) =>
      _fnGlAttachShader(program, shader);

  @override
  void glLinkProgram(int program) => _fnGlLinkProgram(program);

  @override
  int glGetProgramiv(int program, int pname) {
    final buf = _allocator.allocateBytes(4);
    try {
      final ptr = buf.cast<ffi.Int32>();
      _fnGlGetProgramiv(program, pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }

  @override
  String glGetProgramInfoLog(int program) =>
      _readInfoLog(program, glGetProgramiv, _fnGlGetProgramInfoLog);

  @override
  void glUseProgram(int program) => _fnGlUseProgram(program);

  @override
  int glGetUniformLocation(int program, String name) =>
      _allocator.withUtf8(name, (ptr) => _fnGlGetUniformLocation(program, ptr));

  @override
  int glGetAttribLocation(int program, String name) =>
      _allocator.withUtf8(name, (ptr) => _fnGlGetAttribLocation(program, ptr));

  @override
  void glUniform1i(int location, int v0) => _fnGlUniform1i(location, v0);

  @override
  void glUniform1f(int location, double v0) => _fnGlUniform1f(location, v0);

  @override
  void glUniform2fv(int location, int count, Float32List value) {
    _withFloatSlice(value, count * 2, (ptr) {
      _fnGlUniform2fv(location, count, ptr);
    });
  }

  @override
  void glUniform3fv(int location, int count, Float32List value) {
    _withFloatSlice(value, count * 3, (ptr) {
      _fnGlUniform3fv(location, count, ptr);
    });
  }

  @override
  void glUniform4fv(int location, int count, Float32List value) {
    _withFloatSlice(value, count * 4, (ptr) {
      _fnGlUniform4fv(location, count, ptr);
    });
  }

  @override
  void glUniformMatrix4fv(
    int location,
    int count,
    bool transpose,
    Float32List value,
  ) {
    _withFloatSlice(value, count * 16, (ptr) {
      _fnGlUniformMatrix4fv(
        location,
        count,
        transpose ? GL_TRUE : GL_FALSE,
        ptr,
      );
    });
  }

  @override
  void glViewport(int x, int y, int width, int height) =>
      _fnGlViewport(x, y, width, height);

  @override
  void glScissor(int x, int y, int width, int height) =>
      _fnGlScissor(x, y, width, height);

  @override
  void glEnable(int cap) => _fnGlEnable(cap);

  @override
  void glDisable(int cap) => _fnGlDisable(cap);

  @override
  void glDepthMask(bool flag) => _fnGlDepthMask(flag ? GL_TRUE : GL_FALSE);

  @override
  void glDepthFunc(int func) => _fnGlDepthFunc(func);

  @override
  void glBlendFunc(int sfactor, int dfactor) =>
      _fnGlBlendFunc(sfactor, dfactor);

  @override
  void glBlendEquation(int mode) => _fnGlBlendEquation(mode);

  @override
  void glCullFace(int mode) => _fnGlCullFace(mode);

  @override
  void glFrontFace(int mode) => _fnGlFrontFace(mode);

  @override
  void glColorMask(bool red, bool green, bool blue, bool alpha) =>
      _fnGlColorMask(
        red ? GL_TRUE : GL_FALSE,
        green ? GL_TRUE : GL_FALSE,
        blue ? GL_TRUE : GL_FALSE,
        alpha ? GL_TRUE : GL_FALSE,
      );

  @override
  void glClearColor(double red, double green, double blue, double alpha) =>
      _fnGlClearColor(red, green, blue, alpha);

  @override
  void glClear(int mask) => _fnGlClear(mask);

  @override
  void glClearBufferfv(int buffer, int drawbuffer, Float32List value) {
    _withFloatSlice(value, 4, (ptr) {
      _fnGlClearBufferfv(buffer, drawbuffer, ptr);
    });
  }

  @override
  void glDrawArrays(int mode, int first, int count) =>
      _fnGlDrawArrays(mode, first, count);

  @override
  void glDrawArraysInstanced(
    int mode,
    int first,
    int count,
    int instanceCount,
  ) => _fnGlDrawArraysInstanced(mode, first, count, instanceCount);

  @override
  void glDrawElements(int mode, int count, int type, int offsetBytes) =>
      _fnGlDrawElements(
        mode,
        count,
        type,
        ffi.Pointer<ffi.Void>.fromAddress(offsetBytes),
      );

  @override
  void glDrawElementsInstanced(
    int mode,
    int count,
    int type,
    int offsetBytes,
    int instanceCount,
  ) => _fnGlDrawElementsInstanced(
    mode,
    count,
    type,
    ffi.Pointer<ffi.Void>.fromAddress(offsetBytes),
    instanceCount,
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
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'FfiGles3Api.glReadPixels requires positive dimensions, '
        'got ${width}x$height',
      );
    }
    final bpp = _bytesPerPixel(format, type);
    final byteCount = width * height * bpp;
    final buf = _allocator.allocateBytes(byteCount);
    try {
      _fnGlReadPixels(x, y, width, height, format, type, buf.cast<ffi.Void>());
      return Uint8List.fromList(buf.asTypedList(byteCount));
    } finally {
      _allocator.free(buf);
    }
  }

  static int _bytesPerPixel(int format, int type) {
    if (type == GL_UNSIGNED_BYTE) {
      return format == GL_RGBA ? 4 : 1;
    }
    if (type == GL_UNSIGNED_SHORT) {
      return format == GL_RGBA ? 8 : 2;
    }
    return 4;
  }

  @override
  List<int> glGenQueries(int count) => _genIds(count, _fnGlGenQueries);

  @override
  void glDeleteQueries(List<int> ids) => _deleteIds(ids, _fnGlDeleteQueries);

  @override
  void glBeginQuery(int target, int id) => _fnGlBeginQuery(target, id);

  @override
  void glEndQuery(int target) => _fnGlEndQuery(target);

  @override
  int glGetQueryObjectuiv(int id, int pname) {
    final buf = _allocator.allocateBytes(4);
    try {
      final ptr = buf.cast<ffi.Uint32>();
      _fnGlGetQueryObjectuiv(id, pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }

  @override
  int glGetQueryObjectui64v(int id, int pname) {
    final buf = _allocator.allocateBytes(8);
    try {
      final ptr = buf.cast<ffi.Uint64>();
      _fnGlGetQueryObjectui64v(id, pname, ptr);
      return ptr.value;
    } finally {
      _allocator.free(buf);
    }
  }
}
