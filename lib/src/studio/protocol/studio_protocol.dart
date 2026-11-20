/// Studio Protocol v2 (S1-0): versioned typed RPC envelopes, error codes,
/// CLI-parity method registry, and pure-Dart JSON codec.
library;

import 'dart:convert';

const int studioProtocolVersion = 2;

/// Standardized Studio Protocol v2 error codes.
enum StudioErrorCode {
  invalidRequest(-32600),
  methodNotFound(-32601),
  invalidParams(-32602),
  internalError(-32603),
  projectNotOpen(-32001),
  assetNotFound(-32002),
  validationFailed(-32003),
  notSupported(-32004),
  cancelled(-32005);

  final int code;
  const StudioErrorCode(this.code);

  static StudioErrorCode fromCode(int value) {
    for (final entry in values) {
      if (entry.code == value) return entry;
    }
    return StudioErrorCode.internalError;
  }

  static StudioErrorCode fromName(String name) {
    for (final entry in values) {
      if (entry.name == name) return entry;
    }
    return StudioErrorCode.internalError;
  }
}

/// Structured error payload returned inside a failed [StudioResponse].
final class StudioError {
  final StudioErrorCode code;
  final String message;
  final Map<String, Object?>? details;

  const StudioError({required this.code, required this.message, this.details});

  Map<String, Object?> toJson() => {
    'code': code.code,
    'name': code.name,
    'message': message,
    if (details != null) 'details': details,
  };

  factory StudioError.fromJson(Map<String, Object?> json) {
    final rawCode = json['code'];
    final rawName = json['name'];
    final resolvedCode = rawCode is int
        ? StudioErrorCode.fromCode(rawCode)
        : rawName is String
        ? StudioErrorCode.fromName(rawName)
        : StudioErrorCode.internalError;
    final message = json['message'] as String? ?? 'Unknown Studio error';
    final rawDetails = json['details'];
    return StudioError(
      code: resolvedCode,
      message: message,
      details: rawDetails is Map ? rawDetails.cast<String, Object?>() : null,
    );
  }
}

/// Sealed base class for all Studio Protocol v2 envelopes.
sealed class StudioEnvelope {
  final int version;

  const StudioEnvelope({this.version = studioProtocolVersion});

  String get kind;

  Map<String, Object?> toJson();
}

/// Typed client-to-daemon RPC request envelope.
final class StudioRequest extends StudioEnvelope {
  final String id;
  final String method;
  final Map<String, Object?> params;

  const StudioRequest({
    required this.id,
    required this.method,
    this.params = const {},
    super.version = studioProtocolVersion,
  });

  @override
  String get kind => 'request';

  @override
  Map<String, Object?> toJson() => {
    'version': version,
    'kind': kind,
    'id': id,
    'method': method,
    'params': params,
  };

  factory StudioRequest.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    final method = json['method'] as String? ?? '';
    if (id.isEmpty || method.isEmpty) {
      throw const FormatException(
        'StudioRequest requires non-empty id and method',
      );
    }
    final rawParams = json['params'];
    return StudioRequest(
      version: (json['version'] as num?)?.toInt() ?? studioProtocolVersion,
      id: id,
      method: method,
      params: rawParams is Map
          ? rawParams.cast<String, Object?>()
          : const <String, Object?>{},
    );
  }
}

/// Typed daemon-to-client RPC response envelope.
final class StudioResponse extends StudioEnvelope {
  final String id;
  final bool ok;
  final Map<String, Object?>? result;
  final StudioError? error;

  const StudioResponse({
    required this.id,
    required this.ok,
    this.result,
    this.error,
    super.version = studioProtocolVersion,
  });

  factory StudioResponse.ok(
    String id,
    Map<String, Object?> result, {
    int version = studioProtocolVersion,
  }) => StudioResponse(id: id, ok: true, result: result, version: version);

  factory StudioResponse.err(
    String id,
    StudioError error, {
    int version = studioProtocolVersion,
  }) => StudioResponse(id: id, ok: false, error: error, version: version);

  @override
  String get kind => 'response';

  @override
  Map<String, Object?> toJson() => {
    'version': version,
    'kind': kind,
    'id': id,
    'ok': ok,
    if (result != null) 'result': result,
    if (error != null) 'error': error!.toJson(),
  };

  factory StudioResponse.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('StudioResponse requires non-empty id');
    }
    final ok = json['ok'] == true;
    final rawResult = json['result'];
    final rawError = json['error'];
    return StudioResponse(
      version: (json['version'] as num?)?.toInt() ?? studioProtocolVersion,
      id: id,
      ok: ok,
      result: rawResult is Map ? rawResult.cast<String, Object?>() : null,
      error: rawError is Map
          ? StudioError.fromJson(rawError.cast<String, Object?>())
          : null,
    );
  }
}

/// Typed push notification event envelope (logs, task updates, FS watch events).
final class StudioEvent extends StudioEnvelope {
  final String event;
  final Map<String, Object?> payload;
  final int timestampMs;

  const StudioEvent({
    required this.event,
    this.payload = const {},
    this.timestampMs = 0,
    super.version = studioProtocolVersion,
  });

  @override
  String get kind => 'event';

  @override
  Map<String, Object?> toJson() => {
    'version': version,
    'kind': kind,
    'event': event,
    'payload': payload,
    'timestampMs': timestampMs,
  };

  factory StudioEvent.fromJson(Map<String, Object?> json) {
    final event = json['event'] as String? ?? '';
    if (event.isEmpty) {
      throw const FormatException('StudioEvent requires non-empty event name');
    }
    final rawPayload = json['payload'];
    return StudioEvent(
      version: (json['version'] as num?)?.toInt() ?? studioProtocolVersion,
      event: event,
      payload: rawPayload is Map
          ? rawPayload.cast<String, Object?>()
          : const <String, Object?>{},
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Declares a Studio RPC method together with its mandatory CLI mapping
/// (verified by the `[S2-M]` CLI parity gate).
final class StudioMethodDescriptor {
  final String method;
  final String cliCommand;
  final String summary;
  final bool deprecated;

  const StudioMethodDescriptor({
    required this.method,
    required this.cliCommand,
    required this.summary,
    this.deprecated = false,
  });
}

/// Central registry of Studio Protocol v2 methods and their CLI equivalents.
final class StudioMethodRegistry {
  final Map<String, StudioMethodDescriptor> _methods = {};

  StudioMethodRegistry({Iterable<StudioMethodDescriptor>? initialMethods}) {
    for (final desc in initialMethods ?? defaultMethods) {
      register(desc);
    }
  }

  /// Built-in Studio Protocol v2 methods including legacy dashboard RPCs.
  static const List<StudioMethodDescriptor> defaultMethods = [
    StudioMethodDescriptor(
      method: 'studio.init',
      cliCommand: 'volition studio',
      summary: 'Initialize Studio session and query daemon capabilities',
    ),
    StudioMethodDescriptor(
      method: 'doctor.run',
      cliCommand: 'volition doctor --json',
      summary: 'Run local toolchain and GPU readiness diagnostics',
    ),
    StudioMethodDescriptor(
      method: 'entries.list',
      cliCommand: 'volition studio --list-entries',
      summary: 'Discover runnable project entrypoint files',
    ),
    StudioMethodDescriptor(
      method: 'create.run',
      cliCommand: 'volition create',
      summary: 'Scaffold a new glVolition project from a template',
    ),
    StudioMethodDescriptor(
      method: 'build.run',
      cliCommand: 'volition build',
      summary: 'Build project for web, native, or server targets',
    ),
    StudioMethodDescriptor(
      method: 'dist.run',
      cliCommand: 'volition dist',
      summary: 'Package a distributable release bundle',
    ),
    StudioMethodDescriptor(
      method: 'pack.run',
      cliCommand: 'volition pack',
      summary: 'Pack, unpack, or validate .pak asset archives',
    ),
    StudioMethodDescriptor(
      method: 'serve.start',
      cliCommand: 'volition serve',
      summary: 'Start local development HTTP server for a web entry',
    ),
    StudioMethodDescriptor(
      method: 'serve.stop',
      cliCommand: 'volition serve --stop',
      summary: 'Stop active local development server',
    ),
    StudioMethodDescriptor(
      method: 'test.run',
      cliCommand: 'dart test',
      summary: 'Execute unit or integration test suite',
    ),
    StudioMethodDescriptor(
      method: 'gate.run',
      cliCommand: 'dart run tool/verify_all.dart',
      summary: 'Run repository verification gate',
    ),
    StudioMethodDescriptor(
      method: 'inspector.list',
      cliCommand: 'volition inspect --list',
      summary: 'List inspectable .pak, scene, and tape artifacts',
    ),
    StudioMethodDescriptor(
      method: 'inspector.inspect',
      cliCommand: 'volition inspect',
      summary: 'Inspect a .pak archive or scene.json artifact',
    ),
    StudioMethodDescriptor(
      method: 'tape.verify',
      cliCommand: 'volition replay',
      summary: 'Verify deterministic InputTape replay hashes',
    ),
    StudioMethodDescriptor(
      method: 'project.open',
      cliCommand: 'volition project info',
      summary: 'Open a volition.project.json workspace and load AssetDatabase',
    ),
    StudioMethodDescriptor(
      method: 'assets.list',
      cliCommand: 'volition assets list',
      summary: 'List indexed GUID assets and import statuses',
    ),
    StudioMethodDescriptor(
      method: 'assets.reimport',
      cliCommand: 'volition assets reimport',
      summary: 'Trigger incremental or forced asset reimport',
    ),
    StudioMethodDescriptor(
      method: 'scene.load',
      cliCommand: 'volition scene inspect',
      summary: 'Load a GUID-referenced scene document',
    ),
    StudioMethodDescriptor(
      method: 'scene.save',
      cliCommand: 'volition scene validate',
      summary: 'Persist a GUID-referenced scene document atomically',
    ),
    StudioMethodDescriptor(
      method: 'modules.list',
      cliCommand: 'dart run tool/check_module_coverage.dart --report',
      summary: 'List registered vendor module descriptors and maturities',
    ),
  ];

  void register(StudioMethodDescriptor descriptor) {
    if (descriptor.method.trim().isEmpty) {
      throw ArgumentError.value(
        descriptor.method,
        'method',
        'Method name must be non-empty',
      );
    }
    if (descriptor.cliCommand.trim().isEmpty) {
      throw ArgumentError.value(
        descriptor.cliCommand,
        'cliCommand',
        'Every Studio RPC method must declare a CLI command mapping',
      );
    }
    _methods[descriptor.method] = descriptor;
  }

  StudioMethodDescriptor? lookup(String method) => _methods[method];

  bool contains(String method) => _methods.containsKey(method);

  List<StudioMethodDescriptor> get all =>
      List<StudioMethodDescriptor>.unmodifiable(_methods.values);
}

/// Pure-Dart JSON codec for Studio Protocol v2 envelopes.
final class StudioProtocolCodec {
  const StudioProtocolCodec();

  String encode(StudioEnvelope envelope) => jsonEncode(envelope.toJson());

  StudioEnvelope decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Studio envelope must be a JSON object');
    }
    final map = decoded.cast<String, Object?>();
    final version = (map['version'] as num?)?.toInt();
    if (version != null && version != studioProtocolVersion) {
      throw FormatException(
        'Unsupported Studio protocol version $version '
        '(expected $studioProtocolVersion)',
      );
    }
    final kind = map['kind'] as String?;
    return switch (kind) {
      'request' => StudioRequest.fromJson(map),
      'response' => StudioResponse.fromJson(map),
      'event' => StudioEvent.fromJson(map),
      _ => throw FormatException('Unknown Studio envelope kind: $kind'),
    };
  }
}
