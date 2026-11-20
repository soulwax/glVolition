import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cli_gui_assets.dart';
import 'cli_service.dart';

/// Local HTTP + WebSocket RPC server powering `volition gui`.
class VolitionGuiServer {
  VolitionGuiServer({VolitionCliService? service})
    : service = service ?? VolitionCliService();

  final VolitionCliService service;

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  StreamSubscription<CliLogEvent>? _logSub;
  StreamSubscription<CliTaskSnapshot>? _taskSub;

  int? get port => _server?.port;
  Uri? get url =>
      _server != null ? Uri.parse('http://127.0.0.1:${_server!.port}') : null;

  /// Starts listening on [host]:[port] (pass `0` for an ephemeral port).
  Future<Uri> start({String host = '127.0.0.1', int port = 8090}) async {
    if (_server != null) {
      return url!;
    }
    _server = await HttpServer.bind(host, port);

    _logSub = service.logs.listen((event) {
      _broadcast({'type': 'task.log', 'event': event.toJson()});
    });
    _taskSub = service.taskUpdates.listen((task) {
      _broadcast({
        'type': 'task.update',
        'task': task.toJson(),
        'serveStatus': service.serveStatus,
      });
    });

    _server!.listen(_handleHttpRequest);
    return url!;
  }

  /// Stops the HTTP server, closes all WebSockets, and disposes [service].
  Future<void> stop({bool disposeService = true}) async {
    await _logSub?.cancel();
    await _taskSub?.cancel();
    _logSub = null;
    _taskSub = null;

    for (final ws in _clients.toList()) {
      await ws.close();
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;

    if (disposeService) {
      await service.dispose();
    }
  }

  Future<void> _handleHttpRequest(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      _clients.add(ws);
      ws.listen(
        (data) => _handleWsMessage(ws, data),
        onDone: () => _clients.remove(ws),
        onError: (_) => _clients.remove(ws),
      );
      return;
    }

    if (path == '/' || path == '/index.html') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(volitionGuiIndexHtml);
      await req.response.close();
      return;
    }

    if (path == '/health') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'serve': service.serveStatus}));
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  Future<void> _handleWsMessage(WebSocket ws, Object? raw) async {
    if (raw is! String) return;
    Map<String, Object?> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = decoded.cast<String, Object?>();
    } catch (_) {
      _send(ws, {'type': 'error', 'message': 'Invalid JSON payload.'});
      return;
    }

    final method = msg['method'] as String? ?? '';
    final params = (msg['params'] as Map?)?.cast<String, Object?>() ?? const {};
    final id = msg['id'];

    try {
      switch (method) {
        case 'init':
          _send(ws, {
            'id': id,
            'type': 'init',
            'workingDirectory': service.workingDirectory,
            'serveStatus': service.serveStatus,
            'activeTasks': service.activeTasks.map((t) => t.toJson()).toList(),
          });
        case 'doctor.run':
          final report = await service.runDoctor();
          _send(ws, {
            'id': id,
            'type': 'doctor.result',
            'report': report.toJson(),
          });
        case 'entries.list':
          _send(ws, {
            'id': id,
            'type': 'entries.result',
            'entries': service.discoverEntries(),
          });
        case 'create.run':
          final name = (params['name'] as String? ?? '').trim();
          if (name.isEmpty) {
            _send(ws, {
              'id': id,
              'type': 'error',
              'message': 'Project name is required.',
            });
            return;
          }
          final template = (params['template'] as String? ?? '3d').trim();
          final outDir = (params['outDir'] as String? ?? '').trim();
          final args = <String>[name, '--template', template];
          if (outDir.isNotEmpty) {
            args.addAll(['--out', outDir]);
          }
          await service.startVolitionCommand(
            'create',
            args,
            label: 'create $name ($template)',
          );
        case 'build.run':
        case 'dist.run':
          final isDist = method == 'dist.run';
          final entry = (params['entry'] as String? ?? '').trim();
          final target = (params['target'] as String? ?? 'js').trim();
          final version = (params['version'] as String? ?? '').trim();
          final name = (params['name'] as String? ?? '').trim();
          final dryRun = params['dryRun'] == true;
          final args = <String>[];
          if (entry.isNotEmpty) args.add(entry);
          args.addAll(['--target', target]);
          if (version.isNotEmpty) args.addAll(['--version', version]);
          if (name.isNotEmpty) args.addAll(['--name', name]);
          if (dryRun) args.add('--dry-run');
          await service.startVolitionCommand(
            isDist ? 'dist' : 'build',
            args,
            label: '${isDist ? 'dist' : 'build'} ($target)',
          );
        case 'pack.run':
          final mode = (params['mode'] as String? ?? 'pack').trim();
          final inPath = (params['inPath'] as String? ?? '').trim();
          final outPath = (params['outPath'] as String? ?? '').trim();
          final xorKey = (params['xorKey'] as String? ?? '').trim();
          final noCompress = params['noCompress'] == true;
          final args = <String>[mode];
          if (inPath.isNotEmpty) args.addAll(['--in', inPath]);
          if (outPath.isNotEmpty && mode != 'validate') {
            args.addAll(['--out', outPath]);
          }
          if (xorKey.isNotEmpty) args.addAll(['--xor-key', xorKey]);
          if (noCompress) args.add('--no-compress');
          await service.startVolitionCommand('pack', args, label: 'pack $mode');
        case 'serve.start':
          final entry = (params['entry'] as String? ?? '').trim();
          final port = (params['port'] as num?)?.toInt() ?? 8080;
          if (entry.isEmpty) {
            _send(ws, {
              'id': id,
              'type': 'error',
              'message': 'Entrypoint is required to start server.',
            });
            return;
          }
          await service.startServe(entry: entry, port: port);
          _broadcast({
            'type': 'serve.status',
            'serveStatus': service.serveStatus,
          });
        case 'serve.stop':
          await service.stopServe();
          _broadcast({
            'type': 'serve.status',
            'serveStatus': service.serveStatus,
          });
        case 'test.run':
          final filter = (params['filter'] as String? ?? '').trim();
          final args = <String>['test'];
          if (filter.isNotEmpty) args.add(filter);
          await service.startDartCommand(
            args,
            label: filter.isEmpty ? 'dart test' : 'dart test $filter',
          );
        case 'gate.run':
          final gate = (params['gate'] as String? ?? '').trim();
          await _startGate(gate);
        case 'inspector.list':
          _send(ws, {
            'id': id,
            'type': 'inspector.list.result',
            'files': service.discoverInspectableFiles(),
          });
        case 'inspector.inspect':
          final path = (params['path'] as String? ?? '').trim();
          final xorRaw = (params['xorKey'] as String? ?? '').trim();
          final xorKey = xorRaw.isEmpty ? null : int.tryParse(xorRaw);
          if (path.isEmpty) {
            _send(ws, {
              'id': id,
              'type': 'error',
              'message': 'Artifact path is required.',
            });
            return;
          }
          final report = service.inspectArtifact(path, xorKey: xorKey);
          _send(ws, {
            'id': id,
            'type': 'inspector.inspect.result',
            'report': report,
          });
        case 'tape.verify':
          final path = (params['path'] as String? ?? '').trim();
          if (path.isEmpty) {
            _send(ws, {
              'id': id,
              'type': 'error',
              'message': 'Tape path is required.',
            });
            return;
          }
          final result = service.verifyInputTapeFile(path);
          _send(ws, {'id': id, 'type': 'tape.verify.result', 'result': result});
        case 'task.cancel':
          final taskId = params['taskId'] as String? ?? '';
          service.cancelTask(taskId);
        default:
          _send(ws, {
            'id': id,
            'type': 'error',
            'message': 'Unknown RPC method: $method',
          });
      }
    } catch (e) {
      _send(ws, {'id': id, 'type': 'error', 'message': '$e'});
    }
  }

  Future<void> _startGate(String gate) async {
    switch (gate) {
      case 'boundaries':
        await service.startDartCommand([
          'run',
          'tool/check_boundaries.dart',
        ], label: 'check_boundaries');
      case 'analyze':
        await service.startDartCommand(['analyze'], label: 'dart analyze');
      case 'bench':
        await service.startDartCommand([
          'run',
          'tool/renderer_bench.dart',
        ], label: 'renderer_bench');
      case 'verify':
        await service.startDartCommand([
          'run',
          'tool/verify_all.dart',
          '--check-format',
          '--skip-wasm',
        ], label: 'verify_all (fast)');
      case 'verify_wasm':
        await service.startDartCommand([
          'run',
          'tool/verify_all.dart',
          '--check-format',
        ], label: 'verify_all (+wasm)');
      default:
        throw ArgumentError('Unknown gate "$gate"');
    }
  }

  void _send(WebSocket ws, Map<String, Object?> payload) {
    if (ws.readyState == WebSocket.open) {
      ws.add(jsonEncode(payload));
    }
  }

  void _broadcast(Map<String, Object?> payload) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(payload);
    for (final ws in _clients.toList()) {
      if (ws.readyState == WebSocket.open) {
        ws.add(encoded);
      }
    }
  }
}
