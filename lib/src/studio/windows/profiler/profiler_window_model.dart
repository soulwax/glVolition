/// Volition Studio Profiler Window & Frame Debugger Model (`[S8-A]`):
/// Tracks attached player handshake, rolling telemetry ring buffer, GPU
/// hardware vs synthetic timing flags, and Frame Capture save/load.
library;

import 'dart:convert';

import '../../project/project_fs.dart';
import '../../protocol/player_link.dart';

final class ProfilerWindowModel {
  final int maxHistoryFrames;
  PlayerLinkHandshake? connectedPlayer;
  final List<PlayerTelemetryFrame> _frames = [];
  FrameCaptureSnapshot? activeCapture;
  int selectedPassIndex = 0;

  ProfilerWindowModel({this.maxHistoryFrames = 300});

  bool get isAttached => connectedPlayer != null;
  List<PlayerTelemetryFrame> get frames => List.unmodifiable(_frames);

  void attach(PlayerLinkHandshake handshake) {
    connectedPlayer = handshake;
    _frames.clear();
  }

  void detach() {
    connectedPlayer = null;
  }

  void pushFrame(PlayerTelemetryFrame frame) {
    _frames.add(frame);
    if (_frames.length > maxHistoryFrames) {
      _frames.removeAt(0);
    }
  }

  double get averageFrameTimeMs {
    if (_frames.isEmpty) return 0.0;
    final sum = _frames.fold(0.0, (a, f) => a + f.frameTimeMs);
    return sum / _frames.length;
  }

  double get averageGpuTimeMs {
    if (_frames.isEmpty) return 0.0;
    final sum = _frames.fold(0.0, (a, f) => a + f.totalGpuMs);
    return sum / _frames.length;
  }

  bool get hasHardwareGpuTimings =>
      _frames.any((f) => f.gpuPasses.any((p) => !p.isSynthetic));

  Future<void> saveCapture(
    ProjectFileSystem fs,
    String path,
    FrameCaptureSnapshot capture,
  ) async {
    activeCapture = capture;
    await fs.writeString(
      path,
      const JsonEncoder.withIndent('  ').convert(capture.toJson()),
    );
  }

  Future<FrameCaptureSnapshot> loadCapture(
    ProjectFileSystem fs,
    String path,
  ) async {
    final text = await fs.readString(path);
    final capture = FrameCaptureSnapshot.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );
    activeCapture = capture;
    selectedPassIndex = 0;
    return capture;
  }
}
