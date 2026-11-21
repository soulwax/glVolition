/// Volition Studio Light Gizmos (`[S3-E]`):
/// Generates `EditorGizmoLine` geometry for directional arrows, point light
/// range spheres, spot light cones, and directional CSM cascade-split rings.
library;

import 'dart:math' as math;

import 'package:pixeldart/rendering/api/editor_overlay.dart';
import 'package:pixeldart/rendering/api/lights.dart';
import 'package:pixeldart/rendering/math/vec.dart';

import '../../engine.dart';

/// Builds `EditorGizmoLine` primitives for scene [Light] components and
/// optional CSM cascade split debug overlays (`[S3-E]`).
abstract final class LightGizmoBuilder {
  static const LinearColor _lightYellow = LinearColor(1.0, 0.92, 0.35);

  /// Emits gizmo lines for a single [Light] component.
  static List<EditorGizmoLine> buildForLight(
    Light light, {
    int circleSegments = 24,
  }) {
    if (!light.isAttached) return const [];
    final pos = light.transform.position;
    final fwd = light.transform.forward;
    switch (light.type) {
      case LightType.directional:
        return _buildDirectionalArrow(pos, fwd);
      case LightType.point:
        return _buildWireSphere(pos, light.range, circleSegments);
      case LightType.spot:
        return _buildSpotCone(
          pos,
          fwd,
          light.range,
          light.spotAngle,
          circleSegments,
        );
    }
  }

  /// Emits color-coded cascade split boundary rings along camera forward.
  static List<EditorGizmoLine> buildCascadeSplitOverlay({
    required Vec3 cameraPos,
    required Vec3 cameraForward,
    required List<double> splitDistances,
    int segments = 16,
  }) {
    const colors = [
      LinearColor(0.2, 0.9, 0.3),
      LinearColor(0.95, 0.85, 0.15),
      LinearColor(0.95, 0.45, 0.15),
      LinearColor(0.9, 0.15, 0.25),
    ];
    final fwd = cameraForward.normalized;
    final refUp = fwd.y.abs() < 0.95
        ? const Vec3(0, 1, 0)
        : const Vec3(1, 0, 0);
    final right = fwd.cross(refUp).normalized;
    final up = right.cross(fwd).normalized;

    final lines = <EditorGizmoLine>[];
    for (var i = 0; i < splitDistances.length; i++) {
      final d = splitDistances[i];
      final color = colors[i % colors.length];
      final center = cameraPos + fwd * d;
      final r = d * 0.35;
      for (var s = 0; s < segments; s++) {
        final a0 = (s / segments) * math.pi * 2.0;
        final a1 = ((s + 1) / segments) * math.pi * 2.0;
        final p0 =
            center + right * (math.cos(a0) * r) + up * (math.sin(a0) * r);
        final p1 =
            center + right * (math.cos(a1) * r) + up * (math.sin(a1) * r);
        lines.add(EditorGizmoLine(start: p0, end: p1, color: color));
      }
    }
    return lines;
  }

  static List<EditorGizmoLine> _buildDirectionalArrow(Vec3 pos, Vec3 fwd) {
    final dir = fwd.normalized;
    final refUp = dir.y.abs() < 0.95
        ? const Vec3(0, 1, 0)
        : const Vec3(1, 0, 0);
    final right = dir.cross(refUp).normalized;
    final up = right.cross(dir).normalized;
    final lines = <EditorGizmoLine>[];
    const offsets = [
      (0.0, 0.0),
      (0.4, 0.0),
      (-0.4, 0.0),
      (0.0, 0.4),
      (0.0, -0.4),
    ];
    for (final (ox, oy) in offsets) {
      final start = pos + right * ox + up * oy;
      final end = start + dir * 2.5;
      lines.add(EditorGizmoLine(start: start, end: end, color: _lightYellow));
    }
    return lines;
  }

  static List<EditorGizmoLine> _buildWireSphere(
    Vec3 center,
    double radius,
    int segments,
  ) {
    final lines = <EditorGizmoLine>[];
    for (var i = 0; i < segments; i++) {
      final a0 = (i / segments) * math.pi * 2.0;
      final a1 = ((i + 1) / segments) * math.pi * 2.0;
      final c0 = math.cos(a0) * radius;
      final s0 = math.sin(a0) * radius;
      final c1 = math.cos(a1) * radius;
      final s1 = math.sin(a1) * radius;
      // XY, XZ, YZ great circles
      lines.add(
        EditorGizmoLine(
          start: center + Vec3(c0, s0, 0),
          end: center + Vec3(c1, s1, 0),
          color: _lightYellow,
        ),
      );
      lines.add(
        EditorGizmoLine(
          start: center + Vec3(c0, 0, s0),
          end: center + Vec3(c1, 0, s1),
          color: _lightYellow,
        ),
      );
      lines.add(
        EditorGizmoLine(
          start: center + Vec3(0, c0, s0),
          end: center + Vec3(0, c1, s1),
          color: _lightYellow,
        ),
      );
    }
    return lines;
  }

  static List<EditorGizmoLine> _buildSpotCone(
    Vec3 apex,
    Vec3 fwd,
    double range,
    double outerRadians,
    int segments,
  ) {
    final dir = fwd.normalized;
    final refUp = dir.y.abs() < 0.95
        ? const Vec3(0, 1, 0)
        : const Vec3(1, 0, 0);
    final right = dir.cross(refUp).normalized;
    final up = right.cross(dir).normalized;
    final baseCenter = apex + dir * range;
    final baseRadius = math.tan(outerRadians.clamp(0.02, 1.45)) * range;

    final lines = <EditorGizmoLine>[];
    for (var i = 0; i < segments; i++) {
      final a0 = (i / segments) * math.pi * 2.0;
      final a1 = ((i + 1) / segments) * math.pi * 2.0;
      final p0 =
          baseCenter +
          right * (math.cos(a0) * baseRadius) +
          up * (math.sin(a0) * baseRadius);
      final p1 =
          baseCenter +
          right * (math.cos(a1) * baseRadius) +
          up * (math.sin(a1) * baseRadius);
      lines.add(EditorGizmoLine(start: p0, end: p1, color: _lightYellow));
      if (i % (segments ~/ 4).clamp(1, segments) == 0) {
        lines.add(EditorGizmoLine(start: apex, end: p0, color: _lightYellow));
      }
    }
    return lines;
  }
}
