part of '../../engine.dart';

/// Telemetry metrics snapshot capturing runtime performance, memory, draw calls,
/// entity counts, and transient stress diagnostics (P7-W15-C).
final class EngineTelemetrySnapshot {
  final int timestampMs;
  final int frameIndex;
  final double fps;
  final double avgFrameTimeMs;
  final double p50FrameTimeMs;
  final double p95FrameTimeMs;
  final double p99FrameTimeMs;
  final int totalEntityCount;
  final int activeComponentCount;
  final int activeColliders;
  final int activeRigidBodies;
  final int activeParticles;
  final int activeDecals;
  final int activeVfx;
  final int drawCalls;
  final int meshDrawCount;
  final int spriteDrawCount;
  final int heapAllocatedBytes;
  final Map<String, int> transientMetrics;
  final List<String> recentErrors;

  const EngineTelemetrySnapshot({
    required this.timestampMs,
    required this.frameIndex,
    required this.fps,
    required this.avgFrameTimeMs,
    required this.p50FrameTimeMs,
    required this.p95FrameTimeMs,
    required this.p99FrameTimeMs,
    required this.totalEntityCount,
    required this.activeComponentCount,
    required this.activeColliders,
    required this.activeRigidBodies,
    required this.activeParticles,
    required this.activeDecals,
    required this.activeVfx,
    required this.drawCalls,
    required this.meshDrawCount,
    required this.spriteDrawCount,
    required this.heapAllocatedBytes,
    this.transientMetrics = const {},
    this.recentErrors = const [],
  });

  Map<String, Object?> toJson() => {
    'timestampMs': timestampMs,
    'frameIndex': frameIndex,
    'fps': fps,
    'avgFrameTimeMs': avgFrameTimeMs,
    'p50FrameTimeMs': p50FrameTimeMs,
    'p95FrameTimeMs': p95FrameTimeMs,
    'p99FrameTimeMs': p99FrameTimeMs,
    'totalEntityCount': totalEntityCount,
    'activeComponentCount': activeComponentCount,
    'activeColliders': activeColliders,
    'activeRigidBodies': activeRigidBodies,
    'activeParticles': activeParticles,
    'activeDecals': activeDecals,
    'activeVfx': activeVfx,
    'drawCalls': drawCalls,
    'meshDrawCount': meshDrawCount,
    'spriteDrawCount': spriteDrawCount,
    'heapAllocatedBytes': heapAllocatedBytes,
    'transientMetrics': transientMetrics,
    'recentErrors': recentErrors,
  };

  /// Captures a live diagnostics snapshot of [engine] and its active scene.
  static EngineTelemetrySnapshot capture(
    Engine engine, {
    List<double> frameTimeSamplesMs = const [],
    Map<String, int> transientMetrics = const {},
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final scene = engine.scene;

    var entityCount = 0;
    var compCount = 0;
    var colliders = 0;
    var rigidBodies = 0;
    var particles = 0;
    var decals = 0;
    var vfx = 0;
    var meshes = 0;

    void countSubtree(GameObject go) {
      if (go.isDestroyed) return;
      entityCount++;
      compCount += go.components.length;
      for (final c in go.components) {
        if (c is Collider) colliders++;
        if (c is RigidBody) rigidBodies++;
        if (c is ParticleSystem) particles += c.activeParticleCount;
        if (c is DecalProjectorComponent) decals++;
        if (c is VisualEffectComponent) vfx++;
        if (c is MeshRenderer) meshes++;
      }
      for (final child in go.children) {
        countSubtree(child);
      }
    }

    for (final root in scene._roots) {
      countSubtree(root);
    }

    final samples = List<double>.of(frameTimeSamplesMs)..sort();
    var avgMs = 16.66;
    var p50 = 16.66;
    var p95 = 16.66;
    var p99 = 16.66;

    if (samples.isNotEmpty) {
      avgMs = samples.reduce((a, b) => a + b) / samples.length;
      p50 = samples[(samples.length * 0.5).floor()];
      p95 =
          samples[math.min(
            samples.length - 1,
            (samples.length * 0.95).floor(),
          )];
      p99 =
          samples[math.min(
            samples.length - 1,
            (samples.length * 0.99).floor(),
          )];
    }

    final fps = avgMs > 0.0 ? (1000.0 / avgMs) : 60.0;
    final sprites = scene._sprites.length;
    final totalDraws = meshes + sprites;

    return EngineTelemetrySnapshot(
      timestampMs: now,
      frameIndex: engine.time.frameCount,
      fps: fps,
      avgFrameTimeMs: avgMs,
      p50FrameTimeMs: p50,
      p95FrameTimeMs: p95,
      p99FrameTimeMs: p99,
      totalEntityCount: entityCount,
      activeComponentCount: compCount,
      activeColliders: colliders,
      activeRigidBodies: rigidBodies,
      activeParticles: particles,
      activeDecals: decals,
      activeVfx: vfx,
      drawCalls: totalDraws,
      meshDrawCount: meshes,
      spriteDrawCount: sprites,
      heapAllocatedBytes: 0,
      transientMetrics: Map.unmodifiable(transientMetrics),
      recentErrors: List.unmodifiable(EngineTelemetry._errorLog),
    );
  }
}

/// Callback signature for uncaught crash telemetry handlers.
typedef CrashTelemetryCallback =
    void Function(
      Object error,
      StackTrace stack,
      EngineTelemetrySnapshot? snapshot,
    );

/// Global crash telemetry and error tracking registry.
final class EngineTelemetry {
  static CrashTelemetryCallback? onUncaughtCrash;
  static final List<String> _errorLog = [];

  static void recordError(Object error, [StackTrace? stack]) {
    _errorLog.add('${DateTime.now().toIso8601String()}: $error');
    if (_errorLog.length > 50) _errorLog.removeAt(0);
  }

  static void handleUncaught(Object error, StackTrace stack, [Engine? engine]) {
    recordError(error, stack);
    final snap = engine != null
        ? EngineTelemetrySnapshot.capture(engine)
        : null;
    onUncaughtCrash?.call(error, stack, snap);
  }

  static void clearErrorLog() {
    _errorLog.clear();
  }
}
