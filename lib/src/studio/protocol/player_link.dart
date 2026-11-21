/// Volition Studio Player Link Protocol (`[S8-0]`):
/// Pure-Dart typed handshake, CPU/GPU telemetry frames, log stream, remote
/// DebugConsole commands, and Frame Debugger capture snapshots.
library;

/// Handshake sent by a connected player (in-Studio, browser tab, native exe,
/// or dedicated server) when attaching to Volition Studio (`[S8-0]`).
final class PlayerLinkHandshake {
  static const int protocolVersion = 1;

  final String playerId;
  final String target;
  final String buildProfile;
  final bool hardwareGpuTimers;

  const PlayerLinkHandshake({
    required this.playerId,
    required this.target,
    required this.buildProfile,
    this.hardwareGpuTimers = false,
  });

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'playerId': playerId,
    'target': target,
    'buildProfile': buildProfile,
    'hardwareGpuTimers': hardwareGpuTimers,
  };

  factory PlayerLinkHandshake.fromJson(Map<String, Object?> json) =>
      PlayerLinkHandshake(
        playerId: json['playerId'] as String? ?? 'unknown',
        target: json['target'] as String? ?? 'web',
        buildProfile: json['buildProfile'] as String? ?? 'dev',
        hardwareGpuTimers: json['hardwareGpuTimers'] as bool? ?? false,
      );
}

/// CPU profiler span sample from `FrameProfilerComponent`.
final class CpuSpanSample {
  final String name;
  final double durationMs;
  final int depth;

  const CpuSpanSample({
    required this.name,
    required this.durationMs,
    this.depth = 0,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'durationMs': durationMs,
    'depth': depth,
  };

  factory CpuSpanSample.fromJson(Map<String, Object?> json) => CpuSpanSample(
    name: json['name'] as String,
    durationMs: (json['durationMs'] as num).toDouble(),
    depth: (json['depth'] as num?)?.toInt() ?? 0,
  );
}

/// Per-pass GPU timer sample (explicitly tagged [isSynthetic] when captured on
/// `RecordingGlesDevice` without hardware timer queries).
final class GpuPassTimingSample {
  final String passName;
  final double durationMs;
  final bool isSynthetic;

  const GpuPassTimingSample({
    required this.passName,
    required this.durationMs,
    this.isSynthetic = false,
  });

  Map<String, Object?> toJson() => {
    'passName': passName,
    'durationMs': durationMs,
    'isSynthetic': isSynthetic,
  };

  factory GpuPassTimingSample.fromJson(Map<String, Object?> json) =>
      GpuPassTimingSample(
        passName: json['passName'] as String,
        durationMs: (json['durationMs'] as num).toDouble(),
        isSynthetic: json['isSynthetic'] as bool? ?? false,
      );
}

/// Single frame telemetry payload streamed over Player Link (`[S8-0]`).
final class PlayerTelemetryFrame {
  final int frameIndex;
  final double frameTimeMs;
  final List<CpuSpanSample> cpuSpans;
  final List<GpuPassTimingSample> gpuPasses;
  final int drawCalls;
  final int triangles;
  final int stateChanges;
  final int memoryBytes;
  final int loadedAssets;

  const PlayerTelemetryFrame({
    required this.frameIndex,
    required this.frameTimeMs,
    this.cpuSpans = const [],
    this.gpuPasses = const [],
    this.drawCalls = 0,
    this.triangles = 0,
    this.stateChanges = 0,
    this.memoryBytes = 0,
    this.loadedAssets = 0,
  });

  double get totalGpuMs => gpuPasses.fold(0.0, (sum, p) => sum + p.durationMs);

  Map<String, Object?> toJson() => {
    'frameIndex': frameIndex,
    'frameTimeMs': frameTimeMs,
    'cpuSpans': [for (final s in cpuSpans) s.toJson()],
    'gpuPasses': [for (final p in gpuPasses) p.toJson()],
    'drawCalls': drawCalls,
    'triangles': triangles,
    'stateChanges': stateChanges,
    'memoryBytes': memoryBytes,
    'loadedAssets': loadedAssets,
  };

  factory PlayerTelemetryFrame.fromJson(Map<String, Object?> json) =>
      PlayerTelemetryFrame(
        frameIndex: (json['frameIndex'] as num).toInt(),
        frameTimeMs: (json['frameTimeMs'] as num).toDouble(),
        cpuSpans: [
          for (final s in (json['cpuSpans'] as List?) ?? const [])
            CpuSpanSample.fromJson((s as Map).cast<String, Object?>()),
        ],
        gpuPasses: [
          for (final p in (json['gpuPasses'] as List?) ?? const [])
            GpuPassTimingSample.fromJson((p as Map).cast<String, Object?>()),
        ],
        drawCalls: (json['drawCalls'] as num?)?.toInt() ?? 0,
        triangles: (json['triangles'] as num?)?.toInt() ?? 0,
        stateChanges: (json['stateChanges'] as num?)?.toInt() ?? 0,
        memoryBytes: (json['memoryBytes'] as num?)?.toInt() ?? 0,
        loadedAssets: (json['loadedAssets'] as num?)?.toInt() ?? 0,
      );
}

/// Recorded render-graph pass inside a [FrameCaptureSnapshot] (`[S8-A]`).
final class FrameCapturePassRecord {
  final String passName;
  final List<String> drawLabels;
  final Map<String, Object?> pipelineState;

  const FrameCapturePassRecord({
    required this.passName,
    this.drawLabels = const [],
    this.pipelineState = const {},
  });

  Map<String, Object?> toJson() => {
    'passName': passName,
    'drawLabels': drawLabels,
    'pipelineState': pipelineState,
  };

  factory FrameCapturePassRecord.fromJson(Map<String, Object?> json) =>
      FrameCapturePassRecord(
        passName: json['passName'] as String,
        drawLabels: [
          for (final d in (json['drawLabels'] as List?) ?? const []) '$d',
        ],
        pipelineState: ((json['pipelineState'] as Map?) ?? const {})
            .cast<String, Object?>(),
      );
}

/// Serializable Frame Debugger capture snapshot (`[S8-A]`).
final class FrameCaptureSnapshot {
  final int frameIndex;
  final PlayerLinkHandshake player;
  final List<FrameCapturePassRecord> passes;

  const FrameCaptureSnapshot({
    required this.frameIndex,
    required this.player,
    this.passes = const [],
  });

  Map<String, Object?> toJson() => {
    'frameIndex': frameIndex,
    'player': player.toJson(),
    'passes': [for (final p in passes) p.toJson()],
  };

  factory FrameCaptureSnapshot.fromJson(Map<String, Object?> json) =>
      FrameCaptureSnapshot(
        frameIndex: (json['frameIndex'] as num).toInt(),
        player: PlayerLinkHandshake.fromJson(
          (json['player'] as Map).cast<String, Object?>(),
        ),
        passes: [
          for (final p in (json['passes'] as List?) ?? const [])
            FrameCapturePassRecord.fromJson((p as Map).cast<String, Object?>()),
        ],
      );
}
