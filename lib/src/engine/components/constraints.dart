part of '../../engine.dart';

/// Rotates its [GameObject] in `lateUpdate` to face towards [target] (E25-2).
final class LookAtConstraint extends Behaviour {
  TransformComponent? target;
  Vec3 upAxis;
  double weight;

  LookAtConstraint({
    this.target,
    this.upAxis = kUp,
    this.weight = 1.0,
  });

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
