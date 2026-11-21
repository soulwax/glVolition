/// Native AOT GPU-Batched `voxui` Renderer (`[Wave G1]` / `[Wave G3]`):
/// Renders `voxui` [DrawList] commands (solid rects, outlines, lines, circles,
/// crisp built-in 5×7 ASCII bitmap font atlas, and offscreen viewport FBO
/// quads) directly on any GLES3 [GpuDevice] with zero browser overhead.
library;

import 'dart:typed_data';

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';
import 'package:voxui/voxui.dart';

/// Compact 5×7 ASCII (32..126) bitmap font rasterizer for zero-dependency AOT
/// native Studio text rendering (`[Wave G3]`).
abstract final class StudioBitmapFontAtlas {
  static const int atlasWidth = 128;
  static const int atlasHeight = 64;
  static const int cols = 16;
  static const int cellW = 8;
  static const int cellH = 8;

  // Compact 5-bit-wide x 7-row glyphs for printable ASCII (32..95 uppercase +
  // digits + punctuation; lowercase maps to crisp glyphs).
  static const Map<int, List<int>> _glyphRows = {
    33: [4, 4, 4, 4, 4, 0, 4], // !
    35: [10, 31, 10, 10, 31, 10, 0], // #
    40: [2, 4, 8, 8, 8, 4, 2], // (
    41: [8, 4, 2, 2, 2, 4, 8], // )
    43: [0, 4, 4, 31, 4, 4, 0], // +
    44: [0, 0, 0, 0, 4, 4, 8], // ,
    45: [0, 0, 0, 31, 0, 0, 0], // -
    46: [0, 0, 0, 0, 0, 4, 4], // .
    47: [1, 2, 2, 4, 8, 8, 16], // /
    48: [14, 17, 19, 21, 25, 17, 14], // 0
    49: [4, 12, 4, 4, 4, 4, 14], // 1
    50: [14, 17, 1, 6, 8, 16, 31], // 2
    51: [14, 17, 1, 6, 1, 17, 14], // 3
    52: [2, 6, 10, 18, 31, 2, 2], // 4
    53: [31, 16, 30, 1, 1, 17, 14], // 5
    54: [6, 8, 16, 30, 17, 17, 14], // 6
    55: [31, 1, 2, 4, 8, 8, 8], // 7
    56: [14, 17, 17, 14, 17, 17, 14], // 8
    57: [14, 17, 17, 15, 1, 2, 12], // 9
    58: [0, 4, 4, 0, 4, 4, 0], // :
    65: [14, 17, 17, 31, 17, 17, 17], // A
    66: [30, 17, 17, 30, 17, 17, 30], // B
    67: [14, 17, 16, 16, 16, 17, 14], // C
    68: [28, 18, 17, 17, 17, 18, 28], // D
    69: [31, 16, 16, 30, 16, 16, 31], // E
    70: [31, 16, 16, 30, 16, 16, 16], // F
    71: [14, 17, 16, 23, 17, 17, 15], // G
    72: [17, 17, 17, 31, 17, 17, 17], // H
    73: [14, 4, 4, 4, 4, 4, 14], // I
    74: [7, 2, 2, 2, 18, 18, 12], // J
    75: [17, 18, 20, 24, 20, 18, 17], // K
    76: [16, 16, 16, 16, 16, 16, 31], // L
    77: [17, 27, 21, 21, 17, 17, 17], // M
    78: [17, 25, 21, 19, 17, 17, 17], // N
    79: [14, 17, 17, 17, 17, 17, 14], // O
    80: [30, 17, 17, 30, 16, 16, 16], // P
    81: [14, 17, 17, 17, 21, 18, 13], // Q
    82: [30, 17, 17, 30, 20, 18, 17], // R
    83: [14, 17, 16, 14, 1, 17, 14], // S
    84: [31, 4, 4, 4, 4, 4, 4], // T
    85: [17, 17, 17, 17, 17, 17, 14], // U
    86: [17, 17, 17, 17, 17, 10, 4], // V
    87: [17, 17, 17, 21, 21, 27, 17], // W
    88: [17, 17, 10, 4, 10, 17, 17], // X
    89: [17, 17, 10, 4, 4, 4, 4], // Y
    90: [31, 1, 2, 4, 8, 16, 31], // Z
    91: [14, 8, 8, 8, 8, 8, 14], // [
    92: [16, 8, 8, 4, 2, 2, 1], // \
    93: [14, 2, 2, 2, 2, 2, 14], // ]
    95: [0, 0, 0, 0, 0, 0, 31], // _
    60: [2, 4, 8, 16, 8, 4, 2], // <
    61: [0, 0, 31, 0, 31, 0, 0], // =
    62: [8, 4, 2, 1, 2, 4, 8], // >
    63: [14, 17, 1, 2, 4, 0, 4], // ?
    97: [0, 0, 14, 1, 15, 17, 15], // a
    98: [16, 16, 22, 25, 17, 17, 30], // b
    99: [0, 0, 14, 16, 16, 17, 14], // c
    100: [1, 1, 13, 19, 17, 17, 15], // d
    101: [0, 0, 14, 17, 31, 16, 14], // e
    102: [6, 9, 8, 28, 8, 8, 8], // f
    103: [0, 0, 15, 17, 15, 1, 14], // g
    104: [16, 16, 22, 25, 17, 17, 17], // h
    105: [4, 0, 12, 4, 4, 4, 14], // i
    106: [2, 0, 6, 2, 2, 18, 12], // j
    107: [16, 16, 18, 20, 24, 20, 18], // k
    108: [12, 4, 4, 4, 4, 4, 14], // l
    109: [0, 0, 26, 21, 21, 21, 17], // m
    110: [0, 0, 22, 25, 17, 17, 17], // n
    111: [0, 0, 14, 17, 17, 17, 14], // o
    112: [0, 0, 30, 17, 30, 16, 16], // p
    113: [0, 0, 13, 19, 15, 1, 1], // q
    114: [0, 0, 22, 25, 16, 16, 16], // r
    115: [0, 0, 14, 16, 14, 1, 30], // s
    116: [8, 8, 28, 8, 8, 9, 6], // t
    117: [0, 0, 17, 17, 17, 19, 13], // u
    118: [0, 0, 17, 17, 17, 10, 4], // v
    119: [0, 0, 17, 17, 21, 21, 10], // w
    120: [0, 0, 17, 10, 4, 10, 17], // x
    121: [0, 0, 17, 17, 15, 1, 14], // y
    122: [0, 0, 31, 2, 4, 8, 31], // z
    124: [4, 4, 4, 4, 4, 4, 4], // |
  };

  /// Rasterizes the 128×64 RGBA8 font atlas buffer with distinct mixed-case
  /// (`A-Z`, `a-z`), digits, and punctuation glyphs.
  static Uint8List buildRgba8Atlas() {
    final pixels = Uint8List(atlasWidth * atlasHeight * 4);
    for (var code = 32; code < 128; code++) {
      final idx = code - 32;
      final cx = (idx % cols) * cellW;
      final cy = (idx ~/ cols) * cellH;
      final rows = _glyphRows[code];
      if (rows == null) continue;
      for (var ry = 0; ry < 7; ry++) {
        final bits = rows[ry];
        for (var rx = 0; rx < 5; rx++) {
          if ((bits & (1 << (4 - rx))) != 0) {
            final px = cx + rx + 1;
            final py = cy + ry;
            final o = (py * atlasWidth + px) * 4;
            pixels[o + 0] = 255;
            pixels[o + 1] = 255;
            pixels[o + 2] = 255;
            pixels[o + 3] = 255;
          }
        }
      }
    }
    return pixels;
  }

  static (double u0, double v0, double u1, double v1) uvForChar(int codeUnit) {
    final clamped = (codeUnit >= 32 && codeUnit < 128) ? codeUnit : 63;
    final idx = clamped - 32;
    final cx = (idx % cols) * cellW;
    final cy = (idx ~/ cols) * cellH;
    return (
      cx / atlasWidth,
      cy / atlasHeight,
      (cx + cellW) / atlasWidth,
      (cy + cellH) / atlasHeight,
    );
  }
}

/// Batched GLES3 2D UI renderer for AOT Volition Studio (`[Wave G1]` / `[Wave G3]`).
final class VoxUiGlRenderer {
  static const String _vertSrc = '''#version 300 es
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aUv;
layout(location=2) in vec4 aColor;
uniform vec2 uViewportSize;
out vec2 vUv;
out vec4 vColor;
out vec2 vScreenPos;
void main() {
  vec2 ndc = (aPos / max(uViewportSize, vec2(1.0))) * 2.0 - 1.0;
  gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
  vUv = aUv;
  vColor = aColor;
  vScreenPos = aPos;
}
''';

  static const String _fragSrc = '''#version 300 es
precision highp float;
in vec2 vUv;
in vec4 vColor;
in vec2 vScreenPos;
uniform sampler2D uTexture;
uniform float uUseTexture;
uniform vec4 uClipRect;
layout(location=0) out vec4 oColor;
void main() {
  if (vScreenPos.x < uClipRect.x || vScreenPos.y < uClipRect.y ||
      vScreenPos.x > uClipRect.z || vScreenPos.y > uClipRect.w) {
    discard;
  }
  vec4 tex = uUseTexture > 0.5 ? texture(uTexture, vUv) : vec4(1.0);
  oColor = vColor * tex;
}
''';

  static const DrawStateDescriptor _uiDrawState = DrawStateDescriptor(
    depthTest: false,
    depthWrite: false,
    blendEnable: true,
    blendSrc: BlendFactor.srcAlpha,
    blendDst: BlendFactor.oneMinusSrcAlpha,
    cullEnable: false,
  );

  final GpuDevice _device;
  GpuObject? _program;
  GpuObject? _vao;
  GpuObject? _vbo;
  GpuObject? _fontAtlasTex;
  bool _disposed = false;

  int lastSubmittedVertices = 0;
  int lastTextVertices = 0;
  int lastDrawCalls = 0;
  int lastClipBatchCount = 0;

  VoxUiGlRenderer(this._device);

  void _ensureResources() {
    if (_disposed) {
      throw StateError('VoxUiGlRenderer has been disposed');
    }
    _program ??= _device.compileProgram(
      vertexSource: _vertSrc,
      fragmentSource: _fragSrc,
      requiredAttributes: const ['aPos', 'aUv', 'aColor'],
      requiredUniforms: const ['uViewportSize', 'uUseTexture', 'uClipRect'],
    );
    _vao ??= _device.createVertexArray();
    _vbo ??= _device.createBuffer(
      const GpuBufferDescriptor(
        byteLength: 256 * 1024,
        usage: GpuBufferUsage.dynamicDraw,
        kind: GpuBufferKind.vertex,
      ),
    );
    _device.bindVertexArray(_vao!);
    _device.bindArrayBuffer(_vbo!);
    const stride = 8 * 4; // 2 pos + 2 uv + 4 color
    _device.enableVertexAttribArray(0);
    _device.vertexAttribPointer(
      location: 0,
      componentCount: 2,
      strideBytes: stride,
      offsetBytes: 0,
    );
    _device.enableVertexAttribArray(1);
    _device.vertexAttribPointer(
      location: 1,
      componentCount: 2,
      strideBytes: stride,
      offsetBytes: 8,
    );
    _device.enableVertexAttribArray(2);
    _device.vertexAttribPointer(
      location: 2,
      componentCount: 4,
      strideBytes: stride,
      offsetBytes: 16,
    );
    if (_fontAtlasTex == null) {
      _fontAtlasTex = _device.createTexture(
        const GpuTextureDescriptor(
          width: StudioBitmapFontAtlas.atlasWidth,
          height: StudioBitmapFontAtlas.atlasHeight,
          minFilter: GpuTextureFilter.nearest,
          magFilter: GpuTextureFilter.nearest,
        ),
      );
      _device.uploadTextureLayer(
        _fontAtlasTex!,
        0,
        StudioBitmapFontAtlas.buildRgba8Atlas(),
      );
    }
  }

  /// Flushes [drawList] to the bound framebuffer at `[viewportWidth x viewportHeight]`
  /// with exact clip-rect batching for `pushClip` / `popClip`.
  void render(
    DrawList drawList, {
    required int viewportWidth,
    required int viewportHeight,
    bool resetStats = true,
  }) {
    _ensureResources();
    if (resetStats) {
      lastSubmittedVertices = 0;
      lastTextVertices = 0;
      lastDrawCalls = 0;
      lastClipBatchCount = 0;
    }

    final fullClip = VoxRect(
      0,
      0,
      viewportWidth.toDouble(),
      viewportHeight.toDouble(),
    );
    final clipStack = <VoxRect>[fullClip];
    final solidVerts = <double>[];
    final textVerts = <double>[];

    final vpUniform = UniformValue.float2(
      Float32List.fromList([
        viewportWidth.toDouble(),
        viewportHeight.toDouble(),
      ]),
    );

    void flushCurrentBatch() {
      if (solidVerts.isEmpty && textVerts.isEmpty) return;
      final activeClip = clipStack.last;
      final clipUniform = UniformValue.float4(
        Float32List.fromList([
          activeClip.x,
          activeClip.y,
          activeClip.right,
          activeClip.bottom,
        ]),
      );
      _device.applyDrawState(_uiDrawState);
      lastClipBatchCount++;

      if (solidVerts.isNotEmpty) {
        final data = Float32List.fromList(solidVerts);
        final count = solidVerts.length ~/ 8;
        lastSubmittedVertices += count;
        _device.bindVertexArray(_vao!);
        _device.uploadBuffer(_vbo!, data);
        _device.useProgram(_program!);
        _device.setUniform('uViewportSize', vpUniform);
        _device.setUniform('uClipRect', clipUniform);
        _device.setUniform('uUseTexture', const UniformValue.float1(0.0));
        _device.drawArrays(first: 0, count: count);
        lastDrawCalls++;
        solidVerts.clear();
      }

      if (textVerts.isNotEmpty) {
        final data = Float32List.fromList(textVerts);
        final count = textVerts.length ~/ 8;
        lastTextVertices += count;
        _device.bindVertexArray(_vao!);
        _device.uploadBuffer(_vbo!, data);
        _device.useProgram(_program!);
        _device.bindTexture(0, _fontAtlasTex!);
        _device.setUniform('uViewportSize', vpUniform);
        _device.setUniform('uClipRect', clipUniform);
        _device.setUniform('uUseTexture', const UniformValue.float1(1.0));
        _device.drawArrays(first: 0, count: count);
        lastDrawCalls++;
        textVerts.clear();
      }
    }

    for (final cmd in drawList.commands) {
      switch (cmd.type) {
        case DrawCmdType.rectFilled:
          _pushQuad(
            solidVerts,
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.color,
          );
        case DrawCmdType.rectOutline:
          final t = cmd.thickness;
          final r = cmd.rect;
          _pushQuad(solidVerts, r.x, r.y, r.width, t, cmd.color);
          _pushQuad(solidVerts, r.x, r.bottom - t, r.width, t, cmd.color);
          _pushQuad(solidVerts, r.x, r.y, t, r.height, cmd.color);
          _pushQuad(solidVerts, r.right - t, r.y, t, r.height, cmd.color);
        case DrawCmdType.line:
          final dx = cmd.x2 - cmd.rect.x;
          final dy = cmd.y2 - cmd.rect.y;
          final w = dx.abs() < cmd.thickness ? cmd.thickness : dx.abs();
          final h = dy.abs() < cmd.thickness ? cmd.thickness : dy.abs();
          _pushQuad(
            solidVerts,
            dx >= 0 ? cmd.rect.x : cmd.x2,
            dy >= 0 ? cmd.rect.y : cmd.y2,
            w,
            h,
            cmd.color,
          );
        case DrawCmdType.circleFilled:
          _pushQuad(
            solidVerts,
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.color,
          );
        case DrawCmdType.text:
          final text = cmd.text ?? '';
          if (text.isNotEmpty) {
            final charW = cmd.textSize * 0.62;
            final charH = cmd.textSize * 0.95;
            for (var i = 0; i < text.length; i++) {
              final cu = text.codeUnitAt(i);
              if (cu == 32) continue;
              final (u0, v0, u1, v1) = StudioBitmapFontAtlas.uvForChar(cu);
              _pushQuadUv(
                textVerts,
                cmd.rect.x + i * charW,
                cmd.rect.y,
                charW,
                charH,
                u0,
                v0,
                u1,
                v1,
                cmd.color,
              );
            }
          }
        case DrawCmdType.pushClip:
          flushCurrentBatch();
          clipStack.add(cmd.rect);
        case DrawCmdType.popClip:
          flushCurrentBatch();
          if (clipStack.length > 1) {
            clipStack.removeLast();
          }
      }
    }

    flushCurrentBatch();
  }

  /// Composites an offscreen Viewport FBO color texture into [rect] inside the
  /// Studio docking layout (`[Wave G3]`).
  void compositeViewportTexture({
    required GpuObject colorTexture,
    required VoxRect rect,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    _ensureResources();
    final verts = <double>[];
    _pushQuad(verts, rect.x, rect.y, rect.width, rect.height, VoxColor.white);
    final data = Float32List.fromList(verts);
    _device.applyDrawState(_uiDrawState);
    _device.bindVertexArray(_vao!);
    _device.uploadBuffer(_vbo!, data);
    _device.useProgram(_program!);
    _device.bindTexture(0, colorTexture);
    _device.setUniform(
      'uViewportSize',
      UniformValue.float2(
        Float32List.fromList([
          viewportWidth.toDouble(),
          viewportHeight.toDouble(),
        ]),
      ),
    );
    _device.setUniform(
      'uClipRect',
      UniformValue.float4(
        Float32List.fromList([
          0.0,
          0.0,
          viewportWidth.toDouble(),
          viewportHeight.toDouble(),
        ]),
      ),
    );
    _device.setUniform('uUseTexture', const UniformValue.float1(1.0));
    _device.drawArrays(first: 0, count: 6);
    lastDrawCalls++;
  }

  void _pushQuad(
    List<double> out,
    double x,
    double y,
    double w,
    double h,
    VoxColor c,
  ) => _pushQuadUv(out, x, y, w, h, 0, 0, 1, 1, c);

  void _pushQuadUv(
    List<double> out,
    double x,
    double y,
    double w,
    double h,
    double u0,
    double v0,
    double u1,
    double v1,
    VoxColor c,
  ) {
    if (w <= 0 || h <= 0) return;
    final r = c.r / 255.0;
    final g = c.g / 255.0;
    final b = c.b / 255.0;
    final a = c.a / 255.0;
    final x2 = x + w;
    final y2 = y + h;
    out.addAll([
      x,
      y,
      u0,
      v0,
      r,
      g,
      b,
      a,
      x2,
      y,
      u1,
      v0,
      r,
      g,
      b,
      a,
      x2,
      y2,
      u1,
      v1,
      r,
      g,
      b,
      a,
      x,
      y,
      u0,
      v0,
      r,
      g,
      b,
      a,
      x2,
      y2,
      u1,
      v1,
      r,
      g,
      b,
      a,
      x,
      y2,
      u0,
      v1,
      r,
      g,
      b,
      a,
    ]);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_fontAtlasTex != null) {
      _device.deleteTexture(_fontAtlasTex!);
      _fontAtlasTex = null;
    }
    if (_vbo != null) {
      _device.deleteBuffer(_vbo!);
      _vbo = null;
    }
    if (_vao != null) {
      _device.deleteVertexArray(_vao!);
      _vao = null;
    }
    if (_program != null) {
      _device.deleteProgram(_program!);
      _program = null;
    }
  }
}
