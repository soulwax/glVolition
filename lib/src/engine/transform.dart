part of '../engine.dart';

enum Space { self, world }

/// Position, rotation and scale of a [GameObject], local to its parent.
/// Every object has exactly one; it cannot be removed.
///
/// Called `TransformComponent` because pixeldart already exports the value
/// type `Transform`; in game code you mostly write `transform.position`.
final class TransformComponent extends Component {
  TransformComponent._();

  SceneNode get _node => gameObject.node;

  TransformComponent? get parent => gameObject.parent?.transform;
  void setParent(TransformComponent? newParent, {bool worldPositionStays = true}) =>
      gameObject.setParent(newParent?.gameObject, worldPositionStays: worldPositionStays);

  // ── Local space ─────────────────────────────────────────────────────────

  Transform get local => _node.localTransform;
  set local(Transform value) => _node.localTransform = value;

  Vec3 get localPosition => _node.position;
  set localPosition(Vec3 value) => _node.position = value;

  Quat get localRotation => _node.rotation;
  set localRotation(Quat value) => _node.rotation = value;

  /// Uniform scale.
  double get localScale => _node.scale;
  set localScale(double value) => _node.scale = value;

  /// Non-uniform scale along the local axes. Only the node's own geometry is
  /// stretched; children inherit [localScale] but not stretch.
  Vec3 get localStretch => _node.stretch;
  set localStretch(Vec3 value) => _node.stretch = value;

  // ── World space ─────────────────────────────────────────────────────────

  Transform get world => _node.worldTransform;

  Vec3 get position => world.translation;
  set position(Vec3 value) {
    final p = parent;
    localPosition = p == null ? value : p.inverseTransformPoint(value);
  }

  Quat get rotation => world.rotation;
  set rotation(Quat value) {
    final p = parent;
    localRotation = p == null ? value : (p.rotation.inverse * value).normalized;
  }

  double get lossyScale => world.scale;

  Vec3 get forward => rotation.rotate(kForward);
  Vec3 get right => rotation.rotate(kRight);
  Vec3 get up => rotation.rotate(kUp);

  // ── Operations ──────────────────────────────────────────────────────────

  /// Moves by [delta], in local axes by default (as Unity's `Translate`).
  void translate(Vec3 delta, {Space relativeTo = Space.self}) {
    final worldDelta = relativeTo == Space.self ? rotation.rotate(delta) : delta;
    position = position + worldDelta;
  }

  /// Rotates [radians] about [axis], in local axes by default.
  void rotate(Vec3 axis, double radians, {Space relativeTo = Space.self}) {
    final q = Quat.axisAngle(axis, radians);
    if (relativeTo == Space.self) {
      localRotation = (localRotation * q).normalized;
    } else {
      rotation = (q * rotation).normalized;
    }
  }

  /// Points -Z (forward) at [target].
  void lookAt(Vec3 target, {Vec3 worldUp = kUp}) {
    final dir = target - position;
    if (dir.lengthSquared > 1e-12) rotation = lookRotation(dir, worldUp);
  }

  Vec3 transformPoint(Vec3 point) => world.transformPoint(point);

  /// The inverse of [transformPoint] for uniform scale. Stretch is ignored,
  /// matching how children inherit it.
  Vec3 inverseTransformPoint(Vec3 point) {
    final w = world;
    final s = w.scale == 0 ? 0.0 : 1 / w.scale;
    return w.rotation.inverse.rotate(point - w.translation) * s;
  }

  Vec3 transformDirection(Vec3 direction) => rotation.rotate(direction);
  Vec3 inverseTransformDirection(Vec3 direction) => rotation.inverse.rotate(direction);
}
