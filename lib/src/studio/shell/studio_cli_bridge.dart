/// Pure-Dart Studio ↔ CLI Bridge (`[Wave G14]`):
/// Allows the native AOT Studio GUI (toolbar, Settings, Build panel, and New
/// Project Wizard) to invoke real `volition` CLI commands (`doctor`, `create`,
/// `build`, `dist`, `test`, `codegen`, `pack`) without importing `dart:io` in
/// `lib/src/studio/**`. The native CLI host (`bin/volition.dart`) injects a
/// process-backed implementation, while tests inject a deterministic fake.
library;

import '../console/console_model.dart';

/// Result of running a `volition` CLI command from the Studio GUI.
final class StudioCliResult {
  final List<String> args;
  final int exitCode;
  final String stdoutText;
  final String stderrText;
  final int durationMs;

  const StudioCliResult({
    required this.args,
    required this.exitCode,
    this.stdoutText = '',
    this.stderrText = '',
    this.durationMs = 0,
  });

  bool get succeeded => exitCode == 0;
  String get commandLine => 'volition ${args.join(' ')}';
}

/// Platform-neutral interface for running `volition` CLI commands from Studio.
abstract interface class StudioCliBridge {
  Future<StudioCliResult> runCommand(
    List<String> args, {
    String? workingDirectory,
  });
}

/// In-memory deterministic [StudioCliBridge] used by headless tests and as a
/// safe default when no OS process runner is injected.
final class SimulatedStudioCliBridge implements StudioCliBridge {
  final List<List<String>> recordedCommands = [];
  final Map<String, StudioCliResult> cannedResponses;

  SimulatedStudioCliBridge({this.cannedResponses = const {}});

  @override
  Future<StudioCliResult> runCommand(
    List<String> args, {
    String? workingDirectory,
  }) async {
    recordedCommands.add(List<String>.unmodifiable(args));
    final key = args.isEmpty ? '' : args.first;
    final canned = cannedResponses[key];
    if (canned != null) return canned;
    return StudioCliResult(
      args: List<String>.unmodifiable(args),
      exitCode: 0,
      stdoutText: '[cli] volition ${args.join(' ')} completed (ok).',
      durationMs: 12,
    );
  }
}

/// Coordinates CLI invocations from the Studio GUI, streaming output into
/// [ConsolePanelModel] and tracking recent command history.
final class StudioCliController {
  final StudioCliBridge bridge;
  final ConsolePanelModel console;
  final List<StudioCliResult> history = [];
  bool isRunning = false;
  String? activeCommandLabel;

  StudioCliController({required this.bridge, required this.console});

  StudioCliResult? get lastResult => history.isEmpty ? null : history.last;

  Future<StudioCliResult> execute(
    List<String> args, {
    String? workingDirectory,
  }) async {
    isRunning = true;
    activeCommandLabel = 'volition ${args.join(' ')}';
    console.log(ConsoleLogLevel.info, 'Running: $activeCommandLabel');
    try {
      final res = await bridge.runCommand(
        args,
        workingDirectory: workingDirectory,
      );
      history.add(res);
      if (history.length > 50) history.removeAt(0);
      if (res.stdoutText.trim().isNotEmpty) {
        for (final line in res.stdoutText.trim().split('\n').take(8)) {
          console.log(ConsoleLogLevel.info, line.trimRight());
        }
      }
      if (res.stderrText.trim().isNotEmpty) {
        for (final line in res.stderrText.trim().split('\n').take(8)) {
          console.log(ConsoleLogLevel.error, line.trimRight());
        }
      }
      if (!res.succeeded) {
        console.log(
          ConsoleLogLevel.error,
          '${res.commandLine} exited with code ${res.exitCode}.',
        );
      }
      return res;
    } finally {
      isRunning = false;
      activeCommandLabel = null;
    }
  }
}
