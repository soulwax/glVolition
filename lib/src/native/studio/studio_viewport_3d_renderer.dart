/// Native AOT Live 3D Scene & Game Viewport Renderer (`[Wave G6]`):
/// Renders the active [Scene] directly into the bound offscreen GLES3 FBO for
/// both the docked **Scene View** (editor camera, XZ ground grid, shaded 3D
/// scene objects, selection highlight, and 3D X/Y/Z transform gizmo axes) and
/// the docked **Game View** (active scene [Camera] + fixed-step Play Mode).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pixeldart/rendering/webgl/device_api.dart';
import 'package:pixeldart/rendering/webgl/state_cache.dart';

import '../../../gl_volition.dart';
import '../../studio/studio.dart';
import 'viewport_fbo_host.dart';

/// Live GLES3 3D renderer for docked Studio Scene & Game FBOs (`[Wave G6]`).
final class StudioViewport3DRenderer {
  static const String _vertSrc = '''#version 300 es
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec4 aColor;
uniform mat4 uViewProj;
out vec3 vNormal;
out vec4 vColor;
void main() {
  gl_Position = uViewProj * vec4(aPos, 1.0);
  vNormal = aNormal;
  vColor = aColor;
}
''';

  static const String _fragSrc = '''#version 300 es
precision highp float;
in vec3 vNormal;
in vec4 vColor;
layout(location=0) out vec4 oColor;
void main() {
  vec3 n = normalize(vNormal);
  vec3 keyDir = normalize(vec3(0.45, 0.85, 0.35));
  vec3 fillDir = normalize(vec3(-0.6, 0.3, -0.5));
  float ndl = max(dot(n, keyDir), 0.0) * 0.72 + max(dot(n, fillDir), 0.0) * 0.22 + 0.22;
  vec3 lit = vColor.rgb * min(ndl, 1.15);
  oColor = vec4(lit, vColor.a);
}
''';

  static const DrawStateDescriptor _drawState3D = DrawStateDescriptor(
    depthTest: true,
    depthFunc: DepthFunc.lessEqual,
    depthWrite: true,
    blendEnable: true,
    blendSrc: BlendFactor.srcAlpha,
    blendDst: BlendFactor.oneMinusSrcAlpha,
    cullEnable: false,
  );

  final GpuDevice _device;
  GpuObject? _program;
  GpuObject? _vao;
  GpuObject? _vbo;
  bool _disposed = false;

  int lastSceneVertices = 0;
  int lastSceneDrawCalls = 0;
  int lastGameVertices = 0;
  int lastGameDrawCalls = 0;

  StudioViewport3DRenderer(this._device);

  void _ensureResources() {
    if (_disposed) {
      throw StateError('StudioViewport3DRenderer has been disposed');
    }
    _program ??= _device.compileProgram(
      vertexSource: _vertSrc,
      fragmentSource: _fragSrc,
      requiredAttributes: const ['aPos', 'aNormal', 'aColor'],
      requiredUniforms: const ['uViewProj'],
    );
    _vao ??= _device.createVertexArray();
    _vbo ??= _device.createBuffer(
      const GpuBufferDescriptor(
        byteLength: 512 * 1024,
        usage: GpuBufferUsage.dynamicDraw,
        kind: GpuBufferKind.vertex,
      ),
    );
    _device.bindVertexArray(_vao!);
    _device.bindArrayBuffer(_vbo!);
    const stride = 10 * 4; // 3 pos + 3 normal + 4 color
    _device.enableVertexAttribArray(0);
    _device.vertexAttribPointer(
      location: 0,
      componentCount: 3,
      strideBytes: stride,
      offsetBytes: 0,
    );
    _device.enableVertexAttribArray(1);
    _device.vertexAttribPointer(
      location: 1,
      componentCount: 3,
      strideBytes: stride,
      offsetBytes: 12,
    );
    _device.enableVertexAttribArray(2);
    _device.vertexAttribPointer(
      location: 2,
      componentCount: 4,
      strideBytes: stride,
      offsetBytes: 24,
    );
  }

  /// Renders either the `scene` or `game` viewport into the currently bound
  /// offscreen [fbo].
  void renderViewport({
    required StudioWorkspaceShell shell,
    required StudioViewportSlot slot,
    required ViewportFboEntry fbo,
  }) {
    _ensureResources();
    final isScene = slot.panelId == 'scene';
    final aspect = fbo.height > 0 ? fbo.width / fbo.height : 16.0 / 9.0;
    final scene = shell.bridge.session.engine.scene;
    final verts = <double>[];

    final Mat4 viewProj;
    if (isScene) {
      final cam = shell.sceneViewport.editorCamera;
      final view = Mat4.lookAt(
        eye: cam.position,
        forward: cam.forward,
        up: const Vec3(0, 1, 0),
      );
      final proj = Mat4.perspective(
        fovYRadians: cam.fovYRadians,
        aspect: aspect,
        near: cam.nearPlane,
        far: cam.farPlane,
      );
      viewProj = proj * view;

      if (shell.sceneGridVisible) {
        _emitGroundGrid(verts, centerX: cam.target.x, centerZ: cam.target.z);
      }
    } else {
      viewProj = _resolveGameCameraViewProj(scene, aspect);
    }

    final selectedSet = shell.bridge.session.selectedObjects.toSet();
    final allObjects = <GameObject>[];
    void collect(List<GameObject> nodes) {
      for (final go in nodes) {
        if (!go.activeInHierarchy) continue;
        allObjects.add(go);
        if (go.children.isNotEmpty) collect(go.children);
      }
    }

    collect(scene.rootGameObjects);

    for (final go in allObjects) {
      final isSelected = isScene && selectedSet.contains(go);
      final isLight = go.getComponent<Light>() != null;
      final isCam = go.getComponent<Camera>() != null;
      final (r, g, b) = isSelected
          ? (0.95, 0.58, 0.18)
          : isLight
          ? (0.98, 0.88, 0.35)
          : isCam
          ? (0.35, 0.72, 0.96)
          : (0.58, 0.64, 0.74);
      final halfExt = isLight || isCam ? 0.35 : 0.5;
      final w = go.transform.world;
      final st = go.transform.localStretch;
      final worldMatrix = Mat4.compose(
        tx: w.translation.x,
        ty: w.translation.y,
        tz: w.translation.z,
        qx: w.rotation.x,
        qy: w.rotation.y,
        qz: w.rotation.z,
        qw: w.rotation.w,
        sx: w.scale * st.x,
        sy: w.scale * st.y,
        sz: w.scale * st.z,
      );
      _emitShadedBox(
        verts,
        worldMatrix: worldMatrix,
        halfExtent: halfExt,
        r: r,
        g: g,
        b: b,
        a: 1.0,
      );
    }

    if (isScene && shell.sceneGizmosVisible && selectedSet.isNotEmpty) {
      final anchor = selectedSet.first.transform.position;
      final highlightAxis = shell.gizmoInteractor.activeAxis != GizmoAxis.none
          ? shell.gizmoInteractor.activeAxis
          : shell.gizmoInteractor.hoveredAxis;
      _emitTransformGizmo(
        verts,
        anchor,
        length: 1.35,
        highlightAxis: highlightAxis,
      );
    }

    final vertexCount = verts.length ~/ 10;
    if (vertexCount == 0) {
      if (isScene) {
        lastSceneVertices = 0;
        lastSceneDrawCalls = 0;
      } else {
        lastGameVertices = 0;
        lastGameDrawCalls = 0;
      }
      return;
    }

    _device.applyDrawState(_drawState3D);
    _device.bindVertexArray(_vao!);
    _device.uploadBuffer(_vbo!, Float32List.fromList(verts));
    _device.useProgram(_program!);
    _device.setUniform('uViewProj', UniformValue.mat4(viewProj.m));
    _device.drawArrays(first: 0, count: vertexCount);

    if (isScene) {
      lastSceneVertices = vertexCount;
      lastSceneDrawCalls = 1;
    } else {
      lastGameVertices = vertexCount;
      lastGameDrawCalls = 1;
    }
  }

  Mat4 _resolveGameCameraViewProj(Scene scene, double aspect) {
    final cameras = scene.sortedActiveCameras;
    if (cameras.isNotEmpty) {
      final cam = cameras.first;
      final eye = cam.gameObject.transform.position;
      final view = Mat4.lookAt(
        eye: eye,
        forward: cam.gameObject.transform.forward,
        up: const Vec3(0, 1, 0),
      );
      final proj = Mat4.perspective(
        fovYRadians: cam.fovYRadians,
        aspect: aspect,
        near: cam.near,
        far: cam.far,
      );
      return proj * view;
    }
    final view = Mat4.lookAt(
      eye: const Vec3(0, 3.0, 8.0),
      forward: const Vec3(0, -3.0, -8.0).normalized,
      up: const Vec3(0, 1, 0),
    );
    final proj = Mat4.perspective(
      fovYRadians: math.pi / 3.0,
      aspect: aspect,
      near: 0.1,
      far: 500.0,
    );
    return proj * view;
  }

  void _emitGroundGrid(
    List<double> out, {
    required double centerX,
    required double centerZ,
    int halfLines = 10,
    double spacing = 1.0,
  }) {
    final snapX = (centerX / spacing).round() * spacing;
    final snapZ = (centerZ / spacing).round() * spacing;
    final extent = halfLines * spacing;
    const thick = 0.018;

    for (var i = -halfLines; i <= halfLines; i++) {
      final x = snapX + i * spacing;
      final z = snapZ + i * spacing;
      final isAxisZ = x.abs() < 1e-4;
      final isAxisX = z.abs() < 1e-4;

      // Line parallel to Z at X = x
      _emitHorizontalStrip(
        out,
        x0: x - thick,
        z0: snapZ - extent,
        x1: x + thick,
        z1: snapZ + extent,
        r: isAxisZ ? 0.25 : 0.30,
        g: isAxisZ ? 0.45 : 0.32,
        b: isAxisZ ? 0.85 : 0.36,
        a: isAxisZ ? 0.85 : 0.45,
      );
      // Line parallel to X at Z = z
      _emitHorizontalStrip(
        out,
        x0: snapX - extent,
        z0: z - thick,
        x1: snapX + extent,
        z1: z + thick,
        r: isAxisX ? 0.85 : 0.30,
        g: isAxisX ? 0.28 : 0.32,
        b: isAxisX ? 0.28 : 0.36,
        a: isAxisX ? 0.85 : 0.45,
      );
    }
  }

  void _emitHorizontalStrip(
    List<double> out, {
    required double x0,
    required double z0,
    required double x1,
    required double z1,
    required double r,
    required double g,
    required double b,
    required double a,
  }) {
    _pushTri(
      out,
      Vec3(x0, 0, z0),
      Vec3(x1, 0, z0),
      Vec3(x1, 0, z1),
      const Vec3(0, 1, 0),
      r,
      g,
      b,
      a,
    );
    _pushTri(
      out,
      Vec3(x0, 0, z0),
      Vec3(x1, 0, z1),
      Vec3(x0, 0, z1),
      const Vec3(0, 1, 0),
      r,
      g,
      b,
      a,
    );
  }

  void _emitTransformGizmo(
    List<double> out,
    Vec3 origin, {
    double length = 1.35,
    GizmoAxis highlightAxis = GizmoAxis.none,
  }) {
    const t = 0.045;
    final xHi = highlightAxis == GizmoAxis.x;
    final yHi = highlightAxis == GizmoAxis.y;
    final zHi = highlightAxis == GizmoAxis.z;
    // X axis (Red -> Yellow on hover/drag)
    _emitWorldAxisBox(
      out,
      origin + Vec3(length * 0.5, 0, 0),
      Vec3(length * 0.5, t, t),
      xHi ? 1.0 : 0.95,
      xHi ? 0.92 : 0.24,
      xHi ? 0.18 : 0.22,
    );
    // Y axis (Green -> Yellow on hover/drag)
    _emitWorldAxisBox(
      out,
      origin + Vec3(0, length * 0.5, 0),
      Vec3(t, length * 0.5, t),
      yHi ? 1.0 : 0.26,
      yHi ? 0.92 : 0.88,
      yHi ? 0.18 : 0.32,
    );
    // Z axis (Blue -> Yellow on hover/drag)
    _emitWorldAxisBox(
      out,
      origin + Vec3(0, 0, length * 0.5),
      Vec3(t, t, length * 0.5),
      zHi ? 1.0 : 0.24,
      zHi ? 0.92 : 0.52,
      zHi ? 0.18 : 0.96,
    );
  }

  void _emitWorldAxisBox(
    List<double> out,
    Vec3 center,
    Vec3 half,
    double r,
    double g,
    double b,
  ) {
    final m = Mat4.compose(
      tx: center.x,
      ty: center.y,
      tz: center.z,
      sx: half.x * 2.0,
      sy: half.y * 2.0,
      sz: half.z * 2.0,
    );
    _emitShadedBox(
      out,
      worldMatrix: m,
      halfExtent: 0.5,
      r: r,
      g: g,
      b: b,
      a: 1.0,
    );
  }

  void _emitShadedBox(
    List<double> out, {
    required Mat4 worldMatrix,
    required double halfExtent,
    required double r,
    required double g,
    required double b,
    required double a,
  }) {
    final s = halfExtent;
    final faces = <(Vec3, Vec3, Vec3, Vec3, Vec3)>[
      // +Z
      (
        Vec3(-s, -s, s),
        Vec3(s, -s, s),
        Vec3(s, s, s),
        Vec3(-s, s, s),
        const Vec3(0, 0, 1),
      ),
      // -Z
      (
        Vec3(s, -s, -s),
        Vec3(-s, -s, -s),
        Vec3(-s, s, -s),
        Vec3(s, s, -s),
        const Vec3(0, 0, -1),
      ),
      // +X
      (
        Vec3(s, -s, s),
        Vec3(s, -s, -s),
        Vec3(s, s, -s),
        Vec3(s, s, s),
        const Vec3(1, 0, 0),
      ),
      // -X
      (
        Vec3(-s, -s, -s),
        Vec3(-s, -s, s),
        Vec3(-s, s, s),
        Vec3(-s, s, -s),
        const Vec3(-1, 0, 0),
      ),
      // +Y
      (
        Vec3(-s, s, s),
        Vec3(s, s, s),
        Vec3(s, s, -s),
        Vec3(-s, s, -s),
        const Vec3(0, 1, 0),
      ),
      // -Y
      (
        Vec3(-s, -s, -s),
        Vec3(s, -s, -s),
        Vec3(s, -s, s),
        Vec3(-s, -s, s),
        const Vec3(0, -1, 0),
      ),
    ];

    for (final (p0, p1, p2, p3, n) in faces) {
      final w0 = worldMatrix.transformPoint(p0);
      final w1 = worldMatrix.transformPoint(p1);
      final w2 = worldMatrix.transformPoint(p2);
      final w3 = worldMatrix.transformPoint(p3);
      final wn = worldMatrix.transformDir(n).normalized;
      _pushTri(out, w0, w1, w2, wn, r, g, b, a);
      _pushTri(out, w0, w2, w3, wn, r, g, b, a);
    }
  }

  void _pushTri(
    List<double> out,
    Vec3 a,
    Vec3 b,
    Vec3 c,
    Vec3 n,
    double r,
    double g,
    double bl,
    double al,
  ) {
    out.addAll([
      a.x,
      a.y,
      a.z,
      n.x,
      n.y,
      n.z,
      r,
      g,
      bl,
      al,
      b.x,
      b.y,
      b.z,
      n.x,
      n.y,
      n.z,
      r,
      g,
      bl,
      al,
      c.x,
      c.y,
      c.z,
      n.x,
      n.y,
      n.z,
      r,
      g,
      bl,
      al,
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
