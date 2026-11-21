/// Volition Studio Reflection Probe Gizmos (`[S4-B]`):
/// Emits wireframe bounding box and blend-distance bounds for
/// [ReflectionProbeComponent].
library;

import 'package:pixeldart/rendering/api/editor_overlay.dart';
import 'package:pixeldart/rendering/api/lights.dart';
import 'package:pixeldart/rendering/math/vec.dart';

import '../../engine.dart';

abstract final class ProbeGizmoBuilder {
  static const LinearColor _probeCyan = LinearColor(0.25, 0.85, 0.95);
  static const LinearColor _blendTeal = LinearColor(0.2, 0.55, 0.65);

  static List<EditorGizmoLine> buildForProbe(ReflectionProbeComponent probe) {
    if (!probe.isAttached) return const [];
    final lines = <EditorGizmoLine>[
      ..._wireBox(probe.boxMin, probe.boxMax, _probeCyan),
    ];
    if (probe.blendDistance > 1e-4) {
      final pad = Vec3(
        probe.blendDistance,
        probe.blendDistance,
        probe.blendDistance,
      );
      lines.addAll(
        _wireBox(probe.boxMin - pad, probe.boxMax + pad, _blendTeal),
      );
    }
    return lines;
  }

  static List<EditorGizmoLine> _wireBox(Vec3 bMin, Vec3 bMax, LinearColor c) {
    final p000 = Vec3(bMin.x, bMin.y, bMin.z);
    final p100 = Vec3(bMax.x, bMin.y, bMin.z);
    final p010 = Vec3(bMin.x, bMax.y, bMin.z);
    final p110 = Vec3(bMax.x, bMax.y, bMin.z);
    final p001 = Vec3(bMin.x, bMin.y, bMax.z);
    final p101 = Vec3(bMax.x, bMin.y, bMax.z);
    final p011 = Vec3(bMin.x, bMax.y, bMax.z);
    final p111 = Vec3(bMax.x, bMax.y, bMax.z);
    return [
      EditorGizmoLine(start: p000, end: p100, color: c),
      EditorGizmoLine(start: p100, end: p110, color: c),
      EditorGizmoLine(start: p110, end: p010, color: c),
      EditorGizmoLine(start: p010, end: p000, color: c),
      EditorGizmoLine(start: p001, end: p101, color: c),
      EditorGizmoLine(start: p101, end: p111, color: c),
      EditorGizmoLine(start: p111, end: p011, color: c),
      EditorGizmoLine(start: p011, end: p001, color: c),
      EditorGizmoLine(start: p000, end: p001, color: c),
      EditorGizmoLine(start: p100, end: p101, color: c),
      EditorGizmoLine(start: p110, end: p111, color: c),
      EditorGizmoLine(start: p010, end: p011, color: c),
    ];
  }
}
