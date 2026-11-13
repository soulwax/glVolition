import 'dart:io';

/// Unified local and CI verification runner for glVolition and its submodules.
///
/// Usage:
///   dart run tool/verify_all.dart [--check-format] [--skip-root-tests] [--skip-wasm] [--fail-fast]
Future<void> main(List<String> args) async {
  final options = _VerifyOptions.parse(args);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final root = _resolveRepoRoot();
  final dartExe = _resolveDartExecutable();
  final sep = Platform.pathSeparator;
  final verifyArtifactDir = Directory(
    '${root.path}$sep.dart_tool${sep}ci_verify',
  );
  final pixeldartDir = Directory('${root.path}${sep}vendor${sep}pixeldart');
  final voxnetDir = Directory('${root.path}${sep}vendor${sep}voxnet');

  final steps = <_VerifyStep>[
    if (options.checkFormat)
      _VerifyStep(
        name: 'Format check (dart format root dirs)',
        executable: dartExe,
        arguments: const [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          'bin',
          'lib',
          'test',
          'tool',
          'example',
        ],
        workingDirectory: root.path,
      ),
    _VerifyStep(
      name: 'Boundary check (tool/check_boundaries.dart)',
      executable: dartExe,
      arguments: const ['run', 'tool/check_boundaries.dart'],
      workingDirectory: root.path,
    ),
    _VerifyStep(
      name: 'Static analysis (dart analyze)',
      executable: dartExe,
      arguments: const ['analyze'],
      workingDirectory: root.path,
    ),
    if (!options.skipRootTests)
      _VerifyStep(
        name: 'Root test suite (dart test)',
        executable: dartExe,
        arguments: const ['test'],
        workingDirectory: root.path,
      ),
    _VerifyStep(
      name: 'vendor/pixeldart renderer boundary check',
      executable: dartExe,
      arguments: const ['run', 'tools/renderer/check_boundary.dart'],
      workingDirectory: pixeldartDir.path,
    ),
    _VerifyStep(
      name: 'vendor/pixeldart generated shader check',
      executable: dartExe,
      arguments: const ['run', 'tools/renderer/shaders.dart', '--check'],
      workingDirectory: pixeldartDir.path,
    ),
    _VerifyStep(
      name: 'vendor/pixeldart renderer test suite',
      executable: dartExe,
      arguments: const ['run', 'tools/renderer/test_all.dart'],
      workingDirectory: pixeldartDir.path,
    ),
    _VerifyStep(
      name: 'vendor/voxnet test suite',
      executable: dartExe,
      arguments: const ['test'],
      workingDirectory: voxnetDir.path,
    ),
    _VerifyStep(
      name: 'Compile JS smoke (example/prism_pulse/main.dart)',
      executable: dartExe,
      arguments: const [
        'compile',
        'js',
        'example/prism_pulse/main.dart',
        '-o',
        '.dart_tool/ci_verify/prism.js',
      ],
      workingDirectory: root.path,
      prepare: () => _ensureCleanDir(verifyArtifactDir),
    ),
    _VerifyStep(
      name: 'Compile native exe smoke (bin/volition.dart)',
      executable: dartExe,
      arguments: [
        'compile',
        'exe',
        'bin/volition.dart',
        '-o',
        '.dart_tool/ci_verify/${Platform.isWindows ? 'volition.exe' : 'volition'}',
      ],
      workingDirectory: root.path,
      prepare: () => _ensureDir(verifyArtifactDir),
    ),
    if (!options.skipWasm)
      _VerifyStep(
        name: 'Compile Wasm smoke (example/prism_pulse/main.dart)',
        executable: dartExe,
        arguments: const [
          'compile',
          'wasm',
          'example/prism_pulse/main.dart',
          '-o',
          '.dart_tool/ci_verify/prism.wasm',
        ],
        workingDirectory: root.path,
        prepare: () => _ensureDir(verifyArtifactDir),
        skipReason: () => _checkWasmSupport(dartExe, root.path),
      ),
  ];

  final results = <_StepResult>[];
  final totalSw = Stopwatch()..start();

  try {
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      stdout.writeln('');
      stdout.writeln('=== [${i + 1}/${steps.length}] ${step.name} ===');

      final skipReason = step.skipReason?.call();
      if (skipReason != null) {
        stdout.writeln('SKIPPED: $skipReason');
        results.add(_StepResult.skipped(step.name, skipReason));
        continue;
      }

      if (!Directory(step.workingDirectory).existsSync()) {
        stderr.writeln(
          'ERROR: working directory does not exist: ${step.workingDirectory}',
        );
        results.add(
          _StepResult(
            name: step.name,
            exitCode: 2,
            elapsed: Duration.zero,
            skipped: false,
          ),
        );
        if (options.failFast) break;
        continue;
      }

      step.prepare?.call();
      final stepSw = Stopwatch()..start();
      final proc = await Process.start(
        step.executable,
        step.arguments,
        workingDirectory: step.workingDirectory,
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await proc.exitCode;
      stepSw.stop();

      results.add(
        _StepResult(
          name: step.name,
          exitCode: code,
          elapsed: stepSw.elapsed,
          skipped: false,
        ),
      );

      if (code != 0) {
        stderr.writeln(
          'FAILED: ${step.name} (exit $code, ${_fmtDuration(stepSw.elapsed)})',
        );
        if (options.failFast) break;
      } else {
        stdout.writeln(
          'PASSED: ${step.name} (${_fmtDuration(stepSw.elapsed)})',
        );
      }
    }
  } finally {
    _cleanupDir(verifyArtifactDir);
  }

  totalSw.stop();
  _printSummary(results, totalSw.elapsed);

  final anyFailed = results.any((r) => !r.skipped && r.exitCode != 0);
  if (anyFailed) {
    exitCode = 1;
  }
}

final class _VerifyOptions {
  final bool checkFormat;
  final bool skipRootTests;
  final bool skipWasm;
  final bool failFast;
  final bool showHelp;

  const _VerifyOptions({
    required this.checkFormat,
    required this.skipRootTests,
    required this.skipWasm,
    required this.failFast,
    required this.showHelp,
  });

  factory _VerifyOptions.parse(List<String> args) {
    var checkFormat = false;
    var skipRootTests = false;
    var skipWasm = false;
    var failFast = false;
    var showHelp = false;

    for (final arg in args) {
      switch (arg) {
        case '--check-format':
          checkFormat = true;
        case '--skip-root-tests':
          skipRootTests = true;
        case '--skip-wasm':
          skipWasm = true;
        case '--fail-fast':
          failFast = true;
        case '-h':
        case '--help':
          showHelp = true;
        default:
          stderr.writeln('Unknown option: $arg');
          _printUsage();
          exit(64);
      }
    }

    return _VerifyOptions(
      checkFormat: checkFormat,
      skipRootTests: skipRootTests,
      skipWasm: skipWasm,
      failFast: failFast,
      showHelp: showHelp,
    );
  }
}

final class _VerifyStep {
  final String name;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final void Function()? prepare;
  final String? Function()? skipReason;

  const _VerifyStep({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    this.prepare,
    this.skipReason,
  });
}

final class _StepResult {
  final String name;
  final int exitCode;
  final Duration elapsed;
  final bool skipped;
  final String? skipMessage;

  const _StepResult({
    required this.name,
    required this.exitCode,
    required this.elapsed,
    required this.skipped,
    this.skipMessage,
  });

  factory _StepResult.skipped(String name, String reason) => _StepResult(
    name: name,
    exitCode: 0,
    elapsed: Duration.zero,
    skipped: true,
    skipMessage: reason,
  );
}

void _printUsage() {
  stdout.writeln('''
glVolition Verification Runner

Usage:
  dart run tool/verify_all.dart [options]

Options:
  --check-format     Run `dart format --output=none --set-exit-if-changed .`
  --skip-root-tests  Skip root `dart test` suite
  --skip-wasm        Skip `dart compile wasm` smoke build
  --fail-fast        Abort immediately on first failing step
  -h, --help         Show this help message
''');
}

Directory _resolveRepoRoot() {
  final cwd = Directory.current;
  if (_looksLikeRepoRoot(cwd)) return cwd;

  var dir = File.fromUri(Platform.script).absolute.parent;
  while (true) {
    if (_looksLikeRepoRoot(dir)) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  stderr.writeln('Unable to locate repository root from ${cwd.path}.');
  exit(2);
}

bool _looksLikeRepoRoot(Directory dir) {
  final sep = Platform.pathSeparator;
  return File('${dir.path}${sep}pubspec.yaml').existsSync() &&
      File('${dir.path}${sep}lib${sep}gl_volition.dart').existsSync();
}

String _resolveDartExecutable() {
  final current = Platform.resolvedExecutable;
  final lower = current.toLowerCase();
  if (lower.endsWith('dart') || lower.endsWith('dart.exe')) {
    return current;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}

void _ensureCleanDir(Directory dir) {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
}

void _ensureDir(Directory dir) {
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
}

void _cleanupDir(Directory dir) {
  try {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  } catch (e) {
    stderr.writeln('Warning: failed to clean up ${dir.path}: $e');
  }
}

String? _checkWasmSupport(String dartExe, String workingDirectory) {
  try {
    final probe = Process.runSync(dartExe, const [
      'compile',
      'wasm',
      '--help',
    ], workingDirectory: workingDirectory);
    if (probe.exitCode == 0) {
      return null;
    }
    return 'dart compile wasm is not supported by this Dart SDK (exit ${probe.exitCode})';
  } catch (e) {
    return 'unable to probe dart compile wasm support: $e';
  }
}

String _fmtDuration(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

void _printSummary(List<_StepResult> results, Duration totalElapsed) {
  stdout.writeln('');
  stdout.writeln('==================================================');
  stdout.writeln(' Verification Summary (${_fmtDuration(totalElapsed)})');
  stdout.writeln('==================================================');
  var passed = 0;
  var failed = 0;
  var skipped = 0;
  for (final r in results) {
    if (r.skipped) {
      skipped++;
      stdout.writeln('  [SKIP] ${r.name} (${r.skipMessage})');
    } else if (r.exitCode == 0) {
      passed++;
      stdout.writeln('  [PASS] ${r.name} (${_fmtDuration(r.elapsed)})');
    } else {
      failed++;
      stdout.writeln(
        '  [FAIL] ${r.name} (exit ${r.exitCode}, ${_fmtDuration(r.elapsed)})',
      );
    }
  }
  stdout.writeln('--------------------------------------------------');
  stdout.writeln('  Passed: $passed | Failed: $failed | Skipped: $skipped');
  stdout.writeln('==================================================');
}
