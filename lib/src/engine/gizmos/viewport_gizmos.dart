part of '../../engine.dart';

/// Interaction mode for 3D viewport gizmos (P7-W15-B).
enum ViewportGizmoMode { translate, rotate, scale }

/// Coordinate space used by [ViewportGizmos] handles and drag projections (P10-W18-A).
enum ViewportGizmoSpace { world, local }

/// Specific coordinate axis or plane targeted by viewport raycast or drag.
enum ViewportGizmoAxis { none, x, y, z, xy, xz, yz, all }

/// Raycast hit result against a 3D viewport gizmo handle.
final class ViewportGizmoHit {
  final ViewportGizmoAxis axis;
  final double distance;
  final Vec3 hitPoint;

  const ViewportGizmoHit({
    required this.axis,
    required this.distance,
    required this.hitPoint,
  });
}

/// Tracks one property override against base prefab values (P7-W15-B).
final class PrefabOverride {
  final String propertyName;
  final Object? originalValue;
  Object? overrideValue;

  PrefabOverride({
    required this.propertyName,
    required this.originalValue,
    required this.overrideValue,
  });
}

/// Component attached to a [GameObject] instantiated from a Prefab, tracking
/// variant overrides and supporting per-property or full revert (P7-W15-B).
class PrefabInstanceComponent extends Component {
  String prefabName;
  final List<PrefabOverride> overrides = [];

  PrefabInstanceComponent({
    required this.prefabName,
    List<PrefabOverride>? initialOverrides,
  }) {
    if (initialOverrides != null) {
      overrides.addAll(initialOverrides);
    }
  }

  bool hasOverride(String propertyName) =>
      overrides.any((o) => o.propertyName == propertyName);

  PrefabOverride? getOverride(String propertyName) {
    for (final o in overrides) {
      if (o.propertyName == propertyName) return o;
    }
    return null;
  }

  void addOrUpdateOverride(
    String propertyName,
    Object? originalValue,
    Object? overrideValue,
  ) {
    final existing = getOverride(propertyName);
    if (existing != null) {
      existing.overrideValue = overrideValue;
    } else {
      overrides.add(
        PrefabOverride(
          propertyName: propertyName,
          originalValue: originalValue,
          overrideValue: overrideValue,
        ),
      );
    }
  }

  bool revertOverride(String propertyName) {
    final idx = overrides.indexWhere((o) => o.propertyName == propertyName);
    if (idx != -1) {
      final o = overrides.removeAt(idx);
      _applyRevert(o);
      return true;
    }
    return false;
  }

  void revertAll() {
    for (final o in List.of(overrides)) {
      _applyRevert(o);
    }
    overrides.clear();
  }

  void _applyRevert(PrefabOverride o) {
    if (o.propertyName == 'position' && o.originalValue is Vec3) {
      transform.position = o.originalValue as Vec3;
    } else if (o.propertyName == 'rotation' && o.originalValue is Quat) {
      transform.rotation = o.originalValue as Quat;
    } else if (o.propertyName == 'scale' && o.originalValue is double) {
      transform.localScale = o.originalValue as double;
    }
  }

  static final spec = ComponentSpec<PrefabInstanceComponent>(
    'PrefabInstanceComponent',
    () => PrefabInstanceComponent(prefabName: ''),
    [Field.text('prefabName', (c) => c.prefabName, (c, v) => c.prefabName = v)],
  );
}

final class _SelectionDragSnapshot {
  final GameObject object;
  final Vec3 startWorldPos;
  final Vec3 startLocalPos;
  final Quat startWorldRot;
  final Quat startLocalRot;
  final double startScale;

  const _SelectionDragSnapshot({
    required this.object,
    required this.startWorldPos,
    required this.startLocalPos,
    required this.startWorldRot,
    required this.startLocalRot,
    required this.startScale,
  });
}

/// Interactive 3D viewport gizmo controller with hit-testing, local/world
/// coordinate spaces, planar dual-axis handles, snapping, and multi-selection
/// pivot drag manipulation synchronized with [EditorSession] (P7-W15-B, P10-W18-A).
class ViewportGizmos {
  final Scene scene;

  ViewportGizmoMode mode = ViewportGizmoMode.translate;
  ViewportGizmoSpace space = ViewportGizmoSpace.world;
  ViewportGizmoAxis activeAxis = ViewportGizmoAxis.none;
  ViewportGizmoAxis hoveredAxis = ViewportGizmoAxis.none;

  double gizmoSize = 1.5;
  double hitThreshold = 0.25;

  bool snapEnabled = false;
  double translateSnap = 0.5;
  double rotateSnapDegrees = 15.0;
  double scaleSnap = 0.25;

  Ray? _startRay;
  Vec3? _startPosition;
  Quat? _startRotation;
  double? _startScale;
  final List<_SelectionDragSnapshot> _selectionSnapshots = [];

  ViewportGizmos(this.scene);

  double snap(double val, double step) {
    if (!snapEnabled || step <= 0.0) return val;
    return (val / step).round() * step;
  }

  Vec3 snapVec3(Vec3 v, double step) {
    if (!snapEnabled || step <= 0.0) return v;
    return Vec3(snap(v.x, step), snap(v.y, step), snap(v.z, step));
  }

  /// Resolves the unit axis direction for [axis], rotating by [rotation] when
  /// [space] is [ViewportGizmoSpace.local].
  Vec3 axisDirection(ViewportGizmoAxis axis, {Quat? rotation}) {
    final Vec3 base;
    switch (axis) {
      case ViewportGizmoAxis.x:
      case ViewportGizmoAxis.yz:
        base = const Vec3(1, 0, 0);
      case ViewportGizmoAxis.y:
      case ViewportGizmoAxis.xz:
        base = const Vec3(0, 1, 0);
      case ViewportGizmoAxis.z:
      case ViewportGizmoAxis.xy:
        base = const Vec3(0, 0, 1);
      default:
        base = const Vec3(1, 1, 1).normalized;
    }
    if (space == ViewportGizmoSpace.local && rotation != null) {
      return rotation.rotate(base).normalized;
    }
    return base;
  }

  /// Intersects [ray] against the infinite plane through [planeOrigin] with
  /// unit [planeNormal]. Returns `null` when parallel or behind the ray origin.
  static Vec3? intersectRayPlane(Ray ray, Vec3 planeOrigin, Vec3 planeNormal) {
    final dir = ray.direction.normalized;
    final n = planeNormal.normalized;
    final denom = n.dot(dir);
    if (denom.abs() < 1e-6) return null;
    final t = (planeOrigin - ray.origin).dot(n) / denom;
    if (t < 0.0) return null;
    return ray.origin + dir * t;
  }

  static bool _isPlanarAxis(ViewportGizmoAxis axis) =>
      axis == ViewportGizmoAxis.xy ||
      axis == ViewportGizmoAxis.xz ||
      axis == ViewportGizmoAxis.yz;

  /// Hit tests a camera [ray] against the 3D axis handles (and planar quad
  /// handles in translate mode) around [origin].
  ViewportGizmoHit? hitTest(Ray ray, Vec3 origin, {Quat? rotation}) {
    final scale = gizmoSize;
    final xDir = axisDirection(ViewportGizmoAxis.x, rotation: rotation);
    final yDir = axisDirection(ViewportGizmoAxis.y, rotation: rotation);
    final zDir = axisDirection(ViewportGizmoAxis.z, rotation: rotation);

    final axes = <(ViewportGizmoAxis, Vec3)>[
      (ViewportGizmoAxis.x, xDir),
      (ViewportGizmoAxis.y, yDir),
      (ViewportGizmoAxis.z, zDir),
    ];

    ViewportGizmoHit? closestHit;
    var minDistance = double.infinity;
    final rayDir = ray.direction.normalized;

    for (final (axis, axisDir) in axes) {
      final t = EditorSession.projectRayOntoAxis(ray, origin, axisDir);
      if (t >= 0.0 && t <= scale) {
        final ptOnAxis = origin + axisDir * t;
        final v = ptOnAxis - ray.origin;
        final dRay = v.dot(rayDir);
        if (dRay > 0) {
          final closestOnRay = ray.origin + rayDir * dRay;
          final dist = (closestOnRay - ptOnAxis).length;
          if (dist <= hitThreshold && dist < minDistance) {
            minDistance = dist;
            closestHit = ViewportGizmoHit(
              axis: axis,
              distance: dist,
              hitPoint: ptOnAxis,
            );
          }
        }
      }
    }

    if (mode == ViewportGizmoMode.translate) {
      final minBound = 0.15 * scale;
      final maxBound = 0.45 * scale;
      final planes = <(ViewportGizmoAxis, Vec3, Vec3, Vec3)>[
        (ViewportGizmoAxis.xy, xDir, yDir, zDir),
        (ViewportGizmoAxis.xz, xDir, zDir, yDir),
        (ViewportGizmoAxis.yz, yDir, zDir, xDir),
      ];
      var bestPlaneRayT = double.infinity;
      ViewportGizmoHit? bestPlaneHit;
      for (final (axis, uAxis, vAxis, normal) in planes) {
        final hitPt = intersectRayPlane(ray, origin, normal);
        if (hitPt == null) continue;
        final rel = hitPt - origin;
        final u = rel.dot(uAxis);
        final v = rel.dot(vAxis);
        if (u >= minBound && u <= maxBound && v >= minBound && v <= maxBound) {
          final rayT = (hitPt - ray.origin).dot(rayDir);
          if (rayT > 0 && rayT < bestPlaneRayT) {
            bestPlaneRayT = rayT;
            bestPlaneHit = ViewportGizmoHit(
              axis: axis,
              distance: 0.0,
              hitPoint: hitPt,
            );
          }
        }
      }
      if (bestPlaneHit != null && (closestHit == null || minDistance > 1e-4)) {
        return bestPlaneHit;
      }
    }

    return closestHit;
  }

  /// Begins a drag operation along [axis] from [startRay].
  void beginDrag(ViewportGizmoAxis axis, Ray startRay, GameObject target) {
    _selectionSnapshots.clear();
    activeAxis = axis;
    _startRay = startRay;
    _startPosition = target.transform.position;
    _startRotation = target.transform.rotation;
    _startScale = target.transform.localScale;
  }

  /// Updates drag position/rotation/scale on [target] from [currentRay].
  void updateDrag(Ray currentRay, GameObject target) {
    if (activeAxis == ViewportGizmoAxis.none ||
        _startRay == null ||
        _startPosition == null) {
      return;
    }

    final startPos = _startPosition!;
    final axisDir = axisDirection(activeAxis, rotation: _startRotation);

    switch (mode) {
      case ViewportGizmoMode.translate:
        if (_isPlanarAxis(activeAxis)) {
          final hitStart = intersectRayPlane(_startRay!, startPos, axisDir);
          final hitCurrent = intersectRayPlane(currentRay, startPos, axisDir);
          if (hitStart != null && hitCurrent != null) {
            final delta = hitCurrent - hitStart;
            target.transform.position = snapVec3(
              startPos + delta,
              translateSnap,
            );
          }
        } else {
          final rawPos = EditorSession.computeAxisDragPosition(
            initialWorldPosition: startPos,
            axisDir: axisDir,
            startRay: _startRay!,
            currentRay: currentRay,
          );
          target.transform.position = snapVec3(rawPos, translateSnap);
        }

      case ViewportGizmoMode.rotate:
        final s0 = EditorSession.projectRayOntoAxis(
          _startRay!,
          startPos,
          axisDir,
        );
        final s1 = EditorSession.projectRayOntoAxis(
          currentRay,
          startPos,
          axisDir,
        );
        final angleRad = (s1 - s0) * 0.5;
        final snappedAngle = snapEnabled
            ? (angleRad * 180.0 / math.pi / rotateSnapDegrees).round() *
                  rotateSnapDegrees *
                  math.pi /
                  180.0
            : angleRad;
        final rotDelta = Quat.axisAngle(axisDir, snappedAngle);
        target.transform.rotation =
            rotDelta * (_startRotation ?? Quat.identity);

      case ViewportGizmoMode.scale:
        final s0 = EditorSession.projectRayOntoAxis(
          _startRay!,
          startPos,
          axisDir,
        );
        final s1 = EditorSession.projectRayOntoAxis(
          currentRay,
          startPos,
          axisDir,
        );
        final scaleDelta = (s1 - s0) * 0.25;
        final rawScale = math.max(0.01, (_startScale ?? 1.0) + scaleDelta);
        target.transform.localScale = snap(rawScale, scaleSnap);
    }
  }

  /// Completes drag and returns reversible [TransformMoveCommand] to commit to editor undo stack.
  TransformMoveCommand? endDrag(GameObject target) {
    if (activeAxis == ViewportGizmoAxis.none || _startPosition == null) {
      activeAxis = ViewportGizmoAxis.none;
      _startRay = null;
      return null;
    }

    final cmd = TransformMoveCommand(
      targetName: target.name,
      oldPosition: _startPosition!,
      newPosition: target.transform.position,
      oldRotation: _startRotation,
      newRotation: target.transform.rotation,
      oldScale: _startScale,
      newScale: target.transform.localScale,
    );

    activeAxis = ViewportGizmoAxis.none;
    _startRay = null;
    _startPosition = null;
    _startRotation = null;
    _startScale = null;

    return cmd;
  }

  /// Begins a multi-selection pivot drag around [session.selectionCentroid]
  /// (P10-W18-A). Returns `false` when no objects are selected.
  bool beginSelectionDrag(
    ViewportGizmoAxis axis,
    Ray startRay,
    EditorSession session,
  ) {
    final selected = session.selectedObjects;
    final centroid = session.selectionCentroid;
    if (selected.isEmpty || centroid == null) return false;

    activeAxis = axis;
    _startRay = startRay;
    _startPosition = centroid;
    _startRotation = selected.last.transform.rotation;
    _startScale = 1.0;
    _selectionSnapshots
      ..clear()
      ..addAll([
        for (final go in selected)
          _SelectionDragSnapshot(
            object: go,
            startWorldPos: go.transform.position,
            startLocalPos: go.transform.localPosition,
            startWorldRot: go.transform.rotation,
            startLocalRot: go.transform.localRotation,
            startScale: go.transform.localScale,
          ),
      ]);
    return true;
  }

  /// Updates transforms for all objects captured in [beginSelectionDrag].
  void updateSelectionDrag(Ray currentRay, EditorSession session) {
    if (activeAxis == ViewportGizmoAxis.none ||
        _startRay == null ||
        _startPosition == null ||
        _selectionSnapshots.isEmpty) {
      return;
    }

    final pivot = _startPosition!;
    final axisDir = axisDirection(activeAxis, rotation: _startRotation);

    switch (mode) {
      case ViewportGizmoMode.translate:
        Vec3 delta;
        if (_isPlanarAxis(activeAxis)) {
          final hitStart = intersectRayPlane(_startRay!, pivot, axisDir);
          final hitCurrent = intersectRayPlane(currentRay, pivot, axisDir);
          if (hitStart == null || hitCurrent == null) return;
          delta = hitCurrent - hitStart;
        } else {
          final rawPivot = EditorSession.computeAxisDragPosition(
            initialWorldPosition: pivot,
            axisDir: axisDir,
            startRay: _startRay!,
            currentRay: currentRay,
          );
          delta = rawPivot - pivot;
        }
        final snappedDelta = snapVec3(delta, translateSnap);
        for (final snapItem in _selectionSnapshots) {
          if (snapItem.object.isDestroyed) continue;
          snapItem.object.transform.position =
              snapItem.startWorldPos + snappedDelta;
        }

      case ViewportGizmoMode.rotate:
        final s0 = EditorSession.projectRayOntoAxis(_startRay!, pivot, axisDir);
        final s1 = EditorSession.projectRayOntoAxis(currentRay, pivot, axisDir);
        final angleRad = (s1 - s0) * 0.5;
        final snappedAngle = snapEnabled
            ? (angleRad * 180.0 / math.pi / rotateSnapDegrees).round() *
                  rotateSnapDegrees *
                  math.pi /
                  180.0
            : angleRad;
        final rotDelta = Quat.axisAngle(axisDir, snappedAngle);
        for (final snapItem in _selectionSnapshots) {
          if (snapItem.object.isDestroyed) continue;
          final offset = snapItem.startWorldPos - pivot;
          snapItem.object.transform.position = pivot + rotDelta.rotate(offset);
          snapItem.object.transform.rotation =
              rotDelta * snapItem.startWorldRot;
        }

      case ViewportGizmoMode.scale:
        final s0 = EditorSession.projectRayOntoAxis(_startRay!, pivot, axisDir);
        final s1 = EditorSession.projectRayOntoAxis(currentRay, pivot, axisDir);
        final rawFactor = math.max(0.01, 1.0 + (s1 - s0) * 0.25);
        final factor = snap(rawFactor, scaleSnap);
        for (final snapItem in _selectionSnapshots) {
          if (snapItem.object.isDestroyed) continue;
          final offset = snapItem.startWorldPos - pivot;
          snapItem.object.transform.position = pivot + offset * factor;
          snapItem.object.transform.localScale = math.max(
            0.01,
            snapItem.startScale * factor,
          );
        }
    }
  }

  /// Completes a multi-selection pivot drag and returns a reversible
  /// [CompoundCommand] across all dragged objects.
  EditorCommand? endSelectionDrag(EditorSession session) {
    if (activeAxis == ViewportGizmoAxis.none || _selectionSnapshots.isEmpty) {
      activeAxis = ViewportGizmoAxis.none;
      _startRay = null;
      _selectionSnapshots.clear();
      return null;
    }

    final commands = <EditorCommand>[
      for (final item in _selectionSnapshots)
        if (!item.object.isDestroyed)
          TransformMoveCommand(
            targetName: item.object.name,
            oldPosition: item.startLocalPos,
            newPosition: item.object.transform.localPosition,
            oldRotation: item.startLocalRot,
            newRotation: item.object.transform.localRotation,
            oldScale: item.startScale,
            newScale: item.object.transform.localScale,
          ),
    ];

    activeAxis = ViewportGizmoAxis.none;
    _startRay = null;
    _startPosition = null;
    _startRotation = null;
    _startScale = null;
    _selectionSnapshots.clear();

    if (commands.isEmpty) return null;
    return CompoundCommand(
      name: 'Multi-Selection Gizmo Transform',
      commands: commands,
    );
  }

  /// Renders the 3D gizmo handles into [scene.gizmos] around [position],
  /// optionally oriented by [rotation] when [space] is [ViewportGizmoSpace.local].
  void render(Vec3 position, {Quat? rotation}) {
    final g = scene.gizmos;
    if (!g.enabled) return;

    final xDir = axisDirection(ViewportGizmoAxis.x, rotation: rotation);
    final yDir = axisDirection(ViewportGizmoAxis.y, rotation: rotation);
    final zDir = axisDirection(ViewportGizmoAxis.z, rotation: rotation);

    final xCol =
        (activeAxis == ViewportGizmoAxis.x ||
            hoveredAxis == ViewportGizmoAxis.x)
        ? 0xFFFFFF00
        : 0xFFFF3B3B;
    final yCol =
        (activeAxis == ViewportGizmoAxis.y ||
            hoveredAxis == ViewportGizmoAxis.y)
        ? 0xFFFFFF00
        : 0xFF3BFF3B;
    final zCol =
        (activeAxis == ViewportGizmoAxis.z ||
            hoveredAxis == ViewportGizmoAxis.z)
        ? 0xFFFFFF00
        : 0xFF3B82FF;

    final s = gizmoSize;
    switch (mode) {
      case ViewportGizmoMode.translate:
        g.arrow(position, position + xDir * s, color: xCol);
        g.arrow(position, position + yDir * s, color: yCol);
        g.arrow(position, position + zDir * s, color: zCol);

        // Render planar quad outlines (XY, XZ, YZ)
        final minB = 0.15 * s;
        final maxB = 0.45 * s;
        void drawPlaneQuad(
          ViewportGizmoAxis axis,
          Vec3 u,
          Vec3 v,
          int baseCol,
        ) {
          final col = (activeAxis == axis || hoveredAxis == axis)
              ? 0xFFFFFF00
              : baseCol;
          final p00 = position + u * minB + v * minB;
          final p10 = position + u * maxB + v * minB;
          final p11 = position + u * maxB + v * maxB;
          final p01 = position + u * minB + v * maxB;
          g.line(p00, p10, color: col);
          g.line(p10, p11, color: col);
          g.line(p11, p01, color: col);
          g.line(p01, p00, color: col);
        }

        drawPlaneQuad(ViewportGizmoAxis.xy, xDir, yDir, 0xFF3B82FF);
        drawPlaneQuad(ViewportGizmoAxis.xz, xDir, zDir, 0xFF3BFF3B);
        drawPlaneQuad(ViewportGizmoAxis.yz, yDir, zDir, 0xFFFF3B3B);

      case ViewportGizmoMode.rotate:
        g.wireDisc(position, s, xDir, color: xCol);
        g.wireDisc(position, s, yDir, color: yCol);
        g.wireDisc(position, s, zDir, color: zCol);

      case ViewportGizmoMode.scale:
        const halfSize = 0.08;
        final xTip = position + xDir * s;
        g.line(position, xTip, color: xCol);
        g.wireBox(
          Aabb(
            xTip - const Vec3(halfSize, halfSize, halfSize),
            xTip + const Vec3(halfSize, halfSize, halfSize),
          ),
          color: xCol,
        );

        final yTip = position + yDir * s;
        g.line(position, yTip, color: yCol);
        g.wireBox(
          Aabb(
            yTip - const Vec3(halfSize, halfSize, halfSize),
            yTip + const Vec3(halfSize, halfSize, halfSize),
          ),
          color: yCol,
        );

        final zTip = position + zDir * s;
        g.line(position, zTip, color: zCol);
        g.wireBox(
          Aabb(
            zTip - const Vec3(halfSize, halfSize, halfSize),
            zTip + const Vec3(halfSize, halfSize, halfSize),
          ),
          color: zCol,
        );
    }
  }
}
