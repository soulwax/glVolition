part of '../engine.dart';

/// Rolling frame-timing and scene-population snapshot exposed by
/// [DebugController].
final class DebugMetrics {
  final double fps;
  final double p50FrameMs;
  final double p95FrameMs;
  final int fixedStepsLastFrame;
  final int gameObjectCount;
  final int activeBehaviourCount;
  final int colliderCount;
  final int particleSystemCount;
  final int activeLightCount;
  final double timeScale;
  final bool paused;

  const DebugMetrics({
    required this.fps,
    required this.p50FrameMs,
    required this.p95FrameMs,
    required this.fixedStepsLastFrame,
    required this.gameObjectCount,
    required this.activeBehaviourCount,
    required this.colliderCount,
    required this.particleSystemCount,
    required this.activeLightCount,
    required this.timeScale,
    required this.paused,
  });

  @override
  String toString() =>
      'FPS ${fps.toStringAsFixed(0)} (p50 ${p50FrameMs.toStringAsFixed(1)}ms, p95 ${p95FrameMs.toStringAsFixed(1)}ms) | '
      'fixed $fixedStepsLastFrame | GO $gameObjectCount | Beh $activeBehaviourCount | '
      'Col $colliderCount | Scale ${timeScale}x${paused ? " [PAUSED]" : ""}';
}

/// In-game diagnostics and time-control behaviour (E2-4).
///
/// Toggle overlay with `Backquote` (`` ` ``). While open:
/// - `Space`: pause / resume (`time.timeScale = 0` / restore prior scale)
/// - `Period` (`.`): single-step one `fixedDeltaTime` while paused
/// - `BracketLeft` (`[`) / `BracketRight` (`]`): halve / double `timeScale` (`0.125×` .. `4.0×`)
final class DebugController extends Behaviour {
  @override
  int get executionOrder => -10000;

  bool isOpen;
  final String toggleKey;
  final String pauseKey;
  final String stepKey;
  final String slowDownKey;
  final String speedUpKey;

  final List<double> _frameSamplesMs = [];
  static const int _maxSamples = 60;

  bool _paused = false;
  double _savedTimeScale = 1.0;

  DebugController({
    this.isOpen = false,
    this.toggleKey = 'Backquote',
    this.pauseKey = 'Space',
    this.stepKey = 'Period',
    this.slowDownKey = 'BracketLeft',
    this.speedUpKey = 'BracketRight',
  });

  bool get isPaused => _paused;

  void pause() {
    if (_paused) return;
    _paused = true;
    _savedTimeScale = time.timeScale > 0 ? time.timeScale : 1.0;
    time.timeScale = 0;
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    time.timeScale = _savedTimeScale;
  }

  void togglePause() => _paused ? resume() : pause();

  /// Advances the simulation by exactly one [Time.fixedDeltaTime] while
  /// keeping the game paused afterwards.
  void stepSingleFrame() {
    if (!_paused) pause();
    final dt = time.fixedDeltaTime;
    time._deltaTime = dt;
    time._time += dt;
    time._fixedTime += dt;
    time._inFixedStep = true;
    try {
      scene._fixedStep();
    } finally {
      time._inFixedStep = false;
    }
  }

  void setTimeScale(double scale) {
    final clamped = scale.clamp(0.125, 4.0);
    _savedTimeScale = clamped;
    if (!_paused) {
      time.timeScale = clamped;
    }
  }

  @override
  void update() {
    final rawMs = time.unscaledDeltaTime * 1000.0;
    if (rawMs > 0) {
      _frameSamplesMs.add(rawMs);
      if (_frameSamplesMs.length > _maxSamples) _frameSamplesMs.removeAt(0);
    }

    final raw = engine.host.input;
    if (raw.wasPressed(toggleKey)) {
      isOpen = !isOpen;
    }
    if (!isOpen) return;

    if (raw.wasPressed(pauseKey)) {
      togglePause();
    }
    if (_paused && raw.wasPressed(stepKey)) {
      stepSingleFrame();
    }
    if (raw.wasPressed(slowDownKey)) {
      setTimeScale(_savedTimeScale * 0.5);
    }
    if (raw.wasPressed(speedUpKey)) {
      setTimeScale(_savedTimeScale * 2.0);
    }
  }

  DebugMetrics metrics() {
    double p50 = 0, p95 = 0, fps = 0;
    if (_frameSamplesMs.isNotEmpty) {
      final sorted = List.of(_frameSamplesMs)..sort();
      p50 = sorted[sorted.length ~/ 2];
      p95 = sorted[((sorted.length - 1) * 0.95).round()];
      final mean = sorted.reduce((a, b) => a + b) / sorted.length;
      if (mean > 0) fps = 1000.0 / mean;
    }
    return DebugMetrics(
      fps: fps,
      p50FrameMs: p50,
      p95FrameMs: p95,
      fixedStepsLastFrame: time._fixedStepsLastFrame,
      gameObjectCount: scene._allObjects(includeInactive: false).length,
      activeBehaviourCount: scene._behaviours.where((b) => b._active && !b._destroyRequested).length,
      colliderCount: scene.physics.colliders.length,
      particleSystemCount: scene._particles.length,
      activeLightCount: scene._lights.where((l) => l._active).length,
      timeScale: _paused ? 0 : time.timeScale,
      paused: _paused,
    );
  }
}
