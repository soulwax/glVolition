part of '../engine.dart';

/// One world-space debug line segment with an ARGB colour.
final class GizmoLine {
  final Vec3 a;
  final Vec3 b;
  final int color;
  const GizmoLine(this.a, this.b, this.color);
}

/// One projected drawing-buffer-space segment produced by [Gizmos.project].
typedef GizmoScreenLine = ({double x0, double y0, double x1, double y1, int color});

/// Host-neutral immediate-mode debug drawing (E15-1).
///
/// Game code and editor tooling queue world-space lines each frame
/// (`scene.gizmos.wireBox(...)`); the scene projects them through the active
/// [Camera] and encodes them as an overlay sprite batch after UI, then clears
/// the queue. Auto-gizmos ([showColliders], [showContacts], [showSelection])
/// are regenerated every frame from live engine state, so they never go stale.
final class Gizmos {
  final Scene _scene;
  final List<GizmoLine> _lines = [];

  /// Master switch. When false nothing is collected or drawn.
  bool enabled = false;
  bool showColliders = true;
  bool showContacts = true;
  bool showSelection = true;

  double thickness = 1.5;
  int colliderColor = 0xFF39FF88;
  int triggerColor = 0xFF39C8FF;
  int contactColor = 0xFFFF3B6B;
  int selectionColor = 0xFFFFD23F;

  /// Number of segments used to approximate circles.
  int circleSegments = 24;

  Camera2D? _overlayCamera;
  final SpriteBatch _batch = SpriteBatch(initialCapacity: 1024, debugLabel: 'gizmos');

  Gizmos._(this._scene);

  List<GizmoLine> get lines => List.unmodifiable(_lines);
  int get lineCount => _lines.length;

  void clear() => _lines.clear();

  void line(Vec3 a, Vec3 b, {int? color}) {
    if (!enabled) return;
    _lines.add(GizmoLine(a, b, color ?? colliderColor));
  }

  void ray(Vec3 origin, Vec3 direction, {double length = 1, int? color}) =>
      line(origin, origin + direction.normalized * length, color: color);

  void arrow(Vec3 from, Vec3 to, {double headSize = 0.25, int? color}) {
    line(from, to, color: color);
    final dir = to - from;
    final len = dir.length;
    if (len < 1e-6) return;
    final unitDir = dir * (1.0 / len);
    final helper = unitDir.y.abs() < 0.99 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
    final side = unitDir.cross(helper).normalized * headSize;
    final up = unitDir.cross(side).normalized * headSize;
    final headBase = to - unitDir * headSize;
    line(to, headBase + side, color: color);
    line(to, headBase - side, color: color);
    line(to, headBase + up, color: color);
    line(to, headBase - up, color: color);
  }

  void wireDisc(Vec3 center, double radius, Vec3 normal, {int? color}) {
    final n = normal.lengthSquared > 1e-10 ? normal.normalized : const Vec3(0, 1, 0);
    final helper = n.y.abs() < 0.99 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
    final u = n.cross(helper).normalized;
    final v = n.cross(u).normalized;
    circle(center, radius, u, v, color: color);
  }

  void cross(Vec3 p, {double size = 0.25, int? color}) {
    line(p - Vec3(size, 0, 0), p + Vec3(size, 0, 0), color: color);
    line(p - Vec3(0, size, 0), p + Vec3(0, size, 0), color: color);
    line(p - Vec3(0, 0, size), p + Vec3(0, 0, size), color: color);
  }

  void wireBox(Aabb box, {int? color}) {
    final mn = box.min, mx = box.max;
    final c = [
      Vec3(mn.x, mn.y, mn.z), Vec3(mx.x, mn.y, mn.z), Vec3(mx.x, mn.y, mx.z), Vec3(mn.x, mn.y, mx.z), //
      Vec3(mn.x, mx.y, mn.z), Vec3(mx.x, mx.y, mn.z), Vec3(mx.x, mx.y, mx.z), Vec3(mn.x, mx.y, mx.z),
    ];
    for (var i = 0; i < 4; i++) {
      line(c[i], c[(i + 1) % 4], color: color);
      line(c[i + 4], c[(i + 1) % 4 + 4], color: color);
      line(c[i], c[i + 4], color: color);
    }
  }

  /// Circle of [radius] around [center] in the plane spanned by [u] and [v].
  void circle(Vec3 center, double radius, Vec3 u, Vec3 v, {int? color, double arcStart = 0, double arc = math.pi * 2}) {
    final n = math.max(3, (circleSegments * arc / (math.pi * 2)).ceil());
    Vec3 at(int i) {
      final t = arcStart + arc * i / n;
      return center + u * (math.cos(t) * radius) + v * (math.sin(t) * radius);
    }

    var prev = at(0);
    for (var i = 1; i <= n; i++) {
      final next = at(i);
      line(prev, next, color: color);
      prev = next;
    }
  }

  void wireSphere(Vec3 center, double radius, {int? color}) {
    const x = Vec3(1, 0, 0), y = Vec3(0, 1, 0), z = Vec3(0, 0, 1);
    circle(center, radius, x, y, color: color);
    circle(center, radius, x, z, color: color);
    circle(center, radius, y, z, color: color);
  }

  void wireCapsule(Vec3 start, Vec3 end, double radius, {int? color}) {
    final axis = end - start;
    final up = axis.lengthSquared > 1e-10 ? axis.normalized : const Vec3(0, 1, 0);
    final helper = up.y.abs() < 0.99 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
    final u = up.cross(helper).normalized;
    final v = up.cross(u).normalized;
    circle(start, radius, u, v, color: color);
    circle(end, radius, u, v, color: color);
    for (final side in [u, -u, v, -v]) {
      line(start + side * radius, end + side * radius, color: color);
    }
    // Hemisphere arcs: end cap bulges along +up, start cap along -up.
    circle(end, radius, u, up, color: color, arc: math.pi);
    circle(end, radius, v, up, color: color, arc: math.pi);
    circle(start, radius, u, -up, color: color, arc: math.pi);
    circle(start, radius, v, -up, color: color, arc: math.pi);
  }

  void collider(Collider c, {int? color}) {
    final col = color ?? (c.isTrigger ? triggerColor : colliderColor);
    switch (c) {
      case SphereCollider s:
        wireSphere(s.worldCenter, s.worldRadius, color: col);
      case BoxCollider b:
        wireBox(b.worldBounds, color: col);
      case CapsuleCollider cap:
        wireCapsule(cap.segmentStart, cap.segmentEnd, cap.worldRadius, color: col);
    }
  }

  /// Rebuilds auto-gizmos from live physics/editor state.
  void collectAuto() {
    if (!enabled) return;
    final physics = _scene.physics;
    if (showColliders) {
      for (final c in physics._colliders) {
        if (c._active) collider(c);
      }
    }
    if (showContacts) {
      for (final (a, b) in physics.contactPairs) {
        final m = PhysicsWorld.debugManifold(a, b);
        final pa = a.worldBounds.center, pb = b.worldBounds.center;
        final mid = (pa + pb) * 0.5;
        cross(mid, size: 0.1, color: contactColor);
        if (m != null) {
          final len = math.max(0.25, m.$2 * 4);
          ray(mid, m.$1, length: len, color: contactColor);
        }
      }
    }
    if (showSelection && _scene.isLoaded) {
      final sel = _scene.engine.editor.selected;
      if (sel != null && !sel.isDestroyed && sel.scene == _scene) {
        final p = sel.transform.position;
        ray(p, const Vec3(1, 0, 0), color: 0xFFFF4040);
        ray(p, const Vec3(0, 1, 0), color: 0xFF40FF40);
        ray(p, const Vec3(0, 0, 1), color: 0xFF4080FF);
        for (final c in sel.getComponents<Collider>()) {
          collider(c, color: selectionColor);
        }
      }
    }
  }

  /// Projects queued lines through [camera] into drawing-buffer pixels,
  /// clipping segments that cross behind the near plane.
  List<GizmoScreenLine> project(Camera camera) {
    final out = <GizmoScreenLine>[];
    for (final l in _lines) {
      final a = camera.worldToScreenPoint(l.a);
      final b = camera.worldToScreenPoint(l.b);
      if (a != null && b != null) {
        out.add((x0: a.x, y0: a.y, x1: b.x, y1: b.y, color: l.color));
      } else if (a != null || b != null) {
        // Bisect towards the visible endpoint until the point is in front.
        var front = a != null ? l.a : l.b;
        var back = a != null ? l.b : l.a;
        for (var i = 0; i < 12; i++) {
          final mid = (front + back) * 0.5;
          if (camera.worldToScreenPoint(mid) != null) {
            front = mid;
          } else {
            back = mid;
          }
        }
        final vis = (a ?? b)!;
        final clip = camera.worldToScreenPoint(front);
        if (clip != null) {
          out.add((x0: vis.x, y0: vis.y, x1: clip.x, y1: clip.y, color: l.color));
        }
      }
    }
    return out;
  }

  void _encode(RenderEncoder encoder, int vw, int vh) {
    if (!enabled || _lines.isEmpty || vw <= 0 || vh <= 0) {
      _lines.clear();
      return;
    }
    final cam = Camera.of(_scene);
    if (cam != null && cam._active) {
      var overlay = _overlayCamera;
      if (overlay == null || overlay.designWidth != vw || overlay.designHeight != vh) {
        overlay = _overlayCamera = Camera2D(
          designWidth: vw.toDouble(),
          designHeight: vh.toDouble(),
          snapToPixels: false,
        );
      }
      overlay
        ..setViewport(vw, vh)
        ..x = vw * 0.5
        ..y = vh * 0.5;
      _batch.clear();
      for (final s in project(cam)) {
        _batch.drawLine(s.x0, s.y0, s.x1, s.y1, thickness: thickness, color: s.color);
      }
      if (!_batch.isEmpty) {
        encoder.drawSprites(_batch, overlay, stage: SpriteStage.overlay);
      }
    }
    _lines.clear();
  }
}
