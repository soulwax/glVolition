import 'dart:convert';
import 'dart:io';

/// Subprocess execution callback used by [NativePackager] so builds run real
/// `dart compile` / `dotnet` commands in production and deterministic stubs in
/// unit tests.
typedef NativeProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Supported native desktop and WebView wrapper packaging targets.
enum NativeBuildTarget {
  windows,
  linux,
  macos,
  webview;

  /// Parses CLI `--target` names (`windows`, `linux`, `macos`, `webview`,
  /// `native`, `exe`) into a concrete [NativeBuildTarget].
  ///
  /// `native` and `exe` resolve to [hostOperatingSystem] (defaults to
  /// [Platform.operatingSystem]). Returns `null` for web-only or unknown
  /// targets such as `js` or `wasm`.
  static NativeBuildTarget? tryParse(
    String raw, {
    String? hostOperatingSystem,
  }) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'windows':
        return NativeBuildTarget.windows;
      case 'linux':
        return NativeBuildTarget.linux;
      case 'macos':
        return NativeBuildTarget.macos;
      case 'webview':
        return NativeBuildTarget.webview;
      case 'native':
      case 'exe':
        final os = (hostOperatingSystem ?? Platform.operatingSystem)
            .trim()
            .toLowerCase();
        if (os == 'windows') return NativeBuildTarget.windows;
        if (os == 'macos') return NativeBuildTarget.macos;
        return NativeBuildTarget.linux;
      default:
        return null;
    }
  }

  /// Whether this target compiles a Dart native AOT executable via
  /// `dart compile exe`.
  bool get isNativeAot => this != NativeBuildTarget.webview;

  /// Whether this target uses Windows batch launcher conventions.
  bool get usesWindowsLauncher =>
      this == NativeBuildTarget.windows || this == NativeBuildTarget.webview;

  /// Resolves the output executable filename for [name].
  String binaryFileName(String name) {
    switch (this) {
      case NativeBuildTarget.windows:
        return '$name.exe';
      case NativeBuildTarget.linux:
      case NativeBuildTarget.macos:
        return name;
      case NativeBuildTarget.webview:
        return 'GlVolitionGame.exe';
    }
  }

  /// Expected native graphics/windowing shared libraries for this target.
  List<String> get runtimeLibraryFilenames {
    switch (this) {
      case NativeBuildTarget.windows:
        return const ['SDL3.dll', 'libGLESv2.dll', 'libEGL.dll'];
      case NativeBuildTarget.linux:
        return const ['libSDL3.so.0', 'libGLESv2.so.2', 'libEGL.so.1'];
      case NativeBuildTarget.macos:
        return const ['libSDL3.dylib', 'libGLESv2.dylib', 'libEGL.dylib'];
      case NativeBuildTarget.webview:
        return const [];
    }
  }

  /// Launcher script filename generated alongside the packaged output.
  String launcherFileName(String name) =>
      usesWindowsLauncher ? 'Launch_$name.cmd' : 'launch_$name.sh';
}

/// Planned single-file copy operation (e.g. a `.pak` archive or shared library).
final class PlannedFileCopy {
  final String fileName;
  final String sourcePath;
  final String destinationPath;

  const PlannedFileCopy({
    required this.fileName,
    required this.sourcePath,
    required this.destinationPath,
  });
}

/// Planned recursive asset directory copy operation.
final class PlannedDirectoryCopy {
  final String folderName;
  final String sourcePath;
  final String destinationPath;

  const PlannedDirectoryCopy({
    required this.folderName,
    required this.sourcePath,
    required this.destinationPath,
  });
}

/// Complete, side-effect-free build plan produced by [NativePackager.planBuild].
final class NativePackagePlan {
  final NativeBuildTarget target;
  final String requestedTarget;
  final String name;
  final String version;
  final String entryPath;
  final String workspaceDir;
  final String outputDir;
  final String binaryFileName;
  final String binaryPath;
  final String launcherFileName;
  final String launcherPath;
  final String metadataPath;
  final List<String> expectedRuntimeLibraries;
  final List<String> librarySearchDirs;
  final List<PlannedDirectoryCopy> assetDirectories;
  final List<PlannedFileCopy> pakFiles;
  final List<PlannedFileCopy> runtimeLibraries;
  final List<String> missingRuntimeLibraries;
  final String compileExecutable;
  final List<String> compileArguments;
  final String? indexHtmlSourcePath;
  final String? webviewHostSourcePath;
  final String? webviewCsprojPath;
  final List<String> steps;

  const NativePackagePlan({
    required this.target,
    required this.requestedTarget,
    required this.name,
    required this.version,
    required this.entryPath,
    required this.workspaceDir,
    required this.outputDir,
    required this.binaryFileName,
    required this.binaryPath,
    required this.launcherFileName,
    required this.launcherPath,
    required this.metadataPath,
    required this.expectedRuntimeLibraries,
    required this.librarySearchDirs,
    required this.assetDirectories,
    required this.pakFiles,
    required this.runtimeLibraries,
    required this.missingRuntimeLibraries,
    required this.compileExecutable,
    required this.compileArguments,
    required this.indexHtmlSourcePath,
    required this.webviewHostSourcePath,
    required this.webviewCsprojPath,
    required this.steps,
  });

  /// Full command vector `[compileExecutable, ...compileArguments]`.
  List<String> get compileCommand =>
      List<String>.unmodifiable([compileExecutable, ...compileArguments]);

  /// Formats a human-readable build plan for `--dry-run` output.
  String formatDryRunReport() {
    final buf = StringBuffer()
      ..writeln(
        'Dry-run build plan for "$name" [${target.name}] (requested: $requestedTarget)',
      )
      ..writeln('  Version:     $version')
      ..writeln('  Entry:       ${_toSlashPath(entryPath)}')
      ..writeln('  Output dir:  ${_toSlashPath(outputDir)}')
      ..writeln('  Binary:      ${_toSlashPath(binaryPath)}')
      ..writeln('  Compile cmd: ${compileCommand.join(' ')}')
      ..writeln('  Launcher:    ${_toSlashPath(launcherPath)}')
      ..writeln('  Metadata:    ${_toSlashPath(metadataPath)}');

    if (assetDirectories.isNotEmpty) {
      buf.writeln(
        '  Assets:      ${assetDirectories.map((d) => '${d.folderName} (${_toSlashPath(d.sourcePath)})').join(', ')}',
      );
    } else {
      buf.writeln('  Assets:      (none found)');
    }

    if (pakFiles.isNotEmpty) {
      buf.writeln(
        '  Pak files:   ${pakFiles.map((p) => '${p.fileName} (${_toSlashPath(p.sourcePath)})').join(', ')}',
      );
    }

    if (target.isNativeAot) {
      if (runtimeLibraries.isNotEmpty) {
        buf.writeln(
          '  Native libs: ${runtimeLibraries.map((l) => '${l.fileName} <- ${_toSlashPath(l.sourcePath)}').join(', ')}',
        );
      } else {
        buf.writeln('  Native libs: (none found in search directories)');
      }
      if (missingRuntimeLibraries.isNotEmpty) {
        buf.writeln(
          '  Optional missing libs: ${missingRuntimeLibraries.join(', ')}',
        );
      }
    } else if (webviewCsprojPath != null) {
      buf.writeln(
        '  WebView2 csproj: ${_toSlashPath(webviewCsprojPath!)} (host: ${_toSlashPath(webviewHostSourcePath ?? '')})',
      );
    }

    buf.writeln('  Steps:');
    for (var i = 0; i < steps.length; i++) {
      buf.writeln('    ${i + 1}. ${steps[i]}');
    }
    return buf.toString().trimRight();
  }

  static String _toSlashPath(String path) => path.replaceAll('\\', '/');
}

/// Outcome returned by [NativePackager.package] and [NativePackager.executePlan].
final class NativePackageResult {
  final NativePackagePlan plan;
  final bool dryRun;
  final bool success;
  final int exitCode;
  final String? errorMessage;
  final List<String> copiedAssets;
  final List<String> copiedPakFiles;
  final List<String> bundledLibraries;
  final List<String> missingLibraries;
  final bool launcherGenerated;
  final bool metadataWritten;
  final int? binarySizeBytes;

  const NativePackageResult({
    required this.plan,
    required this.dryRun,
    required this.success,
    required this.exitCode,
    this.errorMessage,
    this.copiedAssets = const [],
    this.copiedPakFiles = const [],
    this.bundledLibraries = const [],
    this.missingLibraries = const [],
    this.launcherGenerated = false,
    this.metadataWritten = false,
    this.binarySizeBytes,
  });
}

/// Plans and packages glVolition native AOT desktop builds (`windows`, `linux`,
/// `macos`) as well as `.NET 10` WinForms `WebView2` desktop bundles.
final class NativePackager {
  static const List<String> staticAssetFolderNames = <String>[
    'models',
    'audio',
    'assets',
    'res',
  ];

  final String dartExecutable;
  final NativeProcessRunner processRunner;
  final String Function()? gitCommitResolver;
  final DateTime Function()? clock;
  final String hostOperatingSystem;

  NativePackager({
    String? dartExecutable,
    NativeProcessRunner? processRunner,
    this.gitCommitResolver,
    this.clock,
    String? hostOperatingSystem,
  }) : dartExecutable = dartExecutable ?? resolveDartExecutable(),
       processRunner = processRunner ?? _defaultProcessRunner,
       hostOperatingSystem = (hostOperatingSystem ?? Platform.operatingSystem)
           .trim()
           .toLowerCase();

  /// Resolves the `dart` SDK CLI executable even when running from a compiled
  /// standalone AOT executable such as `volition.exe`.
  static String resolveDartExecutable() {
    final current = Platform.resolvedExecutable;
    final lower = current.toLowerCase();
    if (lower.endsWith('dart') || lower.endsWith('dart.exe')) {
      return current;
    }
    return Platform.isWindows ? 'dart.exe' : 'dart';
  }

  /// Resolves version from [explicit], `<distRoot>/version`, `pubspec.yaml`,
  /// or `'UNRELEASED'`.
  static String resolveVersion({
    String? explicit,
    String distRoot = 'dist',
    String? workspaceDir,
  }) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }
    final base = workspaceDir ?? Directory.current.path;
    final resolvedDistRoot = _resolveFromWorkspace(base, distRoot);
    final distVerFile = File(_joinPath(resolvedDistRoot, 'version'));
    if (distVerFile.existsSync()) {
      final v = distVerFile.readAsStringSync().trim();
      if (v.isNotEmpty) return v;
    }
    final pubspecFile = File(_joinPath(base, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      for (final line in pubspecFile.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.startsWith('version:')) {
          final v = trimmed.substring('version:'.length).trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
    return 'UNRELEASED';
  }

  /// Resolves a package/game name from [explicit] or [entryFile].
  static String resolveName(File entryFile, {String? explicit}) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }
    final normalized = _toSlashPath(entryFile.path);
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    final exampleIdx = parts.indexOf('example');
    if (exampleIdx != -1 && exampleIdx + 1 < parts.length) {
      final seg = parts[exampleIdx + 1];
      if (seg != 'main.dart' && !seg.endsWith('.dart')) {
        return seg;
      }
    }
    final parent = _toSlashPath(entryFile.parent.path).split('/').last;
    if (parent.isNotEmpty &&
        parent != '.' &&
        parent != 'lib' &&
        parent != 'bin') {
      return parent;
    }
    final fileName = parts.isEmpty ? 'game' : parts.last;
    return fileName.endsWith('.dart')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
  }

  /// Resolves the short git HEAD hash in [workingDirectory], or `'unknown'`.
  static String resolveGitCommit({String? workingDirectory}) {
    try {
      final res = Process.runSync('git', const [
        'rev-parse',
        '--short',
        'HEAD',
      ], workingDirectory: workingDirectory);
      if (res.exitCode == 0) {
        final out = (res.stdout as String).trim();
        if (out.isNotEmpty) return out;
      }
    } on Object {
      // Ignore missing git executable or non-git workspace.
    }
    return 'unknown';
  }

  /// Default search directories probed when locating native runtime shared
  /// libraries for [target].
  static List<String> defaultLibrarySearchDirs({
    required String entryDir,
    required String workspaceDir,
    required NativeBuildTarget target,
  }) {
    final envDir = Platform.environment['VOLITION_NATIVE_LIBS_DIR'];
    final envPaths = <String>[];
    if (envDir != null && envDir.trim().isNotEmpty) {
      final sep = Platform.isWindows ? ';' : ':';
      for (final part in envDir.split(sep)) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) envPaths.add(trimmed);
      }
    }

    final raw = <String>[
      ...envPaths,
      entryDir,
      _joinPath(entryDir, 'native'),
      _joinPath(entryDir, 'native/${target.name}'),
      _joinPath(workspaceDir, 'native'),
      _joinPath(workspaceDir, 'native/${target.name}'),
      _joinPath(workspaceDir, 'third_party/native/${target.name}'),
      _joinPath(workspaceDir, 'vendor/native/${target.name}'),
      workspaceDir,
    ];
    return _deduplicatePaths(raw);
  }

  /// Discovers existing static asset folders (`models`, `audio`, `assets`,
  /// `res`) for [entryDir] and [workspaceDir], mapping them into [outputDir].
  static List<PlannedDirectoryCopy> discoverStaticAssetDirectories({
    required String entryDir,
    required String workspaceDir,
    required String outputDir,
  }) {
    final planned = <PlannedDirectoryCopy>[];
    for (final folder in staticAssetFolderNames) {
      final candidates = _deduplicatePaths([
        _joinPath(entryDir, folder),
        _joinPath(workspaceDir, folder),
        _joinPath(workspaceDir, 'vendor/pixeldart/web/$folder'),
        _joinPath(workspaceDir, 'vendor/pixeldart/examples/example_1/$folder'),
      ]);
      for (final candidate in candidates) {
        if (Directory(candidate).existsSync()) {
          planned.add(
            PlannedDirectoryCopy(
              folderName: folder,
              sourcePath: candidate,
              destinationPath: _joinPath(outputDir, folder),
            ),
          );
          break;
        }
      }
    }
    return List<PlannedDirectoryCopy>.unmodifiable(planned);
  }

  /// Discovers `.pak` files directly inside [entryDir] and [workspaceDir].
  ///
  /// Entry-adjacent `.pak` files take precedence over workspace-level `.pak`
  /// files of the same filename.
  static List<PlannedFileCopy> discoverPakFiles({
    required String entryDir,
    required String workspaceDir,
    required String outputDir,
  }) {
    final byName = <String, File>{};
    for (final dirPath in _deduplicatePaths([entryDir, workspaceDir])) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: false, followLinks: true)) {
        if (entity is! File) continue;
        final fileName = _baseName(entity.path);
        if (!fileName.toLowerCase().endsWith('.pak')) continue;
        byName.putIfAbsent(fileName, () => entity);
      }
    }

    final sortedNames = byName.keys.toList()..sort();
    return List<PlannedFileCopy>.unmodifiable([
      for (final fileName in sortedNames)
        PlannedFileCopy(
          fileName: fileName,
          sourcePath: byName[fileName]!.path,
          destinationPath: _joinPath(outputDir, fileName),
        ),
    ]);
  }

  /// Recursively copies [src] into [dst].
  static void copyDirectory(Directory src, Directory dst) {
    if (_samePath(src.path, dst.path)) return;
    dst.createSync(recursive: true);
    for (final entity in src.listSync(recursive: false, followLinks: true)) {
      final name = _baseName(entity.path);
      if (entity is File) {
        entity.copySync(_joinPath(dst.path, name));
      } else if (entity is Directory) {
        copyDirectory(entity, Directory(_joinPath(dst.path, name)));
      }
    }
  }

  /// Writes standardized `metadata.json` into [destDir].
  static void writeBuildMetadata(
    Directory destDir, {
    required String name,
    required String version,
    required String target,
    required String entryPath,
    required String binaryFileName,
    required bool nativeAot,
    required List<String> bundledLibraries,
    List<String> pakFiles = const [],
    String? commit,
    DateTime? builtAt,
  }) {
    final meta = <String, Object?>{
      'name': name,
      'version': version,
      'target': target,
      'entry': _toSlashPath(entryPath),
      'binary': binaryFileName,
      'nativeAot': nativeAot,
      'bundledLibraries': bundledLibraries,
      if (pakFiles.isNotEmpty) 'pakFiles': pakFiles,
      'builtAt': (builtAt ?? DateTime.now()).toUtc().toIso8601String(),
      'commit': commit ?? resolveGitCommit(),
    };
    File(
      _joinPath(destDir.path, 'metadata.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  }

  /// Builds a deterministic [NativePackagePlan] without mutating disk or
  /// invoking compilers. Used for both `--dry-run` and real builds.
  NativePackagePlan planBuild({
    required String entryPath,
    required NativeBuildTarget target,
    String? requestedTarget,
    String? outputDir,
    String? name,
    String? version,
    String distRoot = 'dist',
    String? workspaceDir,
    List<String>? librarySearchDirs,
  }) {
    final resolvedWorkspace = workspaceDir ?? Directory.current.path;
    final resolvedDistRoot = _resolveFromWorkspace(resolvedWorkspace, distRoot);
    final entryFile = File(entryPath);
    final entryDir = entryFile.parent.path;
    final resolvedVersion = resolveVersion(
      explicit: version,
      distRoot: distRoot,
      workspaceDir: resolvedWorkspace,
    );
    final resolvedName = resolveName(entryFile, explicit: name);
    final effectiveRequested = (requestedTarget ?? target.name)
        .trim()
        .toLowerCase();
    final targetSubdir =
        (effectiveRequested == 'native' || effectiveRequested == 'exe')
        ? 'native'
        : target.name;
    final resolvedOutputDir =
        outputDir ??
        _joinPath(
          resolvedDistRoot,
          '$resolvedVersion/$resolvedName/$targetSubdir',
        );

    final binaryFileName = target.binaryFileName(resolvedName);
    final binaryPath = _joinPath(resolvedOutputDir, binaryFileName);
    final launcherFileName = target.launcherFileName(resolvedName);
    final launcherPath = _joinPath(resolvedOutputDir, launcherFileName);
    final metadataPath = _joinPath(resolvedOutputDir, 'metadata.json');

    final assetDirectories = discoverStaticAssetDirectories(
      entryDir: entryDir,
      workspaceDir: resolvedWorkspace,
      outputDir: resolvedOutputDir,
    );
    final pakFiles = discoverPakFiles(
      entryDir: entryDir,
      workspaceDir: resolvedWorkspace,
      outputDir: resolvedOutputDir,
    );

    final expectedLibs = target.runtimeLibraryFilenames;
    final searchDirs = _deduplicatePaths(
      librarySearchDirs ??
          defaultLibrarySearchDirs(
            entryDir: entryDir,
            workspaceDir: resolvedWorkspace,
            target: target,
          ),
    );

    final foundLibs = <PlannedFileCopy>[];
    final missingLibs = <String>[];
    if (expectedLibs.isNotEmpty) {
      for (final libName in expectedLibs) {
        String? foundPath;
        for (final dir in searchDirs) {
          final candidate = _joinPath(dir, libName);
          final kind = FileSystemEntity.typeSync(candidate, followLinks: true);
          if (kind == FileSystemEntityType.file) {
            foundPath = candidate;
            break;
          }
        }
        if (foundPath != null) {
          foundLibs.add(
            PlannedFileCopy(
              fileName: libName,
              sourcePath: foundPath,
              destinationPath: _joinPath(resolvedOutputDir, libName),
            ),
          );
        } else {
          missingLibs.add(libName);
        }
      }
    }

    final indexHtmlCandidate = File(_joinPath(entryDir, 'index.html'));
    final indexHtmlSourcePath = indexHtmlCandidate.existsSync()
        ? indexHtmlCandidate.path
        : null;

    String? webviewHostSourcePath;
    String? webviewCsprojPath;
    final List<String> compileArguments;

    if (target.isNativeAot) {
      final isCrossOs = target.name != hostOperatingSystem;
      compileArguments = List<String>.unmodifiable([
        'compile',
        'exe',
        if (isCrossOs) ...['--target-os', target.name],
        '-o',
        binaryPath,
        entryPath,
      ]);
    } else {
      final outJs = _joinPath(resolvedOutputDir, 'main.dart.js');
      compileArguments = List<String>.unmodifiable([
        'compile',
        'js',
        '-O4',
        '--no-source-maps',
        '-o',
        outJs,
        entryPath,
      ]);
      final hostCs = File(
        _joinPath(
          resolvedWorkspace,
          'vendor/pixeldart/examples/desktop_host/Program.cs',
        ),
      );
      if (hostCs.existsSync()) {
        webviewHostSourcePath = hostCs.path;
        webviewCsprojPath = _joinPath(
          resolvedOutputDir,
          'desktop/GlVolitionGame.csproj',
        );
      }
    }

    final steps = _buildPlanSteps(
      target: target,
      entryPath: entryPath,
      outputDir: resolvedOutputDir,
      binaryPath: binaryPath,
      launcherPath: launcherPath,
      metadataPath: metadataPath,
      compileArguments: compileArguments,
      assetDirectories: assetDirectories,
      pakFiles: pakFiles,
      runtimeLibraries: foundLibs,
      missingRuntimeLibraries: missingLibs,
      indexHtmlSourcePath: indexHtmlSourcePath,
      webviewCsprojPath: webviewCsprojPath,
    );

    return NativePackagePlan(
      target: target,
      requestedTarget: effectiveRequested,
      name: resolvedName,
      version: resolvedVersion,
      entryPath: entryPath,
      workspaceDir: resolvedWorkspace,
      outputDir: resolvedOutputDir,
      binaryFileName: binaryFileName,
      binaryPath: binaryPath,
      launcherFileName: launcherFileName,
      launcherPath: launcherPath,
      metadataPath: metadataPath,
      expectedRuntimeLibraries: List<String>.unmodifiable(expectedLibs),
      librarySearchDirs: List<String>.unmodifiable(searchDirs),
      assetDirectories: assetDirectories,
      pakFiles: pakFiles,
      runtimeLibraries: List<PlannedFileCopy>.unmodifiable(foundLibs),
      missingRuntimeLibraries: List<String>.unmodifiable(missingLibs),
      compileExecutable: dartExecutable,
      compileArguments: compileArguments,
      indexHtmlSourcePath: indexHtmlSourcePath,
      webviewHostSourcePath: webviewHostSourcePath,
      webviewCsprojPath: webviewCsprojPath,
      steps: steps,
    );
  }

  /// Plans and optionally executes packaging for [entryPath] and [target].
  ///
  /// When [dryRun] is `true`, no directories are created, no files are copied,
  /// and no compiler subprocesses are invoked.
  Future<NativePackageResult> package({
    required String entryPath,
    required NativeBuildTarget target,
    String? requestedTarget,
    String? outputDir,
    String? name,
    String? version,
    String distRoot = 'dist',
    String? workspaceDir,
    List<String>? librarySearchDirs,
    bool dryRun = false,
    void Function(String message)? onLog,
  }) {
    final plan = planBuild(
      entryPath: entryPath,
      target: target,
      requestedTarget: requestedTarget,
      outputDir: outputDir,
      name: name,
      version: version,
      distRoot: distRoot,
      workspaceDir: workspaceDir,
      librarySearchDirs: librarySearchDirs,
    );
    return executePlan(plan, dryRun: dryRun, onLog: onLog);
  }

  /// Executes an existing [NativePackagePlan] (or returns a dry-run result
  /// without touching disk when [dryRun] is `true`).
  Future<NativePackageResult> executePlan(
    NativePackagePlan plan, {
    bool dryRun = false,
    void Function(String message)? onLog,
  }) async {
    if (dryRun) {
      return NativePackageResult(
        plan: plan,
        dryRun: true,
        success: true,
        exitCode: 0,
        copiedAssets: plan.assetDirectories.map((d) => d.folderName).toList(),
        copiedPakFiles: plan.pakFiles.map((p) => p.fileName).toList(),
        bundledLibraries: plan.runtimeLibraries.map((l) => l.fileName).toList(),
        missingLibraries: plan.missingRuntimeLibraries,
      );
    }

    if (!File(plan.entryPath).existsSync()) {
      return NativePackageResult(
        plan: plan,
        dryRun: false,
        success: false,
        exitCode: 66,
        errorMessage: 'Entry file not found: ${plan.entryPath}',
        missingLibraries: plan.missingRuntimeLibraries,
      );
    }

    final destDir = Directory(plan.outputDir)..createSync(recursive: true);

    if (plan.target.isNativeAot) {
      return _executeNativeAot(plan, destDir, onLog: onLog);
    }
    return _executeWebView(plan, destDir, onLog: onLog);
  }

  Future<NativePackageResult> _executeNativeAot(
    NativePackagePlan plan,
    Directory destDir, {
    void Function(String message)? onLog,
  }) async {
    onLog?.call('Compiling native AOT executable -> ${plan.binaryPath}');
    final compileRes = await processRunner(
      plan.compileExecutable,
      plan.compileArguments,
      workingDirectory: plan.workspaceDir,
    );
    if (compileRes.exitCode != 0) {
      final output = '${compileRes.stdout}\n${compileRes.stderr}'.trim();
      return NativePackageResult(
        plan: plan,
        dryRun: false,
        success: false,
        exitCode: compileRes.exitCode == 0 ? 1 : compileRes.exitCode,
        errorMessage: output.isEmpty
            ? 'dart compile exe failed with exit code ${compileRes.exitCode}'
            : output,
        missingLibraries: plan.missingRuntimeLibraries,
      );
    }

    final copiedAssets = _copyPlannedAssets(plan, onLog: onLog);
    final copiedPaks = _copyPlannedPaks(plan, onLog: onLog);
    final bundledLibraries = _copyPlannedLibraries(plan, onLog: onLog);

    _writeNativeLauncher(plan, destDir);
    _chmodExecutableIfPosix(plan);

    final binaryFile = File(plan.binaryPath);
    final sizeBytes = binaryFile.existsSync() ? binaryFile.lengthSync() : null;

    writeBuildMetadata(
      destDir,
      name: plan.name,
      version: plan.version,
      target: plan.target.name,
      entryPath: plan.entryPath,
      binaryFileName: plan.binaryFileName,
      nativeAot: true,
      bundledLibraries: bundledLibraries,
      pakFiles: copiedPaks,
      commit:
          gitCommitResolver?.call() ??
          resolveGitCommit(workingDirectory: plan.workspaceDir),
      builtAt: clock?.call(),
    );

    return NativePackageResult(
      plan: plan,
      dryRun: false,
      success: true,
      exitCode: 0,
      copiedAssets: copiedAssets,
      copiedPakFiles: copiedPaks,
      bundledLibraries: bundledLibraries,
      missingLibraries: plan.missingRuntimeLibraries,
      launcherGenerated: true,
      metadataWritten: true,
      binarySizeBytes: sizeBytes,
    );
  }

  Future<NativePackageResult> _executeWebView(
    NativePackagePlan plan,
    Directory destDir, {
    void Function(String message)? onLog,
  }) async {
    if (plan.indexHtmlSourcePath != null) {
      final htmlDst = _joinPath(destDir.path, 'index.html');
      if (!_samePath(plan.indexHtmlSourcePath!, htmlDst)) {
        File(plan.indexHtmlSourcePath!).copySync(htmlDst);
      }
    }
    final copiedAssets = _copyPlannedAssets(plan, onLog: onLog);
    final copiedPaks = _copyPlannedPaks(plan, onLog: onLog);

    final buildSubdir = Directory(_joinPath(destDir.path, 'build'))
      ..createSync(recursive: true);
    final outJs = _joinPath(destDir.path, 'main.dart.js');
    final outBuildJs = _joinPath(buildSubdir.path, 'main.dart.js');

    onLog?.call('Compiling JS bundle for WebView2 desktop host -> $outJs');
    final compileRes = await processRunner(
      plan.compileExecutable,
      plan.compileArguments,
      workingDirectory: plan.workspaceDir,
    );
    if (compileRes.exitCode != 0) {
      final output = '${compileRes.stdout}\n${compileRes.stderr}'.trim();
      return NativePackageResult(
        plan: plan,
        dryRun: false,
        success: false,
        exitCode: compileRes.exitCode == 0 ? 1 : compileRes.exitCode,
        errorMessage: output.isEmpty
            ? 'dart compile js failed with exit code ${compileRes.exitCode}'
            : output,
        copiedAssets: copiedAssets,
        copiedPakFiles: copiedPaks,
      );
    }
    if (File(outJs).existsSync()) {
      File(outJs).copySync(outBuildJs);
    }

    _writeWebViewLaunchers(plan, destDir);

    int? sizeBytes;
    final hostPath = plan.webviewHostSourcePath;
    final csprojPath = plan.webviewCsprojPath;
    if (hostPath != null && csprojPath != null) {
      final csprojFile = File(csprojPath);
      csprojFile.parent.createSync(recursive: true);
      final hostAbs = File(hostPath).absolute.path;
      csprojFile.writeAsStringSync(
        _webviewCsprojTemplate(name: plan.name, hostAbsPath: hostAbs),
      );

      final pubDir = _joinPath(csprojFile.parent.path, 'publish');
      try {
        final pubRes = await processRunner('dotnet', [
          'publish',
          csprojFile.path,
          '-c',
          'Release',
          '-o',
          pubDir,
        ], workingDirectory: plan.workspaceDir);
        if (pubRes.exitCode == 0) {
          final builtExe = File(_joinPath(pubDir, 'GlVolitionGame.exe'));
          final finalExe = File(_joinPath(destDir.path, 'GlVolitionGame.exe'));
          final namedExe = File(_joinPath(destDir.path, '${plan.name}.exe'));
          if (builtExe.existsSync()) {
            builtExe.copySync(finalExe.path);
            if (plan.name != 'GlVolitionGame') {
              builtExe.copySync(namedExe.path);
            }
            sizeBytes = finalExe.lengthSync();
            onLog?.call(
              'Built single-file WebView2 executable -> ${finalExe.path}',
            );
          }
        }
      } on Object {
        // Fallback cleanly to generated .csproj + HTML/JS bundle if dotnet is missing.
      }
    }

    writeBuildMetadata(
      destDir,
      name: plan.name,
      version: plan.version,
      target: plan.target.name,
      entryPath: plan.entryPath,
      binaryFileName: plan.binaryFileName,
      nativeAot: false,
      bundledLibraries: const [],
      pakFiles: copiedPaks,
      commit:
          gitCommitResolver?.call() ??
          resolveGitCommit(workingDirectory: plan.workspaceDir),
      builtAt: clock?.call(),
    );

    return NativePackageResult(
      plan: plan,
      dryRun: false,
      success: true,
      exitCode: 0,
      copiedAssets: copiedAssets,
      copiedPakFiles: copiedPaks,
      bundledLibraries: const [],
      launcherGenerated: true,
      metadataWritten: true,
      binarySizeBytes: sizeBytes,
    );
  }

  List<String> _copyPlannedAssets(
    NativePackagePlan plan, {
    void Function(String message)? onLog,
  }) {
    final copied = <String>[];
    for (final dirCopy in plan.assetDirectories) {
      copyDirectory(
        Directory(dirCopy.sourcePath),
        Directory(dirCopy.destinationPath),
      );
      copied.add(dirCopy.folderName);
      onLog?.call(
        'Copied asset directory ${dirCopy.folderName} -> ${dirCopy.destinationPath}',
      );
    }
    return List<String>.unmodifiable(copied);
  }

  List<String> _copyPlannedPaks(
    NativePackagePlan plan, {
    void Function(String message)? onLog,
  }) {
    final copied = <String>[];
    for (final pak in plan.pakFiles) {
      if (!_samePath(pak.sourcePath, pak.destinationPath)) {
        File(pak.sourcePath).copySync(pak.destinationPath);
      }
      copied.add(pak.fileName);
      onLog?.call('Copied pak ${pak.fileName} -> ${pak.destinationPath}');
    }
    return List<String>.unmodifiable(copied);
  }

  List<String> _copyPlannedLibraries(
    NativePackagePlan plan, {
    void Function(String message)? onLog,
  }) {
    final copied = <String>[];
    for (final lib in plan.runtimeLibraries) {
      if (!_samePath(lib.sourcePath, lib.destinationPath)) {
        File(lib.sourcePath).copySync(lib.destinationPath);
      }
      copied.add(lib.fileName);
      onLog?.call(
        'Bundled native library ${lib.fileName} -> ${lib.destinationPath}',
      );
    }
    return List<String>.unmodifiable(copied);
  }

  void _writeNativeLauncher(NativePackagePlan plan, Directory destDir) {
    final launcher = File(plan.launcherPath);
    final name = plan.name;
    if (plan.target.usesWindowsLauncher) {
      final script = [
        '@echo off',
        'setlocal',
        'cd /d "%~dp0"',
        'set "PATH=%~dp0;%PATH%"',
        'if exist "%~dp0$name.exe" (',
        '    start "" "%~dp0$name.exe" %*',
        '    exit /b 0',
        ')',
        'echo [ERROR] Expected native executable "$name.exe" not found in "%~dp0".',
        'pause',
        'exit /b 1',
      ].join('\r\n');
      launcher.writeAsStringSync('$script\r\n');
    } else {
      final script = [
        '#!/usr/bin/env sh',
        'set -eu',
        r'DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"',
        r'export LD_LIBRARY_PATH="$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"',
        r'export DYLD_LIBRARY_PATH="$DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"',
        'if [ -x "\$DIR/$name" ]; then',
        '  exec "\$DIR/$name" "\$@"',
        'fi',
        'echo "[ERROR] Expected native executable \'$name\' not found in \'\$DIR\'." >&2',
        'exit 1',
      ].join('\n');
      launcher.writeAsStringSync('$script\n');
    }
  }

  void _writeWebViewLaunchers(NativePackagePlan plan, Directory destDir) {
    final name = plan.name;
    final script = [
      '@echo off',
      'setlocal',
      'cd /d "%~dp0"',
      'if exist "$name.exe" (',
      '    start "" "%~dp0$name.exe"',
      '    exit /b 0',
      ')',
      'if exist "GlVolitionGame.exe" (',
      '    start "" "%~dp0GlVolitionGame.exe"',
      '    exit /b 0',
      ')',
      'if exist "index.html" (',
      '    start "" msedge --app="%~dp0index.html"',
      '    exit /b 0',
      ')',
      'echo [ERROR] No runnable game binary found.',
      'pause',
    ].join('\r\n');
    File(plan.launcherPath).writeAsStringSync('$script\r\n');
    File(
      _joinPath(destDir.path, 'launch_desktop.cmd'),
    ).writeAsStringSync('$script\r\n');
  }

  void _chmodExecutableIfPosix(NativePackagePlan plan) {
    if (Platform.isWindows || plan.target.usesWindowsLauncher) return;
    try {
      final targets = <String>[
        if (File(plan.binaryPath).existsSync()) plan.binaryPath,
        if (File(plan.launcherPath).existsSync()) plan.launcherPath,
      ];
      if (targets.isNotEmpty) {
        Process.runSync('chmod', ['+x', ...targets]);
      }
    } on Object {
      // Ignore chmod failures on filesystems without POSIX mode bits.
    }
  }

  List<String> _buildPlanSteps({
    required NativeBuildTarget target,
    required String entryPath,
    required String outputDir,
    required String binaryPath,
    required String launcherPath,
    required String metadataPath,
    required List<String> compileArguments,
    required List<PlannedDirectoryCopy> assetDirectories,
    required List<PlannedFileCopy> pakFiles,
    required List<PlannedFileCopy> runtimeLibraries,
    required List<String> missingRuntimeLibraries,
    required String? indexHtmlSourcePath,
    required String? webviewCsprojPath,
  }) {
    final steps = <String>[
      'Ensure output directory ${_toSlashPath(outputDir)}',
    ];
    if (target.isNativeAot) {
      steps.add('Run $dartExecutable ${compileArguments.join(' ')}');
      for (final asset in assetDirectories) {
        steps.add(
          'Copy asset directory ${_toSlashPath(asset.sourcePath)} -> ${_toSlashPath(asset.destinationPath)}',
        );
      }
      for (final pak in pakFiles) {
        steps.add(
          'Copy pak file ${_toSlashPath(pak.sourcePath)} -> ${_toSlashPath(pak.destinationPath)}',
        );
      }
      for (final lib in runtimeLibraries) {
        steps.add(
          'Copy runtime library ${_toSlashPath(lib.sourcePath)} -> ${_toSlashPath(lib.destinationPath)}',
        );
      }
      if (missingRuntimeLibraries.isNotEmpty) {
        steps.add(
          'Skip unavailable optional runtime libraries: ${missingRuntimeLibraries.join(', ')}',
        );
      }
    } else {
      if (indexHtmlSourcePath != null) {
        steps.add(
          'Copy ${_toSlashPath(indexHtmlSourcePath)} -> ${_toSlashPath(_joinPath(outputDir, 'index.html'))}',
        );
      }
      for (final asset in assetDirectories) {
        steps.add(
          'Copy asset directory ${_toSlashPath(asset.sourcePath)} -> ${_toSlashPath(asset.destinationPath)}',
        );
      }
      for (final pak in pakFiles) {
        steps.add(
          'Copy pak file ${_toSlashPath(pak.sourcePath)} -> ${_toSlashPath(pak.destinationPath)}',
        );
      }
      steps.add('Run $dartExecutable ${compileArguments.join(' ')}');
      steps.add(
        'Copy ${_toSlashPath(_joinPath(outputDir, 'main.dart.js'))} -> ${_toSlashPath(_joinPath(outputDir, 'build/main.dart.js'))}',
      );
      if (webviewCsprojPath != null) {
        steps.add(
          'Generate ${_toSlashPath(webviewCsprojPath)} and run dotnet publish -c Release',
        );
      }
    }
    steps.add('Generate launcher ${_toSlashPath(launcherPath)}');
    steps.add('Write metadata ${_toSlashPath(metadataPath)}');
    return List<String>.unmodifiable(steps);
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.run(executable, arguments, workingDirectory: workingDirectory);

  static String _webviewCsprojTemplate({
    required String name,
    required String hostAbsPath,
  }) =>
      '''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net10.0-windows</TargetFramework>
    <UseWindowsForms>true</UseWindowsForms>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <AssemblyName>GlVolitionGame</AssemblyName>
    <AssemblyTitle>$name</AssemblyTitle>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Web.WebView2" Version="1.0.3856.49" />
    <Compile Include="$hostAbsPath" Link="Program.cs" />
    <EmbeddedResource Include="..\\index.html" LogicalName="game/index.html" />
    <EmbeddedResource Include="..\\main.dart.js" LogicalName="game/main.dart.js" />
    <EmbeddedResource Include="..\\build\\main.dart.js" LogicalName="game/build/main.dart.js" />
    <EmbeddedResource Include="..\\res\\**\\*" LogicalName="game/res/%(RecursiveDir)%(Filename)%(Extension)" Condition="Exists('..\\res')" />
  </ItemGroup>
</Project>
''';

  static bool _isAbsolutePath(String path) =>
      path.startsWith('/') ||
      path.startsWith('\\') ||
      RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path);

  static String _resolveFromWorkspace(String workspaceDir, String path) =>
      _isAbsolutePath(path) ? path : _joinPath(workspaceDir, path);

  static String _joinPath(String a, String b) {
    final cleanA = a.replaceAll(RegExp(r'[/\\]+$'), '');
    final cleanB = b.replaceAll(RegExp(r'^[/\\]+'), '');
    if (cleanA.isEmpty) return cleanB;
    if (cleanB.isEmpty) return cleanA;
    final sep = Platform.pathSeparator;
    return '$cleanA$sep${cleanB.replaceAll(RegExp(r'[/\\]'), sep)}';
  }

  static String _toSlashPath(String path) => path.replaceAll('\\', '/');

  static String _baseName(String path) {
    final parts = _toSlashPath(
      path,
    ).split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  static bool _samePath(String a, String b) =>
      _toSlashPath(File(a).absolute.path).toLowerCase() ==
      _toSlashPath(File(b).absolute.path).toLowerCase();

  static List<String> _deduplicatePaths(Iterable<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final p in raw) {
      if (p.trim().isEmpty) continue;
      final key = _toSlashPath(Directory(p).absolute.path).toLowerCase();
      if (seen.add(key)) {
        result.add(p);
      }
    }
    return result;
  }
}
