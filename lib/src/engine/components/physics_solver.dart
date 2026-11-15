part of '../../engine.dart';

final class PhysicsHit {
  final Collider collider;
  final Vec3 point;
  final double distance;

  const PhysicsHit({
    required this.collider,
    required this.point,
    required this.distance,
  });

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
/// steps with rotational dynamics, sequential impulse resolution, sleeping and CCD.
final class RigidBody extends Component {
  Vec3 velocity;
  Vec3 angularVelocity;
  double mass;
  double gravityScale;
  double linearDrag;
  double angularDrag;
  double restitution;
  double staticFriction;
  double dynamicFriction;
  bool isKinematic;
  bool useGravity;
  bool freezeY;
  bool freezeRotation;
  bool useContinuousCollision;
  bool canSleep;
  bool isSleeping;
  Vec3? inertiaTensorOverride;

  Vec3 _accumulatedForce = Vec3.zero;
  Vec3 _accumulatedTorque = Vec3.zero;
  double _sleepTimer = 0.0;
  static const double _sleepLinearThresholdSq = 0.09;
  static const double _sleepAngularThresholdSq = 0.09;
  static const double _sleepTimeRequired = 0.3;

  RigidBody({
    this.velocity = Vec3.zero,
    this.angularVelocity = Vec3.zero,
    this.mass = 1.0,
    this.gravityScale = 1.0,
    this.linearDrag = 0.05,
    this.angularDrag = 0.05,
    this.restitution = 0.5,
    this.staticFriction = 0.6,
    this.dynamicFriction = 0.4,
    this.isKinematic = false,
    this.useGravity = true,
    this.freezeY = false,
    this.freezeRotation = false,
    this.useContinuousCollision = false,
    this.canSleep = true,
    this.isSleeping = false,
    this.inertiaTensorOverride,
  });

  static final spec = ComponentSpec<RigidBody>('RigidBody', RigidBody.new, [
    Field.vec3('velocity', (r) => r.velocity, (r, v) => r.velocity = v),
    Field.number('mass', (r) => r.mass, (r, v) => r.mass = v),
    Field.number(
      'gravityScale',
      (r) => r.gravityScale,
      (r, v) => r.gravityScale = v,
    ),
    Field.number('linearDrag', (r) => r.linearDrag, (r, v) => r.linearDrag = v),
    Field.number(
      'restitution',
      (r) => r.restitution,
      (r, v) => r.restitution = v,
    ),
    Field.boolean(
      'isKinematic',
      (r) => r.isKinematic,
      (r, v) => r.isKinematic = v,
    ),
    Field.boolean(
      'useGravity',
      (r) => r.useGravity,
      (r, v) => r.useGravity = v,
    ),
    Field.boolean('freezeY', (r) => r.freezeY, (r, v) => r.freezeY = v),
    Field.vec3(
      'angularVelocity',
      (r) => r.angularVelocity,
      (r, v) => r.angularVelocity = v,
    ),
    Field.number(
      'angularDrag',
      (r) => r.angularDrag,
      (r, v) => r.angularDrag = v,
    ),
    Field.number(
      'staticFriction',
      (r) => r.staticFriction,
      (r, v) => r.staticFriction = v,
    ),
    Field.number(
      'dynamicFriction',
      (r) => r.dynamicFriction,
      (r, v) => r.dynamicFriction = v,
    ),
    Field.boolean(
      'freezeRotation',
      (r) => r.freezeRotation,
      (r, v) => r.freezeRotation = v,
    ),
    Field.boolean(
      'useContinuousCollision',
      (r) => r.useContinuousCollision,
      (r, v) => r.useContinuousCollision = v,
    ),
    Field.boolean('canSleep', (r) => r.canSleep, (r, v) => r.canSleep = v),
    Field.boolean(
      'isSleeping',
      (r) => r.isSleeping,
      (r, v) => r.isSleeping = v,
    ),
  ]);

  double get inverseMass => (isKinematic || mass <= 0) ? 0.0 : 1.0 / mass;

  /// Principal inertia tensor in body-local coordinates.
  Vec3 get inertiaTensor {
    if (inertiaTensorOverride != null) return inertiaTensorOverride!;
    if (mass <= 0) return const Vec3(1, 1, 1);
    final col = isAttached ? getComponent<Collider>() : null;
    if (col is BoxCollider) {
      final s = col.size;
      final m = mass;
      return Vec3(
        math.max(1e-4, (1.0 / 12.0) * m * (s.y * s.y + s.z * s.z)),
        math.max(1e-4, (1.0 / 12.0) * m * (s.x * s.x + s.z * s.z)),
        math.max(1e-4, (1.0 / 12.0) * m * (s.x * s.x + s.y * s.y)),
      );
    } else if (col is SphereCollider) {
      final r = col.radius;
      final val = math.max(1e-4, 0.4 * mass * r * r);
      return Vec3(val, val, val);
    } else if (col is CapsuleCollider) {
      final r = col.radius;
      final h = col.height;
      final iy = math.max(1e-4, 0.5 * mass * r * r);
      final ixz = math.max(1e-4, (1.0 / 12.0) * mass * (3 * r * r + h * h));
      return Vec3(ixz, iy, ixz);
    } else {
      final val = math.max(1e-4, (1.0 / 6.0) * mass);
      return Vec3(val, val, val);
    }
  }

  /// Inverse inertia tensor in body-local coordinates.
  Vec3 get inverseInertiaTensor {
    if (isKinematic || freezeRotation || mass <= 0) return Vec3.zero;
    final it = inertiaTensor;
    return Vec3(
      it.x > 1e-6 ? 1.0 / it.x : 0.0,
      it.y > 1e-6 ? 1.0 / it.y : 0.0,
      it.z > 1e-6 ? 1.0 / it.z : 0.0,
    );
  }

  /// Transforms [torque] from world space into local coordinates, multiplies
  /// by inverse inertia, and transforms back into world space.
  Vec3 applyInverseInertia(Vec3 torque) {
    if (isKinematic || freezeRotation || mass <= 0) return Vec3.zero;
    final invI = inverseInertiaTensor;
    final q = transform.rotation;
    final localTorque = q.inverse.rotate(torque);
    final localAngAccel = Vec3(
      localTorque.x * invI.x,
      localTorque.y * invI.y,
      localTorque.z * invI.z,
    );
    return q.rotate(localAngAccel);
  }

  /// Puts this body to sleep immediately, zeroing linear and angular velocities.
  void sleep() {
    if (!canSleep || isKinematic) return;
    isSleeping = true;
    velocity = Vec3.zero;
    angularVelocity = Vec3.zero;
    _sleepTimer = 0.0;
  }

  /// Wakes up this body from sleep.
  void wakeUp() {
    if (isSleeping) {
      isSleeping = false;
      _sleepTimer = 0.0;
    }
  }

  /// Applies a continuous force (in Newtons) for the next fixed step.
  void addForce(Vec3 force) {
    if (isKinematic) return;
    wakeUp();
    _accumulatedForce += force;
  }

  /// Applies a continuous torque (in N*m) for the next fixed step.
  void addTorque(Vec3 torque) {
    if (isKinematic || freezeRotation) return;
    wakeUp();
    _accumulatedTorque += torque;
  }

  /// Applies an instantaneous velocity impulse (`impulse / mass`).
  void addImpulse(Vec3 impulse) {
    if (isKinematic) return;
    wakeUp();
    velocity += impulse * inverseMass;
    if (freezeY) velocity = Vec3(velocity.x, 0, velocity.z);
  }

  /// Applies an instantaneous angular velocity impulse (`I^-1 * angularImpulse`).
  void addAngularImpulse(Vec3 angularImpulse) {
    if (isKinematic || freezeRotation) return;
    wakeUp();
    angularVelocity += applyInverseInertia(angularImpulse);
  }

  /// Applies a force at a specific [worldPoint], producing both linear force
  /// and angular torque $(\mathbf{r} \times \mathbf{F})$.
  void addForceAtPosition(Vec3 force, Vec3 worldPoint) {
    if (isKinematic) return;
    wakeUp();
    _accumulatedForce += force;
    if (!freezeRotation) {
      final r = worldPoint - transform.position;
      _accumulatedTorque += r.cross(force);
    }
  }

  /// Applies a radial explosion impulse radiating outward from [epicenter]
  /// within [explosionRadius] (E17-2).
  void addExplosionForce(
    double explosionForce,
    Vec3 epicenter,
    double explosionRadius, {
    double upwardsModifier = 0.0,
  }) {
    if (isKinematic || explosionRadius <= 0) return;
    wakeUp();
    var delta = transform.position - epicenter;
    if (upwardsModifier != 0) {
      delta = Vec3(delta.x, delta.y + upwardsModifier, delta.z);
    }
    final dist = delta.length;
    if (dist >= explosionRadius) return;
    final normDir = dist > 1e-6 ? delta * (1.0 / dist) : Vec3.unitY;
    final factor = 1.0 - (dist / explosionRadius);
    final impulse = normDir * (explosionForce * factor);
    addImpulse(impulse);
  }

  void _integrate(double dt, Vec3 worldGravity) {
    if (isKinematic || dt <= 0) {
      _accumulatedForce = Vec3.zero;
      _accumulatedTorque = Vec3.zero;
      return;
    }

    if (isSleeping) {
      _accumulatedForce = Vec3.zero;
      _accumulatedTorque = Vec3.zero;
      return;
    }

    // Linear velocity integration
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

    // Angular velocity integration
    if (!freezeRotation) {
      final angAccel = applyInverseInertia(_accumulatedTorque);
      angularVelocity += angAccel * dt;
      if (angularDrag > 0) {
        final dampFactor = math.max(0.0, 1.0 - angularDrag * dt);
        angularVelocity *= dampFactor;
      }
    } else {
      angularVelocity = Vec3.zero;
    }
    _accumulatedTorque = Vec3.zero;

    // Sleeping detection
    if (canSleep) {
      final speedSq = velocity.lengthSquared;
      final angSpeedSq = angularVelocity.lengthSquared;
      if (speedSq < _sleepLinearThresholdSq &&
          angSpeedSq < _sleepAngularThresholdSq) {
        _sleepTimer += dt;
        if (_sleepTimer >= _sleepTimeRequired) {
          sleep();
          return;
        }
      } else {
        _sleepTimer = 0.0;
      }
    }

    // If useContinuousCollision is true, position update is handled by swept CCD in PhysicsWorld
    if (!useContinuousCollision) {
      if (velocity.lengthSquared > 1e-12) {
        transform.position += velocity * dt;
      }
      _integrateOrientation(dt);
    }
  }

  void _integrateOrientation(double dt) {
    if (freezeRotation) return;
    final angSpeed = angularVelocity.length;
    if (angSpeed > 1e-8) {
      final angle = angSpeed * dt;
      final axis = angularVelocity * (1.0 / angSpeed);
      final dq = Quat.axisAngle(axis, angle);
      transform.rotation = (dq * transform.rotation).normalized;
    }
  }

  @override
  void _onEnableInternal() => scene.physics._registerBody(this);

  @override
  void _onDisableInternal() => scene.physics._unregisterBody(this);
}

final class _ContactPointConstraint {
  final Vec3 point;
  final double depth;
  final Vec3 rA;
  final Vec3 rB;
  final Vec3 normal;
  final double normalEffectiveMass;
  final double velocityBias;
  final double restitutionVelocity;

  double normalImpulse = 0.0;

  _ContactPointConstraint({
    required this.point,
    required this.depth,
    required this.rA,
    required this.rB,
    required this.normal,
    required this.normalEffectiveMass,
    required this.velocityBias,
    required this.restitutionVelocity,
  });
}

final class _SolidContactConstraint {
  final Collider colliderA;
  final Collider colliderB;
  final RigidBody? bodyA;
  final RigidBody? bodyB;
  final double friction;
  final List<_ContactPointConstraint> points;

  _SolidContactConstraint({
    required this.colliderA,
    required this.colliderB,
    required this.bodyA,
    required this.bodyB,
    required this.friction,
    required this.points,
  });

  double get totalNormalImpulse {
    var sum = 0.0;
    for (final pt in points) {
      sum += pt.normalImpulse;
    }
    return sum;
  }
}

/// Sequential impulse contact solver helper invoked by [PhysicsWorld].
abstract final class PhysicsSolver {
  /// Resolves an immediate solid collision (backward compatibility).
  static void resolveSolidCollision(
    Collider a,
    Collider b, {
    required bool isNew,
    required void Function(Collider receiver, Collision collision)
    onNotifyCollision,
  }) {
    final rbA = a.getComponent<RigidBody>();
    final rbB = b.getComponent<RigidBody>();
    final invMassA = rbA?.inverseMass ?? 0.0;
    final invMassB = rbB?.inverseMass ?? 0.0;
    final totalInvMass = invMassA + invMassB;
    if (totalInvMass <= 0) return;

    final manifold = PhysicsNarrowphase.computeManifold(a, b);
    if (manifold == null) return;
    final (normal, depth) = manifold;

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
        onNotifyCollision(
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
        onNotifyCollision(
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

  static List<(Vec3 point, double depth)> _computeContactPoints(
    Collider a,
    Collider b,
    PhysicsContactManifold manifold,
  ) {
    if (a is BoxCollider && b is BoxCollider) {
      final norm = manifold.normal;
      final scaleA = a.transform.lossyScale;
      final scaleB = b.transform.lossyScale;
      final sizeA = a.size * scaleA;
      final sizeB = b.size * scaleB;

      final areaA = sizeA.x * sizeA.z;
      final areaB = sizeB.x * sizeB.z;
      final refBox = areaB <= areaA ? b : a;

      final localNorm = refBox.transform.rotation.inverse.rotate(norm);
      final ax = localNorm.x.abs();
      final ay = localNorm.y.abs();
      final az = localNorm.z.abs();

      final Vec3 localT1;
      final Vec3 localT2;
      final double localDist;

      if (ay >= ax && ay >= az) {
        final hx = math.min(sizeA.x, sizeB.x) * 0.4;
        final hz = math.min(sizeA.z, sizeB.z) * 0.4;
        localT1 = Vec3(hx, 0, 0);
        localT2 = Vec3(0, 0, hz);
        localDist = (refBox.size.y * 0.5 * refBox.transform.lossyScale);
      } else if (ax >= ay && ax >= az) {
        final hy = math.min(sizeA.y, sizeB.y) * 0.4;
        final hz = math.min(sizeA.z, sizeB.z) * 0.4;
        localT1 = Vec3(0, hy, 0);
        localT2 = Vec3(0, 0, hz);
        localDist = (refBox.size.x * 0.5 * refBox.transform.lossyScale);
      } else {
        final hx = math.min(sizeA.x, sizeB.x) * 0.4;
        final hy = math.min(sizeA.y, sizeB.y) * 0.4;
        localT1 = Vec3(hx, 0, 0);
        localT2 = Vec3(0, hy, 0);
        localDist = (refBox.size.z * 0.5 * refBox.transform.lossyScale);
      }

      final t1 = refBox.transform.rotation.rotate(localT1);
      final t2 = refBox.transform.rotation.rotate(localT2);

      final Vec3 contactCenter;
      if (identical(refBox, b)) {
        contactCenter =
            b.worldCenter - norm * (localDist - manifold.depth * 0.5);
      } else {
        contactCenter =
            a.worldCenter + norm * (localDist - manifold.depth * 0.5);
      }

      return [
        (contactCenter + t1 + t2, manifold.depth),
        (contactCenter - t1 + t2, manifold.depth),
        (contactCenter - t1 - t2, manifold.depth),
        (contactCenter + t1 - t2, manifold.depth),
      ];
    }

    if (manifold.contactPoints.isNotEmpty) {
      return manifold.contactPoints.map((p) => (p, manifold.depth)).toList();
    }
    final defaultPt = a.worldCenter + manifold.normal * (manifold.depth * 0.5);
    return [(defaultPt, manifold.depth)];
  }

  static _SolidContactConstraint? _buildContactConstraint(
    Collider a,
    Collider b,
    PhysicsContactManifold manifold,
    Map<(int, int), List<(double, double, double)>> warmStartCache,
    double dt,
  ) {
    final rbA = a.getComponent<RigidBody>();
    final rbB = b.getComponent<RigidBody>();
    final invMassA = rbA?.inverseMass ?? 0.0;
    final invMassB = rbB?.inverseMass ?? 0.0;
    if (invMassA + invMassB <= 0.0) return null;

    final normal = manifold.normal;

    final dynamicMuA = rbA?.dynamicFriction ?? 0.4;
    final dynamicMuB = rbB?.dynamicFriction ?? 0.4;
    final friction = math.sqrt(dynamicMuA * dynamicMuB);

    final restA = rbA?.restitution ?? 0.5;
    final restB = rbB?.restitution ?? 0.5;
    final restitution = math.min(restA, restB);

    final pairKey = a.instanceId < b.instanceId
        ? (a.instanceId, b.instanceId)
        : (b.instanceId, a.instanceId);
    final cachedWarm = warmStartCache[pairKey];

    final rawPoints = _computeContactPoints(a, b, manifold);
    final pointConstraints = <_ContactPointConstraint>[];

    for (var i = 0; i < rawPoints.length; i++) {
      final (pt, depth) = rawPoints[i];
      final rA = pt - a.transform.position;
      final rB = pt - b.transform.position;

      final uA = rA.cross(normal);
      final uB = rB.cross(normal);
      final rotA = (rbA != null && !rbA.freezeRotation)
          ? uA.dot(rbA.applyInverseInertia(uA))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? uB.dot(rbB.applyInverseInertia(uB))
          : 0.0;
      final kn = invMassA + invMassB + rotA + rotB;
      final normalEffMass = kn > 1e-12 ? 1.0 / kn : 0.0;

      const slop = 0.002;
      const baumgarte = 0.2;
      final excessDepth = math.max(0.0, depth - slop);
      final vBias = (excessDepth * (baumgarte / dt)).clamp(0.0, 5.0);

      final vA =
          (rbA?.velocity ?? Vec3.zero) +
          (rbA != null && !rbA.freezeRotation
              ? rbA.angularVelocity.cross(rA)
              : Vec3.zero);
      final vB =
          (rbB?.velocity ?? Vec3.zero) +
          (rbB != null && !rbB.freezeRotation
              ? rbB.angularVelocity.cross(rB)
              : Vec3.zero);
      final relVel = vB - vA;
      final velAlongNormal = relVel.dot(normal);

      var vRest = 0.0;
      if (velAlongNormal < -0.5) {
        vRest = -velAlongNormal * restitution;
      }

      final pc = _ContactPointConstraint(
        point: pt,
        depth: depth,
        rA: rA,
        rB: rB,
        normal: normal,
        normalEffectiveMass: normalEffMass,
        velocityBias: vBias,
        restitutionVelocity: vRest,
      );

      if (cachedWarm != null && i < cachedWarm.length) {
        final (wn, _, _) = cachedWarm[i];
        pc.normalImpulse = wn * 0.8;

        final warmImp = normal * pc.normalImpulse;
        if (invMassA > 0) {
          rbA!.velocity -= warmImp * invMassA;
          if (!rbA.freezeRotation) {
            rbA.angularVelocity -= rbA.applyInverseInertia(rA.cross(warmImp));
          }
        }
        if (invMassB > 0) {
          rbB!.velocity += warmImp * invMassB;
          if (!rbB.freezeRotation) {
            rbB.angularVelocity += rbB.applyInverseInertia(rB.cross(warmImp));
          }
        }
      }

      pointConstraints.add(pc);
    }

    return _SolidContactConstraint(
      colliderA: a,
      colliderB: b,
      bodyA: rbA,
      bodyB: rbB,
      friction: friction,
      points: pointConstraints,
    );
  }

  static void _solveContactConstraint(_SolidContactConstraint c) {
    final rbA = c.bodyA;
    final rbB = c.bodyB;
    final invMassA = rbA?.inverseMass ?? 0.0;
    final invMassB = rbB?.inverseMass ?? 0.0;

    // 1. Normal impulses at each point
    for (final pt in c.points) {
      final vA =
          (rbA?.velocity ?? Vec3.zero) +
          (rbA != null && !rbA.freezeRotation
              ? rbA.angularVelocity.cross(pt.rA)
              : Vec3.zero);
      final vB =
          (rbB?.velocity ?? Vec3.zero) +
          (rbB != null && !rbB.freezeRotation
              ? rbB.angularVelocity.cross(pt.rB)
              : Vec3.zero);
      final relVel = vB - vA;
      final vn = relVel.dot(pt.normal);
      final deltaV = -vn + pt.velocityBias + pt.restitutionVelocity;
      final deltaPn = deltaV * pt.normalEffectiveMass;
      final newPn = math.max(0.0, pt.normalImpulse + deltaPn);
      final actualPn = newPn - pt.normalImpulse;
      pt.normalImpulse = newPn;
      final impN = pt.normal * actualPn;

      if (invMassA > 0) {
        rbA!.velocity -= impN * invMassA;
        if (!rbA.freezeRotation) {
          rbA.angularVelocity -= rbA.applyInverseInertia(pt.rA.cross(impN));
        }
      }
      if (invMassB > 0) {
        rbB!.velocity += impN * invMassB;
        if (!rbB.freezeRotation) {
          rbB.angularVelocity += rbB.applyInverseInertia(pt.rB.cross(impN));
        }
      }
    }

    // 2. Direct Coulomb friction opposing relative tangential velocity
    final totalNormal = c.totalNormalImpulse;
    if (totalNormal > 0 && c.friction > 0) {
      final totalInvMass = invMassA + invMassB;
      if (totalInvMass > 0) {
        final vA = rbA?.velocity ?? Vec3.zero;
        final vB = rbB?.velocity ?? Vec3.zero;
        final relVel = vB - vA;
        final norm = c.points.first.normal;
        final normalComp = norm * relVel.dot(norm);
        final tangentVel = relVel - normalComp;
        final speed = tangentVel.length;
        if (speed > 1e-4) {
          final tDir = tangentVel * (1.0 / speed);
          final maxFriction = c.friction * totalNormal;
          final desiredImpulse = speed / totalInvMass;
          final frictionMag = math.min(desiredImpulse, maxFriction);
          final impFriction = tDir * frictionMag;

          if (invMassA > 0) {
            rbA!.velocity += impFriction * invMassA;
          }
          if (invMassB > 0) {
            rbB!.velocity -= impFriction * invMassB;
          }
        }
      }
    }
  }

  static void _applyPositionCorrection(_SolidContactConstraint c) {
    final rbA = c.bodyA;
    final rbB = c.bodyB;
    final invMassA = rbA?.inverseMass ?? 0.0;
    final invMassB = rbB?.inverseMass ?? 0.0;
    final totalInvMass = invMassA + invMassB;
    if (totalInvMass <= 0.0) return;

    var maxDepth = 0.0;
    for (final pt in c.points) {
      if (pt.depth > maxDepth) maxDepth = pt.depth;
    }
    const slop = 0.005;
    if (maxDepth > slop) {
      final corr = (maxDepth - slop) * 0.2;
      final norm = c.points.first.normal;
      if (invMassA > 0) {
        c.colliderA.transform.position -=
            norm * (corr * (invMassA / totalInvMass));
      }
      if (invMassB > 0) {
        c.colliderB.transform.position +=
            norm * (corr * (invMassB / totalInvMass));
      }
    }
  }
}
