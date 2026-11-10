part of '../../engine.dart';

/// Base class for collision shapes. Phase 1 physics is trigger and query
/// driven: overlaps fire `onTriggerEnter`/`Stay`/`Exit` on every active
/// [Behaviour] on both objects, and [PhysicsWorld] supports raycasts and
/// sphere queries with 32-bit layer masks.
sealed class Collider extends Component {
  Vec3 center;
  bool isTrigger;

  /// Bitmask of object layers (0..31) this collider interacts with.
  int collidesWithMask;

  Collider({
    this.center = Vec3.zero,
    this.isTrigger = true,
    this.collidesWithMask = -1,
  });

  Vec3 get worldCenter => transform.transformPoint(center);
  Aabb get worldBounds;

  double? _raycast(Ray ray);

  @override
  void _onEnableInternal() => scene.physics._register(this);

  @override
  void _onDisableInternal() => scene.physics._unregister(this);
}

final class SphereCollider extends Collider {
  double radius;

  SphereCollider({
    this.radius = 0.5,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  /// World-space radius, scaled by the object's uniform [TransformComponent.lossyScale].
  double get worldRadius => radius * transform.lossyScale;

  @override
  Aabb get worldBounds {
    final c = worldCenter;
    final r = Vec3(worldRadius, worldRadius, worldRadius);
    return Aabb(c - r, c + r);
  }

  @override
  double? _raycast(Ray ray) => ray.intersectSphere(BoundingSphere(worldCenter, worldRadius));
}

final class BoxCollider extends Collider {
  Vec3 size;

  BoxCollider({
    this.size = const Vec3(1, 1, 1),
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  @override
  Aabb get worldBounds {
    final half = size * 0.5;
    return Aabb(center - half, center + half).transformed(transform.world.toMat4());
  }

  @override
  double? _raycast(Ray ray) => ray.intersectAabb(worldBounds);
}

final class PhysicsHit {
  final Collider collider;
  final Vec3 point;
  final double distance;

  const PhysicsHit({required this.collider, required this.point, required this.distance});

  GameObject get gameObject => collider.gameObject;
}

/// Per-scene collision world.
final class PhysicsWorld {
  final Scene _scene;
  final List<Collider> _colliders = [];
  Set<(int, int)> _overlaps = {};
  final Map<int, Collider> _byId = {};

  PhysicsWorld._(this._scene);

  List<Collider> get colliders => List.unmodifiable(_colliders);

  void _register(Collider c) {
    _colliders.add(c);
    _byId[c.instanceId] = c;
  }

  void _unregister(Collider c) {
    _colliders.remove(c);
    _byId.remove(c.instanceId);
    final id = c.instanceId;
    final stale = _overlaps.where((p) => p.$1 == id || p.$2 == id).toList();
    for (final pair in stale) {
      _overlaps.remove(pair);
      final other = _byId[pair.$1 == id ? pair.$2 : pair.$1];
      if (other != null && other._active) _notify(other, c, _Phase.exit);
    }
  }

  /// Every active collider overlapping the sphere ([center], [radius]) whose
  /// object layer is enabled in [layerMask].
  Iterable<Collider> overlapSphere(Vec3 center, double radius, {int layerMask = -1}) sync* {
    for (final c in _colliders) {
      if (!c._active) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      if (_intersectsSphere(c, center, radius)) yield c;
    }
  }

  PhysicsHit? raycast(Ray ray, {double maxDistance = double.infinity, int layerMask = -1}) {
    Collider? best;
    var bestT = maxDistance;
    for (final c in _colliders) {
      if (!c._active) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final t = c._raycast(ray);
      if (t != null && t <= bestT) {
        bestT = t;
        best = c;
      }
    }
    return best == null ? null : PhysicsHit(collider: best, point: ray.at(bestT), distance: bestT);
  }

  void _step() {
    final active = _colliders.where((c) => c._active && !c._destroyRequested).toList();
    final next = <(int, int)>{};
    final pairs = <(Collider, Collider)>[];

    for (var i = 0; i < active.length; i++) {
      final a = active[i];
      final aBit = 1 << a.gameObject.layer;
      for (var j = i + 1; j < active.length; j++) {
        final b = active[j];
        if (identical(a.gameObject, b.gameObject)) continue;
        final bBit = 1 << b.gameObject.layer;
        if ((a.collidesWithMask & bBit) == 0 || (b.collidesWithMask & aBit) == 0) continue;
        if (!_intersects(a, b)) continue;
        final key = a.instanceId < b.instanceId ? (a.instanceId, b.instanceId) : (b.instanceId, a.instanceId);
        next.add(key);
        pairs.add((a, b));
      }
    }

    for (final key in _overlaps) {
      if (!next.contains(key)) {
        final a = _byId[key.$1];
        final b = _byId[key.$2];
        if (a != null && b != null) {
          if (a._active) _notify(a, b, _Phase.exit);
          if (b._active) _notify(b, a, _Phase.exit);
        }
      }
    }

    for (final (a, b) in pairs) {
      final key = a.instanceId < b.instanceId ? (a.instanceId, b.instanceId) : (b.instanceId, a.instanceId);
      final phase = _overlaps.contains(key) ? _Phase.stay : _Phase.enter;
      if (a._active && b._active) _notify(a, b, phase);
      if (a._active && b._active) _notify(b, a, phase);
    }

    _overlaps = next;
  }

  void _notify(Collider receiver, Collider other, _Phase phase) {
    for (final c in List.of(receiver.gameObject._components)) {
      if (c is Behaviour && c._active && !c._destroyRequested) {
        switch (phase) {
          case _Phase.enter:
            _scene._guard(() => c.onTriggerEnter(other));
          case _Phase.stay:
            _scene._guard(() => c.onTriggerStay(other));
          case _Phase.exit:
            _scene._guard(() => c.onTriggerExit(other));
        }
      }
    }
  }

  static bool _intersects(Collider a, Collider b) => switch ((a, b)) {
        (SphereCollider s1, SphereCollider s2) => _sphereSphere(
            s1.worldCenter,
            s1.worldRadius,
            s2.worldCenter,
            s2.worldRadius,
          ),
        (SphereCollider s, BoxCollider box) || (BoxCollider box, SphereCollider s) =>
          _sphereAabb(s.worldCenter, s.worldRadius, box.worldBounds),
        (BoxCollider b1, BoxCollider b2) => _aabbAabb(b1.worldBounds, b2.worldBounds),
      };

  static bool _aabbAabb(Aabb a, Aabb b) =>
      a.min.x <= b.max.x &&
      a.max.x >= b.min.x &&
      a.min.y <= b.max.y &&
      a.max.y >= b.min.y &&
      a.min.z <= b.max.z &&
      a.max.z >= b.min.z;

  static bool _intersectsSphere(Collider c, Vec3 center, double radius) => switch (c) {
        SphereCollider s => _sphereSphere(s.worldCenter, s.worldRadius, center, radius),
        BoxCollider b => _sphereAabb(center, radius, b.worldBounds),
      };

  static bool _sphereSphere(Vec3 c1, double r1, Vec3 c2, double r2) {
    final r = r1 + r2;
    return (c1 - c2).lengthSquared <= r * r;
  }

  static bool _sphereAabb(Vec3 center, double radius, Aabb box) {
    final closest = Vec3(
      center.x.clamp(box.min.x, box.max.x),
      center.y.clamp(box.min.y, box.max.y),
      center.z.clamp(box.min.z, box.max.z),
    );
    return (center - closest).lengthSquared <= radius * radius;
  }
}

enum _Phase { enter, stay, exit }
