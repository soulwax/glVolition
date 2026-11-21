import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../tool/asset_packer.dart';
import '../tool/cli_gui_server.dart';
import '../tool/cli_service.dart';
import '../tool/package_native.dart';
import '../tool/codegen/spec_codegen.dart';
import '../tool/studio/studio_daemon.dart';
import 'package:gl_volition/gl_volition_native.dart';
import 'package:gl_volition/src/studio/studio.dart';

final log = voxlog.stdoutColor('volition', level: LogLevel.info);

String get _dartExecutable => NativePackager.resolveDartExecutable();

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    if (Platform.isWindows && stdout.hasTerminal) {
      stdout.writeln('--------------------------------------------------');
      stdout.writeln('Interactive Launcher (Console):');
      stdout.writeln(
        '  [1] serve  - Start live dev server with hot reload (pixel_rocket)',
      );
      stdout.writeln(
        '  [2] build  - Build game into ./dist/<version>/<name>/<target>/',
      );
      stdout.writeln(
        '  [3] dist   - Package complete distribution (CLI + Game targets)',
      );
      stdout.writeln('  [4] test   - Run engine test suite');
      stdout.writeln('  [5] gui    - Launch glVolition Studio GUI');
      stdout.writeln('  [q] exit');
      stdout.writeln('--------------------------------------------------');
      stdout.write('Select an option [1]: ');
      final input = stdin.readLineSync()?.trim();
      if (input == null || input == 'q' || input == 'quit' || input == 'exit') {
        return;
      }
      if (input.isEmpty || input == '1') {
        await _runServe(['example/pixel_rocket/main.dart']);
      } else if (input == '2') {
        await _runBuild([
          'example/pixel_rocket/main.dart',
          '--target',
          'webview',
        ]);
        stdout.writeln('\nBuild completed. Press Enter to exit.');
        stdin.readLineSync();
      } else if (input == '3') {
        await _runDist(['example/pixel_rocket/main.dart']);
        stdout.writeln(
          '\nDistribution packaging completed. Press Enter to exit.',
        );
        stdin.readLineSync();
      } else if (input == '4') {
        final proc = await Process.start(_dartExecutable, [
          'test',
        ], mode: ProcessStartMode.inheritStdio);
        final code = await proc.exitCode;
        stdout.writeln('\nTests exited with code $code. Press Enter to exit.');
        stdin.readLineSync();
        exit(code);
      } else if (input == '5') {
        await _runGui(const []);
      } else {
        final parts = input.split(RegExp(r'\s+'));
        await main(parts);
      }
    }
    return;
  }

  if (args.first == '--help' || args.first == '-h') {
    _printUsage();
    return;
  }

  final cmd = args.first;
  final rest = args.sublist(1);
  switch (cmd) {
    case 'test':
      final proc = await Process.start(_dartExecutable, [
        'test',
        ...rest,
      ], mode: ProcessStartMode.inheritStdio);
      exit(await proc.exitCode);
    case 'serve':
      await _runServe(rest);
    case 'build':
      await _runBuild(rest);
    case 'dist':
      await _runDist(rest);
    case 'pack':
      await _runPack(rest);
    case 'doctor':
      await _runDoctor(rest);
    case 'create':
      await _runCreate(rest);
    case 'rpc':
      await _runRpc(rest);
    case 'codegen':
      await _runCodegen(rest);
    case 'gui':
      await _runGui(rest);
    case 'replay':
      await _runReplay(rest);
    default:
      log.error('Unknown command "$cmd".');
      _printUsage();
      exit(64);
  }
}

void _printUsage() {
  stdout.writeln('''
glVolition CLI (volition)

Usage:
  dart run gl_volition:volition test [test-args...]
  dart run gl_volition:volition doctor [--json]
  dart run gl_volition:volition gui [--port 8090] [--no-open]
  dart run gl_volition:volition replay <tape.json> [--json]
  dart run gl_volition:volition create <project-name> [--template 2d|3d|multiplayer] [--out <dir>]
  dart run gl_volition:volition serve <entry.dart> [--port 8080] [--root <dir>]
  dart run gl_volition:volition build <entry.dart> [--target js|wasm|windows|linux|macos|native|exe|webview|server] [--version <ver>] [--name <name>] [--out <dir>] [--dist <dir>] [--lib-dir <dir>] [--dry-run]
  dart run gl_volition:volition dist [entry.dart] [--target all|windows|linux|macos|native|exe|webview|js|wasm|server] [--version <ver>] [--name <name>] [--dist <dir>] [--lib-dir <dir>] [--dry-run]
  dart run gl_volition:volition pack [pack|obj2qmesh|cube2lut|validate] [--in <dir>] [--out <bundle.pak>] [--cook-dir <dir>] [--manifest <sidecar.json>] [--no-compress] [--xor-key <int>] [--dry-run]

Targets:
  windows|linux|macos|native|exe  Native AOT executable + runtime DLLs/SOs/Dylibs + assets/.pak
  server                          Dedicated headless multiplayer server executable (zero GPU/window)
  webview                         .NET 10 WinForms WebView2 desktop host wrapper
  js|wasm                         Web browser bundles

Outputs default to a versioned, named folder structure under ./dist:
  ./dist/<version>/<name>/<target>/
''');
}

Future<void> _runPack(List<String> args) async {
  final code = await runAssetPackerCli(
    args,
    log: stdout.writeln,
    onError: log.error,
  );
  if (code != 0) {
    exit(code);
  }
}

Future<void> _runServe(List<String> args) async {
  String? entryPath;
  var port = 8080;
  String? rootDir;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (a == '--root' && i + 1 < args.length) {
      rootDir = args[++i];
    } else if (!a.startsWith('-')) {
      entryPath ??= a;
    }
  }

  entryPath ??= 'example/pixel_rocket/main.dart';
  final entryFile = File(entryPath);
  if (!entryFile.existsSync()) {
    log.error('Entry file not found: $entryPath');
    exit(66);
  }

  final serveRoot = Directory(rootDir ?? entryFile.parent.path);
  final outDir = Directory('.dart_tool/volition_serve')
    ..createSync(recursive: true);
  final jsOut = File('${outDir.path}/main.dart.js');

  final sseClients = <HttpResponse>[];
  String? lastError;

  Future<bool> compile() async {
    final sw = Stopwatch()..start();
    final res = await Process.run(_dartExecutable, [
      'compile',
      'js',
      '-O0',
      '--no-source-maps',
      '-o',
      jsOut.path,
      entryFile.path,
    ]);
    sw.stop();
    if (res.exitCode == 0) {
      lastError = null;
      log.info('Compiled ${entryFile.path} in ${sw.elapsedMilliseconds}ms');
      _broadcastSse(sseClients, 'reload', 'ok');
      return true;
    } else {
      lastError = '${res.stdout}\n${res.stderr}'.trim();
      log.error('Compile error:\n$lastError');
      _broadcastSse(sseClients, 'compile_error', jsonEncode(lastError));
      return false;
    }
  }

  await compile();

  // Watch lib/ and entry directory with 80ms debounce
  Timer? debounce;
  var compiling = false;
  var pendingRecompile = false;

  Future<void> triggerCompile() async {
    if (compiling) {
      pendingRecompile = true;
      return;
    }
    compiling = true;
    try {
      await compile();
    } finally {
      compiling = false;
      if (pendingRecompile) {
        pendingRecompile = false;
        unawaited(triggerCompile());
      }
    }
  }

  final watchedDirs = <Directory>{
    if (Directory('lib').existsSync()) Directory('lib'),
    entryFile.parent,
  };
  for (final dir in watchedDirs) {
    dir.watch(recursive: true).listen((event) {
      if (!event.path.endsWith('.dart') && !event.path.endsWith('.html')) {
        return;
      }
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 80), triggerCompile);
    });
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  log.info('Serving ${serveRoot.path} at http://localhost:$port/');

  await for (final req in server) {
    final path = req.uri.path;
    if (path == '/__rocket_save_scene' && req.method == 'POST') {
      final body = await utf8.decoder.bind(req).join();
      final saveFile = File('${serveRoot.path}/scene.json');
      await saveFile.writeAsString(body);
      log.info('Saved scene JSON -> ${saveFile.path}');
      req.response
        ..statusCode = HttpStatus.ok
        ..write('ok');
      await req.response.close();
      continue;
    }

    if (path == '/__rocket_events') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..headers.set(HttpHeaders.connectionHeader, 'keep-alive')
        ..bufferOutput = false;
      req.response.write(': connected\n\n');
      if (lastError != null) {
        req.response.write(
          'event: compile_error\ndata: ${jsonEncode(lastError)}\n\n',
        );
      }
      sseClients.add(req.response);
      req.response.done.whenComplete(() => sseClients.remove(req.response));
      continue;
    }

    if (path == '/main.dart.js' && jsOut.existsSync()) {
      req.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/javascript; charset=utf-8',
      );
      await req.response.addStream(jsOut.openRead());
      await req.response.close();
      continue;
    }

    final rel = path == '/' ? 'index.html' : path.substring(1);
    var file = File('${serveRoot.path}/$rel');
    if (!file.existsSync() && Directory('vendor/pixeldart/web').existsSync()) {
      final fallback = File('vendor/pixeldart/web/$rel');
      if (fallback.existsSync()) file = fallback;
    }

    if (!file.existsSync()) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found: $path');
      await req.response.close();
      continue;
    }

    if (rel == 'index.html') {
      req.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/html; charset=utf-8',
      );
      final html = await file.readAsString();
      req.response.write(_injectLiveReload(html));
      await req.response.close();
      continue;
    }

    req.response.headers.set(HttpHeaders.contentTypeHeader, _mimeType(rel));
    await req.response.addStream(file.openRead());
    await req.response.close();
  }
}

void _broadcastSse(List<HttpResponse> clients, String event, String data) {
  for (final client in List.of(clients)) {
    try {
      client.write('event: $event\ndata: $data\n\n');
    } catch (_) {
      clients.remove(client);
    }
  }
}

String _injectLiveReload(String html) {
  const snippet = '''
<script>
(() => {
  const es = new EventSource('/__rocket_events');
  let banner = null;
  es.addEventListener('reload', () => location.reload());
  es.addEventListener('compile_error', (e) => {
    if (!banner) {
      banner = document.createElement('pre');
      banner.style.cssText = 'position:fixed;inset:12px;background:rgba(40,8,14,0.95);color:#ffd2d8;padding:16px;border:2px solid #ff4d6a;border-radius:8px;z-index:999999;overflow:auto;font:13px/1.4 ui-monospace,Consolas,monospace;';
      document.body.appendChild(banner);
    }
    try { banner.textContent = JSON.parse(e.data); } catch (_) { banner.textContent = e.data; }
  });
})();
</script>
''';
  if (html.contains('</body>')) {
    return html.replaceFirst('</body>', '$snippet</body>');
  }
  return '$html\n$snippet';
}

void _writeDistVersion(String version, {String distRoot = 'dist'}) {
  try {
    final dir = Directory(distRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('$distRoot/version').writeAsStringSync(version.trim());
  } catch (_) {}
}

void _writeWebLauncher(Directory destDir) {
  final launcher = File('${destDir.path}/launch_web.cmd');
  launcher.writeAsStringSync(
    '@echo off\r\nstart "" msedge --app="%~dp0index.html"\r\n',
  );
}

String _requireOptionValue(List<String> args, int index, String flag) {
  if (index + 1 >= args.length) {
    log.error('Missing value for $flag.');
    exit(64);
  }
  return args[index + 1];
}

Future<void> _runBuild(List<String> args) async {
  String? entryPath;
  var target = 'js';
  String? outPath;
  String? explicitVersion;
  String? explicitName;
  var distRoot = 'dist';
  var dryRun = false;
  var studioBundle = false;
  final libSearchDirs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-h' || a == '--help') {
      _printUsage();
      return;
    } else if (a == '--studio') {
      studioBundle = true;
    } else if (a == '--target') {
      target = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--out') {
      outPath = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--version') {
      explicitVersion = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--name') {
      explicitName = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--dist') {
      distRoot = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--lib-dir') {
      libSearchDirs.add(_requireOptionValue(args, i, a));
      i++;
    } else if (a == '--dry-run') {
      dryRun = true;
    } else if (a.startsWith('-')) {
      log.error('Unknown build option "$a".');
      exit(64);
    } else {
      entryPath ??= a;
    }
  }

  if (studioBundle) {
    await _runDistStudioBundle(
      distRoot: distRoot,
      libSearchDirs: libSearchDirs,
      dryRun: dryRun,
    );
    return;
  }

  entryPath ??= 'example/pixel_rocket/main.dart';
  final entryFile = File(entryPath);
  if (!entryFile.existsSync()) {
    log.error('Entry file not found: $entryPath');
    exit(66);
  }

  final version = NativePackager.resolveVersion(
    explicit: explicitVersion,
    distRoot: distRoot,
  );
  final name = NativePackager.resolveName(entryFile, explicit: explicitName);
  final normalizedTarget = target.trim().toLowerCase();

  final nativeTarget = NativeBuildTarget.tryParse(normalizedTarget);
  if (nativeTarget != null) {
    final packager = NativePackager(dartExecutable: _dartExecutable);
    final result = await packager.package(
      entryPath: entryFile.path,
      target: nativeTarget,
      requestedTarget: normalizedTarget,
      outputDir: outPath,
      name: name,
      version: version,
      distRoot: distRoot,
      librarySearchDirs: libSearchDirs.isEmpty ? null : libSearchDirs,
      dryRun: dryRun,
      onLog: dryRun ? null : log.info,
    );

    if (dryRun) {
      stdout.writeln(result.plan.formatDryRunReport());
      return;
    }

    if (!result.success) {
      log.error(result.errorMessage ?? 'Build failed for target "$target".');
      exit(result.exitCode != 0 ? result.exitCode : 1);
    }

    _writeDistVersion(version, distRoot: distRoot);

    final sizeText = result.binarySizeBytes != null
        ? ' (${(result.binarySizeBytes! / 1024).toStringAsFixed(1)} KB)'
        : '';
    log.info('Built ${result.plan.binaryPath}$sizeText');
    if (result.bundledLibraries.isNotEmpty) {
      log.info(
        'Bundled runtime libraries: ${result.bundledLibraries.join(', ')}',
      );
    }
    if (result.missingLibraries.isNotEmpty) {
      log.info(
        'Optional runtime libraries not bundled (install or pass --lib-dir if needed): '
        '${result.missingLibraries.join(', ')}',
      );
    }
    log.info('Launcher -> ${result.plan.launcherPath}');
    log.info('Metadata -> ${result.plan.metadataPath}');
    return;
  }

  if (normalizedTarget == 'server') {
    final serverOutDir = outPath ?? '$distRoot/$version/$name/server';
    final serverExeName = Platform.isWindows
        ? '${name}_server.exe'
        : '${name}_server';
    final serverExePath = '$serverOutDir/$serverExeName';

    if (dryRun) {
      stdout.writeln(
        'DRY RUN: compile exe ${entryFile.path} -> $serverExePath',
      );
      return;
    }

    final outDirObj = Directory(serverOutDir);
    if (!outDirObj.existsSync()) {
      outDirObj.createSync(recursive: true);
    }

    log.info(
      'Compiling dedicated headless server ($name) to $serverExePath...',
    );
    final proc = await Process.start(_dartExecutable, [
      'compile',
      'exe',
      entryFile.path,
      '-o',
      serverExePath,
    ], mode: ProcessStartMode.inheritStdio);
    final code = await proc.exitCode;
    if (code != 0) {
      log.error('Dedicated server compilation failed with exit code $code.');
      exit(code);
    }

    _writeDistVersion(version, distRoot: distRoot);
    final file = File(serverExePath);
    final sizeKb = file.existsSync()
        ? (file.lengthSync() / 1024).toStringAsFixed(1)
        : '?';
    log.info(
      'Dedicated server built successfully: $serverExePath ($sizeKb KB)',
    );
    return;
  }

  if (normalizedTarget != 'js' && normalizedTarget != 'wasm') {
    log.error(
      'Unsupported --target "$target" '
      '(expected js, wasm, windows, linux, macos, native, exe, or webview).',
    );
    exit(64);
  }

  final destPath = (outPath ?? '$distRoot/$version/$name/$normalizedTarget')
      .replaceAll(RegExp(r'[/\\]+$'), '');
  final isWasm = normalizedTarget == 'wasm';
  final outArtifact = isWasm ? '$destPath/main.wasm' : '$destPath/main.dart.js';
  final compileArgs = isWasm
      ? ['compile', 'wasm', '-O4', '-o', outArtifact, entryFile.path]
      : [
          'compile',
          'js',
          '-O4',
          '--no-source-maps',
          '-o',
          outArtifact,
          entryFile.path,
        ];

  if (dryRun) {
    final assetDirs = NativePackager.discoverStaticAssetDirectories(
      entryDir: entryFile.parent.path,
      workspaceDir: Directory.current.path,
      outputDir: destPath,
    );
    final pakFiles = NativePackager.discoverPakFiles(
      entryDir: entryFile.parent.path,
      workspaceDir: Directory.current.path,
      outputDir: destPath,
    );
    stdout.writeln('Dry-run build plan for "$name" [$normalizedTarget]');
    stdout.writeln('  Version:     $version');
    stdout.writeln('  Entry:       ${entryFile.path.replaceAll('\\', '/')}');
    stdout.writeln('  Output dir:  ${destPath.replaceAll('\\', '/')}');
    stdout.writeln('  Compile cmd: $_dartExecutable ${compileArgs.join(' ')}');
    stdout.writeln(
      '  Assets:      ${assetDirs.isEmpty ? '(none found)' : assetDirs.map((a) => a.folderName).join(', ')}',
    );
    if (pakFiles.isNotEmpty) {
      stdout.writeln(
        '  Pak files:   ${pakFiles.map((p) => p.fileName).join(', ')}',
      );
    }
    stdout.writeln('  Launcher:    $destPath/launch_web.cmd');
    stdout.writeln('  Metadata:    $destPath/metadata.json');
    return;
  }

  final destDir = Directory(destPath)..createSync(recursive: true);
  _writeDistVersion(version, distRoot: distRoot);

  log.info('Building "$name" [$normalizedTarget] into: ${destDir.path}');
  _copyWebStaticAssets(entryFile.parent, destDir);

  final res = await Process.run(_dartExecutable, compileArgs);
  if (res.exitCode != 0) {
    stderr.writeln(res.stdout);
    stderr.writeln(res.stderr);
    exit(res.exitCode);
  }
  if (isWasm) {
    log.info('Built $outArtifact');
  } else {
    final sizeKb = (File(outArtifact).lengthSync() / 1024).toStringAsFixed(1);
    log.info('Built $outArtifact ($sizeKb KB)');
  }
  _writeWebLauncher(destDir);

  NativePackager.writeBuildMetadata(
    destDir,
    name: name,
    version: version,
    target: normalizedTarget,
    entryPath: entryFile.path,
    binaryFileName: isWasm ? 'main.wasm' : 'main.dart.js',
    nativeAot: false,
    bundledLibraries: const [],
  );
}

Future<void> _runDist(List<String> args) async {
  String? entryPath;
  var target = 'all';
  String? explicitVersion;
  String? explicitName;
  var distRoot = 'dist';
  var dryRun = false;
  var studioBundle = false;
  final libSearchDirs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-h' || a == '--help') {
      _printUsage();
      return;
    } else if (a == '--studio') {
      studioBundle = true;
    } else if (a == '--target') {
      target = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--version') {
      explicitVersion = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--name') {
      explicitName = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--dist') {
      distRoot = _requireOptionValue(args, i, a);
      i++;
    } else if (a == '--lib-dir') {
      libSearchDirs.add(_requireOptionValue(args, i, a));
      i++;
    } else if (a == '--dry-run') {
      dryRun = true;
    } else if (a.startsWith('-')) {
      log.error('Unknown dist option "$a".');
      exit(64);
    } else {
      entryPath ??= a;
    }
  }

  if (studioBundle) {
    await _runDistStudioBundle(
      distRoot: distRoot,
      libSearchDirs: libSearchDirs,
      dryRun: dryRun,
    );
    return;
  }

  entryPath ??= 'example/pixel_rocket/main.dart';
  final entryFile = File(entryPath);
  if (!entryFile.existsSync()) {
    log.error('Entry file not found: $entryPath');
    exit(66);
  }

  final version = NativePackager.resolveVersion(
    explicit: explicitVersion,
    distRoot: distRoot,
  );
  final name = NativePackager.resolveName(entryFile, explicit: explicitName);
  final targetsToBuild = target == 'all'
      ? const ['windows', 'js', 'wasm']
      : [target];

  final ext = Platform.isWindows ? '.exe' : '';
  final volitionExe = '$distRoot/$version/bin/volition$ext';

  if (dryRun) {
    stdout.writeln(
      'Dry-run distribution plan for "$name" (version: $version, targets: ${targetsToBuild.join(', ')})',
    );
    stdout.writeln(
      '  CLI compile: $_dartExecutable compile exe -o $volitionExe bin/volition.dart',
    );
    for (final t in targetsToBuild) {
      stdout.writeln('');
      await _runBuild([
        entryFile.path,
        '--target',
        t,
        '--version',
        version,
        '--name',
        name,
        '--dist',
        distRoot,
        for (final dir in libSearchDirs) ...['--lib-dir', dir],
        '--dry-run',
      ]);
    }
    return;
  }

  _writeDistVersion(version, distRoot: distRoot);
  log.info(
    'Packaging distribution for "$name" (version: $version, target: $target)...',
  );

  final versionDir = Directory('$distRoot/$version')
    ..createSync(recursive: true);
  Directory('${versionDir.path}/bin').createSync(recursive: true);

  // 1. Build CLI native executable
  log.info('Compiling CLI executable -> $volitionExe');
  final compileCli = await Process.run(_dartExecutable, [
    'compile',
    'exe',
    '-o',
    volitionExe,
    'bin/volition.dart',
  ]);
  if (compileCli.exitCode == 0) {
    log.info('Compiled CLI executable ($volitionExe)');
  } else {
    log.warn('Could not compile native CLI executable');
  }

  // 2. Build game targets
  for (final t in targetsToBuild) {
    log.info('Building target [$t] for "$name"...');
    await _runBuild([
      entryFile.path,
      '--target',
      t,
      '--version',
      version,
      '--name',
      name,
      '--dist',
      distRoot,
      for (final dir in libSearchDirs) ...['--lib-dir', dir],
    ]);
  }

  // 3. Write top-level metadata.json in dist/<version>/metadata.json
  final meta = {
    'name': name,
    'version': version,
    'targets': targetsToBuild,
    'entry': entryFile.path.replaceAll('\\', '/'),
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'commit': NativePackager.resolveGitCommit(),
  };
  File(
    '${versionDir.path}/metadata.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));

  log.info('Distribution packaging complete: ${versionDir.path}/');
}

void _copyWebStaticAssets(Directory sourceDir, Directory destDir) {
  final indexFile = File('${sourceDir.path}/index.html');
  if (indexFile.existsSync()) {
    indexFile.copySync('${destDir.path}/index.html');
  }
  final assetDirs = NativePackager.discoverStaticAssetDirectories(
    entryDir: sourceDir.path,
    workspaceDir: Directory.current.path,
    outputDir: destDir.path,
  );
  for (final asset in assetDirs) {
    NativePackager.copyDirectory(
      Directory(asset.sourcePath),
      Directory(asset.destinationPath),
    );
  }
  final paks = NativePackager.discoverPakFiles(
    entryDir: sourceDir.path,
    workspaceDir: Directory.current.path,
    outputDir: destDir.path,
  );
  for (final pak in paks) {
    File(pak.sourcePath).copySync(pak.destinationPath);
  }
}

String _mimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
    return 'application/javascript; charset=utf-8';
  }
  if (lower.endsWith('.wasm')) return 'application/wasm';
  if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
  if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
  if (lower.endsWith('.glb')) return 'model/gltf-binary';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  return 'application/octet-stream';
}

Future<void> _runDoctor(List<String> args) async {
  final asJson = args.contains('--json');
  final service = VolitionCliService();
  try {
    final report = await service.runDoctor();
    if (asJson) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
      return;
    }

    stdout.writeln('glVolition Doctor — Environment & Toolchain Diagnostics\n');
    for (final c in report.checks) {
      final icon = c.status == DoctorStatus.ok ? '✓' : '!';
      stdout.writeln('[$icon] ${c.name}: ${c.detail}');
    }
    stdout.writeln('\nDoctor inspection completed.');
  } finally {
    await service.dispose();
  }
}

Future<void> _runCreate(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stdout.writeln(
      'Usage: volition create <project-name> [--template 2d|3d|multiplayer] [--out <dir>]',
    );
    return;
  }

  final projectName = args.first;
  var template = '3d';
  String? outDir;

  for (var i = 1; i < args.length; i++) {
    final a = args[i];
    if (a == '--template' && i + 1 < args.length) {
      template = args[++i].toLowerCase();
    } else if (a == '--out' && i + 1 < args.length) {
      outDir = args[++i];
    }
  }

  final targetDir = Directory(outDir ?? projectName);
  if (targetDir.existsSync()) {
    stdout.writeln('Error: Directory ${targetDir.path} already exists.');
    exit(1);
  }
  targetDir.createSync(recursive: true);

  final pubspecContent =
      '''
name: $projectName
description: A new glVolition game.
version: 0.1.0
publish_to: none

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  gl_volition:
    path: ${Directory.current.path.replaceAll('\\', '/')}
''';
  File('${targetDir.path}/pubspec.yaml').writeAsStringSync(pubspecContent);

  final libDir = Directory('${targetDir.path}/lib')..createSync();
  final binDir = Directory('${targetDir.path}/bin')..createSync();

  String mainContent;
  switch (template) {
    case '2d':
      mainContent = '''
import 'package:gl_volition/gl_volition.dart';

void main() {
  final engine = Engine(HeadlessHost());
  final player = engine.scene.createGameObject('Player', position: Vec3.zero);
  player.addComponent(RigidBody2D());
  player.addComponent(BoxCollider2D(size: const Vec2(1.0, 1.0)));
  print('glVolition 2D Game initialized.');
}
''';
    case 'multiplayer':
      mainContent = '''
import 'package:gl_volition/gl_volition.dart';

void main() async {
  final engine = Engine(HeadlessHost());
  engine.scene.network.startServer();
  print('glVolition Multiplayer Server initialized.');
}
''';
    case '3d':
    default:
      mainContent = '''
import 'package:gl_volition/gl_volition.dart';

void main() {
  final engine = Engine(HeadlessHost());
  engine.scene.createGameObject('Cube', position: const Vec3(0, 1, 0));
  engine.scene.createGameObject('Light').addComponent(Light.directional());
  print('glVolition 3D Game initialized.');
}
''';
  }

  File('${libDir.path}/main.dart').writeAsStringSync(mainContent);
  File('${binDir.path}/server.dart').writeAsStringSync('''
import 'package:gl_volition/gl_volition_native.dart';

void main(List<String> args) async {
  final server = DedicatedServerHost(port: 7777);
  await server.start();
}
''');
  File('${targetDir.path}/index.html').writeAsStringSync('''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>$projectName</title>
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #0d1117; }
    canvas#game-canvas { display: block; width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <canvas id="game-canvas"></canvas>
  <script defer src="main.dart.js"></script>
</body>
</html>
''');

  stdout.writeln(
    'Created new glVolition project "$projectName" (template: $template) in ${targetDir.path}',
  );
  stdout.writeln('Next steps:');
  stdout.writeln('  cd ${targetDir.path}');
  stdout.writeln('  dart pub get');
  stdout.writeln('  dart run bin/server.dart');
}

Future<void> _runGui(List<String> args) async {
  var port = 8090;
  var openBrowser = true;
  var nativeMode = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (a == '--no-open') {
      openBrowser = false;
    } else if (a == '--native' || a == '--app') {
      nativeMode = true;
    } else if (a == '--web') {
      nativeMode = false;
    } else if (a == '--help' || a == '-h') {
      stdout.writeln(
        'Usage: dart run gl_volition:volition gui [--native|--web] [--port 8090] [--no-open]',
      );
      return;
    }
  }

  if (nativeMode) {
    log.info(
      'Starting glVolition Studio in native AOT mode (checking SDL3/ANGLE capabilities)...',
    );
    final engine = Engine(HeadlessHost());
    final scene = Scene('VolitionStudio');
    scene.createGameObject('MainCamera').addComponent(Camera());
    scene.createGameObject('Sun').addComponent(Light.directional());
    engine.loadScene(scene);
    final bridge = SessionEditorHostBridge(EditorSession(engine));
    final shell = StudioWorkspaceShell(bridge: bridge);
    final res = await Sdl3StudioRunner.tryLaunchHardware(shell: shell);
    if (res.launched) {
      log.info(
        'Native AOT Studio closed after ${res.framesRendered} frame(s).',
      );
      return;
    }
    log.warn(
      res.diagnostic ??
          'Native SDL3 Studio unavailable; falling back to local browser Studio.',
    );
  }

  final service = VolitionCliService();
  final server = VolitionGuiServer(service: service);
  final url = await server.start(port: port);

  log.info('glVolition Studio GUI listening at $url');
  stdout.writeln('Press Ctrl+C to stop glVolition Studio.');

  if (openBrowser) {
    final browser = await service.findBrowserExecutable();
    if (browser != null) {
      await Process.start(browser, [
        '--app=$url',
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        url.toString(),
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [
        url.toString(),
      ], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [
        url.toString(),
      ], mode: ProcessStartMode.detached);
    }
  }

  await ProcessSignal.sigint.watch().first;
  log.info('Shutting down glVolition Studio...');
  await server.stop();
}

Future<void> _runReplay(List<String> args) async {
  var asJson = false;
  String? tapePath;
  for (final a in args) {
    if (a == '--help' || a == '-h') {
      stdout.writeln(
        'Usage: dart run gl_volition:volition replay <tape.json> [--json]',
      );
      return;
    } else if (a == '--json') {
      asJson = true;
    } else if (!a.startsWith('-')) {
      tapePath ??= a;
    }
  }
  if (tapePath == null || tapePath.isEmpty) {
    stderr.writeln('Usage: volition replay <tape.json> [--json]');
    exit(64);
  }

  final service = VolitionCliService();
  try {
    final result = service.verifyInputTapeFile(tapePath);
    final passed = result['passed'] == true;
    if (asJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    } else {
      stdout.writeln(
        '[${passed ? 'PASS' : 'FAIL'}] Replay "${result['tapeName']}" '
        '(${result['framesExecuted']} frames, ${result['checkpointCount']} checkpoints, '
        'hash=${result['finalSceneHash']})',
      );
      final mismatches = (result['mismatches'] as List<Object?>?) ?? const [];
      for (final m in mismatches) {
        stderr.writeln('  MISMATCH: $m');
      }
    }
    if (!passed) {
      exit(1);
    }
  } finally {
    await service.dispose();
  }
}

Future<void> _runRpc(List<String> args) async {
  var asJson = false;
  var listMethods = false;
  String? method;
  var params = <String, Object?>{};

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--help' || a == '-h') {
      stdout.writeln(
        'Usage: dart run gl_volition:volition rpc <method> [--params <json>] [--json]\n'
        '       dart run gl_volition:volition rpc --list [--json]',
      );
      return;
    } else if (a == '--json') {
      asJson = true;
    } else if (a == '--list') {
      listMethods = true;
    } else if (a == '--params' && i + 1 < args.length) {
      final raw = jsonDecode(args[++i]);
      if (raw is Map<String, Object?>) {
        params = raw;
      } else if (raw is Map) {
        params = raw.map((k, v) => MapEntry('$k', v));
      } else {
        stderr.writeln('--params must be a JSON object.');
        exit(64);
      }
    } else if (!a.startsWith('-')) {
      method ??= a;
    }
  }

  if (listMethods) {
    final registry = StudioMethodRegistry();
    final rows = [
      for (final m in registry.all)
        {'method': m.method, 'cliCommand': m.cliCommand, 'summary': m.summary},
    ];
    if (asJson) {
      stdout.writeln(jsonEncode({'methods': rows}));
    } else {
      for (final r in rows) {
        stdout.writeln('${r['method']} -> ${r['cliCommand']}');
      }
    }
    return;
  }

  if (method == null || method.isEmpty) {
    stderr.writeln('Usage: volition rpc <method> [--params <json>] [--json]');
    exit(64);
  }

  final daemon = StudioDaemon();
  try {
    final res = await daemon.dispatch(
      StudioRequest(id: 'cli', method: method, params: params),
    );
    if (asJson) {
      stdout.writeln(jsonEncode(res.toJson()));
    } else if (res.ok) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(res.result));
    } else {
      stderr.writeln(
        'RPC error (${res.error?.code.name}): ${res.error?.message}',
      );
    }
    if (!res.ok) {
      exit(1);
    }
  } finally {
    await daemon.cliService.dispose();
  }
}

Future<void> _runCodegen(List<String> args) async {
  var targetDir = 'lib';
  var checkOnly = false;
  for (final a in args) {
    if (a == '--help' || a == '-h') {
      stdout.writeln(
        'Usage: dart run gl_volition:volition codegen [dir] [--check]',
      );
      return;
    } else if (a == '--check') {
      checkOnly = true;
    } else if (!a.startsWith('-')) {
      targetDir = a;
    }
  }
  final dir = Directory(targetDir);
  if (!dir.existsSync()) {
    stderr.writeln('Directory not found: $targetDir');
    exit(64);
  }
  var generatedFiles = 0;
  var totalErrors = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File ||
        !entity.path.endsWith('.dart') ||
        entity.path.endsWith('.spec.g.dart')) {
      continue;
    }
    final src = entity.readAsStringSync();
    if (!src.contains('@Serialized') && !src.contains('@serialized')) {
      continue;
    }
    final res = SpecCodeGenerator.generateForSource(src, filePath: entity.path);
    for (final d in res.diagnostics) {
      stderr.writeln(d);
      totalErrors++;
    }
    if (res.classCount > 0 && !res.hasErrors) {
      final outPath =
          '${entity.path.substring(0, entity.path.length - 5)}.spec.g.dart';
      if (!checkOnly) {
        File(outPath).writeAsStringSync(res.generatedCode);
      }
      generatedFiles++;
    }
  }
  stdout.writeln(
    'volition codegen: processed $generatedFiles spec file(s), $totalErrors diagnostic(s).',
  );
  if (totalErrors > 0) exit(1);
}

Future<void> _runDistStudioBundle({
  required String distRoot,
  required List<String> libSearchDirs,
  required bool dryRun,
}) async {
  final outDir = Directory('$distRoot/studio');
  final exeName = Platform.isWindows
      ? 'volition_studio.exe'
      : 'volition_studio';
  final exePath = '${outDir.path}/$exeName';
  final runtimeLibs = Platform.isWindows
      ? const ['SDL3.dll', 'libEGL.dll', 'libGLESv2.dll']
      : Platform.isMacOS
      ? const ['libSDL3.dylib', 'libEGL.dylib', 'libGLESv2.dylib']
      : const ['libSDL3.so.0', 'libEGL.so.1', 'libGLESv2.so.2'];

  final searchDirs = <String>[
    ...libSearchDirs,
    Directory.current.path,
    '${Directory.current.path}/native_libs',
  ];
  final foundLibs = <String, String>{};
  final missingLibs = <String>[];

  for (final lib in runtimeLibs) {
    String? matched;
    for (final dir in searchDirs) {
      final candidate = File('$dir/$lib');
      if (candidate.existsSync()) {
        matched = candidate.path;
        break;
      }
    }
    if (matched != null) {
      foundLibs[lib] = matched;
    } else {
      missingLibs.add(lib);
    }
  }

  final manifest = <String, Object?>{
    'bundle': 'volition_studio_aot',
    'platform': Platform.operatingSystem,
    'executable': exePath,
    'dryRun': dryRun,
    'foundRuntimeLibraries': foundLibs,
    'missingRuntimeLibraries': missingLibs,
  };

  if (dryRun) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
    return;
  }

  outDir.createSync(recursive: true);
  log.info('Compiling portable AOT Volition Studio -> $exePath ...');
  final res = await Process.run(_dartExecutable, [
    'compile',
    'exe',
    'bin/volition.dart',
    '-o',
    exePath,
  ]);
  if (res.exitCode != 0) {
    stderr.write(res.stderr);
    exit(res.exitCode);
  }
  for (final entry in foundLibs.entries) {
    File(entry.value).copySync('${outDir.path}/${entry.key}');
  }
  File(
    '${outDir.path}/studio_bundle_manifest.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  log.info('Portable AOT Studio bundle written to ${outDir.path}');
  if (missingLibs.isNotEmpty) {
    log.warn(
      'Optional native runtime libraries not found in search dirs: '
      '${missingLibs.join(', ')}. Place them beside $exeName or pass --lib-dir <path>.',
    );
  }
}
