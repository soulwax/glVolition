part of '../../engine.dart';

/// Rotates its [GameObject] in `lateUpdate` to face towards [target] (E25-2).
final class LookAtConstraint extends Behaviour {
  TransformComponent? target;
  Vec3 upAxis;
  double weight;

  LookAtConstraint({this.target, this.upAxis = kUp, this.weight = 1.0});

  static final spec = ComponentSpec<LookAtConstraint>(
    'LookAtConstraint',
    LookAtConstraint.new,
    [
      Field.number('weight', (c) => c.weight, (c, v) => c.weight = v),
      Field.vec3('upAxis', (c) => c.upAxis, (c, v) => c.upAxis = v),
    ],
  );

  @override
  void lateUpdate() {
    final t = target;
    if (t == null || !t.isAttached || weight <= 0.0) return;

    final dir = t.position - transform.position;
    if (dir.lengthSquared < 1e-10) return;

    final targetRot = lookRotation(dir, upAxis);
    if (weight >= 1.0) {
      transform.rotation = targetRot;
    } else {
      transform.rotation = Mathfx.slerp(transform.rotation, targetRot, weight);
    }
  }
}

/// Follows a [target] transform with a spatial [offset] and optional smoothing (E25-2).
final class FollowConstraint extends Behaviour {
  TransformComponent? target;
  Vec3 offset;
  double smoothing;
  bool lockX;
  bool lockY;
  bool lockZ;

  FollowConstraint({
    this.target,
    this.offset = Vec3.zero,
    this.smoothing = 0.0,
    this.lockX = false,
    this.lockY = false,
    this.lockZ = false,
  });

  static final spec = ComponentSpec<FollowConstraint>(
    'FollowConstraint',
    FollowConstraint.new,
    [
      Field.vec3('offset', (c) => c.offset, (c, v) => c.offset = v),
      Field.number('smoothing', (c) => c.smoothing, (c, v) => c.smoothing = v),
      Field.boolean('lockX', (c) => c.lockX, (c, v) => c.lockX = v),
      Field.boolean('lockY', (c) => c.lockY, (c, v) => c.lockY = v),
      Field.boolean('lockZ', (c) => c.lockZ, (c, v) => c.lockZ = v),
    ],
  );

  @override
  void lateUpdate() {
    final t = target;
    if (t == null || !t.isAttached) return;

    final cur = transform.position;
    final targetPos = t.position + offset;
    final desired = Vec3(
      lockX ? cur.x : targetPos.x,
      lockY ? cur.y : targetPos.y,
      lockZ ? cur.z : targetPos.z,
    );

    if (smoothing <= 0.0) {
      transform.position = desired;
    } else {
      final dt = isAttached ? time.deltaTime : 1 / 60;
      transform.position = Mathfx.dampVec3(cur, desired, smoothing, dt);
    }
  }
}

/// Base class for 3D physics joints connecting two rigidbodies (or a rigidbody to the world).
abstract base class PhysicsJoint extends Component {
  /// The other rigidbody this joint connects to. If null, the joint is anchored to the world.
  RigidBody? connectedBody;

  /// Anchor point in local space of this GameObject.
  Vec3 anchor;

  /// Anchor point in local space of [connectedBody] (or world space if [connectedBody] == null).
  Vec3 connectedAnchor;

  /// Maximum force this joint can sustain before breaking (<= 0 for unbreakable).
  double breakForce;

  /// Maximum torque this joint can sustain before breaking (<= 0 for unbreakable).
  double breakTorque;

  /// Whether the joint has broken.
  bool isBroken = false;

  PhysicsJoint({
    this.connectedBody,
    this.anchor = Vec3.zero,
    this.connectedAnchor = Vec3.zero,
    this.breakForce = 0.0,
    this.breakTorque = 0.0,
  });

  /// The primary rigidbody attached to this GameObject.
  RigidBody? get body => getComponent<RigidBody>();

  /// Anchor on this GameObject in world space.
  Vec3 get worldAnchor => transform.transformPoint(anchor);

  /// Anchor on [connectedBody] in world space.
  Vec3 get worldConnectedAnchor {
    final cb = connectedBody;
    if (cb == null) return connectedAnchor;
    return cb.transform.transformPoint(connectedAnchor);
  }

  @override
  void _onEnableInternal() => scene.physics._registerJoint(this);

  @override
  void _onDisableInternal() => scene.physics._unregisterJoint(this);

  /// Solves velocity and positional constraints for this joint during a solver iteration.
  void _solve(double dt, double baumgarte);
}

/// Fixed joint locking both relative translation and relative rotation between two bodies.
final class FixedJoint extends PhysicsJoint {
  FixedJoint({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.breakForce,
    super.breakTorque,
  });

  static final spec = ComponentSpec<FixedJoint>('FixedJoint', FixedJoint.new, [
    Field.vec3('anchor', (j) => j.anchor, (j, v) => j.anchor = v),
    Field.vec3(
      'connectedAnchor',
      (j) => j.connectedAnchor,
      (j, v) => j.connectedAnchor = v,
    ),
    Field.number('breakForce', (j) => j.breakForce, (j, v) => j.breakForce = v),
    Field.number(
      'breakTorque',
      (j) => j.breakTorque,
      (j, v) => j.breakTorque = v,
    ),
  ]);

  @override
  void _solve(double dt, double baumgarte) {
    final rbA = body;
    if (rbA == null ||
        (rbA.isKinematic &&
            (connectedBody == null || connectedBody!.isKinematic))) {
      return;
    }
    final rbB = connectedBody;
    final pA = worldAnchor;
    final pB = worldConnectedAnchor;
    final rA = pA - transform.position;
    final rB = rbB != null ? pB - rbB.transform.position : Vec3.zero;

    final vA =
        rbA.velocity +
        (!rbA.freezeRotation ? rbA.angularVelocity.cross(rA) : Vec3.zero);
    final vB =
        (rbB?.velocity ?? Vec3.zero) +
        (rbB != null && !rbB.freezeRotation
            ? rbB.angularVelocity.cross(rB)
            : Vec3.zero);

    final relVel = vA - vB;
    final posError = pA - pB;
    final bias = posError * (baumgarte / dt);
    final target = -(relVel + bias);

    final invMassA = rbA.inverseMass;
    final invMassB = rbB?.inverseMass ?? 0.0;

    for (final axis in const [Vec3.unitX, Vec3.unitY, Vec3.unitZ]) {
      final uA = rA.cross(axis);
      final uB = rB.cross(axis);
      final rotA = !rbA.freezeRotation
          ? uA.dot(rbA.applyInverseInertia(uA))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? uB.dot(rbB.applyInverseInertia(uB))
          : 0.0;
      final k = invMassA + invMassB + rotA + rotB;
      if (k > 1e-12) {
        final impulseMag = target.dot(axis) / k;
        final impulse = axis * impulseMag;
        if (invMassA > 0) {
          rbA.velocity += impulse * invMassA;
          if (!rbA.freezeRotation) {
            rbA.angularVelocity += rbA.applyInverseInertia(rA.cross(impulse));
          }
        }
        if (rbB != null && invMassB > 0) {
          rbB.velocity -= impulse * invMassB;
          if (!rbB.freezeRotation) {
            rbB.angularVelocity -= rbB.applyInverseInertia(rB.cross(impulse));
          }
        }
        if (breakForce > 0 && (impulseMag / dt).abs() > breakForce) {
          isBroken = true;
          return;
        }
      }
    }

    final wA = !rbA.freezeRotation ? rbA.angularVelocity : Vec3.zero;
    final wB = (rbB != null && !rbB.freezeRotation)
        ? rbB.angularVelocity
        : Vec3.zero;
    final relAngVel = wA - wB;

    final qA = transform.rotation;
    final qB = rbB?.transform.rotation ?? Quat.identity;
    final qRel = qA * qB.inverse;
    final angError = Vec3(qRel.x, qRel.y, qRel.z) * 2.0;
    final angTarget = -(relAngVel + angError * (baumgarte / dt));

    for (final axis in const [Vec3.unitX, Vec3.unitY, Vec3.unitZ]) {
      final rotA = !rbA.freezeRotation
          ? axis.dot(rbA.applyInverseInertia(axis))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? axis.dot(rbB.applyInverseInertia(axis))
          : 0.0;
      final k = rotA + rotB;
      if (k > 1e-12) {
        final torqueMag = angTarget.dot(axis) / k;
        final torque = axis * torqueMag;
        if (!rbA.freezeRotation && invMassA > 0) {
          rbA.angularVelocity += rbA.applyInverseInertia(torque);
        }
        if (rbB != null && !rbB.freezeRotation && invMassB > 0) {
          rbB.angularVelocity -= rbB.applyInverseInertia(torque);
        }
        if (breakTorque > 0 && (torqueMag / dt).abs() > breakTorque) {
          isBroken = true;
          return;
        }
      }
    }
  }
}

/// Spherical ball-and-socket joint locking translation at anchor while allowing free rotation.
final class BallJoint extends PhysicsJoint {
  BallJoint({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.breakForce,
    super.breakTorque,
  });

  static final spec = ComponentSpec<BallJoint>('BallJoint', BallJoint.new, [
    Field.vec3('anchor', (j) => j.anchor, (j, v) => j.anchor = v),
    Field.vec3(
      'connectedAnchor',
      (j) => j.connectedAnchor,
      (j, v) => j.connectedAnchor = v,
    ),
    Field.number('breakForce', (j) => j.breakForce, (j, v) => j.breakForce = v),
    Field.number(
      'breakTorque',
      (j) => j.breakTorque,
      (j, v) => j.breakTorque = v,
    ),
  ]);

  @override
  void _solve(double dt, double baumgarte) {
    final rbA = body;
    if (rbA == null ||
        (rbA.isKinematic &&
            (connectedBody == null || connectedBody!.isKinematic))) {
      return;
    }
    final rbB = connectedBody;
    final pA = worldAnchor;
    final pB = worldConnectedAnchor;
    final rA = pA - transform.position;
    final rB = rbB != null ? pB - rbB.transform.position : Vec3.zero;

    final vA =
        rbA.velocity +
        (!rbA.freezeRotation ? rbA.angularVelocity.cross(rA) : Vec3.zero);
    final vB =
        (rbB?.velocity ?? Vec3.zero) +
        (rbB != null && !rbB.freezeRotation
            ? rbB.angularVelocity.cross(rB)
            : Vec3.zero);

    final relVel = vA - vB;
    final posError = pA - pB;
    final bias = posError * (baumgarte / dt);
    final target = -(relVel + bias);

    final invMassA = rbA.inverseMass;
    final invMassB = rbB?.inverseMass ?? 0.0;

    for (final axis in const [Vec3.unitX, Vec3.unitY, Vec3.unitZ]) {
      final uA = rA.cross(axis);
      final uB = rB.cross(axis);
      final rotA = !rbA.freezeRotation
          ? uA.dot(rbA.applyInverseInertia(uA))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? uB.dot(rbB.applyInverseInertia(uB))
          : 0.0;
      final k = invMassA + invMassB + rotA + rotB;
      if (k > 1e-12) {
        final impulseMag = target.dot(axis) / k;
        final impulse = axis * impulseMag;
        if (invMassA > 0) {
          rbA.velocity += impulse * invMassA;
          if (!rbA.freezeRotation) {
            rbA.angularVelocity += rbA.applyInverseInertia(rA.cross(impulse));
          }
        }
        if (rbB != null && invMassB > 0) {
          rbB.velocity -= impulse * invMassB;
          if (!rbB.freezeRotation) {
            rbB.angularVelocity -= rbB.applyInverseInertia(rB.cross(impulse));
          }
        }
        if (breakForce > 0 && (impulseMag / dt).abs() > breakForce) {
          isBroken = true;
          return;
        }
      }
    }
  }
}

/// Hinge joint allowing rotation about a specified axis while locking translation
/// and out-of-plane rotation.
final class HingeJoint extends PhysicsJoint {
  Vec3 axis;

  HingeJoint({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.breakForce,
    super.breakTorque,
    this.axis = Vec3.unitY,
  });

  static final spec = ComponentSpec<HingeJoint>('HingeJoint', HingeJoint.new, [
    Field.vec3('anchor', (j) => j.anchor, (j, v) => j.anchor = v),
    Field.vec3(
      'connectedAnchor',
      (j) => j.connectedAnchor,
      (j, v) => j.connectedAnchor = v,
    ),
    Field.vec3('axis', (j) => j.axis, (j, v) => j.axis = v),
    Field.number('breakForce', (j) => j.breakForce, (j, v) => j.breakForce = v),
    Field.number(
      'breakTorque',
      (j) => j.breakTorque,
      (j, v) => j.breakTorque = v,
    ),
  ]);

  /// World-space hinge axis.
  Vec3 get worldAxis => transform.rotation.rotate(axis).normalized;

  @override
  void _solve(double dt, double baumgarte) {
    final rbA = body;
    if (rbA == null ||
        (rbA.isKinematic &&
            (connectedBody == null || connectedBody!.isKinematic))) {
      return;
    }
    final rbB = connectedBody;
    final pA = worldAnchor;
    final pB = worldConnectedAnchor;
    final rA = pA - transform.position;
    final rB = rbB != null ? pB - rbB.transform.position : Vec3.zero;

    final vA =
        rbA.velocity +
        (!rbA.freezeRotation ? rbA.angularVelocity.cross(rA) : Vec3.zero);
    final vB =
        (rbB?.velocity ?? Vec3.zero) +
        (rbB != null && !rbB.freezeRotation
            ? rbB.angularVelocity.cross(rB)
            : Vec3.zero);

    final relVel = vA - vB;
    final posError = pA - pB;
    final bias = posError * (baumgarte / dt);
    final target = -(relVel + bias);

    final invMassA = rbA.inverseMass;
    final invMassB = rbB?.inverseMass ?? 0.0;

    for (final a in const [Vec3.unitX, Vec3.unitY, Vec3.unitZ]) {
      final uA = rA.cross(a);
      final uB = rB.cross(a);
      final rotA = !rbA.freezeRotation
          ? uA.dot(rbA.applyInverseInertia(uA))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? uB.dot(rbB.applyInverseInertia(uB))
          : 0.0;
      final k = invMassA + invMassB + rotA + rotB;
      if (k > 1e-12) {
        final impulseMag = target.dot(a) / k;
        final impulse = a * impulseMag;
        if (invMassA > 0) {
          rbA.velocity += impulse * invMassA;
          if (!rbA.freezeRotation) {
            rbA.angularVelocity += rbA.applyInverseInertia(rA.cross(impulse));
          }
        }
        if (rbB != null && invMassB > 0) {
          rbB.velocity -= impulse * invMassB;
          if (!rbB.freezeRotation) {
            rbB.angularVelocity -= rbB.applyInverseInertia(rB.cross(impulse));
          }
        }
        if (breakForce > 0 && (impulseMag / dt).abs() > breakForce) {
          isBroken = true;
          return;
        }
      }
    }

    final hAxis = worldAxis;
    Vec3 u1;
    if (hAxis.x.abs() > 0.577) {
      u1 = hAxis.cross(const Vec3(0, 1, 0)).normalized;
    } else {
      u1 = hAxis.cross(const Vec3(1, 0, 0)).normalized;
    }
    final u2 = hAxis.cross(u1).normalized;

    final wA = !rbA.freezeRotation ? rbA.angularVelocity : Vec3.zero;
    final wB = (rbB != null && !rbB.freezeRotation)
        ? rbB.angularVelocity
        : Vec3.zero;
    final relAngVel = wA - wB;

    for (final perpAxis in [u1, u2]) {
      final rotA = !rbA.freezeRotation
          ? perpAxis.dot(rbA.applyInverseInertia(perpAxis))
          : 0.0;
      final rotB = (rbB != null && !rbB.freezeRotation)
          ? perpAxis.dot(rbB.applyInverseInertia(perpAxis))
          : 0.0;
      final k = rotA + rotB;
      if (k > 1e-12) {
        final relW = relAngVel.dot(perpAxis);
        final torqueMag = -relW / k;
        final torque = perpAxis * torqueMag;
        if (!rbA.freezeRotation && invMassA > 0) {
          rbA.angularVelocity += rbA.applyInverseInertia(torque);
        }
        if (rbB != null && !rbB.freezeRotation && invMassB > 0) {
          rbB.angularVelocity -= rbB.applyInverseInertia(torque);
        }
        if (breakTorque > 0 && (torqueMag / dt).abs() > breakTorque) {
          isBroken = true;
          return;
        }
      }
    }
  }
}
