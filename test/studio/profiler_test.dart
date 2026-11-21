/// S8-0 / S8-A test: Verifies Player Link Protocol JSON round-trip, rolling
/// telemetry stats, hardware vs synthetic GPU pass timing detection, and
/// Frame Capture save/load.
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S8-0 / S8-A — Player Link Protocol, Profiler & Frame Debugger', () {
    test(
      'PlayerLinkHandshake & PlayerTelemetryFrame round-trip and track GPU timings',
      () {
        const hs = PlayerLinkHandshake(
          playerId: 'native-win-01',
          target: 'windows',
          buildProfile: 'windows-dev',
          hardwareGpuTimers: true,
        );
        final hsRt = PlayerLinkHandshake.fromJson(hs.toJson());
        expect(hsRt.playerId, equals('native-win-01'));
        expect(hsRt.hardwareGpuTimers, isTrue);

        final profiler = ProfilerWindowModel(maxHistoryFrames: 5);
        profiler.attach(hsRt);
        expect(profiler.isAttached, isTrue);

        for (var i = 0; i < 8; i++) {
          final frame = PlayerTelemetryFrame(
            frameIndex: i,
            frameTimeMs: 12.0 + i,
            cpuSpans: const [
              CpuSpanSample(name: 'Physics', durationMs: 2.1),
              CpuSpanSample(name: 'RenderSync', durationMs: 1.4),
            ],
            gpuPasses: const [
              GpuPassTimingSample(passName: 'ShadowCSM', durationMs: 1.2),
              GpuPassTimingSample(passName: 'LitOpaque', durationMs: 3.5),
            ],
            drawCalls: 42,
            triangles: 85000,
          );
          final rt = PlayerTelemetryFrame.fromJson(frame.toJson());
          profiler.pushFrame(rt);
        }

        // Ring buffer capped at 5
        expect(profiler.frames, hasLength(5));
        expect(profiler.hasHardwareGpuTimings, isTrue);
        expect(profiler.averageGpuTimeMs, closeTo(4.7, 1e-6));
      },
    );

    test(
      'FrameCaptureSnapshot saves and loads cleanly via ProjectFileSystem',
      () async {
        final fs = MemoryProjectFileSystem();
        final profiler = ProfilerWindowModel();
        const capture = FrameCaptureSnapshot(
          frameIndex: 120,
          player: PlayerLinkHandshake(
            playerId: 'studio-inproc',
            target: 'web',
            buildProfile: 'web-dev',
          ),
          passes: [
            FrameCapturePassRecord(
              passName: 'ShadowCSM',
              drawLabels: ['Terrain', 'Hero'],
              pipelineState: {'cullFace': 'front'},
            ),
            FrameCapturePassRecord(
              passName: 'LitOpaque',
              drawLabels: ['Terrain', 'Hero', 'Skybox'],
              pipelineState: {'hdr': true},
            ),
          ],
        );

        await profiler.saveCapture(fs, '.volition/captures/f120.json', capture);
        final loaded = await profiler.loadCapture(
          fs,
          '.volition/captures/f120.json',
        );
        expect(loaded.frameIndex, equals(120));
        expect(loaded.passes, hasLength(2));
        expect(loaded.passes.last.drawLabels, contains('Skybox'));
      },
    );
  });
}
