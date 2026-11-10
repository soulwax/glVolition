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
      throw ArgumentError.value(value, 'fixedDeltaTime', 'must be finite and > 0');
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
  double get fixedInterpolation => (_accumulator / _fixedDeltaTime).clamp(0.0, 1.0);

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
