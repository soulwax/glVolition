import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:voxlog/voxlog.dart';

final log = voxlog.stdoutColor('volition', level: LogLevel.info);

String get _dartExecutable {
  // If running inside a compiled standalone exe (e.g. volition.exe),
  // Platform.resolvedExecutable points to volition.exe itself, NOT the Dart SDK.
  // Resolve 'dart' or 'dart.exe' on PATH instead.
  final current = Platform.resolvedExecutable;
  if (current.toLowerCase().endsWith('dart') || current.toLowerCase().endsWith('dart.exe')) {
    return current;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    if (Platform.isWindows && stdout.hasTerminal) {
      stdout.writeln('--------------------------------------------------');
      stdout.writeln('Interactive Launcher (Console):');
      stdout.writeln('  [1] serve  - Start live dev server with hot reload (pixel_rocket)');
      stdout.writeln('  [2] build  - Build game into ./dist/<version>/<name>/<target>/');
      stdout.writeln('  [3] dist   - Package complete distribution (CLI + Game targets)');
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
        await _runBuild(['example/pixel_rocket/main.dart', '--target', 'windows']);
        stdout.writeln('\nBuild completed. Press Enter to exit.');
        stdin.readLineSync();
      } else if (input == '3') {
        await _runDist(['example/pixel_rocket/main.dart']);
        stdout.writeln('\nDistribution packaging completed. Press Enter to exit.');
        stdin.readLineSync();
      } else if (input == '4') {
        final proc = await Process.start(
          _dartExecutable,
          ['test'],
          mode: ProcessStartMode.inheritStdio,
        );
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
      final proc = await Process.start(
        _dartExecutable,
        ['test', ...rest],
        mode: ProcessStartMode.inheritStdio,
      );
      exit(await proc.exitCode);
    case 'serve':
      await _runServe(rest);
    case 'build':
      await _runBuild(rest);
    case 'dist':
      await _runDist(rest);
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
  dart run gl_volition:volition build <entry.dart> [--target js|wasm|windows|native] [--version <ver>] [--name <name>] [--out <dir>]
  dart run gl_volition:volition dist [entry.dart] [--target all|windows|js|wasm] [--version <ver>] [--name <name>] [--dist <dir>]

Outputs default to a versioned, named folder structure under ./dist:
  ./dist/<version>/<name>/<target>/
''');
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
  final outDir = Directory('.dart_tool/volition_serve')..createSync(recursive: true);
  final jsOut = File('${outDir.path}/main.dart.js');

  final sseClients = <HttpResponse>[];
  String? lastError;

  Future<bool> compile() async {
    final sw = Stopwatch()..start();
    final res = await Process.run(Platform.resolvedExecutable, [
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
      if (!event.path.endsWith('.dart') && !event.path.endsWith('.html')) return;
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
        req.response.write('event: compile_error\ndata: ${jsonEncode(lastError)}\n\n');
      }
      sseClients.add(req.response);
      req.response.done.whenComplete(() => sseClients.remove(req.response));
      continue;
    }

    if (path == '/main.dart.js' && jsOut.existsSync()) {
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'application/javascript; charset=utf-8');
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
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
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

String _resolveVersion({String? explicit}) {
  if (explicit != null && explicit.trim().isNotEmpty) {
    return explicit.trim();
  }
  final distVerFile = File('dist/version');
  if (distVerFile.existsSync()) {
    final v = distVerFile.readAsStringSync().trim();
    if (v.isNotEmpty) return v;
  }
  final pubspecFile = File('pubspec.yaml');
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

void _writeDistVersion(String version, {String distRoot = 'dist'}) {
  try {
    final dir = Directory(distRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('$distRoot/version').writeAsStringSync(version.trim());
  } catch (_) {}
}

String _resolveName(File entryFile, {String? explicit}) {
  if (explicit != null && explicit.trim().isNotEmpty) {
    return explicit.trim();
  }
  final normalized = entryFile.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  final exampleIdx = parts.indexOf('example');
  if (exampleIdx != -1 && exampleIdx + 1 < parts.length) {
    final seg = parts[exampleIdx + 1];
    if (seg != 'main.dart' && !seg.endsWith('.dart')) {
      return seg;
    }
  }
  final parent = entryFile.parent.path.replaceAll('\\', '/').split('/').last;
  if (parent.isNotEmpty && parent != '.' && parent != 'lib' && parent != 'bin') {
    return parent;
  }
  final fileName = parts.isEmpty ? 'game' : parts.last;
  return fileName.endsWith('.dart') ? fileName.substring(0, fileName.length - 5) : fileName;
}

String _resolveGitCommit() {
  try {
    final res = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (res.exitCode == 0) {
      final out = (res.stdout as String).trim();
      if (out.isNotEmpty) return out;
    }
  } catch (_) {}
  return 'unknown';
}

void _writeWebLauncher(Directory destDir) {
  final launcher = File('${destDir.path}/launch_web.cmd');
  launcher.writeAsStringSync(
    '@echo off\r\nstart "" msedge --app="%~dp0index.html"\r\n',
  );
}

void _writeNativeLauncher(Directory destDir, {required String name}) {
  final launcher = File('${destDir.path}/Launch_$name.cmd');
  launcher.writeAsStringSync('''@echo off
setlocal
cd /d "%~dp0"
if exist "$name.exe" (
    start "" "%~dp0$name.exe"
    exit /b 0
)
if exist "game.exe" (
    start "" "%~dp0game.exe"
    exit /b 0
)
echo [ERROR] No runnable binary found.
pause
''');
}

void _writeBuildMetadata(
  Directory destDir, {
  required String name,
  required String version,
  required String target,
  required File entryFile,
}) {
  final meta = {
    'name': name,
    'version': version,
    'target': target,
    'entry': entryFile.path.replaceAll('\\', '/'),
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'commit': _resolveGitCommit(),
  };
  File('${destDir.path}/metadata.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(meta),
  );
}

Future<void> _runBuild(List<String> args) async {
  String? entryPath;
  var target = 'js';
  String? outPath;
  String? explicitVersion;
  String? explicitName;
  String distRoot = 'dist';

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else if (a == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    } else if (a == '--version' && i + 1 < args.length) {
      explicitVersion = args[++i];
    } else if (a == '--name' && i + 1 < args.length) {
      explicitName = args[++i];
    } else if (a == '--dist' && i + 1 < args.length) {
      distRoot = args[++i];
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

  final version = _resolveVersion(explicit: explicitVersion);
  final name = _resolveName(entryFile, explicit: explicitName);

  // Default output directory lands in a versioned, named organized folder structure under ./dist
  final targetSubdir = (target == 'native' || target == 'exe') ? 'native' : target;
  final defaultOutDir = '$distRoot/$version/$name/$targetSubdir';
  final destDir = Directory(outPath ?? defaultOutDir)..createSync(recursive: true);

  // Keep dist/version synchronized with active build version
  _writeDistVersion(version, distRoot: distRoot);

  log.info('Building "$name" [$target] into: ${destDir.path}');
  _copyStaticAssets(entryFile.parent, destDir);

  switch (target) {
    case 'js':
      final outJs = '${destDir.path}/main.dart.js';
      log.info('Building JS bundle -> $outJs');
      final res = await Process.run(_dartExecutable, [
        'compile',
        'js',
        '-O4',
        '--no-source-maps',
        '-o',
        outJs,
        entryFile.path,
      ]);
      if (res.exitCode != 0) {
        stderr.writeln(res.stdout);
        stderr.writeln(res.stderr);
        exit(res.exitCode);
      }
      final sizeKb = (File(outJs).lengthSync() / 1024).toStringAsFixed(1);
      log.info('Built $outJs ($sizeKb KB)');
      _writeWebLauncher(destDir);

    case 'wasm':
      final outWasm = '${destDir.path}/main.wasm';
      log.info('Building WebAssembly bundle -> $outWasm');
      final res = await Process.run(_dartExecutable, [
        'compile',
        'wasm',
        '-O4',
        '-o',
        outWasm,
        entryFile.path,
      ]);
      if (res.exitCode != 0) {
        stderr.writeln(res.stdout);
        stderr.writeln(res.stderr);
        exit(res.exitCode);
      }
      log.info('Built $outWasm');
      _writeWebLauncher(destDir);

    case 'windows':
      await _buildWindowsExecutable(entryFile, destDir, name: name);

    case 'exe':
    case 'native':
      final ext = Platform.isWindows ? '.exe' : '';
      final outExe = '${destDir.path}/$name$ext';
      log.info('Building native AOT executable -> $outExe');
      final res = await Process.run(_dartExecutable, [
        'compile',
        'exe',
        '-o',
        outExe,
        entryFile.path,
      ]);
      if (res.exitCode != 0) {
        stderr.writeln(res.stdout);
        stderr.writeln(res.stderr);
        exit(res.exitCode);
      }
      final sizeKb = (File(outExe).lengthSync() / 1024).toStringAsFixed(1);
      log.info('Built $outExe ($sizeKb KB)');
      _writeNativeLauncher(destDir, name: name);

    default:
      log.error(
        'Unsupported --target "$target" (expected js, wasm, windows, or exe).',
      );
      exit(64);
  }

  _writeBuildMetadata(
    destDir,
    name: name,
    version: version,
    target: target,
    entryFile: entryFile,
  );
}

Future<void> _runDist(List<String> args) async {
  String? entryPath;
  var target = 'all';
  String? explicitVersion;
  String? explicitName;
  String distRoot = 'dist';

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else if (a == '--version' && i + 1 < args.length) {
      explicitVersion = args[++i];
    } else if (a == '--name' && i + 1 < args.length) {
      explicitName = args[++i];
    } else if (a == '--dist' && i + 1 < args.length) {
      distRoot = args[++i];
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

  final version = _resolveVersion(explicit: explicitVersion);
  _writeDistVersion(version, distRoot: distRoot);
  final name = _resolveName(entryFile, explicit: explicitName);

  log.info('Packaging distribution for "$name" (version: $version, target: $target)...');

  final versionDir = Directory('$distRoot/$version')..createSync(recursive: true);
  final binDir = Directory('${versionDir.path}/bin')..createSync(recursive: true);

  // 1. Build CLI native executable
  final ext = Platform.isWindows ? '.exe' : '';
  final volitionExe = '${binDir.path}/volition$ext';
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
  final targetsToBuild = target == 'all'
      ? ['windows', 'js', 'wasm']
      : [target];

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
    ]);
  }

  // 3. Write top-level metadata.json in dist/<version>/metadata.json
  final meta = {
    'name': name,
    'version': version,
    'targets': targetsToBuild,
    'entry': entryFile.path.replaceAll('\\', '/'),
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'commit': _resolveGitCommit(),
  };
  File('${versionDir.path}/metadata.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));

  log.info('Distribution packaging complete: ${versionDir.path}/');
}

void _copyStaticAssets(Directory sourceDir, Directory destDir) {
  final indexFile = File('${sourceDir.path}/index.html');
  if (indexFile.existsSync()) {
    indexFile.copySync('${destDir.path}/index.html');
  }
  for (final folder in const ['models', 'audio', 'assets', 'res']) {
    final candidates = [
      Directory('${sourceDir.path}/$folder'),
      Directory('vendor/pixeldart/web/$folder'),
      Directory('vendor/pixeldart/examples/example_1/$folder'),
    ];
    for (final src in candidates) {
      if (src.existsSync()) {
        _copyDirectory(src, Directory('${destDir.path}/$folder'));
        break;
      }
    }
  }
}

Future<void> _buildWindowsExecutable(
  File entryFile,
  Directory destDir, {
  String name = 'game',
}) async {
  final buildSubdir = Directory('${destDir.path}/build')..createSync(recursive: true);
  final outJs = '${destDir.path}/main.dart.js';
  final outBuildJs = '${buildSubdir.path}/main.dart.js';
  log.info('Compiling JS bundle for Windows desktop host...');
  final res = await Process.run(_dartExecutable, [
    'compile',
    'js',
    '-O4',
    '--no-source-maps',
    '-o',
    outJs,
    entryFile.path,
  ]);
  if (res.exitCode != 0) {
    stderr.writeln(res.stdout);
    stderr.writeln(res.stderr);
    exit(res.exitCode);
  }
  File(outJs).copySync(outBuildJs);

  final launcherScript = '''@echo off
setlocal
cd /d "%~dp0"
if exist "$name.exe" (
    start "" "%~dp0$name.exe"
    exit /b 0
)
if exist "GlVolitionGame.exe" (
    start "" "%~dp0GlVolitionGame.exe"
    exit /b 0
)
if exist "index.html" (
    start "" msedge --app="%~dp0index.html"
    exit /b 0
)
echo [ERROR] No runnable game binary found.
pause
''';

  File('${destDir.path}/Launch_$name.cmd').writeAsStringSync(launcherScript);
  File('${destDir.path}/launch_desktop.cmd').writeAsStringSync(launcherScript);

  final hostCs = File('vendor/pixeldart/examples/desktop_host/Program.cs');
  if (!hostCs.existsSync()) {
    log.info('Packaged Windows web bundle in ${destDir.path}');
    return;
  }

  final desktopDir = Directory('${destDir.path}/desktop')..createSync(recursive: true);
  final csproj = File('${desktopDir.path}/GlVolitionGame.csproj');
  final hostAbs = hostCs.absolute.path;
  csproj.writeAsStringSync('''
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
    <Compile Include="$hostAbs" Link="Program.cs" />
    <EmbeddedResource Include="..\\index.html" LogicalName="game/index.html" />
    <EmbeddedResource Include="..\\main.dart.js" LogicalName="game/main.dart.js" />
    <EmbeddedResource Include="..\\build\\main.dart.js" LogicalName="game/build/main.dart.js" />
    <EmbeddedResource Include="..\\res\\**\\*" LogicalName="game/res/%(RecursiveDir)%(Filename)%(Extension)" Condition="Exists('..\\res')" />
  </ItemGroup>
</Project>
''');

  try {
    final pubDir = '${desktopDir.path}/publish';
    final pubRes = await Process.run('dotnet', [
      'publish',
      csproj.path,
      '-c',
      'Release',
      '-o',
      pubDir,
    ]);
    if (pubRes.exitCode == 0) {
      final builtExe = File('$pubDir/GlVolitionGame.exe');
      final finalExe = File('${destDir.path}/GlVolitionGame.exe');
      final namedExe = File('${destDir.path}/$name.exe');
      if (builtExe.existsSync()) {
        builtExe.copySync(finalExe.path);
        if (name != 'GlVolitionGame') {
          builtExe.copySync(namedExe.path);
        }
        log.info('Built single-file Windows executable -> ${finalExe.path}');
        return;
      }
    }
  } catch (_) {}

  log.info('Packaged Windows desktop project in ${destDir.path}');
}

void _copyDirectory(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync(recursive: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is File) {
      entity.copySync('${dst.path}/$name');
    } else if (entity is Directory) {
      _copyDirectory(entity, Directory('${dst.path}/$name'));
    }
  }
}

String _mimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'application/javascript; charset=utf-8';
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
