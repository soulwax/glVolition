import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printUsage();
    return;
  }

  final cmd = args.first;
  final rest = args.sublist(1);
  switch (cmd) {
    case 'test':
      final proc = await Process.start(
        Platform.resolvedExecutable,
        ['test', ...rest],
        mode: ProcessStartMode.inheritStdio,
      );
      exit(await proc.exitCode);
    case 'serve':
      await _runServe(rest);
    case 'build':
      await _runBuild(rest);
    default:
      stderr.writeln('Unknown command "$cmd".');
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
  dart run gl_volition:volition build <entry.dart> [--target js|wasm|windows] [--out <dir>]
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
    stderr.writeln('Entry file not found: $entryPath');
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
      stdout.writeln('[volition] Compiled ${entryFile.path} in ${sw.elapsedMilliseconds}ms');
      _broadcastSse(sseClients, 'reload', 'ok');
      return true;
    } else {
      lastError = '${res.stdout}\n${res.stderr}'.trim();
      stderr.writeln('[volition] Compile error:\n$lastError');
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
  stdout.writeln('[volition] Serving ${serveRoot.path} at http://localhost:$port/');

  await for (final req in server) {
    final path = req.uri.path;
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
    if (!file.existsSync() && Directory('pixeldart/web').existsSync()) {
      final fallback = File('pixeldart/web/$rel');
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

Future<void> _runBuild(List<String> args) async {
  String? entryPath;
  var target = 'js';
  String? outPath;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else if (a == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    } else if (!a.startsWith('-')) {
      entryPath ??= a;
    }
  }

  entryPath ??= 'example/pixel_rocket/main.dart';
  final entryFile = File(entryPath);
  if (!entryFile.existsSync()) {
    stderr.writeln('Entry file not found: $entryPath');
    exit(66);
  }

  final destDir = Directory(outPath ?? 'build/$target')..createSync(recursive: true);
  _copyStaticAssets(entryFile.parent, destDir);

  switch (target) {
    case 'js':
      final outJs = '${destDir.path}/main.dart.js';
      stdout.writeln('[volition] Building JS bundle -> $outJs');
      final res = await Process.run(Platform.resolvedExecutable, [
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
      stdout.writeln('[volition] Built $outJs ($sizeKb KB)');
    case 'wasm':
      final outWasm = '${destDir.path}/main.wasm';
      stdout.writeln('[volition] Building WebAssembly bundle -> $outWasm');
      final res = await Process.run(Platform.resolvedExecutable, [
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
      stdout.writeln('[volition] Built $outWasm');
    case 'windows':
      final outJs = '${destDir.path}/main.dart.js';
      stdout.writeln('[volition] Packaging Windows desktop bundle -> ${destDir.path}');
      final res = await Process.run(Platform.resolvedExecutable, [
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
      File('${destDir.path}/launch_desktop.cmd').writeAsStringSync(
        '@echo off\r\nstart "" msedge --app="%~dp0index.html"\r\n',
      );
      stdout.writeln('[volition] Packaged Windows bundle in ${destDir.path}');
    default:
      stderr.writeln('Unsupported --target "$target" (expected js, wasm, or windows).');
      exit(64);
  }
}

void _copyStaticAssets(Directory sourceDir, Directory destDir) {
  final indexFile = File('${sourceDir.path}/index.html');
  if (indexFile.existsSync()) {
    indexFile.copySync('${destDir.path}/index.html');
  }
  for (final folder in const ['models', 'audio', 'assets']) {
    final candidates = [
      Directory('${sourceDir.path}/$folder'),
      Directory('pixeldart/web/$folder'),
    ];
    for (final src in candidates) {
      if (src.existsSync()) {
        _copyDirectory(src, Directory('${destDir.path}/$folder'));
        break;
      }
    }
  }
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
