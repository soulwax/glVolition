part of '../engine.dart';

/// The game clock. Owned by [Engine]; components reach it as `time`.
///
/// Inside `fixedUpdate` [deltaTime] is [fixedDeltaTime] and [time] is
/// [fixedTime], as in Unity, so movement code reads the same in both.
final class Time {
  double _fixedDeltaTime = 1 / 50;

  /// Frames longer than this (tab switches, debugger pauses) are clamped so
  /// the simulation does not leap.
  double maximumDeltaTime = 0.1;

  /// Upper bound on physics steps per frame. When exceeded the remaining
  /// backlog is dropped instead of spiralling.
  int maxFixedStepsPerFrame = 8;

  double _timeScale = 1;

  double _time = 0;
  double _unscaledTime = 0;
  double _deltaTime = 0;
  double _unscaledDeltaTime = 0;
  double _fixedTime = 0;
  double _accumulator = 0;
  int _frameCount = 0;
  int _fixedStepsLastFrame = 0;
  bool _inFixedStep = false;

  double get fixedDeltaTime => _fixedDeltaTime;
  set fixedDeltaTime(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'fixedDeltaTime',
        'must be finite and > 0',
      );
    }
    _fixedDeltaTime = value;
  }

  double get timeScale => _timeScale;
  set timeScale(double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, 'timeScale', 'must be finite and >= 0');
    }
    _timeScale = value;
  }

  double get time => _inFixedStep ? _fixedTime : _time;
  double get deltaTime => _inFixedStep ? _fixedDeltaTime : _deltaTime;
  double get unscaledTime => _unscaledTime;
  double get unscaledDeltaTime => _unscaledDeltaTime;
  double get fixedTime => _fixedTime;
  int get frameCount => _frameCount;
  bool get inFixedTimeStep => _inFixedStep;

  /// How far the clock is between the last fixed step and the next, 0..1.
  /// Use it to interpolate rendered positions of fixed-step bodies.
  double get fixedInterpolation =>
      (_accumulator / _fixedDeltaTime).clamp(0.0, 1.0);

  /// Computes a smoothly damped value from [current] to [target] over [smoothTime] seconds (E21-3).
  ///
  /// Matches Unity's `Mathf.SmoothDamp`, returning `(current: double, velocity: double)`.
  ({double current, double velocity}) smoothDamp(
    double current,
    double target,
    double currentVelocity, {
    required double smoothTime,
    double maxSpeed = double.infinity,
    double? dt,
  }) {
    final actualDt = dt ?? deltaTime;
    final st = math.max(0.0001, smoothTime);
    final omega = 2.0 / st;

    final x = omega * actualDt;
    final exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);
    var change = current - target;
    final originalTo = target;

    // Clamp maximum speed
    final maxChange = maxSpeed * st;
    change = change.clamp(-maxChange, maxChange);
    final targetClamped = current - change;

    final temp = (currentVelocity + omega * change) * actualDt;
    var newVelocity = (currentVelocity - omega * temp) * exp;
    var output = targetClamped + (change + temp) * exp;

    // Prevent overshooting
    if ((originalTo - current > 0.0) == (output > originalTo)) {
      output = originalTo;
      newVelocity = (output - originalTo) / actualDt;
    }

    return (current: output, velocity: newVelocity);
  }

  /// Computes a smoothly damped 3D vector from [current] to [target] over [smoothTime] seconds (E21-3).
  ({Vec3 current, Vec3 velocity}) smoothDampVec3(
    Vec3 current,
    Vec3 target,
    Vec3 currentVelocity, {
    required double smoothTime,
    double maxSpeed = double.infinity,
    double? dt,
  }) {
    final resX = smoothDamp(
      current.x,
      target.x,
      currentVelocity.x,
      smoothTime: smoothTime,
      maxSpeed: maxSpeed,
      dt: dt,
    );
    final resY = smoothDamp(
      current.y,
      target.y,
      currentVelocity.y,
      smoothTime: smoothTime,
      maxSpeed: maxSpeed,
      dt: dt,
    );
    final resZ = smoothDamp(
      current.z,
      target.z,
      currentVelocity.z,
      smoothTime: smoothTime,
      maxSpeed: maxSpeed,
      dt: dt,
    );
    return (
      current: Vec3(resX.current, resY.current, resZ.current),
      velocity: Vec3(resX.velocity, resY.velocity, resZ.velocity),
    );
  }

  void _beginFrame(double rawDelta) {
    final raw = rawDelta.isFinite && rawDelta > 0 ? rawDelta : 0.0;
    _unscaledDeltaTime = math.min(raw, maximumDeltaTime);
    _unscaledTime += _unscaledDeltaTime;
    _deltaTime = _unscaledDeltaTime * _timeScale;
    _time += _deltaTime;
    _accumulator += _deltaTime;
    _frameCount++;
  }
}
