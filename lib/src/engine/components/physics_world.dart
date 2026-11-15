part of '../../engine.dart';

/// Per-scene collision world.
final class PhysicsWorld {
  final Scene _scene;
  Vec3 gravity = const Vec3(0, -9.81, 0);
  PhysicsBroadphase broadphase = SpatialPhysicsBroadphase();
  int solverIterations = 10;
  final List<Collider> _colliders = [];
  final List<RigidBody> _bodies = [];
  final List<PhysicsJoint> _joints = [];
  Set<(int, int)> _overlaps = {};
  final Map<int, Collider> _byId = {};
  final List<int> _layerCollisionMatrix = List.filled(32, -1);
  final Map<(int, int), List<(double, double, double)>> _warmStartCache = {};

  PhysicsWorld._(this._scene);

  List<Collider> get colliders => List.unmodifiable(_colliders);
  List<RigidBody> get bodies => List.unmodifiable(_bodies);
  List<PhysicsJoint> get joints => List.unmodifiable(_joints);

  /// Returns whether objects on [layerA] (0..31) can collide with [layerB]
  /// according to the global physics layer matrix (E17-1).
  bool getLayerCollision(int layerA, int layerB) {
    if (layerA < 0 || layerA > 31 || layerB < 0 || layerB > 31) return false;
    return (_layerCollisionMatrix[layerA] & (1 << layerB)) != 0;
  }

  /// Enables or disables collisions between all objects on [layerA] and [layerB] (E17-1).
  void setLayerCollision(int layerA, int layerB, bool canCollide) {
    if (layerA < 0 || layerA > 31 || layerB < 0 || layerB > 31) {
      throw RangeError('Layers must be in range 0..31');
    }
    if (canCollide) {
      _layerCollisionMatrix[layerA] |= (1 << layerB);
      _layerCollisionMatrix[layerB] |= (1 << layerA);
    } else {
      _layerCollisionMatrix[layerA] &= ~(1 << layerB);
      _layerCollisionMatrix[layerB] &= ~(1 << layerA);
    }
  }

  /// Applies [explosionForce] to all active dynamic [RigidBody]s within
  /// [explosionRadius] of [epicenter] (E17-2).
  void addExplosionForce(
    double explosionForce,
    Vec3 epicenter,
    double explosionRadius, {
    double upwardsModifier = 0.0,
  }) {
    for (final b in _bodies) {
      if (b._active && !b.isKinematic && !b._destroyRequested) {
        b.addExplosionForce(
          explosionForce,
          epicenter,
          explosionRadius,
          upwardsModifier: upwardsModifier,
        );
      }
    }
  }

  /// Collider pairs that overlapped during the last fixed step (E15-1).
  Iterable<(Collider, Collider)> get contactPairs sync* {
    for (final (ia, ib) in _overlaps) {
      final a = _byId[ia], b = _byId[ib];
      if (a != null && b != null && a._active && b._active) yield (a, b);
    }
  }

  void _register(Collider c) {
    _colliders.add(c);
    _byId[c.instanceId] = c;
    broadphase.upsert(c);
  }

  void _unregister(Collider c) {
    _colliders.remove(c);
    _byId.remove(c.instanceId);
    broadphase.remove(c);
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

  void _registerJoint(PhysicsJoint joint) => _joints.add(joint);
  void _unregisterJoint(PhysicsJoint joint) => _joints.remove(joint);

  /// Every active collider overlapping the sphere ([center], [radius]) whose
  /// object layer is enabled in [layerMask].
  Iterable<Collider> overlapSphere(
    Vec3 center,
    double radius, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) sync* {
    broadphase.sync(_colliders);
    final candidates = broadphase.querySphere(center, radius);
    for (final c in candidates) {
      if (!c._active || c._destroyRequested) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      if (c.intersectsSphere(center, radius)) yield c;
    }
  }

  /// Every active collider overlapping the world-space AABB [bounds] whose
  /// object layer is enabled in [layerMask] (E12-2).
  Iterable<Collider> overlapBox(
    Aabb bounds, {
    int layerMask = -1,
    bool includeTriggers = true,
  }) sync* {
    broadphase.sync(_colliders);
    final candidates = broadphase.queryAabb(bounds);
    for (final c in candidates) {
      if (!c._active || c._destroyRequested) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      if (c.intersectsAabb(bounds)) yield c;
    }
  }

  PhysicsHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    broadphase.sync(_colliders);
    Collider? best;
    var bestT = maxDistance;
    for (final c in broadphase.queryRay(ray, maxDistance: maxDistance)) {
      if (!c._active || c._destroyRequested) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final t = c._raycast(ray);
      if (t != null && t <= bestT) {
        bestT = t;
        best = c;
      }
    }
    return best == null
        ? null
        : PhysicsHit(collider: best, point: ray.at(bestT), distance: bestT);
  }

  /// Returns all colliders intersected by [ray] within [maxDistance], sorted by
  /// ascending hit distance (E12-2).
  List<PhysicsHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = -1,
    bool includeTriggers = true,
  }) {
    broadphase.sync(_colliders);
    final hits = <PhysicsHit>[];
    for (final c in broadphase.queryRay(ray, maxDistance: maxDistance)) {
      if (!c._active || c._destroyRequested) continue;
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
    broadphase.sync(_colliders);
    Collider? best;
    var bestT = maxDistance;
    for (final c in broadphase.querySweptSphere(
      ray,
      r,
      maxDistance: maxDistance,
    )) {
      if (!c._active || c._destroyRequested) continue;
      if (!includeTriggers && c.isTrigger) continue;
      if ((layerMask & (1 << c.gameObject.layer)) == 0) continue;
      final t = c.sweepSphere(ray, r);
      if (t != null && t <= bestT) {
        bestT = t;
        best = c;
      }
    }
    return best == null
        ? null
        : PhysicsHit(collider: best, point: ray.at(bestT), distance: bestT);
  }

  void _performCcd(double dt) {
    for (final body in _bodies) {
      if (!body._active ||
          body._destroyRequested ||
          body.isKinematic ||
          body.isSleeping) {
        continue;
      }
      if (!body.useContinuousCollision) continue;

      final disp = body.velocity * dt;
      final dist = disp.length;
      if (dist < 1e-4) continue;

      final dir = disp * (1.0 / dist);
      final startPos = body.transform.position;
      final ray = Ray(origin: startPos, direction: dir);

      final col = body.getComponent<Collider>();
      final radius = col is SphereCollider
          ? col.worldRadius
          : ((col != null) ? col.worldBounds.extent.length * 0.5 : 0.5);

      broadphase.sync(_colliders);
      final candidates = broadphase.querySweptSphere(
        ray,
        radius,
        maxDistance: dist,
      );

      Collider? closestCol;
      var closestT = dist;

      for (final c in candidates) {
        if (!c._active || c._destroyRequested || c.isTrigger) continue;
        if (identical(c.gameObject, body.gameObject)) continue;
        if (!getLayerCollision(body.gameObject.layer, c.gameObject.layer)) {
          continue;
        }

        final t = c.sweepSphere(ray, radius);
        if (t != null && t >= 0.0 && t <= closestT) {
          closestT = t;
          closestCol = c;
        }
      }

      if (closestCol != null) {
        final safeT = math.max(0.0, closestT - 0.005);
        body.transform.position = startPos + dir * safeT;
        body._integrateOrientation(dt * (safeT / dist));

        final otherBody = closestCol.getComponent<RigidBody>();
        otherBody?.wakeUp();

        var normal = -dir;
        if (col != null) {
          final m = PhysicsNarrowphase.computeContactManifold(col, closestCol);
          if (m != null) normal = m.normal;
        }
        final vn = body.velocity.dot(normal);
        if (vn < 0) {
          final rest = math.min(
            body.restitution,
            otherBody?.restitution ?? 0.5,
          );
          final j = -(1.0 + rest) * vn;
          body.velocity += normal * j;
          if (otherBody != null && !otherBody.isKinematic) {
            otherBody.addImpulse(-normal * (j * body.mass));
          }
        }

        final myCol = col ?? closestCol;
        _notifyCollision(
          myCol,
          Collision(
            other: closestCol,
            contactNormal: -normal,
            penetrationDepth: 0.01,
            relativeVelocity:
                body.velocity - (otherBody?.velocity ?? Vec3.zero),
          ),
        );
        _notifyCollision(
          closestCol,
          Collision(
            other: myCol,
            contactNormal: normal,
            penetrationDepth: 0.01,
            relativeVelocity:
                (otherBody?.velocity ?? Vec3.zero) - body.velocity,
          ),
        );
      } else {
        body.transform.position += disp;
        body._integrateOrientation(dt);
      }
    }
  }

  void _step() {
    final dt = _scene._engine?.time.fixedDeltaTime ?? (1.0 / 60.0);
    for (final body in List.of(_bodies)) {
      if (body._active && !body._destroyRequested) {
        body._integrate(dt, gravity);
      }
    }

    _performCcd(dt);

    final active = _colliders
        .where((c) => c._active && !c._destroyRequested)
        .toList();
    broadphase.sync(active);
    final next = <(int, int)>{};
    final candidatePairs = broadphase.queryCandidatePairs(active);

    candidatePairs.sort((p1, p2) {
      final k1a = math.min(p1.$1.instanceId, p1.$2.instanceId);
      final k1b = math.max(p1.$1.instanceId, p1.$2.instanceId);
      final k2a = math.min(p2.$1.instanceId, p2.$2.instanceId);
      final k2b = math.max(p2.$1.instanceId, p2.$2.instanceId);
      final c = k1a.compareTo(k2a);
      return c != 0 ? c : k1b.compareTo(k2b);
    });

    final solidPairs =
        <(Collider, Collider, PhysicsContactManifold, bool isNew)>[];

    for (final (a, b) in candidatePairs) {
      if (identical(a.gameObject, b.gameObject)) continue;
      if (!getLayerCollision(a.gameObject.layer, b.gameObject.layer)) {
        continue;
      }
      final aBit = 1 << a.gameObject.layer;
      final bBit = 1 << b.gameObject.layer;
      if ((a.collidesWithMask & bBit) == 0 ||
          (b.collidesWithMask & aBit) == 0) {
        continue;
      }
      if (!PhysicsNarrowphase.intersects(a, b)) continue;

      final key = a.instanceId < b.instanceId
          ? (a.instanceId, b.instanceId)
          : (b.instanceId, a.instanceId);
      final isNew = !_overlaps.contains(key);
      next.add(key);

      final rbA = a.getComponent<RigidBody>();
      final rbB = b.getComponent<RigidBody>();
      if (rbA != null && rbB != null) {
        if (!rbA.isKinematic && !rbA.isSleeping && rbB.isSleeping) {
          rbB.wakeUp();
        }
        if (!rbB.isKinematic && !rbB.isSleeping && rbA.isSleeping) {
          rbA.wakeUp();
        }
      }

      if (!a.isTrigger && !b.isTrigger) {
        final manifold = PhysicsNarrowphase.computeContactManifold(a, b);
        if (manifold != null && manifold.depth > 0) {
          solidPairs.add((a, b, manifold, isNew));
        }
      }

      final phase = isNew ? _Phase.enter : _Phase.stay;
      if (a._active && b._active) _notify(a, b, phase);
      if (a._active && b._active) _notify(b, a, phase);
    }

    for (final key in _overlaps) {
      if (!next.contains(key)) {
        final a = _byId[key.$1];
        final b = _byId[key.$2];
        if (a != null && b != null) {
          if (a._active) _notify(a, b, _Phase.exit);
          if (b._active) _notify(b, a, _Phase.exit);
        }
        _warmStartCache.remove(key);
      }
    }

    final constraints = <_SolidContactConstraint>[];
    for (final (a, b, manifold, isNew) in solidPairs) {
      final c = PhysicsSolver._buildContactConstraint(
        a,
        b,
        manifold,
        _warmStartCache,
        dt,
      );
      if (c != null) constraints.add(c);

      if (isNew) {
        final velA = a.getComponent<RigidBody>()?.velocity ?? Vec3.zero;
        final velB = b.getComponent<RigidBody>()?.velocity ?? Vec3.zero;
        final relVel = velB - velA;
        if (a._active && b._active) {
          _notifyCollision(
            a,
            Collision(
              other: b,
              contactNormal: -manifold.normal,
              penetrationDepth: manifold.depth,
              relativeVelocity: -relVel,
            ),
          );
        }
        if (a._active && b._active) {
          _notifyCollision(
            b,
            Collision(
              other: a,
              contactNormal: manifold.normal,
              penetrationDepth: manifold.depth,
              relativeVelocity: relVel,
            ),
          );
        }
      }
    }

    final activeJoints =
        _joints
            .where((j) => j._active && !j._destroyRequested && !j.isBroken)
            .toList()
          ..sort((j1, j2) => j1.instanceId.compareTo(j2.instanceId));

    final iters = solverIterations > 0 ? solverIterations : 10;
    for (var iter = 0; iter < iters; iter++) {
      for (final joint in activeJoints) {
        joint._solve(dt, 0.2);
      }
      for (final c in constraints) {
        PhysicsSolver._solveContactConstraint(c);
      }
    }

    for (final c in constraints) {
      final key = c.colliderA.instanceId < c.colliderB.instanceId
          ? (c.colliderA.instanceId, c.colliderB.instanceId)
          : (c.colliderB.instanceId, c.colliderA.instanceId);
      _warmStartCache[key] = c.points
          .map((p) => (p.normalImpulse, 0.0, 0.0))
          .toList();
      PhysicsSolver._applyPositionCorrection(c);
    }

    for (final body in _bodies) {
      if (body.isSleeping) {
        body.velocity = Vec3.zero;
        body.angularVelocity = Vec3.zero;
      }
    }

    _overlaps = next;
  }

  void _notifyCollision(Collider receiver, Collision collision) {
    for (final c in List.of(receiver.gameObject._components)) {
      if (c is Behaviour && c._active && !c._destroyRequested) {
        _scene._guard(() => c.onCollisionEnter(collision));
      }
    }
  }

  /// Contact normal (pointing from [a] toward [b]) and penetration depth for
  /// two colliders, or null when separated. Exposed for gizmos/inspectors.
  static (Vec3 normal, double depth)? debugManifold(Collider a, Collider b) =>
      PhysicsNarrowphase.computeManifold(a, b);

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
}

enum _Phase { enter, stay, exit }
