part of '../engine.dart';

/// Game math utility functions equivalent to Unity's `Mathf` (E24-1).
///
/// Pure Dart, deterministic, and frame-rate-independent.
abstract final class Mathfx {
  static const double epsilon = 1e-6;

  /// Returns whether [a] and [b] are equal within [epsilon].
  static bool approximately(double a, double b, [double eps = epsilon]) =>
      (a - b).abs() <= eps;

  /// Calculates the linear parameter `t` that produces the interpolant [value]
  /// within the range `[a, b]`. Result is clamped to `[0, 1]`.
  static double inverseLerp(double a, double b, double value) {
    if ((b - a).abs() <= epsilon) return 0.0;
    return ((value - a) / (b - a)).clamp(0.0, 1.0);
  }

  /// Ping-pongs [t] so that it is never larger than [length] and never smaller
  /// than `0.0`.
  static double pingPong(double t, double length) {
    if (length <= 0) return 0.0;
    final l2 = length * 2.0;
    final rem = repeat(t, l2);
    return length - (rem - length).abs();
  }

  /// Loops [t] so that it is never larger than [length] and never smaller than `0.0`.
  static double repeat(double t, double length) {
    if (length <= 0) return 0.0;
    return (t - (t / length).floorToDouble() * length).clamp(0.0, length);
  }

  /// Calculates the shortest difference between two angles in radians, in the
  /// range `[-pi, pi]`.
  static double deltaAngle(double current, double target) {
    var delta = repeat(target - current, math.pi * 2);
    if (delta > math.pi) delta -= math.pi * 2;
    return delta;
  }

  /// Calculates the shortest difference between two angles in degrees, in the
  /// range `[-180.0, 180.0]`.
  static double deltaAngleDeg(double current, double target) {
    var delta = repeat(target - current, 360.0);
    if (delta > 180.0) delta -= 360.0;
    return delta;
  }

  /// Moves [current] towards [target] by at most [maxDelta] without overshooting.
  static double moveTowards(double current, double target, double maxDelta) {
    if ((target - current).abs() <= maxDelta) return target;
    return current + (target - current).sign * maxDelta;
  }

  /// Moves 3D point [current] towards [target] by at most [maxDelta] without overshooting.
  static Vec3 moveTowardsVec3(Vec3 current, Vec3 target, double maxDelta) {
    final diff = target - current;
    final dist = diff.length;
    if (dist <= maxDelta || dist <= epsilon) return target;
    return current + diff * (maxDelta / dist);
  }

  /// Frame-rate-independent exponential decay smoothing from [current] towards
  /// [target] with smoothing coefficient [lambda] (`lambda > 0`) over [dt] seconds.
  ///
  /// Formula: `target + (current - target) * exp(-lambda * dt)`
  static double damp(double current, double target, double lambda, double dt) {
    if (dt <= 0 || lambda <= 0) return current;
    return target + (current - target) * math.exp(-lambda * dt);
  }

  /// Frame-rate-independent exponential decay smoothing for 3D vectors.
  static Vec3 dampVec3(Vec3 current, Vec3 target, double lambda, double dt) {
    if (dt <= 0 || lambda <= 0) return current;
    final factor = math.exp(-lambda * dt);
    return target + (current - target) * factor;
  }

  /// Spherical linear interpolation between quaternions [a] and [b] with parameter [t] (`0..1`).
  static Quat slerp(Quat a, Quat b, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    var cosHalfTheta = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var bx = b.x, by = b.y, bz = b.z, bw = b.w;

    if (cosHalfTheta < 0.0) {
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
      cosHalfTheta = -cosHalfTheta;
    }

    if (cosHalfTheta >= 0.9995) {
      final x = a.x + (bx - a.x) * clampedT;
      final y = a.y + (by - a.y) * clampedT;
      final z = a.z + (bz - a.z) * clampedT;
      final w = a.w + (bw - a.w) * clampedT;
      final len = math.sqrt(x * x + y * y + z * z + w * w);
      if (len <= 0.0) return Quat.identity;
      return Quat(x / len, y / len, z / len, w / len);
    }

    final halfTheta = math.acos(cosHalfTheta);
    final sinHalfTheta = math.sqrt(1.0 - cosHalfTheta * cosHalfTheta);
    final ratioA = math.sin((1.0 - clampedT) * halfTheta) / sinHalfTheta;
    final ratioB = math.sin(clampedT * halfTheta) / sinHalfTheta;

    return Quat(
      a.x * ratioA + bx * ratioB,
      a.y * ratioA + by * ratioB,
      a.z * ratioA + bz * ratioB,
      a.w * ratioA + bw * ratioB,
    );
  }
}
