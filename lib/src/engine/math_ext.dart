part of '../engine.dart';

/// World conventions: right-handed, +Y up, objects and cameras face -Z.
/// (Unity is left-handed with +Z forward; pixeldart's camera looks down -Z.)
const Vec3 kForward = Vec3(0, 0, -1);
const Vec3 kRight = Vec3(1, 0, 0);
const Vec3 kUp = Vec3(0, 1, 0);

extension QuatEngineOps on Quat {
  /// The inverse of a unit quaternion.
  Quat get inverse => Quat(-x, -y, -z, w);
}

/// A rotation whose -Z axis points along [forward] and whose +Y axis is as
/// close to [up] as possible. The engine counterpart of Unity's
/// `Quaternion.LookRotation`.
Quat lookRotation(Vec3 forward, [Vec3 up = kUp]) {
  if (forward.lengthSquared < 1e-12) return Quat.identity;
  final z = -forward.normalized;
  var x = up.cross(z);
  if (x.lengthSquared < 1e-10) {
    x = (z.y.abs() < 0.99 ? kUp : kRight).cross(z);
  }
  x = x.normalized;
  final y = z.cross(x);

  final m00 = x.x, m01 = y.x, m02 = z.x;
  final m10 = x.y, m11 = y.y, m12 = z.y;
  final m20 = x.z, m21 = y.z, m22 = z.z;
  final trace = m00 + m11 + m22;
  if (trace > 0) {
    final s = math.sqrt(trace + 1) * 2;
    return Quat((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s);
  }
  if (m00 > m11 && m00 > m22) {
    final s = math.sqrt(1 + m00 - m11 - m22) * 2;
    return Quat(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s);
  }
  if (m11 > m22) {
    final s = math.sqrt(1 + m11 - m00 - m22) * 2;
    return Quat((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s);
  }
  final s = math.sqrt(1 + m22 - m00 - m11) * 2;
  return Quat((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s);
}

/// Frame-rate independent exponential smoothing factor: the fraction of the
/// remaining distance to cover this frame when approaching at [rate] per
/// second.
double damp(double rate, double deltaTime) => 1 - math.exp(-rate * deltaTime);
