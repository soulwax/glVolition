import 'dart:io';

import 'package:gl_volition/gl_volition_native.dart';

import '../dungeon_2d/game.dart';
import '../island_3d/game.dart';
import '../prism_pulse/game.dart';
import '../procession/game.dart';

Future<void> main() async {
  final device = GlesDevice();
  final runner = await NativeEngineHost.boot(
    device: device,
    width: 1280,
    height: 720,
    requestedProfile: QualityProfile.clean,
    registerSpecs: (reg) {
      registerDungeon2DSpecs(reg);
      registerProcessionSpecs(reg);
      registerIsland3DSpecs(reg);
      registerPrismPulseSpecs(reg);
    },
    initialScene: buildDungeon2DScene(),
  );

  final dungeonStats = runner.renderFrame(1 / 60);
  stdout.writeln(
    '[native_smoke] Dungeon2D  -> draws=${dungeonStats.drawCalls}, '
    'tris=${dungeonStats.trianglesSubmitted}, '
    'programs=${device.programCompileCalls}',
  );

  runner.engine.loadScene(buildProcessionScene());
  final processionStats = runner.renderFrame(1 / 60);
  stdout.writeln(
    '[native_smoke] Procession -> draws=${processionStats.drawCalls}, '
    'tris=${processionStats.trianglesSubmitted}',
  );

  runner.engine.loadScene(buildIsland3DScene());
  final islandStats = runner.renderFrame(1 / 60);
  stdout.writeln(
    '[native_smoke] Island3D   -> draws=${islandStats.drawCalls}, '
    'tris=${islandStats.trianglesSubmitted}, '
    'vram=${(islandStats.liveGpuBytes / 1024).toStringAsFixed(1)} KB',
  );

  runner.engine.loadScene(buildPrismPulseScene());
  final prismStats = runner.renderFrame(1 / 60);
  stdout.writeln(
    '[native_smoke] PrismPulse -> draws=${prismStats.drawCalls}, '
    'tris=${prismStats.trianglesSubmitted}, '
    'vram=${(prismStats.liveGpuBytes / 1024).toStringAsFixed(1)} KB',
  );

  runner.dispose();
  if (device.liveObjectCount != 0) {
    stderr.writeln('Expected 0 live GPU objects after dispose, got ${device.liveObjectCount}');
    exit(1);
  }
  stdout.writeln('[native_smoke] Clean shutdown (liveObjectCount = 0).');
}
