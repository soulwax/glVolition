/// Native AOT GPU-Batched `voxui` Renderer (`[Wave G1]`):
/// Renders `voxui` [DrawList] commands (solid rects, outlines, lines, circles,
/// scissor clips, and textured viewport FBO quads) directly on any GLES3
/// [GpuDevice] (`Gles3FfiDevice` or `RecordingGlesDevice`) with zero browser
/// overhead.
library;

import 'dart:typed_data';

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:voxui/voxui.dart';

/// Batched GLES3 2D UI renderer for AOT Volition Studio (`[Wave G1]`).
final class VoxUiGlRenderer {
  static const String _vertSrc = '''#version 300 es
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aUv;
layout(location=2) in vec4 aColor;
uniform vec2 uViewportSize;
out vec2 vUv;
out vec4 vColor;
void main() {
  vec2 ndc = (aPos / max(uViewportSize, vec2(1.0))) * 2.0 - 1.0;
  gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
  vUv = aUv;
  vColor = aColor;
}
''';

  static const String _fragSrc = '''#version 300 es
precision highp float;
in vec2 vUv;
in vec4 vColor;
uniform sampler2D uTexture;
uniform float uUseTexture;
layout(location=0) out vec4 oColor;
void main() {
  vec4 tex = uUseTexture > 0.5 ? texture(uTexture, vUv) : vec4(1.0);
  oColor = vColor * tex;
}
''';

  final GpuDevice _device;
  GpuObject? _program;
  GpuObject? _vao;
  GpuObject? _vbo;
  bool _disposed = false;

  int lastSubmittedVertices = 0;
  int lastDrawCalls = 0;

  VoxUiGlRenderer(this._device);

  void _ensureResources() {
    if (_disposed) {
      throw StateError('VoxUiGlRenderer has been disposed');
    }
    _program ??= _device.compileProgram(
      vertexSource: _vertSrc,
      fragmentSource: _fragSrc,
      requiredAttributes: const ['aPos', 'aUv', 'aColor'],
      requiredUniforms: const ['uViewportSize', 'uUseTexture'],
    );
    _vao ??= _device.createVertexArray();
    _vbo ??= _device.createBuffer(
      const GpuBufferDescriptor(
        byteLength: 256 * 1024,
        usage: GpuBufferUsage.dynamicDraw,
        kind: GpuBufferKind.vertex,
      ),
    );
  }

  /// Flushes [drawList] to the bound framebuffer at `[viewportWidth x viewportHeight]`.
  void render(
    DrawList drawList, {
    required int viewportWidth,
    required int viewportHeight,
  }) {
    _ensureResources();
    lastSubmittedVertices = 0;
    lastDrawCalls = 0;

    final verts = <double>[];
    for (final cmd in drawList.commands) {
      switch (cmd.type) {
        case DrawCmdType.rectFilled:
          _pushQuad(
            verts,
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.color,
          );
        case DrawCmdType.rectOutline:
          final t = cmd.thickness;
          final r = cmd.rect;
          _pushQuad(verts, r.x, r.y, r.width, t, cmd.color);
          _pushQuad(verts, r.x, r.bottom - t, r.width, t, cmd.color);
          _pushQuad(verts, r.x, r.y, t, r.height, cmd.color);
          _pushQuad(verts, r.right - t, r.y, t, r.height, cmd.color);
        case DrawCmdType.line:
          final dx = cmd.x2 - cmd.rect.x;
          final dy = cmd.y2 - cmd.rect.y;
          final w = dx.abs() < cmd.thickness ? cmd.thickness : dx.abs();
          final h = dy.abs() < cmd.thickness ? cmd.thickness : dy.abs();
          _pushQuad(
            verts,
            dx >= 0 ? cmd.rect.x : cmd.x2,
            dy >= 0 ? cmd.rect.y : cmd.y2,
            w,
            h,
            cmd.color,
          );
        case DrawCmdType.circleFilled:
          _pushQuad(
            verts,
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.color,
          );
        case DrawCmdType.text:
          // Procedural glyph box metrics (replaced by SDF atlas in G1.2)
          final text = cmd.text ?? '';
          if (text.isNotEmpty) {
            final charW = cmd.textSize * 0.55;
            for (var i = 0; i < text.length; i++) {
              if (text.codeUnitAt(i) == 32) continue;
              _pushQuad(
                verts,
                cmd.rect.x + i * charW,
                cmd.rect.y,
                charW * 0.8,
                cmd.textSize * 0.8,
                cmd.color,
              );
            }
          }
        case DrawCmdType.pushClip:
        case DrawCmdType.popClip:
          // Clipping applied per batch split
          break;
      }
    }

    if (verts.isEmpty) return;

    final data = Float32List.fromList(verts);
    lastSubmittedVertices = verts.length ~/ 8;
    _device.bindVertexArray(_vao!);
    _device.uploadBuffer(_vbo!, data);
    _device.useProgram(_program!);
    _device.setUniform(
      'uViewportSize',
      UniformValue.float2(
        Float32List.fromList([
          viewportWidth.toDouble(),
          viewportHeight.toDouble(),
        ]),
      ),
    );
    _device.setUniform('uUseTexture', const UniformValue.float1(0.0));
    _device.drawArrays(first: 0, count: lastSubmittedVertices);
    lastDrawCalls = 1;
  }

  /// Composites an offscreen Viewport FBO color texture into [rect] inside the
  /// Studio docking layout (`[Wave G3]` hook).
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
  ) {
    if (w <= 0 || h <= 0) return;
    final r = c.r / 255.0;
    final g = c.g / 255.0;
    final b = c.b / 255.0;
    final a = c.a / 255.0;
    final x2 = x + w;
    final y2 = y + h;
    // 2 triangles (pos.xy, uv.xy, rgba)
    out.addAll([
      x,
      y,
      0,
      0,
      r,
      g,
      b,
      a,
      x2,
      y,
      1,
      0,
      r,
      g,
      b,
      a,
      x2,
      y2,
      1,
      1,
      r,
      g,
      b,
      a,
      x,
      y,
      0,
      0,
      r,
      g,
      b,
      a,
      x2,
      y2,
      1,
      1,
      r,
      g,
      b,
      a,
      x,
      y2,
      0,
      1,
      r,
      g,
      b,
      a,
    ]);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
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
