part of '../../engine.dart';

/// Interaction mode for 3D viewport gizmos (P7-W15-B).
enum ViewportGizmoMode { translate, rotate, scale }

/// Specific coordinate axis or plane targeted by viewport raycast or drag.
enum ViewportGizmoAxis { none, x, y, z, all }

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

/// Interactive 3D viewport gizmo controller with hit-testing, snapping, and
/// drag manipulation synchronized with [EditorSession] (P7-W15-B).
class ViewportGizmos {
  final Scene scene;

  ViewportGizmoMode mode = ViewportGizmoMode.translate;
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

  ViewportGizmos(this.scene);

  double snap(double val, double step) {
    if (!snapEnabled || step <= 0.0) return val;
    return (val / step).round() * step;
  }

  Vec3 snapVec3(Vec3 v, double step) {
    if (!snapEnabled || step <= 0.0) return v;
    return Vec3(snap(v.x, step), snap(v.y, step), snap(v.z, step));
  }

  /// Hit tests a camera [ray] against the 3D axis handles around [origin].
  ViewportGizmoHit? hitTest(Ray ray, Vec3 origin) {
    final scale = gizmoSize;
    final axes = <(ViewportGizmoAxis, Vec3, Vec3)>[
      (ViewportGizmoAxis.x, origin, origin + Vec3(scale, 0, 0)),
      (ViewportGizmoAxis.y, origin, origin + Vec3(0, scale, 0)),
      (ViewportGizmoAxis.z, origin, origin + Vec3(0, 0, scale)),
    ];

    ViewportGizmoHit? closestHit;
    var minDistance = double.infinity;

    for (final (axis, a, b) in axes) {
      final axisDir = (b - a).normalized;
      final t = EditorSession.projectRayOntoAxis(ray, a, axisDir);
      if (t >= 0.0 && t <= scale) {
        final ptOnAxis = a + axisDir * t;
        final rayDir = ray.direction.normalized;
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

    return closestHit;
  }

  /// Begins a drag operation along [axis] from [startRay].
  void beginDrag(ViewportGizmoAxis axis, Ray startRay, GameObject target) {
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
    Vec3 axisDir;
    switch (activeAxis) {
      case ViewportGizmoAxis.x:
        axisDir = const Vec3(1, 0, 0);
      case ViewportGizmoAxis.y:
        axisDir = const Vec3(0, 1, 0);
      case ViewportGizmoAxis.z:
        axisDir = const Vec3(0, 0, 1);
      default:
        axisDir = const Vec3(1, 1, 1);
    }

    switch (mode) {
      case ViewportGizmoMode.translate:
        final rawPos = EditorSession.computeAxisDragPosition(
          initialWorldPosition: startPos,
          axisDir: axisDir,
          startRay: _startRay!,
          currentRay: currentRay,
        );
        target.transform.position = snapVec3(rawPos, translateSnap);

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

  /// Renders the 3D gizmo handles into [scene.gizmos] around [position].
  void render(Vec3 position) {
    final g = scene.gizmos;
    if (!g.enabled) return;

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
        g.arrow(position, position + Vec3(s, 0, 0), color: xCol);
        g.arrow(position, position + Vec3(0, s, 0), color: yCol);
        g.arrow(position, position + Vec3(0, 0, s), color: zCol);

      case ViewportGizmoMode.rotate:
        g.wireDisc(position, s, const Vec3(1, 0, 0), color: xCol);
        g.wireDisc(position, s, const Vec3(0, 1, 0), color: yCol);
        g.wireDisc(position, s, const Vec3(0, 0, 1), color: zCol);

      case ViewportGizmoMode.scale:
        const halfSize = 0.08;
        final xTip = position + Vec3(s, 0, 0);
        g.line(position, xTip, color: xCol);
        g.wireBox(
          Aabb(
            xTip - const Vec3(halfSize, halfSize, halfSize),
            xTip + const Vec3(halfSize, halfSize, halfSize),
          ),
          color: xCol,
        );

        final yTip = position + Vec3(0, s, 0);
        g.line(position, yTip, color: yCol);
        g.wireBox(
          Aabb(
            yTip - const Vec3(halfSize, halfSize, halfSize),
            yTip + const Vec3(halfSize, halfSize, halfSize),
          ),
          color: yCol,
        );

        final zTip = position + Vec3(0, 0, s);
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
