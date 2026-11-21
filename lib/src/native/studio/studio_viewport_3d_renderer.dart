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
uniform float uShadingMode;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
layout(location=0) out vec4 oColor;
void main() {
  vec3 n = normalize(vNormal);
  if (uShadingMode > 2.5 && uShadingMode < 3.5) {
    // Normals mode
    oColor = vec4(n * 0.5 + 0.5, vColor.a);
    return;
  }
  if (uShadingMode > 1.5 && uShadingMode < 2.5) {
    // Albedo mode
    oColor = vColor;
    return;
  }
  if (uShadingMode > 3.5) {
    // Heatmap mode (blue -> green -> yellow -> red by elevation/density)
    float h = clamp(abs(n.y) * 0.4 + 0.45, 0.0, 1.0);
    vec3 heat = mix(vec3(0.15, 0.45, 0.95), vec3(0.95, 0.32, 0.14), h);
    oColor = vec4(heat, vColor.a);
    return;
  }
  if (uShadingMode > 0.5 && uShadingMode < 1.5) {
    // Wireframe mode (unlit bright edges)
    oColor = vec4(vColor.rgb * 1.15, vColor.a);
    return;
  }
  // Lit mode (directional scene sun + hemisphere ambient)
  vec3 keyDir = normalize(uSunDir);
  vec3 fillDir = normalize(vec3(-0.6, 0.3, -0.5));
  float ndl = max(dot(n, keyDir), 0.0) * 0.78 + max(dot(n, fillDir), 0.0) * 0.18;
  float hemi = n.y * 0.12 + 0.24;
  vec3 lit = vColor.rgb * (uSunColor * ndl + vec3(hemi));
  oColor = vec4(min(lit, vec3(1.2)), vColor.a);
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
  int lastShadingModeIndex = 0;
  int lastGizmoVertexCount = 0;

  StudioViewport3DRenderer(this._device);

  void _ensureResources() {
    if (_disposed) {
      throw StateError('StudioViewport3DRenderer has been disposed');
    }
    _program ??= _device.compileProgram(
      vertexSource: _vertSrc,
      fragmentSource: _fragSrc,
      requiredAttributes: const ['aPos', 'aNormal', 'aColor'],
      requiredUniforms: const [
        'uViewProj',
        'uShadingMode',
        'uSunDir',
        'uSunColor',
      ],
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

    final shadingModeIndex = isScene
        ? switch (shell.sceneShadingMode) {
            'Wire' => 1,
            'Albedo' => 2,
            'Normals' => 3,
            'Heatmap' => 4,
            _ => 0,
          }
        : 0;
    lastShadingModeIndex = shadingModeIndex;

    // Extract primary directional light from the active scene for Lit shading
    var sunDir = const Vec3(0.45, 0.85, 0.35).normalized;
    var sunColor = const Vec3(1.0, 0.98, 0.94);
    for (final go in allObjects) {
      final light = go.getComponent<Light>();
      if (light != null && light.type == LightType.directional) {
        final fwd = go.transform.forward;
        sunDir = Vec3(-fwd.x, -fwd.y, -fwd.z).normalized;
        final intensity = light.intensity.clamp(0.2, 2.5);
        sunColor = Vec3(
          light.color.r * intensity,
          light.color.g * intensity,
          light.color.b * intensity,
        );
        break;
      }
    }

    var gizmoVertStart = 0;
    for (final go in allObjects) {
      final isSelected = isScene && selectedSet.contains(go);
      final light = go.getComponent<Light>();
      final camComp = go.getComponent<Camera>();
      final isLight = light != null;
      final isCam = camComp != null;
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
      if (shadingModeIndex == 1) {
        _emitWireBox(
          verts,
          worldMatrix: worldMatrix,
          halfExtent: halfExt,
          r: r,
          g: g,
          b: b,
        );
      } else {
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

      if (isScene && shell.sceneGizmosVisible) {
        final beforeGizmos = verts.length;
        if (isSelected) {
          _emitWireBox(
            verts,
            worldMatrix: worldMatrix,
            halfExtent: halfExt + 0.04,
            r: 1.0,
            g: 0.68,
            b: 0.16,
          );
        }
        if (isCam) {
          _emitCameraFrustumGizmo(verts, go.transform, camComp);
        }
        if (isLight) {
          _emitLightGizmo(verts, go.transform, light);
        }
        gizmoVertStart += (verts.length - beforeGizmos) ~/ 10;
      }
    }

    if (isScene && shell.sceneGizmosVisible && selectedSet.isNotEmpty) {
      final beforeAxis = verts.length;
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
      gizmoVertStart += (verts.length - beforeAxis) ~/ 10;
    }
    if (isScene) {
      lastGizmoVertexCount = gizmoVertStart;
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
    _device.setUniform(
      'uShadingMode',
      UniformValue.float1(shadingModeIndex.toDouble()),
    );
    _device.setUniform(
      'uSunDir',
      UniformValue.float3(Float32List.fromList([sunDir.x, sunDir.y, sunDir.z])),
    );
    _device.setUniform(
      'uSunColor',
      UniformValue.float3(
        Float32List.fromList([sunColor.x, sunColor.y, sunColor.z]),
      ),
    );
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

  void _emitSegmentBeam(
    List<double> out,
    Vec3 a,
    Vec3 b, {
    double thickness = 0.025,
    required double r,
    required double g,
    required double bl,
  }) {
    final diff = b - a;
    final len = diff.length;
    if (len < 1e-5) return;
    final dir = diff * (1.0 / len);
    final upRef = dir.y.abs() > 0.9 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
    final side = dir.cross(upRef).normalized * thickness;
    final ortho = side.cross(dir).normalized * thickness;
    _pushTri(
      out,
      a - side,
      b - side,
      b + side,
      ortho.normalized,
      r,
      g,
      bl,
      1.0,
    );
    _pushTri(
      out,
      a - side,
      b + side,
      a + side,
      ortho.normalized,
      r,
      g,
      bl,
      1.0,
    );
    _pushTri(
      out,
      a - ortho,
      b - ortho,
      b + ortho,
      side.normalized,
      r,
      g,
      bl,
      1.0,
    );
    _pushTri(
      out,
      a - ortho,
      b + ortho,
      a + ortho,
      side.normalized,
      r,
      g,
      bl,
      1.0,
    );
  }

  void _emitWireBox(
    List<double> out, {
    required Mat4 worldMatrix,
    required double halfExtent,
    required double r,
    required double g,
    required double b,
  }) {
    final s = halfExtent;
    final corners = [
      worldMatrix.transformPoint(Vec3(-s, -s, -s)),
      worldMatrix.transformPoint(Vec3(s, -s, -s)),
      worldMatrix.transformPoint(Vec3(s, s, -s)),
      worldMatrix.transformPoint(Vec3(-s, s, -s)),
      worldMatrix.transformPoint(Vec3(-s, -s, s)),
      worldMatrix.transformPoint(Vec3(s, -s, s)),
      worldMatrix.transformPoint(Vec3(s, s, s)),
      worldMatrix.transformPoint(Vec3(-s, s, s)),
    ];
    const edges = [
      (0, 1),
      (1, 2),
      (2, 3),
      (3, 0),
      (4, 5),
      (5, 6),
      (6, 7),
      (7, 4),
      (0, 4),
      (1, 5),
      (2, 6),
      (3, 7),
    ];
    for (final (i0, i1) in edges) {
      _emitSegmentBeam(out, corners[i0], corners[i1], r: r, g: g, bl: b);
    }
  }

  void _emitCameraFrustumGizmo(
    List<double> out,
    TransformComponent tr,
    Camera cam,
  ) {
    final eye = tr.position;
    final fwd = tr.forward;
    final right = tr.right;
    final up = tr.up;
    final dist = 2.4;
    final halfH = math.tan(cam.fovYRadians * 0.5) * dist;
    final halfW = halfH * 1.6;
    final center = eye + fwd * dist;
    final tl = center - right * halfW + up * halfH;
    final trPt = center + right * halfW + up * halfH;
    final br = center + right * halfW - up * halfH;
    final bl = center - right * halfW - up * halfH;
    for (final corner in [tl, trPt, br, bl]) {
      _emitSegmentBeam(out, eye, corner, r: 0.45, g: 0.82, bl: 0.98);
    }
    _emitSegmentBeam(out, tl, trPt, r: 0.45, g: 0.82, bl: 0.98);
    _emitSegmentBeam(out, trPt, br, r: 0.45, g: 0.82, bl: 0.98);
    _emitSegmentBeam(out, br, bl, r: 0.45, g: 0.82, bl: 0.98);
    _emitSegmentBeam(out, bl, tl, r: 0.45, g: 0.82, bl: 0.98);
  }

  void _emitLightGizmo(List<double> out, TransformComponent tr, Light light) {
    final origin = tr.position;
    if (light.type == LightType.directional) {
      final fwd = tr.forward;
      final right = tr.right;
      final up = tr.up;
      for (final offset in [
        Vec3.zero,
        right * 0.28,
        right * -0.28,
        up * 0.28,
        up * -0.28,
      ]) {
        _emitSegmentBeam(
          out,
          origin + offset,
          origin + offset + fwd * 1.6,
          r: 1.0,
          g: 0.92,
          bl: 0.35,
        );
      }
    } else {
      final rad = light.range.clamp(0.8, 3.0);
      const segs = 12;
      for (var i = 0; i < segs; i++) {
        final a0 = (i / segs) * math.pi * 2.0;
        final a1 = ((i + 1) / segs) * math.pi * 2.0;
        final p0 = origin + Vec3(math.cos(a0) * rad, 0, math.sin(a0) * rad);
        final p1 = origin + Vec3(math.cos(a1) * rad, 0, math.sin(a1) * rad);
        _emitSegmentBeam(out, p0, p1, r: 1.0, g: 0.92, bl: 0.35);
      }
    }
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
