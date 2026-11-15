part of '../../engine.dart';

/// Clock offset and RTT synchronization helper for client-server replication.
final class NetworkClockSync {
  double serverOffsetMs = 0.0;
  double smoothedRttMs = 0.0;
  double jitterMs = 0.0;
  int sampleCount = 0;
  double lastDriftCorrectionMs = 0.0;

  void updateFromPong({
    required int clientSentTimeMs,
    required int serverTimeMs,
    required int clientReceivedTimeMs,
  }) {
    final rtt = math.max(0, clientReceivedTimeMs - clientSentTimeMs).toDouble();
    final estimatedOffset = serverTimeMs + (rtt * 0.5) - clientReceivedTimeMs;
    if (sampleCount == 0) {
      smoothedRttMs = rtt;
      serverOffsetMs = estimatedOffset;
      jitterMs = 0.0;
      lastDriftCorrectionMs = 0.0;
    } else {
      final deltaRtt = (rtt - smoothedRttMs).abs();
      smoothedRttMs = smoothedRttMs * 0.875 + rtt * 0.125;
      jitterMs = jitterMs * 0.75 + deltaRtt * 0.25;
      final blendedOffset = serverOffsetMs * 0.8 + estimatedOffset * 0.2;
      lastDriftCorrectionMs = blendedOffset - serverOffsetMs;
      serverOffsetMs = blendedOffset;
    }
    sampleCount++;
  }

  int estimatedServerTimeMs(int localTimeMs) =>
      localTimeMs + serverOffsetMs.round();

  void reset() {
    serverOffsetMs = 0.0;
    smoothedRttMs = 0.0;
    jitterMs = 0.0;
    sampleCount = 0;
    lastDriftCorrectionMs = 0.0;
  }
}

/// Lifecycle tick and reconciliation callback contract for multiplayer systems.
abstract interface class NetworkTickHook {
  void onPreFixedTick(NetworkManager manager, int tick, double dt);
  void onPostFixedTick(NetworkManager manager, int tick, double dt);
  void onSnapshotReconcile(
    NetworkIdentity identity,
    int serverTick,
    Vec3 correctionDelta,
  );
}

/// Network replication, delta compression, and prediction configuration.
final class NetworkSyncConfig {
  final double snapshotRateHz;
  final double interpolationDelaySeconds;
  final int maxRollbackTicks;
  final double divergenceThresholdSq;
  final bool enableDeltaCompression;
  final bool enableAutoTickSync;
  final net.NetTransportAuthOptions auth;
  final int heartbeatIntervalMs;
  final int reconnectInitialDelayMs;
  final int reconnectMaxDelayMs;
  final int maxReconnectAttempts;

  const NetworkSyncConfig({
    this.snapshotRateHz = 20.0,
    this.interpolationDelaySeconds = 0.05,
    this.maxRollbackTicks = 64,
    this.divergenceThresholdSq = 0.04,
    this.enableDeltaCompression = true,
    this.enableAutoTickSync = true,
    this.auth = const net.NetTransportAuthOptions(),
    this.heartbeatIntervalMs = 2000,
    this.reconnectInitialDelayMs = 250,
    this.reconnectMaxDelayMs = 8000,
    this.maxReconnectAttempts = 5,
  });
}

/// Cumulative network replication and transport telemetry counters.
final class NetworkSyncStats {
  int packetsPolled = 0;
  int snapshotsSent = 0;
  int snapshotsDeltaSkipped = 0;
  int snapshotsApplied = 0;
  int rpcsSent = 0;
  int rpcsDispatched = 0;
  int rollbackReconciliations = 0;
  int inputsSent = 0;

  void reset() {
    packetsPolled = 0;
    snapshotsSent = 0;
    snapshotsDeltaSkipped = 0;
    snapshotsApplied = 0;
    rpcsSent = 0;
    rpcsDispatched = 0;
    rollbackReconciliations = 0;
    inputsSent = 0;
  }
}
