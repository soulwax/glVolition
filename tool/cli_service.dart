import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gl_volition/gl_volition.dart';

import 'package_native.dart';

final class _CliReplayHost implements EngineHost {
  final HeadlessHost _inner = HeadlessHost();

  @override
  final Input input;

  _CliReplayHost(this.input);

  @override
  SceneNode get sceneRoot => _inner.sceneRoot;
  @override
  Graphics get graphics => _inner.graphics;
  @override
  AssetLoader get assets => _inner.assets;
  @override
  AudioDevice get audio => _inner.audio;
  @override
  KeyValueStore get storage => _inner.storage;
  @override
  void reportError(Object error, StackTrace stack) =>
      _inner.reportError(error, stack);
}

/// Health status of a single environment check in [DoctorReport].
enum DoctorStatus { ok, warning, error }

/// Single environment or toolchain diagnostic entry.
class DoctorCheckItem {
  const DoctorCheckItem({
    required this.id,
    required this.name,
    required this.status,
    required this.detail,
    this.remediation,
  });

  final String id;
  final String name;
  final DoctorStatus status;
  final String detail;
  final String? remediation;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'status': status.name,
    'detail': detail,
    if (remediation != null) 'remediation': remediation,
  };
}

/// Complete environment diagnostic report produced by [VolitionCliService.runDoctor].
class DoctorReport {
  const DoctorReport({
    required this.checks,
    required this.timestampIso,
    this.browserPath,
  });

  final List<DoctorCheckItem> checks;
  final String timestampIso;
  final String? browserPath;

  bool get allOk => checks.every((c) => c.status == DoctorStatus.ok);

  Map<String, Object?> toJson() => {
    'timestamp': timestampIso,
    'allOk': allOk,
    if (browserPath != null) 'browserPath': browserPath,
    'checks': checks.map((c) => c.toJson()).toList(),
  };
}

/// Streamed log line emitted by a running CLI task.
class CliLogEvent {
  const CliLogEvent({
    required this.taskId,
    required this.stream,
    required this.line,
    required this.timestampMs,
  });

  final String taskId;
  final String stream; // 'stdout' | 'stderr' | 'info'
  final String line;
  final int timestampMs;

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'stream': stream,
    'line': line,
    'timestampMs': timestampMs,
  };
}

/// Lifecycle state of a [CliTaskSession].
enum CliTaskState { running, completed, failed, cancelled }

/// Snapshot of a CLI task's execution state.
class CliTaskSnapshot {
  const CliTaskSnapshot({
    required this.taskId,
    required this.label,
    required this.command,
    required this.args,
    required this.state,
    required this.durationMs,
    this.exitCode,
  });

  final String taskId;
  final String label;
  final String command;
  final List<String> args;
  final CliTaskState state;
  final int durationMs;
  final int? exitCode;

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'label': label,
    'command': command,
    'args': args,
    'state': state.name,
    'durationMs': durationMs,
    if (exitCode != null) 'exitCode': exitCode,
  };
}

/// Handle for a running or finished CLI subprocess task.
class CliTaskSession {
  CliTaskSession._({
    required this.taskId,
    required this.label,
    required this.command,
    required this.args,
    required Process process,
    required void Function(CliLogEvent) onLog,
    required void Function(CliTaskSnapshot) onComplete,
  }) : _process = process {
    _stopwatch.start();
    final subOut = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          onLog(
            CliLogEvent(
              taskId: taskId,
              stream: 'stdout',
              line: line,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        });
    final subErr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          onLog(
            CliLogEvent(
              taskId: taskId,
              stream: 'stderr',
              line: line,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        });

    process.exitCode.then((code) async {
      await Future.wait([subOut.cancel(), subErr.cancel()]);
      _stopwatch.stop();
      _exitCode = code;
      if (_cancelled) {
        _state = CliTaskState.cancelled;
      } else {
        _state = code == 0 ? CliTaskState.completed : CliTaskState.failed;
      }
      final snap = snapshot();
      onComplete(snap);
      if (!_doneCompleter.isCompleted) {
        _doneCompleter.complete(snap);
      }
    });
  }

  final String taskId;
  final String label;
  final String command;
  final List<String> args;
  final Process _process;
  final Stopwatch _stopwatch = Stopwatch();
  final Completer<CliTaskSnapshot> _doneCompleter = Completer();

  CliTaskState _state = CliTaskState.running;
  bool _cancelled = false;
  int? _exitCode;

  Future<CliTaskSnapshot> get done => _doneCompleter.future;

  CliTaskSnapshot snapshot() => CliTaskSnapshot(
    taskId: taskId,
    label: label,
    command: command,
    args: args,
    state: _state,
    durationMs: _stopwatch.elapsedMilliseconds,
    exitCode: _exitCode,
  );

  /// Requests termination of the underlying subprocess.
  bool cancel() {
    if (_state != CliTaskState.running) return false;
    _cancelled = true;
    return _process.kill();
  }
}

/// Shared service layer backing both the `volition` CLI and `volition gui`.
class VolitionCliService {
  VolitionCliService({String? workingDirectory})
    : workingDirectory = workingDirectory ?? Directory.current.path;

  final String workingDirectory;

  final StreamController<CliLogEvent> _logController =
      StreamController<CliLogEvent>.broadcast();
  final StreamController<CliTaskSnapshot> _taskController =
      StreamController<CliTaskSnapshot>.broadcast();
  final Map<String, CliTaskSession> _activeTasks = {};
  final List<CliTaskSnapshot> _history = [];

  CliTaskSession? _serveTask;
  int? _servePort;
  String? _serveEntry;
  int _nextTaskSeq = 1;

  Stream<CliLogEvent> get logs => _logController.stream;
  Stream<CliTaskSnapshot> get taskUpdates => _taskController.stream;

  String get dartExecutable => NativePackager.resolveDartExecutable();

  Map<String, Object?> get serveStatus => {
    'running': _serveTask != null,
    if (_servePort != null) 'port': _servePort,
    if (_serveEntry != null) 'entry': _serveEntry,
    if (_serveTask != null && _servePort != null)
      'url': 'http://127.0.0.1:$_servePort',
    if (_serveTask != null) 'taskId': _serveTask!.taskId,
  };

  List<CliTaskSnapshot> get activeTasks =>
      _activeTasks.values.map((t) => t.snapshot()).toList();

  List<CliTaskSnapshot> get recentHistory => List.unmodifiable(_history);

  /// Runs environment and toolchain diagnostics equivalent to `volition doctor`.
  Future<DoctorReport> runDoctor() async {
    final checks = <DoctorCheckItem>[];

    // 1. Dart SDK
    final dartVer = Platform.version.split(' ').first;
    checks.add(
      DoctorCheckItem(
        id: 'dart_sdk',
        name: 'Dart SDK',
        status: DoctorStatus.ok,
        detail: '$dartVer on ${Platform.operatingSystem}',
      ),
    );

    // 2. Web / Chrome / Edge
    final browserPath = await findBrowserExecutable();
    if (browserPath != null) {
      checks.add(
        DoctorCheckItem(
          id: 'browser',
          name: 'Web / Chrome',
          status: DoctorStatus.ok,
          detail: 'Found at $browserPath',
        ),
      );
    } else {
      checks.add(
        const DoctorCheckItem(
          id: 'browser',
          name: 'Web / Chrome',
          status: DoctorStatus.warning,
          detail: 'No standard Chrome/Edge browser found',
          remediation: 'Install Google Chrome or Microsoft Edge for WebGL2.',
        ),
      );
    }

    // 3. C/C++ Host Compiler
    final compilerDesc = await _findNativeCompiler();
    if (compilerDesc != null) {
      checks.add(
        DoctorCheckItem(
          id: 'compiler',
          name: 'C/C++ Host Compiler',
          status: DoctorStatus.ok,
          detail: 'Found $compilerDesc',
        ),
      );
    } else {
      checks.add(
        const DoctorCheckItem(
          id: 'compiler',
          name: 'C/C++ Host Compiler',
          status: DoctorStatus.warning,
          detail: 'Not found in PATH',
          remediation:
              'Install MSVC Build Tools, Clang, or GCC if building FFI.',
        ),
      );
    }

    // 4. Native Runtime Libraries (SDL3 / GLES)
    final sdlDir = _findSdl3Dir();
    if (sdlDir != null) {
      checks.add(
        DoctorCheckItem(
          id: 'native_libs',
          name: 'Native Libraries (SDL3/GLES)',
          status: DoctorStatus.ok,
          detail: 'Found runtime binaries in $sdlDir',
        ),
      );
    } else {
      checks.add(
        const DoctorCheckItem(
          id: 'native_libs',
          name: 'Native Libraries (SDL3/GLES)',
          status: DoctorStatus.warning,
          detail: 'SDL3 runtime binary not in bin/native',
          remediation:
              'Place SDL3/ANGLE shared libraries in bin/native for windowed desktop builds.',
        ),
      );
    }

    // 5. Shader Toolchain
    final shaderFile = File(
      '$workingDirectory${Platform.pathSeparator}vendor${Platform.pathSeparator}pixeldart${Platform.pathSeparator}tools${Platform.pathSeparator}renderer${Platform.pathSeparator}shaders.dart',
    );
    if (shaderFile.existsSync()) {
      checks.add(
        const DoctorCheckItem(
          id: 'shader_toolchain',
          name: 'Shader Toolchain',
          status: DoctorStatus.ok,
          detail: 'pixeldart WGSL/GLSL shader pipeline ready',
        ),
      );
    } else {
      checks.add(
        const DoctorCheckItem(
          id: 'shader_toolchain',
          name: 'Shader Toolchain',
          status: DoctorStatus.warning,
          detail: 'vendor/pixeldart/tools/renderer/shaders.dart not found',
          remediation: 'Run git submodule update --init --recursive.',
        ),
      );
    }

    return DoctorReport(
      checks: checks,
      timestampIso: DateTime.now().toUtc().toIso8601String(),
      browserPath: browserPath,
    );
  }

  /// Discovers runnable Dart entrypoints in the workspace for GUI pickers.
  List<String> discoverEntries() {
    final entries = <String>[];
    final sep = Platform.pathSeparator;

    final exampleDir = Directory('$workingDirectory${sep}example');
    if (exampleDir.existsSync()) {
      for (final entity in exampleDir.listSync()) {
        if (entity is Directory) {
          final mainFile = File('${entity.path}${sep}main.dart');
          if (mainFile.existsSync()) {
            final name = entity.path.split(RegExp(r'[/\\]')).last;
            entries.add('example/$name/main.dart');
          }
        }
      }
    }

    final libMain = File('$workingDirectory${sep}lib${sep}main.dart');
    if (libMain.existsSync()) {
      entries.add('lib/main.dart');
    }

    entries.sort();
    return entries;
  }

  /// Discovers inspectable `.pak` archives, `*scene*.json` files, and
  /// `*tape*.json` replay tapes in [workingDirectory] (skipping `.git`,
  /// `.dart_tool`, and `vendor`).
  Map<String, List<String>> discoverInspectableFiles() {
    final scenes = <String>[];
    final paks = <String>[];
    final tapes = <String>[];
    final rootDir = Directory(workingDirectory);
    if (!rootDir.existsSync()) {
      return {'scenes': scenes, 'paks': paks, 'tapes': tapes};
    }

    final rootNorm = rootDir.absolute.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');

    void walk(Directory dir) {
      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final entity in children) {
        final fullNorm = entity.absolute.path.replaceAll('\\', '/');
        if (!fullNorm.startsWith('$rootNorm/')) continue;
        final rel = fullNorm.substring(rootNorm.length + 1);
        final baseName = rel.split('/').last;
        if (entity is Directory) {
          if (baseName == '.git' ||
              baseName == '.dart_tool' ||
              baseName == 'vendor') {
            continue;
          }
          walk(entity);
        } else if (entity is File) {
          final lower = baseName.toLowerCase();
          if (lower.endsWith('.pak')) {
            paks.add(rel);
          } else if (lower.endsWith('.json') && lower.contains('tape')) {
            tapes.add(rel);
          } else if (lower.endsWith('.json') && lower.contains('scene')) {
            scenes.add(rel);
          }
        }
      }
    }

    walk(rootDir);
    scenes.sort();
    paks.sort();
    tapes.sort();
    return {'scenes': scenes, 'paks': paks, 'tapes': tapes};
  }

  /// Parses a `.pak` VFS archive, `InputTape` JSON, or Scene JSON file and
  /// returns structured inspection metadata for `volition gui` and CLI tools.
  Map<String, Object?> inspectArtifact(String relativePath, {int? xorKey}) {
    final rawFile = File(relativePath);
    final file = rawFile.isAbsolute
        ? rawFile
        : File(
            '$workingDirectory${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
          );
    if (!file.existsSync()) {
      throw FileSystemException('Artifact not found', file.path);
    }

    final normalizedPath = relativePath.replaceAll('\\', '/');
    final lower = normalizedPath.toLowerCase();

    if (lower.endsWith('.pak')) {
      final bytes = file.readAsBytesSync();
      final archive = PakArchive.parse(
        bytes,
        xorKey: xorKey,
        verifyTocChecksum: true,
      );
      var totalRawBytes = 0;
      var totalStoredBytes = 0;
      for (final e in archive.entries) {
        totalRawBytes += e.rawSize;
        totalStoredBytes += e.storedSize;
      }
      return {
        'kind': 'pak',
        'path': normalizedPath,
        'fileSizeBytes': bytes.length,
        'entryCount': archive.entries.length,
        'totalRawBytes': totalRawBytes,
        'totalStoredBytes': totalStoredBytes,
        'entries': [
          for (final e in archive.entries)
            {
              'path': e.path,
              'rawSize': e.rawSize,
              'storedSize': e.storedSize,
              'compressed': e.isCompressed,
              'masked': e.isMasked,
              'crc32': e.crc32,
            },
        ],
      };
    }

    if (lower.endsWith('.json')) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        throw const FormatException('Expected top-level JSON object');
      }
      final data = decoded.cast<String, Object?>();

      if (data['frames'] is List) {
        final frames = data['frames'] as List<Object?>;
        var totalDt = 0.0;
        final distinctKeys = <String>{};
        for (final rawFrame in frames) {
          if (rawFrame is! Map) continue;
          final dt = rawFrame['dt'];
          if (dt is num) totalDt += dt.toDouble();
          for (final listKey in const ['keysDown', 'keysPressed']) {
            final keys = rawFrame[listKey];
            if (keys is List) {
              for (final k in keys) {
                distinctKeys.add(k.toString());
              }
            }
          }
        }
        final checkpoints = data['checkpoints'];
        return {
          'kind': 'tape',
          'path': normalizedPath,
          'fileSizeBytes': file.lengthSync(),
          'tapeName': (data['name'] as String?) ?? 'input_tape',
          'schemaVersion': (data['schemaVersion'] as num?)?.toInt() ?? 1,
          'frameCount': frames.length,
          'totalDurationSeconds': totalDt,
          'checkpointCount': checkpoints is Map ? checkpoints.length : 0,
          'hasInitialScene': data['initialSceneJson'] is Map,
          'distinctKeysUsed': distinctKeys.toList()..sort(),
        };
      }

      final roots = (data['objects'] as List<Object?>?) ?? const [];
      var totalObjects = 0;
      final componentCounts = <String, int>{};

      void countNode(Object? raw) {
        if (raw is! Map) return;
        totalObjects++;
        final comps = raw['components'];
        if (comps is List) {
          for (final c in comps) {
            if (c is Map && c['type'] is String) {
              final t = c['type'] as String;
              componentCounts[t] = (componentCounts[t] ?? 0) + 1;
            }
          }
        }
        final children = raw['children'];
        if (children is List) {
          for (final child in children) {
            countNode(child);
          }
        }
      }

      for (final root in roots) {
        countNode(root);
      }

      return {
        'kind': 'scene',
        'path': normalizedPath,
        'fileSizeBytes': file.lengthSync(),
        'schemaVersion': (data['schemaVersion'] as num?)?.toInt() ?? 1,
        'sceneName': (data['name'] as String?) ?? 'Scene',
        'rootObjectCount': roots.length,
        'totalObjectCount': totalObjects,
        'componentCounts': componentCounts,
        'hasRenderSettings': data['renderSettings'] is Map,
      };
    }

    throw FormatException(
      'Unsupported artifact format for "$relativePath" (expected .pak or .json).',
    );
  }

  /// Loads an [InputTape] JSON file and executes headless deterministic replay
  /// verification via [EngineReplayHarness] (P10-W18-D).
  Map<String, Object?> verifyInputTapeFile(String relativePath) {
    final rawFile = File(relativePath);
    final file = rawFile.isAbsolute
        ? rawFile
        : File(
            '$workingDirectory${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
          );
    if (!file.existsSync()) {
      throw FileSystemException('InputTape file not found', file.path);
    }
    final normalizedPath = relativePath.replaceAll('\\', '/');
    final tape = InputTape.fromJsonString(file.readAsStringSync());
    final driver = ReplayInputDriver();
    final engine = Engine(_CliReplayHost(driver));
    try {
      final result = EngineReplayHarness.run(engine, tape, driver: driver);
      return {
        'path': normalizedPath,
        'tapeName': tape.name,
        'passed': result.passed,
        'framesExecuted': result.framesExecuted,
        'finalSceneHash': result.finalSceneHash,
        'checkpointCount': tape.checkpoints.length,
        'mismatches': result.mismatches,
      };
    } finally {
      engine.dispose();
    }
  }

  /// Spawns a `volition` CLI subcommand (`create`, `build`, `dist`, `pack`, `test`).
  Future<CliTaskSession> startVolitionCommand(
    String subcommand,
    List<String> args, {
    String? label,
  }) {
    final scriptPath = _resolveVolitionScriptPath();
    return _spawnProcess(
      label: label ?? 'volition $subcommand',
      executable: dartExecutable,
      args: ['run', scriptPath, subcommand, ...args],
    );
  }

  /// Spawns a direct `dart` command (e.g. `test`, `analyze`, `format`, `run tool/...`).
  Future<CliTaskSession> startDartCommand(List<String> args, {String? label}) {
    return _spawnProcess(
      label: label ?? 'dart ${args.join(' ')}',
      executable: dartExecutable,
      args: args,
    );
  }

  /// Starts `volition serve` and tracks it as the active dev server session.
  Future<CliTaskSession> startServe({
    required String entry,
    int port = 8080,
    String? root,
  }) async {
    await stopServe();
    final args = <String>[entry, '--port', '$port'];
    if (root != null && root.isNotEmpty) {
      args.addAll(['--root', root]);
    }
    final session = await startVolitionCommand(
      'serve',
      args,
      label: 'serve ($entry :$port)',
    );
    _serveTask = session;
    _servePort = port;
    _serveEntry = entry;
    session.done.then((_) {
      if (identical(_serveTask, session)) {
        _serveTask = null;
        _servePort = null;
        _serveEntry = null;
      }
    });
    return session;
  }

  /// Stops the active `volition serve` process if running.
  Future<bool> stopServe() async {
    final task = _serveTask;
    if (task == null) return false;
    final killed = task.cancel();
    _serveTask = null;
    _servePort = null;
    _serveEntry = null;
    return killed;
  }

  /// Cancels an active task by ID.
  bool cancelTask(String taskId) {
    final task = _activeTasks[taskId];
    if (task == null) return false;
    return task.cancel();
  }

  /// Finds a locally installed Chromium/Chrome/Edge executable, if available.
  Future<String?> findBrowserExecutable() async {
    if (Platform.isWindows) {
      final candidates = [
        'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
        'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
        '${Platform.environment['LOCALAPPDATA']}\\Google\\Chrome\\Application\\chrome.exe',
        'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
        'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          return c;
        }
      }
      return null;
    }

    final res = await Process.run('which', [
      'google-chrome',
      'chromium',
      'google-chrome-stable',
    ]);
    if (res.exitCode == 0 && (res.stdout as String).trim().isNotEmpty) {
      return (res.stdout as String).trim().split('\n').first.trim();
    }
    return null;
  }

  /// Terminates any running tasks and closes stream controllers.
  Future<void> dispose() async {
    await stopServe();
    for (final task in _activeTasks.values.toList()) {
      task.cancel();
    }
    _activeTasks.clear();
    await _logController.close();
    await _taskController.close();
  }

  Future<CliTaskSession> _spawnProcess({
    required String label,
    required String executable,
    required List<String> args,
  }) async {
    final taskId = 'task-${_nextTaskSeq++}';
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );

    final session = CliTaskSession._(
      taskId: taskId,
      label: label,
      command: executable,
      args: args,
      process: process,
      onLog: (event) {
        if (!_logController.isClosed) {
          _logController.add(event);
        }
      },
      onComplete: (snap) {
        _activeTasks.remove(taskId);
        _history.insert(0, snap);
        if (_history.length > 30) {
          _history.removeLast();
        }
        if (!_taskController.isClosed) {
          _taskController.add(snap);
        }
      },
    );

    _activeTasks[taskId] = session;
    if (!_taskController.isClosed) {
      _taskController.add(session.snapshot());
    }
    return session;
  }

  String _resolveVolitionScriptPath() {
    final sep = Platform.pathSeparator;
    final direct = File('$workingDirectory${sep}bin${sep}volition.dart');
    if (direct.existsSync()) {
      return 'bin/volition.dart';
    }
    return 'gl_volition:volition';
  }

  Future<String?> _findNativeCompiler() async {
    if (Platform.isWindows) {
      final whichCl = await Process.run('where', ['cl.exe']);
      if (whichCl.exitCode == 0) {
        return 'MSVC cl.exe (${(whichCl.stdout as String).trim().split('\n').first})';
      }
      final whichClang = await Process.run('where', ['clang.exe']);
      if (whichClang.exitCode == 0) {
        return 'Clang (${(whichClang.stdout as String).trim().split('\n').first})';
      }
      return null;
    }
    final whichClang = await Process.run('which', ['clang', 'gcc']);
    if (whichClang.exitCode == 0) {
      return (whichClang.stdout as String).trim().split('\n').first;
    }
    return null;
  }

  String? _findSdl3Dir() {
    final sep = Platform.pathSeparator;
    const nativeDirs = [
      'bin/native',
      'bin/native/windows',
      'bin/native/linux',
      'bin/native/macos',
    ];
    for (final dir in nativeDirs) {
      final d = Directory('$workingDirectory$sep${dir.replaceAll('/', sep)}');
      if (d.existsSync()) {
        final entries = d.listSync();
        if (entries.any((e) => e.path.toLowerCase().contains('sdl3'))) {
          return dir;
        }
      }
    }
    return null;
  }
}
