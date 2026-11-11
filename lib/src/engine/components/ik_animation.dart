part of '../../engine.dart';

anim.AnimVec3 _toAnimVec3(Vec3 v) => anim.AnimVec3(v.x, v.y, v.z);
Vec3 _toVec3(anim.AnimVec3 v) => Vec3(v.x, v.y, v.z);
anim.AnimQuat _toAnimQuat(Quat q) => anim.AnimQuat(q.x, q.y, q.z, q.w);
Quat _toQuat(anim.AnimQuat q) => Quat(q.x, q.y, q.z, q.w);

/// Analytical 2-bone Inverse Kinematics component for limbs, arms, legs, and foot planting (E34).
class TwoBoneIkComponent extends Behaviour {
  GameObject? rootBone;
  GameObject? midBone;
  GameObject? endEffector;

  GameObject? target;
  Vec3? targetPosition;

  GameObject? pole;
  Vec3? polePosition;

  double weight;

  TwoBoneIkComponent({
    this.rootBone,
    this.midBone,
    this.endEffector,
    this.target,
    this.targetPosition,
    this.pole,
    this.polePosition,
    this.weight = 1.0,
  });

  @override
  void lateUpdate() {
    if (weight <= 0.0) return;

    final root = rootBone ?? gameObject;
    final mid = midBone;
    final end = endEffector;
    if (mid == null || end == null) return;

    final targetPos = target?.transform.position ?? targetPosition;
    if (targetPos == null) return;

    // Default pole position: forward from mid joint
    final polePos = pole?.transform.position ??
        polePosition ??
        (mid.transform.position + mid.transform.forward * 2.0);

    final result = anim.TwoBoneIkSolver.solve(
      root: _toAnimVec3(root.transform.position),
      mid: _toAnimVec3(mid.transform.position),
      end: _toAnimVec3(end.transform.position),
      target: _toAnimVec3(targetPos),
      poleTarget: _toAnimVec3(polePos),
    );

    final w = weight.clamp(0.0, 1.0);

    // Apply root rotation delta
    final rootDelta = _toQuat(result.rootRotationDelta);
    root.transform.rotation = Mathfx.slerp(root.transform.rotation, rootDelta * root.transform.rotation, w);

    // With root rotated, compute mid-to-end alignment to target
    final currentMidToEnd = end.transform.position - mid.transform.position;
    final targetMidToEnd = _toVec3(result.endPosition) - _toVec3(result.midPosition);
    if (currentMidToEnd.lengthSquared > 1e-6 && targetMidToEnd.lengthSquared > 1e-6) {
      final midDelta = Quat.fromTo(currentMidToEnd.normalized, targetMidToEnd.normalized);
      mid.transform.rotation = Mathfx.slerp(mid.transform.rotation, midDelta * mid.transform.rotation, w);
    }
  }
}

/// Aim / LookAt Inverse Kinematics component directing a bone or head towards a 3D target (E34).
class AimIkComponent extends Behaviour {
  GameObject? bone;
  GameObject? target;
  Vec3? targetPosition;

  Vec3 localAimAxis;
  double maxAngleRadians;
  double weight;

  AimIkComponent({
    this.bone,
    this.target,
    this.targetPosition,
    this.localAimAxis = kForward,
    this.maxAngleRadians = math.pi * 0.5,
    this.weight = 1.0,
  });

  @override
  void lateUpdate() {
    if (weight <= 0.0) return;

    final targetBone = bone ?? gameObject;
    final targetPos = target?.transform.position ?? targetPosition;
    if (targetPos == null) return;

    final solvedRot = anim.AimIkSolver.solve(
      bonePosition: _toAnimVec3(targetBone.transform.position),
      currentRotation: _toAnimQuat(targetBone.transform.rotation),
      targetPosition: _toAnimVec3(targetPos),
      localAimAxis: _toAnimVec3(localAimAxis),
      maxAngleRadians: maxAngleRadians,
      weight: weight,
    );

    targetBone.transform.rotation = _toQuat(solvedRot);
  }
}

/// Evaluates a 1D or 2D animation blend tree graph and applies poses to hierarchy (E34).
class BlendTreeComponent extends Behaviour {
  anim.BlendNode? rootNode;
  final Map<String, double> parameters = {};
  double _animationTime = 0.0;

  double get animationTime => _animationTime;

  BlendTreeComponent({
    this.rootNode,
    Map<String, double>? initialParameters,
  }) {
    if (initialParameters != null) {
      parameters.addAll(initialParameters);
    }
  }

  void setFloat(String name, double value) {
    parameters[name] = value;
  }

  double getFloat(String name) => parameters[name] ?? 0.0;

  @override
  void update() {
    final node = rootNode;
    if (node == null) return;

    _animationTime += time.deltaTime;
    final pose = node.evaluate(_animationTime, parameters);

    // Apply evaluated bone poses to matching GameObjects by name
    for (final entry in pose.bones.entries) {
      final boneGo = gameObject.find(entry.key);
      if (boneGo != null) {
        final t = entry.value;
        boneGo.transform.localPosition = _toVec3(t.position);
        boneGo.transform.localRotation = _toQuat(t.rotation);
        boneGo.transform.localScale = (t.scale.x + t.scale.y + t.scale.z) / 3.0;
      }
    }
  }
}
