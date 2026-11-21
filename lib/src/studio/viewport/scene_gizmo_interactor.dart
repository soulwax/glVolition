/// Pure-Dart Scene View Raycast Picking & 3D Transform Gizmo Interactor (`[Wave G7]`):
/// - Casts perspective camera rays through Scene View pixel coordinates.
/// - Picks the closest active [GameObject] via ray-sphere intersection.
/// - Hit-tests and drags 3D X/Y/Z Translate (`W`), Rotate (`E`), and Scale (`R`)
///   gizmo axes with optional grid-snap and single-step undoable [EditorCommand].
library;

import 'dart:math' as math;

import '../../../gl_volition.dart';
import '../bridge/editor_host_bridge.dart';
import 'scene_viewport_model.dart';

/// World-space 3D axis handle on a Transform gizmo.
enum GizmoAxis { none, x, y, z }

/// World-space ray cast from [origin] along unit [direction].
final class SceneRay {
  final Vec3 origin;
  final Vec3 direction;

  const SceneRay({required this.origin, required this.direction});

  Vec3 pointAt(double t) => origin + direction * t;
}

/// Undoable single-step transform command committed when a 3D gizmo drag ends.
final class TransformGizmoCommand implements EditorCommand {
  @override
  final String name;
  final GameObject target;
  final Vec3 beforePosition;
  final Quat beforeRotation;
  final double beforeScale;
  final Vec3 afterPosition;
  final Quat afterRotation;
  final double afterScale;

  TransformGizmoCommand({
    required this.name,
    required this.target,
    required this.beforePosition,
    required this.beforeRotation,
    required this.beforeScale,
    required this.afterPosition,
    required this.afterRotation,
    required this.afterScale,
  });

  @override
  void execute(EditorSession session) {
    if (target.isDestroyed) return;
    target.transform.localPosition = afterPosition;
    target.transform.localRotation = afterRotation;
    target.transform.localScale = afterScale;
  }

  @override
  void undo(EditorSession session) {
    if (target.isDestroyed) return;
    target.transform.localPosition = beforePosition;
    target.transform.localRotation = beforeRotation;
    target.transform.localScale = beforeScale;
  }
}

/// Interactive Scene View ray-picker & 3D X/Y/Z gizmo manipulator (`[Wave G7]`).
final class SceneGizmoInteractor {
  GizmoAxis hoveredAxis = GizmoAxis.none;
  GizmoAxis activeAxis = GizmoAxis.none;

  bool snapEnabled = false;
  double translateSnap = 0.5;
  double rotateSnapDegrees = 15.0;
  double scaleSnap = 0.25;

  GameObject? _dragTarget;
  String _dragTool = 'move';
  Vec3 _startLocalPos = Vec3.zero;
  Quat _startLocalRot = Quat.identity;
  double _startLocalScale = 1.0;
  double _dragAccumulated = 0.0;

  bool get isDragging => activeAxis != GizmoAxis.none && _dragTarget != null;

  /// Unprojects a pixel coordinate `(screenX, screenY)` inside [viewportRect]
  /// into a world-space [SceneRay] from [camera].
  static SceneRay screenPointToRay(
    EditorCameraController camera,
    VoxRect viewportRect,
    double screenX,
    double screenY,
  ) {
    final w = viewportRect.width > 1.0 ? viewportRect.width : 1.0;
    final h = viewportRect.height > 1.0 ? viewportRect.height : 1.0;
    final ndcX = ((screenX - viewportRect.x) / w) * 2.0 - 1.0;
    final ndcY = 1.0 - ((screenY - viewportRect.y) / h) * 2.0;
    final aspect = w / h;
    final tanHalfFov = math.tan(camera.fovYRadians * 0.5);

    final dir =
        (camera.forward +
                camera.right * (ndcX * aspect * tanHalfFov) +
                camera.up * (ndcY * tanHalfFov))
            .normalized;
    return SceneRay(origin: camera.position, direction: dir);
  }

  /// Picks the closest active [GameObject] in [scene] intersected by [ray].
  static GameObject? pickObject(
    Scene scene,
    SceneRay ray, {
    double baseRadius = 0.75,
  }) {
    GameObject? best;
    var bestT = double.infinity;

    void visit(List<GameObject> nodes) {
      for (final go in nodes) {
        if (!go.activeInHierarchy) continue;
        final center = go.transform.position;
        final radius =
            baseRadius * go.transform.lossyScale.abs().clamp(0.4, 8.0);
        final oc = ray.origin - center;
        final b = oc.dot(ray.direction);
        final c = oc.dot(oc) - radius * radius;
        final disc = b * b - c;
        if (disc >= 0.0) {
          final sqrtD = math.sqrt(disc);
          var t = -b - sqrtD;
          if (t < 0.0) t = -b + sqrtD;
          if (t > 0.0 && t < bestT) {
            bestT = t;
            best = go;
          }
        }
        if (go.children.isNotEmpty) visit(go.children);
      }
    }

    visit(scene.rootGameObjects);
    return best;
  }

  /// Hit-tests the 3D X/Y/Z axis shafts anchored at [origin] against [ray].
  static GizmoAxis hitTestGizmoAxis(
    Vec3 origin,
    SceneRay ray, {
    double axisLength = 1.35,
    double hitThreshold = 0.22,
  }) {
    const axes = [
      (GizmoAxis.x, Vec3(1, 0, 0)),
      (GizmoAxis.y, Vec3(0, 1, 0)),
      (GizmoAxis.z, Vec3(0, 0, 1)),
    ];
    var bestAxis = GizmoAxis.none;
    var bestDist = hitThreshold;

    for (final (axis, dir) in axes) {
      final (dist, segT) = _rayToSegmentDistance(
        ray,
        origin,
        origin + dir * axisLength,
      );
      if (segT >= 0.08 && segT <= 1.05 && dist < bestDist) {
        bestDist = dist;
        bestAxis = axis;
      }
    }
    return bestAxis;
  }

  static Vec3 axisVector(GizmoAxis axis) => switch (axis) {
    GizmoAxis.x => const Vec3(1, 0, 0),
    GizmoAxis.y => const Vec3(0, 1, 0),
    GizmoAxis.z => const Vec3(0, 0, 1),
    GizmoAxis.none => Vec3.zero,
  };

  /// Processes pointer events inside the Scene View [viewportRect].
  /// Returns `true` when the pointer event was consumed by a gizmo drag or pick
  /// (so camera orbit should not run simultaneously).
  bool handlePointer({
    required EditorHostBridge bridge,
    required EditorCameraController camera,
    required VoxRect viewportRect,
    required VoxInput input,
    required String activeTool,
    required bool gizmosVisible,
    bool additiveSelect = false,
  }) {
    final scene = bridge.session.engine.scene;
    final selected = bridge.session.selectedObjects;
    final primary = selected.isNotEmpty ? selected.first : null;
    final canManipulate =
        gizmosVisible &&
        primary != null &&
        (activeTool == 'move' ||
            activeTool == 'rotate' ||
            activeTool == 'scale');

    // Finish active gizmo drag and commit single undoable EditorCommand
    if (isDragging && input.wasMouseReleased) {
      _commitDrag(bridge);
      return true;
    }

    // Continue active gizmo drag
    if (isDragging && input.isMouseDown) {
      _updateDrag(camera, input.mouseDeltaX, input.mouseDeltaY);
      return true;
    }

    if (!viewportRect.contains(input.mouseX, input.mouseY)) {
      hoveredAxis = GizmoAxis.none;
      return false;
    }

    final ray = screenPointToRay(
      camera,
      viewportRect,
      input.mouseX,
      input.mouseY,
    );

    if (canManipulate) {
      hoveredAxis = hitTestGizmoAxis(primary.transform.position, ray);
    } else {
      hoveredAxis = GizmoAxis.none;
    }

    if (input.wasMouseClicked) {
      if (canManipulate && hoveredAxis != GizmoAxis.none) {
        activeAxis = hoveredAxis;
        _dragTarget = primary;
        _dragTool = activeTool;
        _startLocalPos = primary.transform.localPosition;
        _startLocalRot = primary.transform.localRotation;
        _startLocalScale = primary.transform.localScale;
        _dragAccumulated = 0.0;
        return true;
      }

      // Otherwise attempt click-to-pick in the 3D scene
      final hit = pickObject(scene, ray);
      if (hit != null) {
        if (additiveSelect) {
          final next = List<GameObject>.from(selected);
          if (!next.contains(hit)) next.add(hit);
          bridge.selectObjects(next);
        } else {
          bridge.selectObjects([hit]);
        }
        return true;
      }
    }

    return false;
  }

  void _updateDrag(
    EditorCameraController camera,
    double deltaX,
    double deltaY,
  ) {
    final target = _dragTarget;
    if (target == null || target.isDestroyed) return;
    if (deltaX == 0.0 && deltaY == 0.0) return;

    final axis = axisVector(activeAxis);
    // Project screen delta onto world axis direction using camera basis
    final screenMove =
        camera.right *
            (deltaX * 0.015 * (camera.distance * 0.12).clamp(0.4, 4.0)) +
        camera.up *
            (-deltaY * 0.015 * (camera.distance * 0.12).clamp(0.4, 4.0));
    final signedDelta = screenMove.dot(axis);
    _dragAccumulated += signedDelta;

    switch (_dragTool) {
      case 'move':
        final dist = snapEnabled && translateSnap > 0
            ? (_dragAccumulated / translateSnap).round() * translateSnap
            : _dragAccumulated;
        target.transform.localPosition = _startLocalPos + axis * dist;
      case 'rotate':
        var deg = _dragAccumulated * 35.0;
        if (snapEnabled && rotateSnapDegrees > 0) {
          deg = (deg / rotateSnapDegrees).round() * rotateSnapDegrees;
        }
        final halfRad = (deg * math.pi / 180.0) * 0.5;
        final s = math.sin(halfRad);
        final deltaQ = Quat(
          axis.x * s,
          axis.y * s,
          axis.z * s,
          math.cos(halfRad),
        );
        target.transform.localRotation = (deltaQ * _startLocalRot).normalized;
      case 'scale':
        var deltaS = _dragAccumulated * 0.5;
        if (snapEnabled && scaleSnap > 0) {
          deltaS = (deltaS / scaleSnap).round() * scaleSnap;
        }
        target.transform.localScale = (_startLocalScale + deltaS).clamp(
          0.05,
          100.0,
        );
    }
  }

  void _commitDrag(EditorHostBridge bridge) {
    final target = _dragTarget;
    final tool = _dragTool;
    final afterPos = target?.transform.localPosition ?? _startLocalPos;
    final afterRot = target?.transform.localRotation ?? _startLocalRot;
    final afterScale = target?.transform.localScale ?? _startLocalScale;

    activeAxis = GizmoAxis.none;
    _dragTarget = null;

    if (target == null || target.isDestroyed) return;
    final changed =
        afterPos != _startLocalPos ||
        afterRot != _startLocalRot ||
        (afterScale - _startLocalScale).abs() > 1e-6;
    if (!changed) return;

    // Restore pre-drag state and execute single undoable command via EditorSession
    target.transform.localPosition = _startLocalPos;
    target.transform.localRotation = _startLocalRot;
    target.transform.localScale = _startLocalScale;
    bridge.session.executeCommand(
      TransformGizmoCommand(
        name:
            'Gizmo ${tool[0].toUpperCase()}${tool.substring(1)} ${target.name}',
        target: target,
        beforePosition: _startLocalPos,
        beforeRotation: _startLocalRot,
        beforeScale: _startLocalScale,
        afterPosition: afterPos,
        afterRotation: afterRot,
        afterScale: afterScale,
      ),
    );
  }

  /// Closest distance between ray `(o, d)` and finite segment `[a, b]`.
  static (double distance, double segmentT) _rayToSegmentDistance(
    SceneRay ray,
    Vec3 a,
    Vec3 b,
  ) {
    final u = ray.direction;
    final v = b - a;
    final w = ray.origin - a;
    final aDot = u.dot(u);
    final bDot = u.dot(v);
    final cDot = v.dot(v);
    final dDot = u.dot(w);
    final eDot = v.dot(w);
    final denom = aDot * cDot - bDot * bDot;

    double sN, sD = denom;
    double tN, tD = denom;

    if (denom < 1e-7) {
      sN = 0.0;
      sD = 1.0;
      tN = eDot;
      tD = cDot;
    } else {
      sN = bDot * eDot - cDot * dDot;
      tN = aDot * eDot - bDot * dDot;
      if (sN < 0.0) {
        sN = 0.0;
        tN = eDot;
        tD = cDot;
      }
    }

    if (tN < 0.0) {
      tN = 0.0;
      sN = math.max(0.0, -dDot);
      sD = aDot;
    } else if (tN > tD) {
      tN = tD;
      sN = math.max(0.0, -dDot + bDot);
      sD = aDot;
    }

    final sc = sN.abs() < 1e-7 ? 0.0 : sN / sD;
    final tc = tN.abs() < 1e-7 ? 0.0 : tN / tD;
    final diff = w + u * sc - v * tc;
    return (diff.length, tc);
  }
}
