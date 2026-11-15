import 'dart:io';

import 'package:gl_volition/gl_volition_native.dart';

import '../dungeon_2d/game.dart';
import '../island_3d/game.dart';
import '../prism_pulse/game.dart';
import '../procession/game.dart';

Future<void> main(List<String> args) async {
  var useHardware = false;

  for (final arg in args) {
    switch (arg) {
      case '--hardware':
        useHardware = true;
      case '--headless':
        useHardware = false;
      case '-h':
      case '--help':
        _printUsage();
        return;
      default:
        stderr.writeln('[native_smoke] Unknown argument: $arg');
        _printUsage(sink: stderr);
        exit(64);
    }
  }

  if (!useHardware) {
    final device = GlesDevice();
    await _runSmokeScenes(device: device, modeLabel: 'headless');
    return;
  }

  final probe = _probeHardwareLibraries();
  if (!probe.isReady) {
    _reportMissingHardwareLibraries(probe);
    exitCode = 1;
    return;
  }

  stdout.writeln(
    '[native_smoke] Hardware libraries loaded: '
    'SDL3=${probe.sdlLibraryName}, GL=${probe.glLoader.libraryName} '
    '(glCreateShader=${probe.glLoader.hasSymbol('glCreateShader')}, '
    'glDrawElements=${probe.glLoader.hasSymbol('glDrawElements')})',
  );

  final transport = NativeGlTransport(procLoader: probe.glLoader);
  final device = transport.createDevice();
  await _runSmokeScenes(device: device, modeLabel: 'hardware');
  stdout.writeln(
    '[native_smoke] NativeGlTransport dispatched ${transport.totalDispatched} commands.',
  );
}

void _printUsage({IOSink? sink}) {
  (sink ?? stdout).writeln(
    'Usage: native_smoke [--headless | --hardware]\n'
    '  --headless  Run software-validated GlesDevice smoke suite (default).\n'
    '  --hardware  Probe SDL3 and ANGLE/GLES3 shared libraries before running.',
  );
}

Future<void> _runSmokeScenes({
  required GlesDevice device,
  required String modeLabel,
}) async {
  stdout.writeln('[native_smoke] Running smoke suite in $modeLabel mode...');
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
    stderr.writeln(
      'Expected 0 live GPU objects after dispose, got ${device.liveObjectCount}',
    );
    exit(1);
  }
  stdout.writeln('[native_smoke] Clean shutdown (liveObjectCount = 0).');
}

final class _HardwareProbeResult {
  final List<String> expectedSdlNames;
  final List<String> expectedGlesNames;
  final bool sdlLoaded;
  final String? sdlLibraryName;
  final String? sdlError;
  final DynamicLibraryGlLoader glLoader;

  const _HardwareProbeResult({
    required this.expectedSdlNames,
    required this.expectedGlesNames,
    required this.sdlLoaded,
    required this.sdlLibraryName,
    required this.sdlError,
    required this.glLoader,
  });

  bool get isReady => sdlLoaded && glLoader.isAvailable;
}

_HardwareProbeResult _probeHardwareLibraries() {
  final List<String> sdlNames;
  final List<String> glesNames;
  if (Platform.isWindows) {
    sdlNames = const ['SDL3.dll'];
    glesNames = const ['libGLESv2.dll', 'libEGL.dll'];
  } else if (Platform.isMacOS) {
    sdlNames = const ['libSDL3.dylib'];
    glesNames = const ['libGLESv2.dylib', 'libEGL.dylib'];
  } else {
    sdlNames = const ['libSDL3.so.0', 'libSDL3.so'];
    glesNames = const ['libGLESv2.so.2', 'libEGL.so.1', 'libGLESv2.so'];
  }

  final extraDirs = _hardwareSearchDirs();
  final sdlCandidates = _expandCandidates(sdlNames, extraDirs);
  final glesCandidates = _expandCandidates(glesNames, extraDirs);

  final sdlProbe = openDynamicLibraryCandidates(sdlCandidates);
  final glLoader = DynamicLibraryGlLoader(candidateLibraries: glesCandidates);

  return _HardwareProbeResult(
    expectedSdlNames: sdlNames,
    expectedGlesNames: glesNames,
    sdlLoaded: sdlProbe.library != null,
    sdlLibraryName: sdlProbe.name,
    sdlError: sdlProbe.error,
    glLoader: glLoader,
  );
}

List<String> _hardwareSearchDirs() {
  final dirs = <String>[];
  final envDir = Platform.environment['VOLITION_NATIVE_LIBS_DIR'];
  if (envDir != null && envDir.trim().isNotEmpty) {
    final sep = Platform.isWindows ? ';' : ':';
    for (final part in envDir.split(sep)) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) dirs.add(trimmed);
    }
  }
  final sep = Platform.pathSeparator;
  final cwd = Directory.current.path;
  dirs.addAll([
    cwd,
    '$cwd${sep}native',
    '$cwd${sep}native$sep${Platform.operatingSystem}',
  ]);
  return dirs;
}

List<String> _expandCandidates(List<String> names, List<String> searchDirs) {
  final sep = Platform.pathSeparator;
  return <String>[
    ...names,
    for (final dir in searchDirs)
      for (final name in names) '$dir$sep$name',
  ];
}

void _reportMissingHardwareLibraries(_HardwareProbeResult probe) {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  stderr.writeln(
    '[native_smoke] Hardware probe failed: native SDL3/ANGLE libraries are unavailable on ${Platform.operatingSystem}.',
  );
  stderr.writeln(
    '  SDL3  (${probe.expectedSdlNames.join(', ')}): '
    '${probe.sdlLoaded ? 'LOADED (${probe.sdlLibraryName})' : 'MISSING (${probe.sdlError ?? 'not found'})'}',
  );
  stderr.writeln(
    '  GLES3 (${probe.expectedGlesNames.join(', ')}): '
    '${probe.glLoader.isAvailable ? 'LOADED (${probe.glLoader.libraryName})' : 'MISSING (${probe.glLoader.loadError ?? 'not found'})'}',
  );
  stderr.writeln('');
  stderr.writeln('How to resolve:');
  stderr.writeln(
    '  1. Place the OS native libraries next to the executable ($exeDir), '
    'on your system library path, or pass --lib-dir <dir> to `volition build ... --target ${Platform.operatingSystem}`.',
  );
  stderr.writeln(
    '  2. Or set VOLITION_NATIVE_LIBS_DIR=<dir> containing those shared libraries.',
  );
  stderr.writeln(
    '  3. Or run without --hardware (or pass --headless) for software-validated GlesDevice verification.',
  );
}
