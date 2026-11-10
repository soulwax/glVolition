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

/// Vertical or rotated 3D capsule collider defined by a hemispherical [radius]
/// and total [height] (E13-1).
final class CapsuleCollider extends Collider {
  double radius;
  double height;

  CapsuleCollider({
    this.radius = 0.4,
    this.height = 1.8,
    super.center,
    super.isTrigger,
    super.collidesWithMask,
  });

  double get worldRadius => radius * transform.lossyScale;

  /// Half-length of the interior line segment between the two hemisphere centers.
  double get halfSegmentLength =>
      math.max(0.0, (height * 0.5 - radius) * transform.lossyScale);

  /// Bottom hemisphere center in world space.
  Vec3 get segmentStart =>
      worldCenter - transform.up * halfSegmentLength;

  /// Top hemisphere center in world space.
  Vec3 get segmentEnd =>
      worldCenter + transform.up * halfSegmentLength;

  /// Returns the point on the capsule's interior segment `[segmentStart, segmentEnd]`
  /// closest to [point].
  Vec3 closestPointOnAxis(Vec3 point) {
    final a = segmentStart;
    final b = segmentEnd;
    final ab = b - a;
    final lenSq = ab.lengthSquared;
    if (lenSq < 1e-12) return a;
    final t = ((point - a).dot(ab) / lenSq).clamp(0.0, 1.0);
    return a + ab * t;
  }

  @override
  Aabb get worldBounds {
    final a = segmentStart;
    final b = segmentEnd;
    final r = Vec3(worldRadius, worldRadius, worldRadius);
    final minPt = Vec3(
      math.min(a.x, b.x) - r.x,
      math.min(a.y, b.y) - r.y,
      math.min(a.z, b.z) - r.z,
    );
    final maxPt = Vec3(
      math.max(a.x, b.x) + r.x,
      math.max(a.y, b.y) + r.y,
      math.max(a.z, b.z) + r.z,
    );
    return Aabb(minPt, maxPt);
  }

  @override
  double? _raycast(Ray ray) {
    // Sample spheres along the capsule segment (top, middle, bottom) and AABB
    if (ray.intersectAabb(worldBounds) == null) return null;
    final r = worldRadius;
    final a = segmentStart;
    final b = segmentEnd;
    double? best;
    const samples = 5;
    for (var i = 0; i <= samples; i++) {
      final p = Vec3.lerp(a, b, i / samples);
      final t = ray.intersectSphere(BoundingSphere(p, r));
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }
}

final class PhysicsHit {
  final Collider collider;
  final Vec3 point;
  final double distance;

  const PhysicsHit({required this.collider, required this.point, required this.distance});

  GameObject get gameObject => collider.gameObject;
}

/// Contact manifold reported to [Behaviour.onCollisionEnter] when two solid
/// (`isTrigger == false`) [Collider]s collide (E9-3).
final class Collision {
  final Collider other;
  final Vec3 contactNormal;
  final double penetrationDepth;
  final Vec3 relativeVelocity;

  const Collision({
    required this.other,
    required this.contactNormal,
    required this.penetrationDepth,
    required this.relativeVelocity,
  });

  GameObject get gameObject => other.gameObject;
}

/// Dynamic or kinematic 3D/2D rigidbody integrated during [PhysicsWorld] fixed
/// steps with solid sphere/AABB collision resolution and impulse restitution (E9-3).
final class RigidBody extends Component {
  Vec3 velocity;
  double mass;
  double gravityScale;
  double linearDrag;
  double restitution;
  bool isKinematic;
  bool useGravity;
  bool freezeY;

  Vec3 _accumulatedForce = Vec3.zero;

  RigidBody({
    this.velocity = Vec3.zero,
    this.mass = 1.0,
    this.gravityScale = 1.0,
    this.linearDrag = 0.05,
    this.restitution = 0.5,
    this.isKinematic = false,
    this.useGravity = true,
    this.freezeY = false,
  });

  static final spec = ComponentSpec<RigidBody>(
    'RigidBody',
    RigidBody.new,
    [
      Field.vec3('velocity', (r) => r.velocity, (r, v) => r.velocity = v),
      Field.number('mass', (r) => r.mass, (r, v) => r.mass = v),
      Field.number('gravityScale', (r) => r.gravityScale, (r, v) => r.gravityScale = v),
      Field.number('linearDrag', (r) => r.linearDrag, (r, v) => r.linearDrag = v),
      Field.number('restitution', (r) => r.restitution, (r, v) => r.restitution = v),
      Field.boolean('isKinematic', (r) => r.isKinematic, (r, v) => r.isKinematic = v),
      Field.boolean('useGravity', (r) => r.useGravity, (r, v) => r.useGravity = v),
      Field.boolean('freezeY', (r) => r.freezeY, (r, v) => r.freezeY = v),
    ],
  );

  double get inverseMass => (isKinematic || mass <= 0) ? 0.0 : 1.0 / mass;

  /// Applies a continuous force (in Newtons) for the next fixed step.
  void addForce(Vec3 force) {
    if (isKinematic) return;
    _accumulatedForce += force;
  }

  /// Applies an instantaneous velocity impulse (`impulse / mass`).
  void addImpulse(Vec3 impulse) {
    if (isKinematic) return;
    velocity += impulse * inverseMass;
    if (freezeY) velocity = Vec3(velocity.x, 0, velocity.z);
  }

  void _integrate(double dt, Vec3 worldGravity) {
    if (isKinematic || dt <= 0) {
      _accumulatedForce = Vec3.zero;
      return;
    }
    var accel = _accumulatedForce * inverseMass;
    _accumulatedForce = Vec3.zero;
    if (useGravity) {
      accel += worldGravity * gravityScale;
    }
    velocity += accel * dt;
    if (linearDrag > 0) {
      final dampFactor = math.max(0.0, 1.0 - linearDrag * dt);
      velocity *= dampFactor;
    }
    if (freezeY) {
      velocity = Vec3(velocity.x, 0, velocity.z);
    }
    if (velocity.lengthSquared > 1e-12) {
      transform.position += velocity * dt;
    }
  }

  @override
  void _onEnableInternal() => scene.physics._registerBody(this);

  @override
  void _onDisableInternal() => scene.physics._unregisterBody(this);
}

/// Per-scene collision world.
final class PhysicsWorld {
  final Scene _scene;
  Vec3 gravity = const Vec3(0, -9.81, 0);
  final List<Collider> _colliders = [];
  final List<RigidBody> _bodies = [];
  Set<(int, int)> _overlaps = {};
  final Map<int, Collider> _byId = {};

  PhysicsWorld._(this._scene);

  List<Collider> get colliders => List.unmodifiable(_colliders);
  List<RigidBody> get bodies => List.unmodifiable(_bodies);

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

  void _registerBody(RigidBody body) => _bodies.add(body);
  void _unregisterBody(RigidBody body) => _bodies.remove(body);

  /// Every active collider overlapping the sphere ([center], [radius]) whose
  /// object layer is enabled in [layerMask].
  Iterable<Collider> overlapSphere(
    Vec3 center,
    double radius, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) sync* {
    for (final c in _colliders) {
      if (!c._active) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      if (_intersectsSphere(c, center, radius)) yield c;
    }
  }

  /// Every active collider overlapping the world-space AABB [bounds] whose
  /// object layer is enabled in [layerMask] (E12-2).
  Iterable<Collider> overlapBox(
    Aabb bounds, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) sync* {
    for (final c in _colliders) {
      if (!c._active) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final hit = switch (c) {
        SphereCollider s => _sphereAabb(s.worldCenter, s.worldRadius, bounds),
        BoxCollider b => _aabbAabb(b.worldBounds, bounds),
        CapsuleCollider cap => _capsuleAabb(cap, bounds),
      };
      if (hit) yield c;
    }
  }

  PhysicsHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    Collider? best;
    var bestT = maxDistance;
    for (final c in _colliders) {
      if (!c._active) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final t = c._raycast(ray);
      if (t != null && t <= bestT) {
        bestT = t;
        best = c;
      }
    }
    return best == null ? null : PhysicsHit(collider: best, point: ray.at(bestT), distance: bestT);
  }

  /// Returns all colliders intersected by [ray] within [maxDistance], sorted by
  /// ascending hit distance (E12-2).
  List<PhysicsHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    final hits = <PhysicsHit>[];
    for (final c in _colliders) {
      if (!c._active) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final t = c._raycast(ray);
      if (t != null && t <= maxDistance) {
        hits.add(PhysicsHit(collider: c, point: ray.at(t), distance: t));
      }
    }
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  /// Sweeps a sphere of [radius] along [ray] up to [maxDistance] and returns
  /// the closest hit (E12-2).
  PhysicsHit? sphereCast(
    Ray ray,
    double radius, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    final r = math.max(0.0, radius);
    final pad = Vec3(r, r, r);
    Collider? best;
    var bestT = maxDistance;
    for (final c in _colliders) {
      if (!c._active) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final double? t = switch (c) {
        SphereCollider s => ray.intersectSphere(
            BoundingSphere(s.worldCenter, s.worldRadius + r),
          ),
        BoxCollider b => ray.intersectAabb(
            Aabb(b.worldBounds.min - pad, b.worldBounds.max + pad),
          ),
        CapsuleCollider cap => ray.intersectAabb(
            Aabb(cap.worldBounds.min - pad, cap.worldBounds.max + pad),
          ),
      };
      if (t != null && t <= bestT) {
        bestT = t;
        best = c;
      }
    }
    return best == null ? null : PhysicsHit(collider: best, point: ray.at(bestT), distance: bestT);
  }

  void _step() {
    final dt = _scene._engine?.time.fixedDeltaTime ?? (1.0 / 60.0);
    for (final body in List.of(_bodies)) {
      if (body._active && !body._destroyRequested) {
        body._integrate(dt, gravity);
      }
    }

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
      final isNew = !_overlaps.contains(key);
      final phase = isNew ? _Phase.enter : _Phase.stay;
      if (!a.isTrigger && !b.isTrigger) {
        _resolveSolidCollision(a, b, isNew: isNew);
      }
      if (a._active && b._active) _notify(a, b, phase);
      if (a._active && b._active) _notify(b, a, phase);
    }

    _overlaps = next;
  }

  void _resolveSolidCollision(Collider a, Collider b, {required bool isNew}) {
    final rbA = a.getComponent<RigidBody>();
    final rbB = b.getComponent<RigidBody>();
    final invMassA = rbA?.inverseMass ?? 0.0;
    final invMassB = rbB?.inverseMass ?? 0.0;
    final totalInvMass = invMassA + invMassB;
    if (totalInvMass <= 0) return;

    final manifold = _computeManifold(a, b);
    if (manifold == null) return;
    final (normal, depth) = manifold; // normal points from A toward B

    // Positional correction
    if (depth > 0) {
      final corrA = normal * (-depth * (invMassA / totalInvMass));
      final corrB = normal * (depth * (invMassB / totalInvMass));
      if (invMassA > 0) a.transform.position += corrA;
      if (invMassB > 0) b.transform.position += corrB;
    }

    final velA = rbA?.velocity ?? Vec3.zero;
    final velB = rbB?.velocity ?? Vec3.zero;
    final relVel = velB - velA;
    final velAlongNormal = relVel.dot(normal);

    if (velAlongNormal < 0) {
      final e = math.min(rbA?.restitution ?? 0.5, rbB?.restitution ?? 0.5);
      final j = -(1.0 + e) * velAlongNormal / totalInvMass;
      final impulse = normal * j;
      rbA?.addImpulse(-impulse);
      rbB?.addImpulse(impulse);
    }

    if (isNew) {
      if (a._active && b._active) {
        _notifyCollision(
          a,
          Collision(
            other: b,
            contactNormal: -normal,
            penetrationDepth: depth,
            relativeVelocity: -relVel,
          ),
        );
      }
      if (a._active && b._active) {
        _notifyCollision(
          b,
          Collision(
            other: a,
            contactNormal: normal,
            penetrationDepth: depth,
            relativeVelocity: relVel,
          ),
        );
      }
    }
  }

  void _notifyCollision(Collider receiver, Collision collision) {
    for (final c in List.of(receiver.gameObject._components)) {
      if (c is Behaviour && c._active && !c._destroyRequested) {
        _scene._guard(() => c.onCollisionEnter(collision));
      }
    }
  }

  static (Vec3 normal, double depth)? _computeManifold(Collider a, Collider b) {
    if (a is SphereCollider && b is SphereCollider) {
      final delta = b.worldCenter - a.worldCenter;
      final dist = delta.length;
      final rSum = a.worldRadius + b.worldRadius;
      if (dist >= rSum) return null;
      final normal = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
      return (normal, rSum - dist);
    }
    final boxA = a.worldBounds;
    final boxB = b.worldBounds;
    final ox = math.min(boxA.max.x, boxB.max.x) - math.max(boxA.min.x, boxB.min.x);
    final oy = math.min(boxA.max.y, boxB.max.y) - math.max(boxA.min.y, boxB.min.y);
    final oz = math.min(boxA.max.z, boxB.max.z) - math.max(boxA.min.z, boxB.min.z);
    if (ox <= 0 || oy <= 0 || oz <= 0) return null;
    final centerDelta = boxB.center - boxA.center;
    if (ox <= oy && ox <= oz) {
      return (Vec3(centerDelta.x >= 0 ? 1 : -1, 0, 0), ox);
    } else if (oy <= ox && oy <= oz) {
      return (Vec3(0, centerDelta.y >= 0 ? 1 : -1, 0), oy);
    } else {
      return (Vec3(0, 0, centerDelta.z >= 0 ? 1 : -1), oz);
    }
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
        (CapsuleCollider cap, SphereCollider s) || (SphereCollider s, CapsuleCollider cap) =>
          _sphereSphere(cap.closestPointOnAxis(s.worldCenter), cap.worldRadius, s.worldCenter, s.worldRadius),
        (CapsuleCollider cap, BoxCollider box) || (BoxCollider box, CapsuleCollider cap) =>
          _capsuleAabb(cap, box.worldBounds),
        (CapsuleCollider c1, CapsuleCollider c2) => _capsuleCapsule(c1, c2),
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
        CapsuleCollider cap => _sphereSphere(cap.closestPointOnAxis(center), cap.worldRadius, center, radius),
      };

  static bool _capsuleAabb(CapsuleCollider cap, Aabb box) {
    final clampedBoxCenter = cap.closestPointOnAxis(box.center);
    return _sphereAabb(clampedBoxCenter, cap.worldRadius, box) ||
        _sphereAabb(cap.segmentStart, cap.worldRadius, box) ||
        _sphereAabb(cap.segmentEnd, cap.worldRadius, box);
  }

  static bool _capsuleCapsule(CapsuleCollider c1, CapsuleCollider c2) {
    final p1 = c1.closestPointOnAxis(c2.worldCenter);
    final p2 = c2.closestPointOnAxis(p1);
    final p1Refined = c1.closestPointOnAxis(p2);
    return _sphereSphere(p1Refined, c1.worldRadius, p2, c2.worldRadius);
  }

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
