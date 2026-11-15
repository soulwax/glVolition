import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:voxlog/voxlog.dart';

import '../tool/asset_packer.dart';
import '../tool/package_native.dart';

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
  dart run gl_volition:volition serve <entry.dart> [--port 8080] [--root <dir>]
  dart run gl_volition:volition build <entry.dart> [--target js|wasm|windows|linux|macos|native|exe|webview] [--version <ver>] [--name <name>] [--out <dir>] [--dist <dir>] [--lib-dir <dir>] [--dry-run]
  dart run gl_volition:volition dist [entry.dart] [--target all|windows|linux|macos|native|exe|webview|js|wasm] [--version <ver>] [--name <name>] [--dist <dir>] [--lib-dir <dir>] [--dry-run]
  dart run gl_volition:volition pack [pack|obj2qmesh|cube2lut|validate] [--in <dir>] [--out <bundle.pak>] [--cook-dir <dir>] [--manifest <sidecar.json>] [--no-compress] [--xor-key <int>] [--dry-run]

Targets:
  windows|linux|macos|native|exe  Native AOT executable + runtime DLLs/SOs/Dylibs + assets/.pak
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
  final libSearchDirs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-h' || a == '--help') {
      _printUsage();
      return;
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
  final libSearchDirs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-h' || a == '--help') {
      _printUsage();
      return;
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
